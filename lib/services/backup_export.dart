import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import '../core/money.dart';
import '../domain/analytics.dart';
import '../domain/models.dart';
import 'security.dart';

class BackupCipher {
  static const iterations = 210000;
  static const header = 'DERK-FINANCE-BACKUP-V1';
  final AesGcm algorithm = AesGcm.with256bits();
  Future<SecretKey> _key(String passphrase, List<int> salt) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
  Future<Uint8List> encrypt(
    Map<String, dynamic> data,
    String passphrase,
  ) async {
    if (passphrase.length < 12)
      throw const FormatException(
        'Пароль резервной копии — не менее 12 символов',
      );
    final salt = base64Url.decode(secureToken(16));
    final box = await algorithm.encrypt(
      utf8.encode(jsonEncode(data)),
      secretKey: await _key(passphrase, salt),
      aad: utf8.encode(header),
    );
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': header,
          'kdf': 'PBKDF2-HMAC-SHA256',
          'iterations': iterations,
          'salt': base64Encode(salt),
          'nonce': base64Encode(box.nonce),
          'ciphertext': base64Encode(box.cipherText),
          'mac': base64Encode(box.mac.bytes),
        }),
      ),
    );
  }

  Future<Map<String, dynamic>> decrypt(
    Uint8List bytes,
    String passphrase,
  ) async {
    if (bytes.length > 50 * 1024 * 1024)
      throw const FormatException('Резервная копия слишком большая');
    try {
      final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (data['format'] != header ||
          data['iterations'] != iterations ||
          data['kdf'] != 'PBKDF2-HMAC-SHA256') {
        throw const FormatException('Неподдерживаемая резервная копия');
      }
      final salt = base64Decode(data['salt'] as String);
      final nonce = base64Decode(data['nonce'] as String);
      final mac = base64Decode(data['mac'] as String);
      if (salt.length != 16 || nonce.length != 12 || mac.length != 16)
        throw const FormatException('Повреждённый заголовок');
      final clear = await algorithm.decrypt(
        SecretBox(
          base64Decode(data['ciphertext'] as String),
          nonce: nonce,
          mac: Mac(mac),
        ),
        secretKey: await _key(passphrase, salt),
        aad: utf8.encode(header),
      );
      return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('Неверный пароль или повреждённая копия');
    }
  }
}

class ExportService {
  static List<FinanceTransaction> filter(
    FinanceSnapshot snapshot, {
    DateWindow? window,
    String? category,
    String? currency,
  }) => snapshot.transactions
      .where(
        (t) =>
            (window == null || window.contains(t.date)) &&
            (category == null || t.category == category) &&
            (currency == null || t.currency == currency),
      )
      .toList();
  static String safeCell(String text) =>
      RegExp(r'^[\s]*[=+@\-\t\r]').hasMatch(text) ? "'$text" : text;
  static Uint8List export(
    List<FinanceTransaction> transactions,
    String format,
  ) {
    if (format == 'json') {
      return Uint8List.fromList(
        utf8.encode(
          const JsonEncoder.withIndent('  ').convert({
            'schemaVersion': 1,
            'moneyUnit': 'minor',
            'transactions': transactions.map((t) => t.toJson()).toList(),
          }),
        ),
      );
    }
    final rows = <List<String>>[
      [
        'id',
        'date',
        'type',
        'amount',
        'currency',
        'category',
        'subcategory',
        'merchant',
        'description',
        'accountId',
        'toAccountId',
        'source',
        'workMinutes',
        'paymentMethod',
        'mcc',
      ],
      ...transactions.map(
        (t) => [
          t.id,
          t.date.toIso8601String(),
          t.kind.name,
          decimalMoney(t.amountMinor),
          t.currency,
          t.category,
          t.subcategory,
          t.merchant,
          t.comment,
          t.accountId,
          t.toAccountId ?? '',
          t.source,
          t.workMinutes.toString(),
          t.paymentMethod,
          t.mcc ?? '',
        ],
      ),
    ];
    if (format == 'csv') {
      final text = const ListToCsvConverter(
        fieldDelimiter: ';',
      ).convert(rows.map((r) => r.map(safeCell).toList()).toList());
      return Uint8List.fromList(utf8.encode('\uFEFF$text'));
    }
    if (format == 'xlsx') {
      final workbook = Excel.createExcel();
      final sheet = workbook['Операции'];
      workbook.setDefaultSheet('Операции');
      workbook.delete('Sheet1');
      for (final row in rows) {
        sheet.appendRow(row.map((v) => TextCellValue(v)).toList());
      }
      for (var i = 0; i < rows.first.length; i++) {
        sheet.setColumnWidth(i, i == 8 ? 36 : 21);
      }
      return Uint8List.fromList(workbook.encode()!);
    }
    throw ArgumentError('Неизвестный формат экспорта');
  }
}
