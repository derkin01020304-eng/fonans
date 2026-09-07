import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../services/finance_assistant_api.dart';
import 'editor.dart';
import 'providers.dart';
import 'widgets.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final scopes = <String>{...LocalFinanceAssistantAPI.readTools};
  String? token;
  DateTime? expiry;
  @override
  Widget build(BuildContext context) => DataView(
    builder: (context, ref, s) => pageList([
      const SectionTitle('Настройки'),
      Panel(
        child: Column(
          children: [
            DropdownButtonFormField<ThemeMode>(
              initialValue: ref.watch(themeProvider),
              decoration: const InputDecoration(labelText: 'Тема'),
              items: const [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text('Как на устройстве'),
                ),
                DropdownMenuItem(
                  value: ThemeMode.light,
                  child: Text('Светлая'),
                ),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Тёмная')),
              ],
              onChanged: (v) async {
                ref.read(themeProvider.notifier).state = v!;
                await ref
                    .read(runtimeProvider)
                    .security
                    .storage
                    .write(key: 'theme', value: v.name);
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: ref.watch(currencyProvider),
              decoration: const InputDecoration(labelText: 'Валюта сводок'),
              items: const [
                'RUB',
                'USD',
                'EUR',
              ].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) async {
                ref.read(currencyProvider.notifier).state = v!;
                await ref
                    .read(runtimeProvider)
                    .security
                    .storage
                    .write(key: 'currency', value: v);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: ref.watch(remindersProvider),
              title: const Text('Напоминания'),
              subtitle: const Text(
                'Не более одного в день, без сумм на экране блокировки.',
              ),
              onChanged: (v) async {
                try {
                  if (v &&
                      !await ref
                          .read(runtimeProvider)
                          .android
                          .requestReminders())
                    return;
                  ref.read(remindersProvider.notifier).state = v;
                  await ref
                      .read(runtimeProvider)
                      .security
                      .storage
                      .write(key: 'reminders', value: '$v');
                  await ref
                      .read(runtimeProvider)
                      .android
                      .reschedule(s, enabled: v);
                } catch (e) {
                  if (context.mounted)
                    message(context, 'Android не разрешил напоминания');
                }
              },
            ),
          ],
        ),
      ),
      Panel(
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Счета и баланс'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/accounts'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sync),
              title: const Text('Банки и импорт'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/integrations'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.save_alt),
              title: const Text('Экспорт и резервные копии'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/exports'),
            ),
          ],
        ),
      ),
      const SectionTitle('Безопасность'),
      const Text(
        'SQLite с SQLCipher. Ключ защищён Android Keystore. Блокировка при уходе в фон и после 2 минут бездействия.',
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () => showEditor(
          context,
          title: 'Сменить PIN приложения',
          fields: const [
            FieldSpec('old', 'Текущий PIN', kind: InputKind.secret),
            FieldSpec('new', 'Новый PIN: 6–12 цифр', kind: InputKind.secret),
            FieldSpec('repeat', 'Повторите PIN', kind: InputKind.secret),
          ],
          onSave: (v) async {
            final security = ref.read(runtimeProvider).security;
            if (!await security.verifyPin(v['old'] as String))
              throw StateError('Неверный текущий PIN');
            if (v['new'] != v['repeat'])
              throw ArgumentError('PIN не совпадают');
            await security.setPin(v['new'] as String);
          },
        ),
        icon: const Icon(Icons.password),
        label: const Text('Сменить PIN'),
      ),
      const SectionTitle('Подключение AI через MCP'),
      const Text(
        'Локальный сервер доступен с компьютера через USB и adb. Включается вручную. Выберите разрешения:',
      ),
      const SizedBox(height: 12),
      for (final tool in ref.read(runtimeProvider).tools)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: scopes.contains(tool['name']),
          title: Text(tool['name'] as String),
          subtitle: Text(
            LocalFinanceAssistantAPI.readTools.contains(tool['name'])
                ? 'Чтение'
                : 'Запись данных',
          ),
          onChanged: (v) => setState(() {
            if (v == true) {
              scopes.add(tool['name'] as String);
            } else {
              scopes.remove(tool['name']);
            }
          }),
        ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: () async {
          try {
            if (scopes.isEmpty)
              throw ArgumentError('Выберите хотя бы одно разрешение');
            if (!await confirm(
              context,
              'Выдать доступ на 15 минут?',
              'Выбрано инструментов: ${scopes.length}. ${scopes.any(LocalFinanceAssistantAPI.writeTools.contains) ? 'Токен позволит AI выполнять выбранные записи без отдельного подтверждения каждой.' : 'Разрешено только чтение.'}',
            ))
              return;
            final server = ref.read(mcpProvider);
            await server.start();
            final grant = ref.read(permissionsProvider).grant(scopes);
            setState(() {
              token = grant.token;
              expiry = grant.expires;
            });
          } catch (e) {
            if (context.mounted) message(context, errorText(e));
          }
        },
        icon: const Icon(Icons.link),
        label: const Text('Включить и выдать токен'),
      ),
      if (token != null) ...[
        const SizedBox(height: 14),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Токен до ${expiry!.hour.toString().padLeft(2, '0')}:${expiry!.minute.toString().padLeft(2, '0')}',
              ),
              const SizedBox(height: 8),
              SelectableText(token!),
              const SizedBox(height: 8),
              const Text(
                'Адрес: http://127.0.0.1:8765/mcp',
                style: TextStyle(fontSize: 12),
              ),
              const Text(
                'После блокировки или ухода в фон токен недействителен.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ],
      OutlinedButton(
        onPressed: () async {
          await ref.read(mcpProvider).stop();
          if (mounted)
            setState(() {
              token = null;
              expiry = null;
            });
        },
        child: const Text('Остановить сервер и отозвать доступ'),
      ),
      const SectionTitle('Демонстрационные данные'),
      Text(
        s.demo
            ? 'Включён демо-режим. Все суммы вымышлены.'
            : 'Демо доступно в пустом учёте. Оно содержит 42 дня вымышленных операций.',
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () async {
          try {
            if (!await confirm(
              context,
              s.demo ? 'Выйти из демо?' : 'Загрузить демо?',
              s.demo
                  ? 'Данные и изменения демо будут удалены. Восстановится учёт до загрузки демо.'
                  : 'Будут загружены вымышленные счета, операции и цели.',
            ))
              return;
            if (s.demo) {
              await ref.read(runtimeProvider).repository.clearDemo();
            } else {
              await ref.read(runtimeProvider).repository.seedDemo();
            }
            await refresh(ref);
          } catch (e) {
            if (context.mounted) message(context, errorText(e));
          }
        },
        child: Text(s.demo ? 'Выйти из демо' : 'Загрузить демо'),
      ),
      const SizedBox(height: 24),
      const Text(
        'Дэрк Финансы · 0.1.1\nОфлайн MVP · Данные принадлежат вам',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12),
      ),
    ]),
  );
}
