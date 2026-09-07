import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;
import 'package:derk_finance/data/database.dart';
import 'package:derk_finance/data/finance_repository.dart';
import 'package:derk_finance/domain/models.dart';
import 'package:derk_finance/services/security.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Production Android configure, migrations and encrypted reopen', (
    tester,
  ) async {
    final security = SecurityService();
    const keyName = 'derk_integration_test_key';
    final folder = await getTemporaryDirectory();
    final path = '${folder.path}/derk_integration_test.db';
    final secret = secureToken();
    Database? db;
    try {
      await security.storage.write(key: keyName, value: secret);
      expect(await security.storage.read(key: keyName), secret);
      await cipher.deleteDatabase(path);
      // Use precisely the same SQLCipher configuration/migrations as startup.
      db = await FinanceDatabase.openEncrypted(path, secret);
      final repository = SqlFinanceRepository(db);
      await repository.initialize();
      expect((await repository.snapshot()).accounts.length, 3);
      expect(
        (await db.rawQuery('PRAGMA foreign_keys')).single.values.single,
        1,
      );
      expect(
        (await db.rawQuery('PRAGMA secure_delete')).single.values.single,
        1,
      );
      expect(await db.getVersion(), FinanceDatabase.version);
      expect(await db.rawQuery('PRAGMA cipher_version'), isNotEmpty);
      await repository.addTransaction(
        FinanceTransaction(
          id: 'native-test',
          kind: TransactionKind.income,
          amountMinor: 12345,
          accountId: 'card',
          date: DateTime.now(),
        ),
      );
      await db.close();
      final bytes = await File(path).readAsBytes();
      expect(
        utf8
            .decode(bytes.take(16).toList(), allowMalformed: true)
            .startsWith('SQLite format 3'),
        false,
      );
      db = await FinanceDatabase.openEncrypted(path, secret);
      final reopened = SqlFinanceRepository(db);
      await reopened.initialize();
      expect(
        (await reopened.snapshot()).transactions.single.amountMinor,
        12345,
      );
    } finally {
      if (db != null && db.isOpen) await db.close();
      await cipher.deleteDatabase(path);
      await security.storage.delete(key: keyName);
    }
  });
}
