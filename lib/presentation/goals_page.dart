import 'package:flutter/material.dart';
import '../core/money.dart';
import '../domain/analytics.dart';
import 'forms.dart';
import 'providers.dart';
import 'widgets.dart';

class GoalsPage extends StatelessWidget {
  const GoalsPage({super.key});
  @override
  Widget build(BuildContext context) => DataView(
    builder: (context, ref, s) {
      final currency = ref.watch(currencyProvider);
      final now = DateTime.now(),
          balance = BalanceSummary(s, currency, DateTime.now());
      final goals = s.goals.where((g) => g.currency == currency).toList();
      final summary = Summary(
        s,
        windowFor(
          ref.watch(periodProvider),
          now,
          first: s.transactions.isEmpty ? null : s.transactions.last.date,
        ),
        currency,
      );
      return pageList([
        Panel(
          color: forest,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Всего в накоплениях',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Text(
                money(balance.savings, currency),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => savingsForm(context, ref, s),
                icon: const Icon(Icons.add),
                label: const Text('Пополнить / снять'),
              ),
            ],
          ),
        ),
        const PeriodSelector(),
        const SizedBox(height: 12),
        Panel(
          child: Metric(
            'Добавлено за период, за вычетом снятий',
            money(summary.saved, currency),
          ),
        ),
        SectionTitle(
          'Мои цели',
          action: 'Создать',
          onAction: () => goalForm(context, ref),
        ),
        if (goals.isEmpty)
          EmptyPanel(
            'На что копим?',
            'Добавьте цель — приложение рассчитает сумму накоплений в день, неделю и месяц.',
            action: 'Создать цель',
            onAction: () => goalForm(context, ref),
          ),
        for (final g in goals)
          Builder(
            builder: (context) {
              final saved = s.goalSaved(g.id),
                  remaining = (g.targetMinor - s.goalSaved(g.id)).clamp(
                    0,
                    g.targetMinor,
                  );
              final daily = ceilDiv(remaining, daysLeft(g.due, now));
              final progress = (saved / g.targetMinor).clamp(0.0, 1.0);
              return Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.flag_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            g.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == 'edit') {
                              await goalForm(context, ref, existing: g);
                              return;
                            }
                            if (await confirm(
                              context,
                              'Удалить цель?',
                              'Деньги останутся на накопительном счёте без привязки к цели.',
                            )) {
                              try {
                                await ref
                                    .read(runtimeProvider)
                                    .repository
                                    .deleteEntity('goals', g.id);
                                await refresh(ref);
                              } catch (e) {
                                if (context.mounted)
                                  message(context, errorText(e));
                              }
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Изменить'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Удалить'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${money(saved, currency)} из ${money(g.targetMinor, currency)}',
                    ),
                    ProgressInfo(
                      value: progress,
                      label:
                          '${(progress * 100).toStringAsFixed(0)}% · Осталось ${money(remaining, currency)}',
                    ),
                    const SizedBox(height: 16),
                    Text('К ${dateLabel(g.due)}'),
                    const SizedBox(height: 8),
                    Text(
                      '${money(daily, currency)} / день · ${money((daily * 7).clamp(0, remaining), currency)} / неделю',
                    ),
                    Text(
                      '${money((daily * 30).clamp(0, remaining), currency)} / 30 дней',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (g.due.isBefore(day(now)) && remaining > 0)
                      Text(
                        'Срок цели прошёл — обновите дату',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    const SizedBox(height: 14),
                    FilledButton.tonal(
                      onPressed: () => savingsForm(context, ref, s, goal: g),
                      child: const Text('Добавить накопление'),
                    ),
                  ],
                ),
              );
            },
          ),
        const SectionTitle('История накоплений'),
        if (s.savings.isEmpty)
          const Text('Пополнения и снятия появятся здесь.'),
        for (final e
            in (s.savings.where((e) => e.currency == currency).toList()
                  ..sort((a, b) => b.date.compareTo(a.date)))
                .take(30))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.savings_outlined),
            title: Text(
              s.goals.where((g) => g.id == e.goalId).firstOrNull?.name ??
                  'Без цели',
            ),
            subtitle: Text(dateLabel(e.date)),
            trailing: Text(money(e.amountMinor, currency)),
          ),
      ]);
    },
  );
}
