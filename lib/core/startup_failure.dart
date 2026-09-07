import 'package:flutter/services.dart';

enum StartupStep {
  locale,
  localFiles,
  androidKey,
  openDatabase,
  configureDatabase,
  migrateDatabase,
  verifyEncryption,
  initializeRecords,
  assistantTools,
}

/// Only a fixed diagnostic code leaves the error boundary. Native exception
/// messages can contain SQL, file paths or arguments and are never displayed.
class StartupFailure {
  const StartupFailure(this.step, this.code);
  final StartupStep step;
  final String code;
  factory StartupFailure.from(Object error, StartupStep step) {
    final text = error.toString().toLowerCase();
    final code = error is MissingPluginException
        ? 'ANDROID_PLUGIN'
        : text.contains('queries can be performed')
        ? 'SQLITE_QUERY_METHOD'
        : text.contains('file is not a database') ||
              text.contains('not a database')
        ? 'DATABASE_KEY_OR_FORMAT'
        : step == StartupStep.androidKey
        ? 'ANDROID_KEYSTORE'
        : step == StartupStep.verifyEncryption
        ? 'CIPHER_CHECK'
        : step == StartupStep.migrateDatabase
        ? 'SCHEMA_MIGRATION'
        : 'STARTUP';
    return StartupFailure(step, code);
  }
  String get report => 'Дэрк Финансы 0.1.1 (2)\nЭтап: ${step.name}\nКод: $code';
}
