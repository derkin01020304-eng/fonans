import '../domain/models.dart';
import '../core/money.dart';
import '../services/categorizer.dart';
import 'finance_repository.dart';

Map<String, dynamic> demoData(DateTime now) {
  final today = day(now);
  final accounts = [
    const Account(
      id: 'demo_card',
      name: 'Повседневная карта',
      kind: AccountKind.card,
      openingMinor: 2500000,
    ),
    const Account(
      id: 'demo_cash',
      name: 'Наличные',
      kind: AccountKind.cash,
      openingMinor: 250000,
    ),
    const Account(
      id: 'demo_savings',
      name: 'Копилка',
      kind: AccountKind.savings,
    ),
  ];
  final transactions = <FinanceTransaction>[];
  final savings = <SavingsEntry>[];
  for (var i = 41; i >= 0; i--) {
    final date = DateTime(today.year, today.month, today.day - i);
    if (i % 6 != 0) {
      transactions.add(
        FinanceTransaction(
          id: 'demo_income_$i',
          kind: TransactionKind.income,
          amountMinor: (2400 + (i % 7) * 180) * 100,
          accountId: 'demo_card',
          date: date,
          category: 'Работа',
          source: 'Демо: доставка',
          workMinutes: 300 + i % 3 * 60,
        ),
      );
    }
    transactions.add(
      FinanceTransaction(
        id: 'demo_food_$i',
        kind: TransactionKind.expense,
        amountMinor: (310 + i % 5 * 95) * 100,
        accountId: 'demo_card',
        date: date,
        category: 'Еда',
        merchant: 'Демо: продуктовый',
        mcc: '5411',
      ),
    );
    if (i % 2 == 0) {
      transactions.add(
        FinanceTransaction(
          id: 'demo_drink_$i',
          kind: TransactionKind.expense,
          amountMinor: 17000,
          accountId: 'demo_cash',
          date: date,
          category: 'Напитки',
          merchant: 'Демо: кофе',
        ),
      );
    }
    if (i % 7 == 0) {
      final txId = 'demo_save_$i';
      transactions.add(
        FinanceTransaction(
          id: txId,
          kind: TransactionKind.transfer,
          amountMinor: 300000,
          accountId: 'demo_card',
          toAccountId: 'demo_savings',
          date: date,
          category: 'Накопления',
          linkType: 'savings',
          linkId: 'demo_goal',
        ),
      );
      savings.add(
        SavingsEntry(
          id: 'saving_$i',
          amountMinor: 300000,
          date: date,
          transactionId: txId,
          goalId: 'demo_goal',
        ),
      );
    }
  }
  final tables = {
    for (final t in SqlFinanceRepository.tables) t: <Map<String, dynamic>>[],
  };
  tables['accounts'] = accounts.map((a) => a.toJson()).toList();
  tables['transactions'] = transactions.map((t) => t.toJson()).toList();
  tables['savings'] = savings.map((s) => s.toJson()).toList();
  tables['categories'] = expenseCategories
      .map((c) => <String, dynamic>{'id': c, 'name': c, 'parentId': null})
      .toList();
  tables['goals'] = [
    Goal(
      id: 'demo_goal',
      name: 'Компьютер',
      targetMinor: 12000000,
      created: today.subtract(const Duration(days: 60)),
      due: today.add(const Duration(days: 150)),
    ).toJson(),
    Goal(
      id: 'demo_reserve',
      name: 'Финансовый резерв',
      targetMinor: 6000000,
      created: today,
      due: today.add(const Duration(days: 120)),
    ).toJson(),
  ];
  tables['debts'] = [
    Debt(
      id: 'demo_debt',
      name: 'Демо: долг другу',
      direction: DebtDirection.iOwe,
      initialMinor: 1500000,
      remainingMinor: 1100000,
      created: today.subtract(const Duration(days: 70)),
      due: today.add(const Duration(days: 18)),
    ).toJson(),
    Debt(
      id: 'demo_owed',
      name: 'Демо: мне вернут',
      direction: DebtDirection.owedToMe,
      initialMinor: 600000,
      remainingMinor: 600000,
      created: today.subtract(const Duration(days: 5)),
      due: today.add(const Duration(days: 8)),
    ).toJson(),
  ];
  tables['credits'] = [
    Credit(
      id: 'demo_credit',
      name: 'Демо: рассрочка',
      bank: 'Тестовый банк',
      initialMinor: 4800000,
      remainingMinor: 3200000,
      annualRateBps: 0,
      monthlyMinor: 400000,
      start: today.subtract(const Duration(days: 120)),
      end: today.add(const Duration(days: 240)),
      nextPayment: today.add(const Duration(days: 12)),
    ).toJson(),
  ];
  tables['recurring_payments'] = [
    RecurringPayment(
      id: 'demo_rent',
      name: 'Аренда',
      amountMinor: 1800000,
      due: today.add(const Duration(days: 9)),
      accountId: 'demo_card',
      reservedMinor: 700000,
      category: 'Жильё',
      anchorDay: today.add(const Duration(days: 9)).day,
    ).toJson(),
    RecurringPayment(
      id: 'demo_mobile',
      name: 'Мобильная связь',
      amountMinor: 65000,
      due: today.add(const Duration(days: 4)),
      accountId: 'demo_card',
      category: 'Связь',
      anchorDay: today.add(const Duration(days: 4)).day,
    ).toJson(),
  ];
  return {'schemaVersion': 2, 'tables': tables};
}
