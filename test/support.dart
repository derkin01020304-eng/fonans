import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:derk_finance/data/database.dart';
import 'package:derk_finance/data/finance_repository.dart';

Future<SqlFinanceRepository> testRepository({int version = 2}) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      singleInstance: false,
      version: version,
      onConfigure: FinanceDatabase.configure,
      onCreate: (db, v) => FinanceDatabase.migrate(
        db,
        0,
        v,
        (n) => File('assets/schema_v$n.sql').readAsString(),
      ),
    ),
  );
  final repo = SqlFinanceRepository(db);
  await repo.initialize();
  return repo;
}
