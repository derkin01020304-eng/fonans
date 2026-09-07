import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/money.dart';
import '../data/finance_repository.dart';
import '../domain/models.dart';
import '../services/categorizer.dart';
import '../services/finance_assistant_api.dart';
import 'forms.dart';
import 'providers.dart';
import 'widgets.dart';

class AssistantPage extends ConsumerStatefulWidget {
  const AssistantPage({super.key});
  @override
  ConsumerState<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends ConsumerState<AssistantPage> {
  final input = TextEditingController();
  String? token;
  final messages = <String>[];
  bool busy = false;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DataView(
    builder: (context, ref, s) => pageList([
      const SectionTitle('Дэрк · финансовый помощник'),
      const Text(
        'Локальные команды работают без интернета. Внешний AI можно подключить через MCP в настройках. Данные передаются только после вашего разрешения.',
      ),
      const SizedBox(height: 16),
      if (token == null)
        FilledButton.tonal(
          onPressed: () async {
            if (!await confirm(
              context,
              'Разрешить чтение финансов?',
              'Помощник получит доступ к сводке и операциям на 15 минут. Блокировка приложения отзовёт доступ.',
            ))
              return;
            final grant = ref
                .read(permissionsProvider)
                .grant(LocalFinanceAssistantAPI.readTools);
            setState(() => token = grant.token);
          },
          child: const Text('Разрешить чтение'),
        ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final q in [
            'Сколько я потратил сегодня?',
            'Сколько ушло на еду за неделю?',
            'Какая категория самая большая?',
            'Сколько осталось накопить?',
            'Могу ли потратить 1000?',
          ])
            ActionChip(
              label: Text(q),
              onPressed: busy ? null : () => _send(q, s),
            ),
        ],
      ),
      const SizedBox(height: 20),
      for (final m in messages) Panel(child: SelectableText(m)),
      TextField(
        controller: input,
        decoration: const InputDecoration(
          hintText: 'Добавь расход 450 на еду',
          labelText: 'Сообщение',
        ),
        onSubmitted: busy ? null : (v) => _send(v, s),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: busy ? null : () => _send(input.text, s),
        icon: const Icon(Icons.arrow_upward),
        label: Text(busy ? 'Обработка…' : 'Отправить'),
      ),
      const SizedBox(height: 12),
      const Text(
        'Поддерживаются типовые русские команды. Это локальный разбор текста, без облачной языковой модели.',
        style: TextStyle(fontSize: 12),
      ),
    ]),
  );
  Future<void> _send(String text, FinanceSnapshot s) async {
    if (text.trim().isEmpty || busy) return;
    input.clear();
    setState(() {
      busy = true;
      messages.add('Вы: $text');
    });
    try {
      final q = text.toLowerCase();
      final write = RegExp(r'добав|заработ|^[+-]?\d').hasMatch(q);
      if (write) {
        if (q.contains('долг')) {
          await debtForm(context, ref, s);
          _answer('Запись долга заполняется и подтверждается в форме.');
          return;
        }
        final parsed = QuickEntry.parse(text);
        final name = parsed.kind == TransactionKind.income
            ? 'add_income'
            : 'add_expense';
        if (!await confirm(
          context,
          'Подтвердить запись',
          '${parsed.kind == TransactionKind.income ? 'Доход' : 'Расход'} ${money(parsed.amountMinor)} · ${parsed.category}\nСчёт: ${s.accounts.firstWhere((a) => a.id == preferredAccount(s)).name}',
        ))
          return;
        final grant = ref.read(permissionsProvider).grant({
          name,
        }, lifetime: const Duration(minutes: 1));
        final account = s.accounts.firstWhere(
          (a) => a.id == preferredAccount(s),
        );
        await ref.read(assistantApiProvider).call(name, {
          'requestId': SqlFinanceRepository.uuid.v4(),
          'amountMinor': parsed.amountMinor,
          'accountId': account.id,
          'currency': account.currency,
          'category': parsed.category,
          'comment': parsed.comment,
        }, token: grant.token);
        await refresh(ref);
        _answer(
          'Записано: ${money(parsed.amountMinor, account.currency)} · ${parsed.category}.',
        );
        return;
      }
      if (token == null) {
        _answer('Сначала разрешите чтение финансов.');
        return;
      }
      final api = ref.read(assistantApiProvider),
          currency = ref.read(currencyProvider);
      if (q.contains('накоп') || q.contains('цел')) {
        final data =
            await api.call('get_goals', {'currency': currency}, token: token!)
                as Map;
        final goals = data['goals'] as List;
        _answer(
          goals.isEmpty
              ? 'Целей пока нет.'
              : goals
                    .map(
                      (g) =>
                          '${g['name']}: осталось ${money(g['remainingMinor'] as int, currency)}.',
                    )
                    .join('\n'),
        );
      } else if (q.contains('могу') || q.contains('баланс')) {
        final data =
            await api.call('get_balance', {'currency': currency}, token: token!)
                as Map;
        final free = data['freeToSpendMinor'] as int;
        final amount = RegExp(r'\d+(?:[.,]\d{1,2})?').firstMatch(q);
        final requested = amount == null ? null : parseMoney(amount.group(0)!);
        _answer(
          'Свободный бюджет: ${money(free, currency)}.\n' +
              (requested == null
                  ? 'После резервов и обязательств на 30 дней.'
                  : free >= requested
                  ? 'Эта трата укладывается в бюджет по записанным данным.'
                  : 'Эта трата превышает свободный бюджет по записанным данным.'),
        );
      } else {
        final period = q.contains('сегодня')
            ? 'day'
            : q.contains('недел')
            ? 'week'
            : q.contains('год')
            ? 'year'
            : 'month';
        final data =
            await api.call('get_summary', {
                  'period': period,
                  'currency': currency,
                }, token: token!)
                as Map;
        final categories = Map<String, dynamic>.from(data['categories'] as Map);
        if (q.contains('еда') || q.contains('еду')) {
          _answer(
            'На еду: ${money(categories['Еда'] as int? ?? 0, currency)}.',
          );
        } else if (q.contains('самая') || q.contains('больш')) {
          _answer(
            categories.isEmpty
                ? 'Расходов в периоде нет.'
                : 'Больше всего: ${categories.keys.first} — ${money(categories.values.first as int, currency)}.',
          );
        } else {
          _answer(
            'Доход: ${money(data['incomeMinor'] as int, currency)}\nРасход: ${money(data['expenseMinor'] as int, currency)}\nРезультат: ${money(data['netMinor'] as int, currency)}',
          );
        }
      }
    } catch (e) {
      _answer(errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _answer(String value) {
    if (mounted) setState(() => messages.add('Дэрк: $value'));
  }
}
