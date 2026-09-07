import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/money.dart';
import '../domain/models.dart';
import 'providers.dart';

const mint = Color(0xFF69D5AF);
const forest = Color(0xFF183E36);
const coral = Color(0xFFF08B78);
const chartColors = [
  Color(0xFF319D7F),
  Color(0xFFE5B858),
  Color(0xFF799BE3),
  Color(0xFFED9586),
  Color(0xFFAB8CD1),
  Color(0xFF6EBAB7),
  Color(0xFFA2AC69),
  Color(0xFFC58D68),
];

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final Color? color;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Card(
    color: color,
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(padding: padding, child: child),
  );
}

class Metric extends StatelessWidget {
  const Metric(this.label, this.value, {super.key, this.color, this.icon});
  final String label, value;
  final Color? color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        value,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: color,
        ),
        maxLines: 2,
      ),
    ],
  );
}

class PairMetrics extends StatelessWidget {
  const PairMetrics(this.left, this.right, {super.key});
  final Widget left, right;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: left),
      const SizedBox(width: 16),
      Expanded(child: right),
    ],
  );
}

class PeriodSelector extends ConsumerWidget {
  const PeriodSelector({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(periodProvider);
    const names = ['Сегодня', 'Неделя', 'Месяц', 'Год', 'Всё время'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < Period.values.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(names[i]),
                selected: period == Period.values[i],
                onSelected: (_) =>
                    ref.read(periodProvider.notifier).state = Period.values[i],
              ),
            ),
        ],
      ),
    );
  }
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel(
    this.title,
    this.description, {
    super.key,
    this.action,
    this.onAction,
  });
  final String title, description;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.add_chart_outlined, size: 32),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(description),
        if (action != null) ...[
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onAction, child: Text(action!)),
        ],
      ],
    ),
  );
}

class ProgressInfo extends StatelessWidget {
  const ProgressInfo({super.key, required this.value, required this.label});
  final double value;
  final String label;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 14),
      LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: 8,
        borderRadius: BorderRadius.circular(8),
      ),
      const SizedBox(height: 8),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

IconData categoryIcon(String category) => switch (category) {
  'Еда' => Icons.restaurant_outlined,
  'Напитки' => Icons.local_cafe_outlined,
  'Транспорт' => Icons.directions_bike,
  'Работа' => Icons.work_outline,
  'Здоровье' => Icons.favorite_border,
  'Жильё' => Icons.home_outlined,
  'Связь' => Icons.phone_android,
  'Накопления' => Icons.savings_outlined,
  'Переводы' => Icons.swap_horiz,
  'Кредиты' => Icons.account_balance_outlined,
  'Долги' => Icons.handshake_outlined,
  'Учёба' => Icons.school_outlined,
  'Покупки' => Icons.shopping_bag_outlined,
  _ => Icons.receipt_long_outlined,
};

class TransactionTile extends StatelessWidget {
  const TransactionTile(
    this.transaction, {
    super.key,
    this.onTap,
    this.onDelete,
  });
  final FinanceTransaction transaction;
  final VoidCallback? onTap, onDelete;
  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final positive = [
      TransactionKind.income,
      TransactionKind.debtIn,
      TransactionKind.creditIn,
    ].contains(t.kind);
    final transfer = t.kind == TransactionKind.transfer;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          transfer ? Icons.swap_horiz : categoryIcon(t.category),
          color: positive
              ? const Color(0xFF319D7F)
              : Theme.of(context).colorScheme.onSurface,
        ),
      ),
      title: Text(
        t.merchant.isNotEmpty
            ? t.merchant
            : t.source.isNotEmpty
            ? t.source
            : t.category,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${t.category} · ${dateLabel(t.date)}${t.needsReview == 1 ? ' · Уточнить категорию' : ''}',
        style: t.needsReview == 1
            ? TextStyle(color: Theme.of(context).colorScheme.error)
            : null,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${transfer
                ? '↔'
                : positive
                ? '+'
                : '−'} ${money(t.amountMinor, t.currency)}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: positive ? const Color(0xFF319D7F) : null,
            ),
          ),
          if (onDelete != null)
            PopupMenuButton<String>(
              onSelected: (_) => onDelete!(),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'delete', child: Text('Удалить')),
              ],
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}

Widget pageList(List<Widget> children) => ListView(
  padding: const EdgeInsets.fromLTRB(20, 8, 20, 104),
  children: children,
);
