import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:derk_finance/core/startup_failure.dart';
import 'package:derk_finance/data/database.dart';
import 'package:derk_finance/main.dart';
import 'support.dart';

/// Android's execSQL contract is stricter than SQLite FFI's execute method.
/// This adapter catches the original startup bug even on a desktop test runner.
class AndroidPragmaContract implements DatabaseExecutor {
  AndroidPragmaContract(this._delegate);
  final DatabaseExecutor _delegate;
  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) {
    if (sql.toLowerCase().startsWith('pragma secure_delete')) {
      throw PlatformException(
        code: 'sqlite_error',
        message:
            'Queries can be performed using SQLiteDatabase query or rawQuery methods only.',
      );
    }
    return _delegate.execute(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) => _delegate.rawQuery(sql, arguments);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Startup config respects Android result-returning PRAGMA contract',
    () async {
      final repo = await testRepository();
      final db = repo.db as Database;
      try {
        await db.rawQuery('PRAGMA secure_delete = OFF');
        final strict = AndroidPragmaContract(db);
        expect(
          () => strict.execute('PRAGMA secure_delete = ON'),
          throwsA(isA<PlatformException>()),
        );
        await FinanceDatabase.configure(strict);
        expect(
          (await db.rawQuery('PRAGMA secure_delete')).single.values.single,
          1,
        );
        expect(
          (await db.rawQuery('PRAGMA foreign_keys')).single.values.single,
          1,
        );
        expect((await repo.snapshot()).accounts.length, 3);
      } finally {
        await db.close();
      }
    },
  );
  test(
    'Startup diagnostics identify failure without exposing native arguments',
    () {
      final failure = StartupFailure.from(
        PlatformException(
          code: 'sqlite_error',
          message:
              'Queries can be performed using SQLiteDatabase query or rawQuery methods only.',
          details: {'password': 'secret-key', 'sql': 'SELECT private_data'},
        ),
        StartupStep.configureDatabase,
      );
      expect(failure.code, 'SQLITE_QUERY_METHOD');
      expect(failure.report, contains('configureDatabase'));
      expect(failure.report, isNot(contains('secret-key')));
      expect(failure.report, isNot(contains('private_data')));
    },
  );
  testWidgets('Startup failure is visible and supplies a copyable code', (
    tester,
  ) async {
    // A deterministic platform failure: no host filesystem or native plugins.
    var attempts = 0;
    await tester.pumpWidget(
      StartupGate(
        openDatabase: (security, {onStep}) async {
          attempts++;
          onStep?.call(StartupStep.localFiles);
          throw MissingPluginException('Unavailable platform plugin');
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Не удалось открыть финансовый учёт.'), findsOneWidget);
    expect(find.textContaining('Код: ANDROID_PLUGIN'), findsOneWidget);
    expect(find.text('Скопировать код ошибки'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.textContaining('Код: ANDROID_PLUGIN'), findsOneWidget);
  });
}
