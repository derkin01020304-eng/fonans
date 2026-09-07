import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/money.dart';
import '../domain/analytics.dart';
import '../services/categorizer.dart';
import 'forms.dart';
import 'providers.dart';
import 'widgets.dart';

class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});
  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  String query = '', category = '';
  bool review = false, allDates = true;
  @override
  Widget build(BuildContext context) => DataView(
    builder: (context, ref, s) {
      final currency = ref.watch(currencyProvider);
      final window = windowFor(
        ref.watch(periodProvider),
        DateTime.now(),
        first: s.transactions.isEmpty ? null : s.transactions.last.date,
      );
      final list = s.transactions
          .where(
            (t) =>
                t.currency == currency &&
                (allDates || window.contains(t.date)) &&
                (category.isEmpty || t.category == category) &&
                (!review || t.needsReview == 1) &&
                '${t.comment} ${t.merchant} ${t.source} ${t.category}'
                    .toLowerCase()
                    .contains(query),
          )
          .toList();
      return pageList([
        TextField(
          decoration: const InputDecoration(
            hintText: 'Магазин, категория, комментарий',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => query = v.trim().toLowerCase()),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              label: const Text('Все даты'),
              selected: allDates,
              onSelected: (v) => setState(() => allDates = v),
            ),
            FilterChip(
              label: Text(
                'Проверить (${s.transactions.where((t) => t.needsReview == 1).length})',
              ),
              selected: review,
              onSelected: (v) => setState(() => review = v),
            ),
            ActionChip(
              label: const Text('Импорт'),
              avatar: const Icon(Icons.file_download_outlined, size: 18),
              onPressed: () => context.push('/integrations'),
            ),
            ActionChip(
              label: const Text('Экспорт'),
              onPressed: () => context.push('/exports'),
            ),
          ],
        ),
        if (!allDates) ...[const SizedBox(height: 12), const PeriodSelector()],
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: category,
          isExpanded: true,
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
          onChanged: (v) => setState(() => category = v ?? ''),
        ),
        SectionTitle('Операции · ${list.length}'),
        if (list.isEmpty)
          EmptyPanel(
            'Операций не найдено',
            'Измените фильтры или добавьте новую операцию.',
            action: 'Добавить расход',
            onAction: () => transactionForm(context, ref, s),
          ),
        for (final t in list)
          TransactionTile(
            t,
            onTap: () => transactionForm(context, ref, s, existing: t),
            onDelete: t.linkType != null
                ? null
                : () async {
                    if (!await confirm(
                      context,
                      'Удалить операцию?',
                      money(t.amountMinor, t.currency),
                    ))
                      return;
                    try {
                      await ref
                          .read(runtimeProvider)
                          .repository
                          .deleteTransaction(t.id);
                      await refresh(ref);
                    } catch (e) {
                      if (context.mounted) message(context, errorText(e));
                    }
                  },
          ),
      ]);
    },
  );
}
