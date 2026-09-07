import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/money.dart';
import '../domain/analytics.dart';
import '../domain/models.dart';
import 'charts.dart';
import 'forms.dart';
import 'providers.dart';
import 'widgets.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});
  @override
  Widget build(BuildContext context) => DataView(
    builder: (context, ref, s) {
      final currency = ref.watch(currencyProvider),
          period = ref.watch(periodProvider);
      final now = DateTime.now();
      final first = s.transactions.isEmpty ? null : s.transactions.last.date;
      final window = windowFor(period, now, first: first);
      final summary = Summary(s, window, currency);
      final today = Summary(s, windowFor(Period.day, now), currency);
      final balance = BalanceSummary(s, currency, now);
      final previous = Summary(s, previousWindow(window), currency);
      final change = period == Period.all
          ? null
          : percentageChange(summary.income, previous.income);
      return pageList([
        Text(
          'Деньги под контролем',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        Panel(
          color: forest,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.account_balance_wallet_outlined,
                    color: mint,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Общий баланс',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const Spacer(),
                  Text(currency, style: const TextStyle(color: mint)),
                ],
              ),
              const SizedBox(height: 16),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  money(balance.total, currency),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Можно свободно потратить',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    Text(
                      money(balance.freeToSpend, currency),
                      style: TextStyle(
                        color: balance.freeToSpend < 0 ? coral : mint,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'После накоплений, резервов и ближайших обязательств на 30 дней.',
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ],
          ),
        ),
        Panel(
          child: PairMetrics(
            Metric(
              'Доход сегодня',
              money(today.income, currency),
              color: const Color(0xFF319D7F),
              icon: Icons.south_west,
            ),
            Metric(
              'Расходы сегодня',
              money(today.expense, currency),
              color: const Color(0xFFD16D5B),
              icon: Icons.north_east,
            ),
          ),
        ),
        if (s.transactions.isEmpty)
          EmptyPanel(
            'Начните со своих денег',
            'Укажите начальные остатки на счетах и добавьте первую операцию.',
            action: 'Настроить счета',
            onAction: () => context.push('/accounts'),
          ),
        const SectionTitle('Финансовая сводка'),
        const PeriodSelector(),
        const SizedBox(height: 14),
        Panel(
          child: Column(
            children: [
              PairMetrics(
                Metric('Доход', money(summary.income, currency)),
                Metric('Расход', money(summary.expense, currency)),
              ),
              const Divider(height: 32),
              PairMetrics(
                Metric('Чистый результат', money(summary.net, currency)),
                Metric('Накоплено за период', money(summary.saved, currency)),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  change == null
                      ? 'Для сравнения доходов недостаточно данных'
                      : 'Доход ${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}% к предыдущим ${window.days} дням',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        Panel(
          child: Column(
            children: [
              PairMetrics(
                Metric('Накопления', money(balance.savings, currency)),
                Metric(
                  'Резерв на платежи',
                  money(balance.paymentReserves, currency),
                ),
              ),
              const Divider(height: 32),
              PairMetrics(
                Metric('Я должен', money(balance.debt, currency)),
                Metric('Кредиты', money(balance.credit, currency)),
              ),
            ],
          ),
        ),
        SectionTitle(
          'Ближайшие платежи',
          action: 'Все',
          onAction: () => context.go('/obligations'),
        ),
        if (s.payments.where((p) => p.currency == currency).isEmpty)
          EmptyPanel(
            'Платежи не добавлены',
            'Аренда, связь и подписки будут собраны здесь.',
            action: 'Добавить',
            onAction: () => paymentForm(context, ref, s),
          )
        else
          Panel(
            child: Column(
              children: s.payments
                  .where((p) => p.currency == currency)
                  .take(3)
                  .map(
                    (p) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined),
                      title: Text(p.name),
                      subtitle: Text(dateLabel(p.due)),
                      trailing: Text(money(p.amountMinor, currency)),
                      onTap: () => context.go('/obligations'),
                    ),
                  )
                  .toList(),
            ),
          ),
        SectionTitle(
          'Расходы по категориям',
          action: 'Статистика',
          onAction: () => context.go('/statistics'),
        ),
        ExpenseDonut(categories: summary.categories, currency: currency),
        SectionTitle(
          'Последние операции',
          action: 'Все',
          onAction: () => context.go('/transactions'),
        ),
        for (final t in s.transactions.take(5))
          TransactionTile(
            t,
            onTap: () => transactionForm(context, ref, s, existing: t),
          ),
      ]);
    },
  );
}
