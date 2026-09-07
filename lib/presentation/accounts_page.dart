import 'package:flutter/material.dart';
import '../core/money.dart';
import '../domain/analytics.dart';
import 'forms.dart';
import 'providers.dart';
import 'widgets.dart';

class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key});
  @override
  Widget build(BuildContext context) => DataView(
    builder: (context, ref, s) {
      final currency = ref.watch(currencyProvider),
          b = BalanceSummary(s, ref.watch(currencyProvider), DateTime.now());
      return pageList([
        SectionTitle(
          'Счета и кошельки',
          action: 'Добавить',
          onAction: () => accountForm(context, ref),
        ),
        for (final a in s.accounts)
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        a.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'edit') {
                          await accountForm(context, ref, existing: a);
                          return;
                        }
                        if (!await confirm(context, 'Удалить счёт?', a.name))
                          return;
                        try {
                          await ref
                              .read(runtimeProvider)
                              .repository
                              .deleteEntity('accounts', a.id);
                          await refresh(ref);
                        } catch (e) {
                          if (context.mounted) message(context, errorText(e));
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Изменить')),
                        PopupMenuItem(value: 'delete', child: Text('Удалить')),
                      ],
                    ),
                  ],
                ),
                Text(
                  accountKinds[a.kind.name]!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                Text(
                  money(s.balance(a), a.currency),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (a.reservedMinor > 0)
                  Text(
                    'Зарезервировано: ${money(a.reservedMinor, a.currency)}',
                  ),
                const SizedBox(height: 8),
                SelectableText(
                  'ID: ${a.id}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        const SectionTitle('Доступность денег'),
        Panel(
          child: Column(
            children: [
              PairMetrics(
                Metric('Общий баланс', money(b.total, currency)),
                Metric('Накопления', money(b.savings, currency)),
              ),
              const Divider(height: 28),
              PairMetrics(
                Metric('Отдельный резерв', money(b.reserved, currency)),
                Metric('Резерв платежей', money(b.paymentReserves, currency)),
              ),
              const Divider(height: 28),
              PairMetrics(
                Metric('Доступно после резервов', money(b.available, currency)),
                Metric('Свободно на 30 дней', money(b.freeToSpend, currency)),
              ),
            ],
          ),
        ),
        const Text(
          'Разные валюты не складываются. Переключатель валюты находится в настройках. Доступный бюджет может быть отрицательным, если обязательства превышают остаток.',
        ),
      ]);
    },
  );
}
