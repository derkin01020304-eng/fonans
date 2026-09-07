import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;
import '../core/startup_failure.dart';
import '../services/security.dart';

class FinanceDatabase {
  static const version = 2;
  static Future<void> migrate(
    DatabaseExecutor db,
    int oldVersion,
    int newVersion,
    Future<String> Function(int) schema,
  ) async {
    for (var version = oldVersion + 1; version <= newVersion; version++) {
      for (final statement in (await schema(version)).split(';')) {
        if (statement.trim().isNotEmpty) await db.execute(statement);
      }
    }
  }

  /// Android execSQL cannot execute a statement that returns a result row.
  /// secure_delete = ON returns that row, so it must use the query channel.
  static Future<void> configure(DatabaseExecutor db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    await db.rawQuery('PRAGMA secure_delete = ON');
    final foreignKeys = await db.rawQuery('PRAGMA foreign_keys');
    final secureDelete = await db.rawQuery('PRAGMA secure_delete');
    if (foreignKeys.isEmpty ||
        foreignKeys.first.values.first != 1 ||
        secureDelete.isEmpty ||
        secureDelete.first.values.first != 1) {
      throw StateError('Database configuration check failed');
    }
  }

  static Future<Database> open(
    SecurityService security, {
    void Function(StartupStep)? onStep,
  }) async {
    onStep?.call(StartupStep.localFiles);
    final folder = await getApplicationSupportDirectory();
    onStep?.call(StartupStep.androidKey);
    final key = await security.databaseKey();
    return openEncrypted(
      p.join(folder.path, 'finance.db'),
      key,
      onStep: onStep,
    );
  }

  /// Also used by the native regression test with its own temporary file/key.
  static Future<Database> openEncrypted(
    String path,
    String key, {
    void Function(StartupStep)? onStep,
  }) async {
    Future<String> schema(int version) =>
        rootBundle.loadString('assets/schema_v$version.sql');
    onStep?.call(StartupStep.openDatabase);
    final db = await cipher.openDatabase(
      path,
      password: key,
      version: version,
      onConfigure: (db) async {
        onStep?.call(StartupStep.configureDatabase);
        await configure(db);
      },
      onCreate: (db, version) async {
        onStep?.call(StartupStep.migrateDatabase);
        await migrate(db, 0, version, schema);
      },
      onUpgrade: (db, old, version) async {
        onStep?.call(StartupStep.migrateDatabase);
        await migrate(db, old, version, schema);
      },
    );
    try {
      onStep?.call(StartupStep.verifyEncryption);
      final cipherVersion = await db.rawQuery('PRAGMA cipher_version');
      if (cipherVersion.isEmpty) throw StateError('SQLCipher unavailable');
      return db;
    } catch (_) {
      await db.close();
      rethrow;
    }
  }
}
