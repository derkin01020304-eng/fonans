import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/money.dart';
import '../domain/analytics.dart';
import 'charts.dart';
import 'providers.dart';
import 'widgets.dart';

class StatisticsPage extends ConsumerStatefulWidget {
  const StatisticsPage({super.key});
  @override
  ConsumerState<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends ConsumerState<StatisticsPage> {
  String metric = 'income', grouping = 'day';
  @override
  Widget build(BuildContext context) => DataView(
    builder: (context, ref, s) {
      final currency = ref.watch(currencyProvider);
      final window = windowFor(
        ref.watch(periodProvider),
        DateTime.now(),
        first: s.transactions.isEmpty ? null : s.transactions.last.date,
      );
      final summary = Summary(s, window, currency);
      final points = timeline(s, window, currency, grouping: grouping);
      return pageList([
        const PeriodSelector(),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            children: [
              PairMetrics(
                Metric('Доход', money(summary.income, currency)),
                Metric('Расход', money(summary.expense, currency)),
              ),
              const Divider(height: 32),
              PairMetrics(
                Metric(
                  'Средний доход в день',
                  money(summary.averageDailyIncome, currency),
                ),
                Metric(
                  'Средний доход в час',
                  summary.averageHourlyIncome == null
                      ? 'Нет рабочих часов'
                      : money(summary.averageHourlyIncome!, currency),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'В день — по календарным дням периода. В час — только по доходам с указанным временем.',
                style: TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        const SectionTitle('Динамика'),
        DropdownButtonFormField<String>(
          initialValue: metric,
          decoration: const InputDecoration(labelText: 'Показатель'),
          items:
              const {
                    'income': 'Доходы',
                    'expense': 'Расходы',
                    'balance': 'Общий баланс',
                    'savings': 'Накопления',
                    'debt': 'Мои долги',
                  }.entries
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
          onChanged: (v) => setState(() => metric = v!),
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'day', label: Text('Дни')),
            ButtonSegment(value: 'week', label: Text('Недели')),
            ButtonSegment(value: 'month', label: Text('Месяцы')),
          ],
          selected: {grouping},
          onSelectionChanged: (s) => setState(() => grouping = s.first),
        ),
        const SizedBox(height: 16),
        FinanceLineChart(points: points, metric: metric, currency: currency),
        const SectionTitle('Структура расходов'),
        ExpenseDonut(categories: summary.categories, currency: currency),
        Panel(
          child: PairMetrics(
            Metric('Чистый результат', money(summary.net, currency)),
            Metric('Накоплено', money(summary.saved, currency)),
          ),
        ),
      ]);
    },
  );
}
