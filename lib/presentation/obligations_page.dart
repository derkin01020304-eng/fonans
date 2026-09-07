import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/money.dart';
import '../domain/analytics.dart';
import '../domain/models.dart';
import 'forms.dart';
import 'providers.dart';
import 'widgets.dart';

Future<void> showHistory(
  BuildContext context,
  WidgetRef ref,
  String table,
  String id,
  String currency,
) async {
  final future = ref.read(runtimeProvider).repository.history(table, id);
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.all(24),
      child: FutureBuilder(
        future: future,
        builder: (context, snap) {
          if (snap.hasError) return Text(errorText(snap.error!));
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());
          final rows = snap.data!;
          return ListView(
            children: [
              Text(
                'История платежей',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text('Платежи ещё не записаны.'),
                ),
              for (final row in rows)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    money(
                      row['amountMinor'] as int? ??
                          (row['principalMinor'] as int) +
                              (row['interestMinor'] as int),
                      currency,
                    ),
                  ),
                  subtitle: Text(
                    dateLabel(DateTime.parse(row['date'] as String)) +
                        (table == 'credit_payments'
                            ? ' · проценты ${money(row['interestMinor'] as int, currency)}'
                            : ''),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class ObligationsPage extends ConsumerStatefulWidget {
  const ObligationsPage({super.key});
  @override
  ConsumerState<ObligationsPage> createState() => _ObligationsPageState();
}

class _ObligationsPageState extends ConsumerState<ObligationsPage> {
  int tab = 0;
  @override
  Widget build(BuildContext context) => DataView(
    builder: (context, ref, s) {
      final currency = ref.watch(currencyProvider), now = DateTime.now();
      final b = BalanceSummary(s, currency, now);
      return pageList([
        Panel(
          child: PairMetrics(
            Metric('Я должен', money(b.debt, currency)),
            Metric('Мне должны', money(b.owedToMe, currency)),
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Долги')),
            ButtonSegment(value: 1, label: Text('Кредиты')),
            ButtonSegment(value: 2, label: Text('Платежи')),
          ],
          selected: {tab},
          onSelectionChanged: (v) => setState(() => tab = v.first),
        ),
        const SizedBox(height: 12),
        if (tab == 0) ...[
          SectionTitle(
            'Долги',
            action: 'Добавить',
            onAction: () => debtForm(context, ref, s),
          ),
          if (s.debts.where((d) => d.currency == currency).isEmpty)
            EmptyPanel(
              'Долгов нет',
              'Здесь учитываются оба направления и частичные возвраты.',
              action: 'Добавить долг',
              onAction: () => debtForm(context, ref, s),
            ),
          for (final d in s.debts.where((d) => d.currency == currency))
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _title(
                    context,
                    d.name,
                    () => debtForm(context, ref, s, existing: d),
                    () => _delete(context, 'debts', d.id),
                  ),
                  Text(
                    d.direction == DebtDirection.iOwe
                        ? 'Я должен'
                        : 'Мне должны',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    money(d.remainingMinor, currency),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    'Изначально ${money(d.initialMinor, currency)} · ${d.status(now)}',
                  ),
                  ProgressInfo(
                    value: d.progress,
                    label:
                        'Погашено ${(d.progress * 100).toStringAsFixed(0)}% · до ${dateLabel(d.due)}',
                  ),
                  if (d.comment.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(d.comment),
                    ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (d.remainingMinor > 0)
                        FilledButton.tonal(
                          onPressed: () => repayDebtForm(context, ref, s, d),
                          child: const Text('Внести платёж'),
                        ),
                      TextButton(
                        onPressed: () => showHistory(
                          context,
                          ref,
                          'debt_payments',
                          d.id,
                          currency,
                        ),
                        child: const Text('История'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
        if (tab == 1) ...[
          SectionTitle(
            'Кредиты и рассрочки',
            action: 'Добавить',
            onAction: () => creditForm(context, ref),
          ),
          Panel(
            child: Metric(
              'Все ежемесячные обязательства',
              money(b.monthlyObligations, currency),
            ),
          ),
          if (s.credits.where((c) => c.currency == currency).isEmpty)
            EmptyPanel(
              'Кредитов нет',
              'Платежи, проценты и остатки появятся после добавления кредита.',
              action: 'Добавить кредит',
              onAction: () => creditForm(context, ref),
            ),
          for (final c in s.credits.where((c) => c.currency == currency))
            Builder(
              builder: (context) {
                final estimate = CreditProjection.estimate(c);
                return Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _title(
                        context,
                        c.name,
                        () => creditForm(context, ref, existing: c),
                        () => _delete(context, 'credits', c.id),
                      ),
                      Text(
                        '${c.bank} · ${(c.annualRateBps / 100).toStringAsFixed(2)}% годовых',
                      ),
                      const SizedBox(height: 14),
                      Text(
                        money(c.remainingMinor, currency),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      ProgressInfo(
                        value: c.progress,
                        label:
                            'Погашено ${(c.progress * 100).toStringAsFixed(0)}% основного долга',
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Платёж ${money(c.monthlyMinor, currency)} · ${dateLabel(c.nextPayment)}',
                      ),
                      Text(
                        'Основного долга выплачено: ${money(c.initialMinor - c.remainingMinor, currency)}',
                      ),
                      Text(
                        'Процентов уплачено: ${money(c.paidInterestMinor, currency)}',
                      ),
                      Text(
                        'Срок: ${dateLabel(c.start)} — ${dateLabel(c.end)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        estimate.amortizing
                            ? 'Оценка всей переплаты: ${money(c.paidInterestMinor + estimate.interestMinor, currency)}'
                            : 'Текущий платёж не погашает кредит',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const Text(
                        'Оценка по месячной ставке без страховок и комиссий. Точные суммы — в графике банка.',
                        style: TextStyle(fontSize: 11),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (c.remainingMinor > 0)
                            FilledButton.tonal(
                              onPressed: () =>
                                  repayCreditForm(context, ref, s, c),
                              child: const Text('Погасить'),
                            ),
                          TextButton(
                            onPressed: () => showHistory(
                              context,
                              ref,
                              'credit_payments',
                              c.id,
                              currency,
                            ),
                            child: const Text('История'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
        if (tab == 2) ...[
          SectionTitle(
            'Обязательные платежи',
            action: 'Добавить',
            onAction: () => paymentForm(context, ref, s),
          ),
          if (s.payments.where((p) => p.currency == currency).isEmpty)
            EmptyPanel(
              'Платежи не добавлены',
              'Настройте аренду, подписки, связь или собственный платёж.',
              action: 'Добавить платёж',
              onAction: () => paymentForm(context, ref, s),
            ),
          for (final p in s.payments.where((p) => p.currency == currency))
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _title(
                    context,
                    p.name,
                    () => paymentForm(context, ref, s, existing: p),
                    () => _delete(context, 'recurring_payments', p.id),
                  ),
                  Text(
                    '${money(p.amountMinor, currency)} · до ${dateLabel(p.due)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  ProgressInfo(
                    value: p.reservedMinor / p.amountMinor,
                    label:
                        'Отложено ${money(p.reservedMinor, currency)} · нужно ещё ${money(p.amountMinor - p.reservedMinor, currency)}',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Откладывать ${money(ceilDiv(p.amountMinor - p.reservedMinor, daysLeft(p.due, now)), currency)} в день',
                  ),
                  Text(
                    '${money(ceilDiv(p.amountMinor - p.reservedMinor, daysLeft(p.due, now)) * 7, currency)} в неделю',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (p.due.isBefore(day(now)))
                    Text(
                      'Срок платежа прошёл',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: 14),
                  FilledButton.tonal(
                    onPressed: () async {
                      if (!await confirm(
                        context,
                        'Записать оплату?',
                        'Со счёта будет списано ${money(p.amountMinor, currency)}. Повторяющийся платёж перейдёт на следующий срок.',
                      ))
                        return;
                      try {
                        await ref
                            .read(runtimeProvider)
                            .repository
                            .payRecurring(p.id, p.accountId, DateTime.now());
                        await refresh(ref);
                      } catch (e) {
                        if (context.mounted) message(context, errorText(e));
                      }
                    },
                    child: const Text('Отметить оплаченным'),
                  ),
                ],
              ),
            ),
        ],
      ]);
    },
  );
  Widget _title(
    BuildContext context,
    String name,
    VoidCallback edit,
    VoidCallback delete,
  ) => Row(
    children: [
      Expanded(
        child: Text(name, style: Theme.of(context).textTheme.titleLarge),
      ),
      PopupMenuButton<String>(
        onSelected: (v) => v == 'edit' ? edit() : delete(),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Изменить')),
          PopupMenuItem(value: 'delete', child: Text('Удалить')),
        ],
      ),
    ],
  );
  Future<void> _delete(BuildContext context, String table, String id) async {
    if (!await confirm(
      context,
      'Удалить запись?',
      'Записи с историей платежей сохраняются для корректного учёта.',
    ))
      return;
    try {
      await ref.read(runtimeProvider).repository.deleteEntity(table, id);
      await refresh(ref);
    } catch (e) {
      if (context.mounted) message(context, errorText(e));
    }
  }
}
