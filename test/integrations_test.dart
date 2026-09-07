import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:derk_finance/data/database.dart';
import 'package:derk_finance/data/finance_repository.dart';
import 'package:derk_finance/domain/models.dart';
import 'package:derk_finance/integrations/banks/bank_sync.dart';
import 'package:derk_finance/integrations/banks/mock_bank_provider.dart';
import 'package:derk_finance/integrations/mcp/permissions.dart';
import 'package:derk_finance/integrations/mcp/schema_validator.dart';
import 'package:derk_finance/services/finance_assistant_api.dart';
import 'package:derk_finance/services/backup_export.dart';
import 'package:derk_finance/services/statement_import.dart';
import 'support.dart';

void main() {
  late SqlFinanceRepository repo;
  setUp(() async {
    repo = await testRepository();
  });
  tearDown(() async {
    await (repo.db as Database).close();
  });
  test('CSV preview, decimal comma, MCC and repeat import', () async {
    final importer = StatementImportService(repo);
    final account = (await repo.snapshot()).accounts.firstWhere(
      (a) => a.id == 'card',
    );
    final bytes = await File('assets/sample_statement.csv').readAsBytes();
    final preview = await importer.preview('statement.csv', bytes, account);
    expect(preview.errors, isEmpty);
    expect(preview.rows.length, 3);
    expect(preview.rows[1].transaction.amountMinor, 45050);
    expect(preview.rows[1].transaction.category, 'Еда');
    expect(await importer.commit(preview.rows), 3);
    final repeat = await importer.preview('renamed.csv', bytes, account);
    expect(repeat.rows.every((r) => r.duplicate), true);
    expect(await importer.commit(repeat.rows), 0);
  });
  test(
    'Two identical no-ID rows retain multiplicity, replay adds nothing',
    () async {
      final importer = StatementImportService(repo);
      final account = (await repo.snapshot()).accounts.firstWhere(
        (a) => a.id == 'card',
      );
      final bytes = Uint8List.fromList(
        utf8.encode(
          'date;amount;merchant\n01.01.2025;-100;Магазин\n01.01.2025;-100;Магазин\n',
        ),
      );
      final preview = await importer.preview('s.csv', bytes, account);
      expect(await importer.commit(preview.rows), 2);
      final second = await importer.preview('s.csv', bytes, account);
      expect(await importer.commit(second.rows), 0);
    },
  );
  test('Bad CSV rows are visible in preview; never silently coerced', () async {
    final a = (await repo.snapshot()).accounts.first;
    final bytes = Uint8List.fromList(
      utf8.encode(
        'date;amount;currency\n31.02.2025;-10;RUB\n01.01.2025;1.001;RUB\n01.01.2025;10;USD',
      ),
    );
    final result = await StatementImportService(
      repo,
    ).preview('s.csv', bytes, a);
    expect(result.rows, isEmpty);
    expect(result.errors.length, 3);
  });
  test('OFX SGML stable FITID and timezone parsing', () async {
    final a = (await repo.snapshot()).accounts.first;
    final bytes = Uint8List.fromList(
      utf8.encode(
        '<OFX><CURDEF>RUB\n<BANKTRANLIST><STMTTRN><TRNTYPE>DEBIT\n<DTPOSTED>20250115120000[3:MSK]\n<TRNAMT>-450.50\n<FITID>ofx-1\n<NAME>SHOP\n</STMTTRN></BANKTRANLIST></OFX>',
      ),
    );
    final preview = await StatementImportService(
      repo,
    ).preview('s.ofx', bytes, a);
    expect(preview.errors, isEmpty);
    expect(preview.rows.single.transaction.amountMinor, 45050);
    expect(
      preview.rows.single.transaction.date.toUtc(),
      DateTime.utc(2025, 1, 15, 9),
    );
  });
  test(
    'XLSX export is readable by importer, CSV defends formula cells',
    () async {
      final t = FinanceTransaction(
        id: 't',
        kind: TransactionKind.expense,
        amountMinor: 12550,
        accountId: 'card',
        date: DateTime(2025, 1, 1),
        merchant: '=HYPERLINK("bad")',
      );
      final bytes = ExportService.export([t], 'xlsx');
      final a = (await repo.snapshot()).accounts.firstWhere(
        (a) => a.id == 'card',
      );
      final preview = await StatementImportService(
        repo,
      ).preview('s.xlsx', bytes, a);
      expect(preview.errors, isEmpty);
      expect(preview.rows.single.transaction.amountMinor, 12550);
      expect(ExportService.safeCell('=1+1'), "'=1+1");
    },
  );
  test(
    'Mock bank is idempotent and opening balance reconciles snapshot',
    () async {
      final sync = BankSyncService(repo), bank = MockBankProvider();
      expect((await sync.sync(bank)).added, 2);
      expect((await sync.sync(bank)).duplicates, 2);
      final s = await repo.snapshot(),
          a = (await repo.snapshot()).accounts.firstWhere(
            (a) => a.bankId == 'mock',
          );
      expect(s.balance(a), 1345500);
    },
  );
  test(
    'Backup authenticated encryption rejects wrong passwords and tampering',
    () async {
      final cipher = BackupCipher(), backup = await repo.exportBackup();
      final encrypted = await cipher.encrypt(backup, 'correct horse battery');
      expect(utf8.decode(encrypted).contains('openingMinor'), false);
      final decrypted = await cipher.decrypt(
        encrypted,
        'correct horse battery',
      );
      expect(decrypted['schemaVersion'], 2);
      await expectLater(
        cipher.decrypt(encrypted, 'incorrect password'),
        throwsFormatException,
      );
      final envelope =
          jsonDecode(utf8.decode(encrypted)) as Map<String, dynamic>;
      final contents = base64Decode(envelope['ciphertext'] as String);
      contents[0] ^= 1;
      envelope['ciphertext'] = base64Encode(contents);
      await expectLater(
        cipher.decrypt(
          Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
          'correct horse battery',
        ),
        throwsFormatException,
      );
    },
  );
  test('Corrupt restore rolls back deletion of current records', () async {
    await repo.addTransaction(
      FinanceTransaction(
        id: 't',
        kind: TransactionKind.income,
        amountMinor: 1000,
        accountId: 'card',
        date: DateTime(2025),
      ),
    );
    final backup =
        jsonDecode(jsonEncode(await repo.exportBackup()))
            as Map<String, dynamic>;
    ((backup['tables'] as Map)['transactions'] as List).add({
      ...((backup['tables'] as Map)['transactions'] as List).first as Map,
      'id': 'bad',
      'amountMinor': -1,
    });
    await expectLater(
      repo.restoreBackup(backup),
      throwsA(isA<DatabaseException>()),
    );
    expect((await repo.snapshot()).transactions.length, 1);
  });
  test(
    'Migration from v1 preserves an existing account and adds permission tables',
    () async {
      final old = await testRepository(version: 1);
      final db = old.db as Database;
      await db.transaction(
        (tx) => FinanceDatabase.migrate(
          tx,
          1,
          2,
          (v) => File('assets/schema_v$v.sql').readAsString(),
        ),
      );
      expect((await db.query('accounts')).length, 3);
      expect(await db.query('api_requests'), isEmpty);
      await db.close();
    },
  );
  test(
    'API rejects reads without consent, write escalation and unknown fields',
    () async {
      final specs =
          (jsonDecode(await File('assets/mcp_tools.json').readAsString())
                  as List)
              .cast<Map<String, dynamic>>();
      final permissions = PermissionService()..unlocked = true;
      final api = LocalFinanceAssistantAPI(repo, permissions, specs);
      await expectLater(
        api.call('get_balance', {}, token: 'unknown'),
        throwsStateError,
      );
      final token = permissions.grant({'get_balance'}).token;
      await expectLater(
        api.call('add_expense', {'amountMinor': 100}, token: token),
        throwsStateError,
      );
      await expectLater(
        api.call('get_balance', {'sql': 'SELECT *'}, token: token),
        throwsFormatException,
      );
      permissions.revokeAll();
      await expectLater(
        api.call('get_balance', {}, token: token),
        throwsStateError,
      );
    },
  );
  test(
    'API write replay is atomic and binds requestId to identical payload',
    () async {
      final specs =
          (jsonDecode(await File('assets/mcp_tools.json').readAsString())
                  as List)
              .cast<Map<String, dynamic>>();
      final permissions = PermissionService()..unlocked = true;
      final api = LocalFinanceAssistantAPI(repo, permissions, specs);
      final token = permissions.grant({'add_expense'}).token;
      final args = {
        'requestId': 'request-1',
        'accountId': 'card',
        'amountMinor': 45000,
      };
      final results = await Future.wait([
        api.call('add_expense', args, token: token),
        api.call('add_expense', args, token: token),
      ]);
      expect(results[0], results[1]);
      expect((await repo.snapshot()).transactions.length, 1);
      await expectLater(
        api.call('add_expense', {...args, 'amountMinor': 50000}, token: token),
        throwsArgumentError,
      );
      expect((await repo.snapshot()).transactions.length, 1);
    },
  );
  test('Schema money must be integer and bounded', () {
    expect(
      () => validateSchema(4.5, {'type': 'integer', 'minimum': 1}),
      throwsFormatException,
    );
    expect(
      () => validateSchema(0, {'type': 'integer', 'minimum': 1}),
      throwsFormatException,
    );
    expect(
      () => validateSchema('2025-02-31T12:00:00', {
        'type': 'string',
        'format': 'date-time',
      }),
      throwsFormatException,
    );
  });
}
