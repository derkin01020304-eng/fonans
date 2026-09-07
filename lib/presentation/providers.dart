import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/finance_repository.dart';
import '../domain/models.dart';
import '../services/android_services.dart';
import '../services/security.dart';
import '../services/finance_assistant_api.dart';
import '../integrations/mcp/mcp_server.dart';
import '../integrations/mcp/permissions.dart';

class AppRuntime {
  AppRuntime(this.repository, this.security, this.tools);
  final SqlFinanceRepository repository;
  final SecurityService security;
  final List<Map<String, dynamic>> tools;
  final AndroidServices android = AndroidServices();
}

final runtimeProvider = Provider<AppRuntime>(
  (ref) => throw StateError('Runtime is required'),
);
final snapshotProvider = FutureProvider<FinanceSnapshot>(
  (ref) => ref.watch(runtimeProvider).repository.snapshot(),
);
final themeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final currencyProvider = StateProvider<String>((ref) => 'RUB');
final periodProvider = StateProvider<Period>((ref) => Period.month);
final remindersProvider = StateProvider<bool>((ref) => false);
final permissionsProvider = Provider<PermissionService>(
  (ref) => PermissionService(),
);
final assistantApiProvider = Provider<LocalFinanceAssistantAPI>((ref) {
  final runtime = ref.watch(runtimeProvider);
  return LocalFinanceAssistantAPI(
    runtime.repository,
    ref.watch(permissionsProvider),
    runtime.tools,
    onWrite: () {
      ref.invalidate(snapshotProvider);
      runtime.repository
          .snapshot()
          .then(
            (s) => runtime.android.reschedule(
              s,
              enabled: ref.read(remindersProvider),
            ),
          )
          .catchError((_) {});
    },
  );
});
final mcpProvider = Provider<FinanceMcpServer>(
  (ref) => FinanceMcpServer(
    ref.watch(assistantApiProvider),
    ref.watch(permissionsProvider),
  ),
);

String errorText(Object e) => e is FormatException
    ? e.message
    : e is ArgumentError
    ? e.message.toString()
    : e is StateError
    ? e.message
    : 'Не удалось выполнить действие. Данные не изменены.';
void message(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<void> refresh(WidgetRef ref) async {
  ref.invalidate(snapshotProvider);
  final s = await ref.read(snapshotProvider.future);
  try {
    await ref
        .read(runtimeProvider)
        .android
        .reschedule(s, enabled: ref.read(remindersProvider));
  } catch (_) {
    /* In-app upcoming payments remain available if OS scheduling fails. */
  }
}

Future<bool> confirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    ) ??
    false;

class DataView extends ConsumerWidget {
  const DataView({super.key, required this.builder});
  final Widget Function(BuildContext, WidgetRef, FinanceSnapshot) builder;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(snapshotProvider)
      .when(
        data: (s) => builder(context, ref, s),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: 12),
                Text(errorText(e), textAlign: TextAlign.center),
                TextButton(
                  onPressed: () => ref.invalidate(snapshotProvider),
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
      );
}
