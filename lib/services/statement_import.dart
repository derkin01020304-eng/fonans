import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import '../core/money.dart';
import '../data/finance_repository.dart';
import '../domain/models.dart';
import '../integrations/banks/bank_sync.dart';
import 'categorizer.dart';

class ImportRow {
  ImportRow({
    required this.transaction,
    required this.rowNumber,
    this.duplicate = false,
  });
  final FinanceTransaction transaction;
  final int rowNumber;
  final bool duplicate;
}

class ImportPreview {
  const ImportPreview(this.rows, this.errors);
  final List<ImportRow> rows;
  final List<String> errors;
}

class StatementImportService {
  StatementImportService(this.repository);
  final SqlFinanceRepository repository;
  static const maxBytes = 10 * 1024 * 1024;
  Future<ImportPreview> preview(
    String fileName,
    Uint8List bytes,
    Account account,
  ) async {
    if (bytes.length > maxBytes)
      throw const FormatException('Максимальный размер выписки — 10 МБ');
    final extension = fileName.split('.').last.toLowerCase();
    if (extension == 'pdf') {
      throw const FormatException(
        'PDF требует шаблона конкретного банка. Экспортируйте выписку в CSV, XLSX или OFX.',
      );
    }
    final rules = Categorizer(await repository.categoryRules());
    final List<Map<String, String>> records;
    if (extension == 'ofx' || extension == 'qfx') {
      records = _ofx(utf8.decode(bytes, allowMalformed: false));
    } else if (extension == 'xlsx') {
      final book = Excel.decodeBytes(bytes);
      final sheet = book.tables.values.firstWhere(
        (s) => s.maxRows > 1,
        orElse: () =>
            throw const FormatException('В книге нет таблицы операций'),
      );
      records = _records(
        sheet.rows
            .map(
              (row) =>
                  row.map((cell) => cell?.value?.toString() ?? '').toList(),
            )
            .toList(),
      );
    } else if (extension == 'csv') {
      var text = utf8
          .decode(bytes, allowMalformed: false)
          .replaceFirst('\uFEFF', '');
      text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      final first = text.split('\n').take(10).join('\n');
      final delimiter = [';', ',', '\t'].reduce(
        (a, b) => first.split(a).length >= first.split(b).length ? a : b,
      );
      records = _records(
        CsvToListConverter(
              fieldDelimiter: delimiter,
              eol: '\n',
              shouldParseNumbers: false,
            )
            .convert(text)
            .map((r) => r.map((c) => c.toString()).toList())
            .toList(),
      );
    } else {
      throw const FormatException('Поддерживаются CSV, XLSX, OFX');
    }
    if (records.length > 50000)
      throw const FormatException('Не более 50 000 строк за импорт');
    final existing = (await repository.db.query(
      'transactions',
      columns: ['externalKey'],
    )).map((r) => r['externalKey']).toSet();
    final rows = <ImportRow>[], errors = <String>[];
    final occurrence = <String, int>{};
    for (var i = 0; i < records.length; i++) {
      try {
        final r = records[i];
        final date = parseStatementDate(r['date'] ?? '');
        var signed = parseMoney(r['amount'] ?? '', allowNegative: true);
        if (RegExp(
          r'debit|expense|расход|списан',
          caseSensitive: false,
        ).hasMatch(r['type'] ?? ''))
          signed = -signed.abs();
        if (signed == 0) throw const FormatException('Нулевая операция');
        final currency =
            (r['currency']?.trim().toUpperCase() ?? account.currency);
        if (currency != account.currency &&
            !(currency == '643' && account.currency == 'RUB')) {
          throw const FormatException('Валюта не совпадает с выбранным счётом');
        }
        final merchant = r['merchant'] ?? '';
        final description = r['description'] ?? '';
        final p = rules.predict(
          merchant: merchant,
          description: description,
          mcc: r['mcc'],
        );
        final signature = jsonEncode([
          account.id,
          date.toIso8601String(),
          signed,
          account.currency,
          normalizeMerchant(merchant),
          description.trim(),
          r['mcc'] ?? '',
        ]);
        occurrence.update(signature, (v) => v + 1, ifAbsent: () => 1);
        final key = (r['id']?.trim().isNotEmpty ?? false)
            ? externalKey(account.id, r['id']!.trim())
            : sha256
                  .convert(utf8.encode('$signature|${occurrence[signature]}'))
                  .toString();
        final t = FinanceTransaction(
          id: SqlFinanceRepository.uuid.v4(),
          kind: signed > 0 ? TransactionKind.income : TransactionKind.expense,
          amountMinor: signed.abs(),
          accountId: account.id,
          date: date,
          currency: account.currency,
          category: signed > 0 ? 'Прочее' : p.category,
          merchant: merchant,
          comment: description,
          mcc: r['mcc'],
          externalKey: key,
          needsReview: signed < 0 && p.needsReview ? 1 : 0,
          source: 'Выписка',
          paymentMethod: 'Банк',
        );
        rows.add(
          ImportRow(
            transaction: t,
            rowNumber: i + 1,
            duplicate: existing.contains(key),
          ),
        );
        existing.add(key);
      } catch (e) {
        errors.add(
          'Строка ${i + 1}: ${e is FormatException ? e.message : 'некорректные данные'}',
        );
      }
    }
    return ImportPreview(rows, errors);
  }

