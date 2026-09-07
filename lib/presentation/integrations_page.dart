import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/money.dart';
import '../domain/models.dart';
import '../integrations/banks/bank_provider.dart';
import '../integrations/banks/mock_bank_provider.dart';
import '../integrations/banks/oauth_bank_provider.dart';
import '../integrations/banks/bank_sync.dart';
import '../services/android_services.dart';
import '../services/categorizer.dart';
import '../services/statement_import.dart';
import 'editor.dart';
import 'forms.dart';
import 'providers.dart';
import 'widgets.dart';

class IntegrationsPage extends ConsumerStatefulWidget {
  const IntegrationsPage({super.key});
  @override
  ConsumerState<IntegrationsPage> createState() => _IntegrationsPageState();
}

class _IntegrationsPageState extends ConsumerState<IntegrationsPage> {
  final providers = <BankProvider>[MockBankProvider()];
  StreamSubscription<dynamic>? subscription;
  bool busy = false, notificationImport = false;
  String? status;
  String? selectedAccount;
  ImportPreview? preview;
  int previewLimit = 50;
  final excludedRows = <String>{};
  final packages = TextEditingController();
  final seenNotifications = <String>{};
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final security = ref.read(runtimeProvider).security;
    final raw = await security.storage.read(key: 'oauth_provider_config');
    if (raw != null) {
      try {
        final c = jsonDecode(raw) as Map<String, dynamic>;
        final provider = OAuthBankProvider(
          OAuthBankConfig(
            id: c['id'] as String,
            name: c['name'] as String,
            clientId: c['clientId'] as String,
            discoveryUrl: c['discoveryUrl'] as String,
            gateway: Uri.parse(c['gateway'] as String),
            scopes: (c['scopes'] as List).cast<String>(),
          ),
          security.storage,
        );
        if (mounted) setState(() => providers.add(provider));
      } catch (_) {
        if (mounted)
          setState(
            () => status = 'Сохранённую конфигурацию банка нужно проверить',
          );
      }
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    packages.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      status = null;
    });
    try {
      await action();
      await refresh(ref);
    } catch (e) {
      if (mounted) setState(() => status = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DataView(
    builder: (context, ref, s) {
      selectedAccount ??= preferredAccount(s);
      if (!s.accounts.any((a) => a.id == selectedAccount))
        selectedAccount = preferredAccount(s);
      return pageList([
        const SectionTitle('Банки'),
        const Text(
          'Подключение через официальный OAuth2. Пароль от банка остаётся у банка. Синхронизация запускается вручную.',
        ),
        const SizedBox(height: 16),
        if (status != null) Panel(child: Text(status!)),
        if (busy) const LinearProgressIndicator(),
        for (final provider in providers)
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: busy
                          ? null
                          : () => _run(() async {
                              if (provider.id == 'mock' &&
                                  !await confirm(
                                    context,
                                    'Подключить демо-банк?',
                                    'Будет создан отдельный тестовый счёт и две тестовые операции. Это вымышленные деньги.',
                                  ))
                                return;
                              await provider.authorize();
                              final result = await BankSyncService(
                                ref.read(runtimeProvider).repository,
                              ).sync(provider);
                              if (mounted)
                                setState(
                                  () => status =
                                      'Добавлено ${result.added}; пропущено дублей ${result.duplicates}; уточнить ${result.review}.',
                                );
                            }),
                      child: const Text('Подключить'),
                    ),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => _run(() async {
                              if (provider.id == 'mock' &&
                                  !await confirm(
                                    context,
                                    'Обновить демо-банк?',
                                    'Выполняется синхронизация вымышленных операций тестового счёта.',
                                  ))
                                return;
                              final result = await BankSyncService(
                                ref.read(runtimeProvider).repository,
                              ).sync(provider);
                              if (mounted)
                                setState(
                                  () => status =
                                      'Добавлено ${result.added}; дубли ${result.duplicates}.',
                                );
                            }),
                      child: const Text('Обновить'),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => _run(() async {
                              if (!await confirm(
                                context,
                                'Отключить банк?',
                                'Доступ будет отозван. Уже импортированные операции останутся.',
                              ))
                                return;
                              await provider.disconnect();
                              await ref
                                  .read(runtimeProvider)
                                  .repository
                                  .db
                                  .update(
                                    'bank_connections',
                                    {'status': 'disconnected'},
                                    where: 'id = ?',
                                    whereArgs: [provider.id],
                                  );
                              if (mounted)
                                setState(() => status = 'Банк отключён');
                            }),
                      child: const Text('Отключить'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        TextButton.icon(
          onPressed: busy ? null : _configure,
          icon: const Icon(Icons.add_link),
          label: const Text('Настроить официальный провайдер'),
        ),
        const SectionTitle('Импорт выписки'),
        DropdownButtonFormField<String>(
          initialValue: selectedAccount,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Счёт выписки'),
          items: accountChoices(s).entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: busy
              ? null
              : (v) => setState(() {
                  selectedAccount = v;
                  preview = null;
                }),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: busy
              ? null
              : () => _run(() async {
                  final picked = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['csv', 'xlsx', 'ofx', 'qfx', 'pdf'],
                    withData: true,
                  );
                  if (picked == null) return;
                  final file = picked.files.single;
                  if (file.size > StatementImportService.maxBytes)
                    throw const FormatException('Максимум 10 МБ');
                  final bytes =
                      file.bytes ?? await File(file.path!).readAsBytes();
                  final result =
                      await StatementImportService(
                        ref.read(runtimeProvider).repository,
                      ).preview(
                        file.name,
                        bytes,
                        s.accounts.firstWhere((a) => a.id == selectedAccount),
                      );
                  if (mounted)
                    setState(() {
                      preview = result;
                      previewLimit = 50;
                      excludedRows.clear();
                    });
                }),
          icon: const Icon(Icons.file_download_outlined),
          label: const Text('Выбрать CSV / XLSX / OFX'),
        ),
        const SizedBox(height: 10),
        const Text(
          'CSV — UTF-8. PDF: нужен адаптер формата конкретного банка. Перед импортом проверьте собственные переводы и возвраты.',
          style: TextStyle(fontSize: 12),
        ),
        if (preview != null) ...[
          const SectionTitle('Предварительный просмотр'),
          const Text(
            'Нажмите строку для правки. Снимите флажок, чтобы пропустить её, например вторую сторону собственного перевода.',
          ),
          Text(
            'Выбрано: ${preview!.rows.where((r) => !r.duplicate && !excludedRows.contains(r.transaction.id)).length} · Дублей: ${preview!.rows.where((r) => r.duplicate).length}',
          ),
          for (final error in preview!.errors.take(20))
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          for (final row in preview!.rows.take(previewLimit))
            ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: row.duplicate || busy
                  ? null
                  : () => _editPreviewRow(row, s),
              trailing: row.duplicate
                  ? const Icon(Icons.check)
                  : Checkbox(
                      value: !excludedRows.contains(row.transaction.id),
                      onChanged: busy
                          ? null
                          : (v) => setState(() {
                              if (v == true) {
                                excludedRows.remove(row.transaction.id);
                              } else {
                                excludedRows.add(row.transaction.id);
                              }
                            }),
                    ),
              title: Text(
                '${row.transaction.merchant} · ${money(row.transaction.amountMinor, row.transaction.currency)}',
              ),
              subtitle: Text(
                '${row.transaction.kind.name} · ${dateLabel(row.transaction.date)} · ${row.duplicate ? 'Уже есть' : row.transaction.category}',
              ),
            ),
          if (preview!.rows.length > previewLimit)
            TextButton(
              onPressed: () => setState(() => previewLimit += 50),
              child: const Text('Показать ещё 50 строк'),
            ),
          FilledButton(
            onPressed: busy
                ? null
                : () => _run(() async {
                    if (!await confirm(
                      context,
                      'Импортировать операции?',
                      'Будут записаны новые строки. Повторные операции пропускаются. Ошибочные строки не импортируются.',
                    ))
                      return;
                    final count =
                        await StatementImportService(
                          ref.read(runtimeProvider).repository,
                        ).commit(
                          preview!.rows
                              .where(
                                (r) => !excludedRows.contains(r.transaction.id),
                              )
                              .toList(),
                        );
                    if (mounted)
                      setState(() {
                        preview = null;
                        status = 'Импортировано: $count';
                      });
                  }),
            child: const Text('Подтвердить импорт'),
          ),
        ],
        const SectionTitle('Уведомления банка · дополнительно'),
        const Text(
          'Только с отдельным разрешением Android и вашим подтверждением каждой операции. Работает, пока этот экран открыт. Коды входа и пароли отбрасываются.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: packages,
          decoration: const InputDecoration(
            labelText: 'Имена пакетов банков через запятую',
            hintText: 'Из документации вашего банка',
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: notificationImport,
          title: const Text('Принимать кандидаты операций'),
          onChanged: (v) async {
            try {
              final names = packages.text
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
              if (v && names.isEmpty)
                throw const FormatException('Укажите пакет приложения банка');
              if (v &&
                  !await confirm(
                    context,
                    'Разрешить чтение банковских уведомлений?',
                    'Android выдаёт доступ к уведомлениям. Приложение обрабатывает только выбранные пакеты, не сохраняет исходный текст и предлагает подтвердить сумму.',
                  ))
                return;
              await ref
                  .read(runtimeProvider)
                  .android
                  .configureNotificationImport(names, v);
              await subscription?.cancel();
              if (v) {
                subscription = AndroidServices.notifications
                    .receiveBroadcastStream()
                    .listen((raw) async {
                      if (!mounted || !ref.read(permissionsProvider).unlocked)
                        return;
                      final data = Map<String, dynamic>.from(raw as Map);
                      final id = data['id'] as String;
                      if (!seenNotifications.add(id)) return;
                      final snapshot = await ref.read(snapshotProvider.future);
                      if (!mounted) return;
                      await transactionForm(
                        context,
                        ref,
                        snapshot,
                        quick: QuickEntry(
                          data['income'] == true
                              ? TransactionKind.income
                              : TransactionKind.expense,
                          data['amountMinor'] as int,
                          'Прочее',
                          'Из уведомления: ${data['package']}',
                        ),
                      );
                    }, onError: (_) {});
                await ref
                    .read(runtimeProvider)
                    .android
                    .openNotificationAccess();
              }
              if (mounted) setState(() => notificationImport = v);
            } catch (e) {
              if (context.mounted) message(context, errorText(e));
            }
          },
        ),
      ]);
    },
  );
  Future<void> _editPreviewRow(ImportRow row, FinanceSnapshot snapshot) async {
    final t = row.transaction;
    final incoming =
        t.kind == TransactionKind.income ||
        (t.kind == TransactionKind.transfer &&
            t.toAccountId == selectedAccount);
    await showEditor(
      context,
      title: 'Проверить операцию выписки',
      note:
          'Для собственного перевода выберите другой счёт. Входящая операция поступает с него, исходящая — переводится на него. Вторую сторону уже учтённого перевода исключите флажком.',
      fields: [
        FieldSpec(
          'kind',
          'Тип',
          kind: InputKind.choice,
          initial: t.kind.name,
          choices: const {
            'income': 'Доход',
            'expense': 'Расход',
            'transfer': 'Перевод',
          },
        ),
        FieldSpec(
          'to',
          'Другой собственный счёт',
          kind: InputKind.choice,
          initial: t.kind == TransactionKind.transfer
              ? (incoming ? t.accountId : t.toAccountId ?? '')
              : '',
          choices: {'': 'Не выбран', ...accountChoices(snapshot)},
        ),
        FieldSpec(
          'category',
          'Категория',
          kind: InputKind.choice,
          initial: t.category,
          choices: {
            for (final c in {...expenseCategories, t.category}) c: c,
          },
        ),
        FieldSpec(
          'comment',
          'Комментарий',
          initial: t.comment,
          required: false,
        ),
      ],
      onSave: (values) async {
        final transfer = values['kind'] == 'transfer';
        if (transfer &&
            (values['to'] == '' || values['to'] == selectedAccount)) {
          throw ArgumentError('Выберите другой собственный счёт');
        }
        final edited = FinanceTransaction.fromJson({
          ...t.toJson(),
          'kind': values['kind'],
          'accountId': transfer && incoming ? values['to'] : selectedAccount,
          'toAccountId': transfer
              ? (incoming ? selectedAccount : values['to'])
              : null,
          'category': transfer ? 'Переводы' : values['category'],
          'comment': values['comment'],
          'needsReview': 0,
        });
        final rows = preview!.rows
            .map(
              (r) => identical(r, row)
                  ? ImportRow(transaction: edited, rowNumber: r.rowNumber)
                  : r,
            )
            .toList();
        if (mounted)
          setState(() => preview = ImportPreview(rows, preview!.errors));
      },
    );
  }

  Future<void> _configure() => showEditor(
    context,
    title: 'Официальный API банка',
    note:
        'Нужны зарегистрированный OAuth-клиент и адаптер API. Client ID — публичный идентификатор, не секрет. Конфигурацию выдаёт разработчик интеграции.',
    fields: const [
      FieldSpec('id', 'ID провайдера'),
      FieldSpec('name', 'Название'),
      FieldSpec('clientId', 'OAuth Client ID'),
      FieldSpec('discoveryUrl', 'HTTPS Discovery URL'),
      FieldSpec('gateway', 'HTTPS API адаптера, с / на конце'),
      FieldSpec(
        'scopes',
        'Scopes через пробел',
        initial: 'accounts transactions',
      ),
    ],
    onSave: (v) async {
      final c = {
        ...v,
        'scopes': (v['scopes'] as String)
            .split(' ')
            .where((s) => s.isNotEmpty)
            .toList(),
      };
      if (c['id'] == 'mock') throw ArgumentError('ID mock зарезервирован');
      final runtime = ref.read(runtimeProvider);
      final provider = OAuthBankProvider(
        OAuthBankConfig(
          id: c['id'] as String,
          name: c['name'] as String,
          clientId: c['clientId'] as String,
          discoveryUrl: c['discoveryUrl'] as String,
          gateway: Uri.parse(c['gateway'] as String),
          scopes: (c['scopes'] as List).cast<String>(),
        ),
        runtime.security.storage,
      );
      await runtime.security.storage.write(
        key: 'oauth_provider_config',
        value: jsonEncode(c),
      );
      if (mounted)
        setState(() {
          providers.removeWhere((p) => p.id != 'mock');
          providers.add(provider);
        });
    },
  );
}
