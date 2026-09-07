import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/analytics.dart';
import '../domain/models.dart';
import '../services/backup_export.dart';
import '../services/categorizer.dart';
import 'providers.dart';
import 'widgets.dart';

Future<void> saveBytes(String name, Uint8List bytes) async {
  await FilePicker.platform.saveFile(
    dialogTitle: 'Сохранить файл',
    fileName: name,
    bytes: bytes,
  );
}

class ExportsPage extends ConsumerStatefulWidget {
  const ExportsPage({super.key});
  @override
  ConsumerState<ExportsPage> createState() => _ExportsPageState();
}

class _ExportsPageState extends ConsumerState<ExportsPage> {
  String format = 'csv', category = '';
  bool all = true, busy = false;
  @override
  Widget build(BuildContext context) => DataView(
    builder: (context, ref, s) {
      return pageList([
        const SectionTitle('Экспорт операций'),
        const Text(
          'Экспорт CSV, XLSX и JSON содержит открытые финансовые данные. Для защищённого переноса используйте резервную копию.',
        ),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          initialValue: format,
          decoration: const InputDecoration(labelText: 'Формат'),
          items: const ['csv', 'xlsx', 'json']
              .map(
                (v) => DropdownMenuItem(value: v, child: Text(v.toUpperCase())),
              )
              .toList(),
          onChanged: (v) => setState(() => format = v!),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: category,
          decoration: const InputDecoration(labelText: 'Категория'),
          items:
              {
                    '': 'Все категории',
                    for (final c in {
                      ...expenseCategories,
                      ...s.transactions.map((t) => t.category),
                    })
                      c: c,
                  }.entries
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
          onChanged: (v) => setState(() => category = v!),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Всё время'),
          value: all,
          onChanged: (v) => setState(() => all = v),
        ),
        if (!all) ...[const PeriodSelector(), const SizedBox(height: 12)],
        FilledButton.icon(
          onPressed: busy
              ? null
              : () async {
                  setState(() => busy = true);
                  try {
                    final list = ExportService.filter(
                      s,
                      category: category.isEmpty ? null : category,
                      window: all
                          ? null
                          : windowFor(ref.read(periodProvider), DateTime.now()),
                      currency: ref.read(currencyProvider),
                    );
                    await saveBytes(
                      'derk_transactions.$format',
                      ExportService.export(list, format),
                    );
                  } catch (e) {
                    if (context.mounted) message(context, errorText(e));
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          icon: const Icon(Icons.file_upload_outlined),
          label: Text(busy ? 'Подготовка…' : 'Сохранить экспорт'),
        ),
        const SectionTitle('Зашифрованная резервная копия'),
        const Text(
          'Включает операции, счета, долги, кредиты, цели и правила категорий. Банковские токены, PIN и разрешения AI не переносятся.',
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: busy ? null : () => _backup(s),
          icon: const Icon(Icons.lock_outline),
          label: const Text('Создать резервную копию'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy ? null : _restore,
          icon: const Icon(Icons.restore),
          label: const Text('Восстановить из копии'),
        ),
      ]);
    },
  );
  Future<String?> _password({bool create = false}) async {
    final first = TextEditingController(), second = TextEditingController();
    String? error;
    final route = DialogRoute<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(create ? 'Пароль резервной копии' : 'Расшифровать копию'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: first,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Пароль, не менее 12 символов',
                ),
              ),
              if (create) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: second,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Повторите пароль',
                  ),
                ),
              ],
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                if (first.text.length < 12 ||
                    (create && first.text != second.text)) {
                  setLocal(
                    () => error = 'Проверьте длину и совпадение паролей',
                  );
                  return;
                }
                Navigator.pop(context, first.text);
              },
              child: const Text('Продолжить'),
            ),
          ],
        ),
      ),
    );
    final result = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    first.dispose();
    second.dispose();
    return result;
  }

  Future<void> _backup(FinanceSnapshot s) async {
    final password = await _password(create: true);
    if (password == null || !mounted) return;
    setState(() => busy = true);
    try {
      final data = await ref.read(runtimeProvider).repository.exportBackup();
      final bytes = await BackupCipher().encrypt(data, password);
      await saveBytes(
        'derk_${DateTime.now().toIso8601String().substring(0, 10)}.dfbackup',
        bytes,
      );
    } catch (e) {
      if (mounted) message(context, errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _restore() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (picked == null || !mounted) return;
    final file = picked.files.single;
    if (file.size > 50 * 1024 * 1024) {
      message(context, 'Копия слишком большая');
      return;
    }
    final password = await _password();
    if (password == null || !mounted) return;
    setState(() => busy = true);
    try {
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final data = await BackupCipher().decrypt(bytes, password);
      if (!mounted) return;
      if (!await confirm(
        context,
        'Заменить текущие данные?',
        'Копия проверена и расшифрована. Все текущие финансовые записи будут заменены её содержимым.',
      ))
        return;
      ref.read(permissionsProvider).revokeAll();
      await ref.read(runtimeProvider).repository.restoreBackup(data);
      await refresh(ref);
      if (mounted) message(context, 'Данные восстановлены');
    } catch (e) {
      if (mounted) message(context, errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
