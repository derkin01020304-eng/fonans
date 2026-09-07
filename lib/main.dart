import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'core/startup_failure.dart';
import 'data/database.dart';
import 'data/finance_repository.dart';
import 'presentation/app.dart';
import 'presentation/providers.dart';
import 'services/security.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StartupGate());
}

/// One startup attempt at a time; retry never deletes the database or its key.
typedef OpenFinanceDatabase =
    Future<Database> Function(
      SecurityService security, {
      void Function(StartupStep)? onStep,
    });

class StartupGate extends StatefulWidget {
  const StartupGate({super.key, this.openDatabase = FinanceDatabase.open});
  final OpenFinanceDatabase openDatabase;
  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  bool busy = false;
  AppRuntime? runtime;
  StartupFailure? failure;
  StartupStep step = StartupStep.locale;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (busy) return;
    setState(() {
      busy = true;
      failure = null;
      step = StartupStep.locale;
    });
    Database? db;
    try {
      await initializeDateFormatting('ru');
      final security = SecurityService();
      db = await widget.openDatabase(security, onStep: (value) => step = value);
      step = StartupStep.initializeRecords;
      final repository = SqlFinanceRepository(db);
      await repository.initialize();
      step = StartupStep.assistantTools;
      final tools =
          (jsonDecode(await rootBundle.loadString('assets/mcp_tools.json'))
                  as List)
              .map((t) => Map<String, dynamic>.from(t as Map))
              .toList();
      if (!mounted) {
        await db.close();
        return;
      }
      setState(() => runtime = AppRuntime(repository, security, tools));
    } catch (error) {
      // Do not log raw native messages: they may contain SQL or key arguments.
      if (db != null && db.isOpen) {
        try {
          await db.close();
        } catch (_) {}
      }
      if (mounted) setState(() => failure = StartupFailure.from(error, step));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = runtime;
    if (ready != null) {
      return ProviderScope(
        overrides: [runtimeProvider.overrideWithValue(ready)],
        child: const FinanceApp(),
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF237B60),
      ),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (busy) ...[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 20),
                      const Text('Открываем финансовый учёт…'),
                    ] else ...[
                      const Icon(Icons.lock_outline, size: 48),
                      const SizedBox(height: 20),
                      const Text(
                        'Не удалось открыть финансовый учёт.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 22),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Данные не удалены. Отправьте код ошибки для исправления. Скриншоты разрешены.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      SelectableText(
                        failure?.report ?? '',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _start,
                        child: const Text('Повторить'),
                      ),
                      TextButton.icon(
                        onPressed: () => Clipboard.setData(
                          ClipboardData(text: failure?.report ?? ''),
                        ),
                        icon: const Icon(Icons.copy),
                        label: const Text('Скопировать код ошибки'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