  Future<int> commit(List<ImportRow> rows) => repository.atomic((tx) async {
    var count = 0;
    for (final row in rows.where((r) => !r.duplicate)) {
      if ((await tx.query(
        'transactions',
        columns: ['id'],
        where: 'externalKey = ?',
        whereArgs: [row.transaction.externalKey],
      )).isNotEmpty)
        continue;
      await SqlFinanceRepository(tx).addTransaction(row.transaction);
      count++;
    }
    return count;
  });
  static String _header(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
  static const aliases = {
    'date': ['date', 'datetime', 'дата', 'датаоперации', 'датаплатежа'],
    'amount': [
      'amount',
      'сумма',
      'суммаоперации',
      'суммаввалютесчета',
      'trnamt',
    ],
    'merchant': [
      'merchant',
      'payee',
      'получатель',
      'магазин',
      'контрагент',
      'name',
    ],
    'description': [
      'description',
      'comment',
      'описание',
      'комментарий',
      'назначениеплатежа',
      'memo',
    ],
    'currency': ['currency', 'валюта', 'валютаоперации'],
    'mcc': ['mcc', 'mccкод', 'кодmcc'],
    'id': ['id', 'transactionid', 'идентификатор', 'номероперации', 'fitid'],
    'type': ['type', 'тип', 'типоперации', 'trntype'],
  };
  List<Map<String, String>> _records(List<List<String>> table) {
    var header = -1;
    var mapping = <String, int>{};
    for (var i = 0; i < table.length && i < 30; i++) {
      final names = table[i].map(_header).toList();
      mapping = {
        for (final e in aliases.entries)
          if (names.any(e.value.contains))
            e.key: names.indexWhere(e.value.contains),
      };
      if (mapping.containsKey('date') && mapping.containsKey('amount')) {
        header = i;
        break;
      }
    }
    if (header < 0)
      throw const FormatException(
        'Не найдены столбцы «дата» и «сумма». Используйте образец CSV.',
      );
    return table
        .skip(header + 1)
        .where((r) => r.any((v) => v.trim().isNotEmpty))
        .map(
          (r) => {
            for (final e in mapping.entries)
              e.key: e.value < r.length ? r[e.value] : '',
          },
        )
        .toList();
  }

  List<Map<String, String>> _ofx(String text) {
    String tag(String block, String tag) =>
        RegExp(
          '<$tag>\\s*([^<\\r\\n]+)',
          caseSensitive: false,
        ).firstMatch(block)?.group(1)?.trim() ??
        '';
    final currency = tag(text, 'CURDEF');
    final blocks = RegExp(
      r'<STMTTRN>(.*?)(?:</STMTTRN>|(?=<STMTTRN>)|(?=</BANKTRANLIST>))',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(text);
    final records = blocks
        .map(
          (b) => {
            'id': tag(b.group(1)!, 'FITID'),
            'date': tag(b.group(1)!, 'DTPOSTED'),
            'amount': tag(b.group(1)!, 'TRNAMT'),
            'type': tag(b.group(1)!, 'TRNTYPE'),
            'merchant': tag(b.group(1)!, 'NAME'),
            'description': tag(b.group(1)!, 'MEMO'),
            if (currency.isNotEmpty) 'currency': currency,
          },
        )
        .toList();
    if (records.isEmpty)
      throw const FormatException('В OFX нет операций STMTTRN');
    return records;
  }
}

DateTime parseStatementDate(String value) {
  final text = value.trim();
  DateTime checked(int y, int m, int d, [int h = 0, int min = 0, int s = 0]) {
    final date = DateTime(y, m, d, h, min, s);
    if (date.year != y ||
        date.month != m ||
        date.day != d ||
        h > 23 ||
        min > 59 ||
        s > 59) {
      throw const FormatException('Некорректная дата');
    }
    return date;
  }

  final ru = RegExp(
    r'^(\d{2})[./](\d{2})[./](\d{4})(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?)?$',
  ).firstMatch(text);
  if (ru != null)
    return checked(
      int.parse(ru[3]!),
      int.parse(ru[2]!),
      int.parse(ru[1]!),
      int.parse(ru[4] ?? '0'),
      int.parse(ru[5] ?? '0'),
      int.parse(ru[6] ?? '0'),
    );
  final ofx = RegExp(
    r'^(\d{4})(\d{2})(\d{2})(?:(\d{2})(\d{2})(\d{2}))?(?:\.\d+)?(?:\[([+-]?\d+(?:\.\d+)?):[^\]]+\])?$',
  ).firstMatch(text);
  if (ofx != null) {
    final d = checked(
      int.parse(ofx[1]!),
      int.parse(ofx[2]!),
      int.parse(ofx[3]!),
      int.parse(ofx[4] ?? '0'),
      int.parse(ofx[5] ?? '0'),
      int.parse(ofx[6] ?? '0'),
    );
    if (ofx[7] == null) return d;
    return DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second)
        .subtract(Duration(minutes: (double.parse(ofx[7]!) * 60).round()))
        .toLocal();
  }
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
  if (iso != null) {
    checked(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
    final parsed = DateTime.tryParse(text);
    if (parsed != null) return parsed.toLocal();
  }
  throw const FormatException('Дата должна быть ДД.ММ.ГГГГ или ISO 8601');
}
