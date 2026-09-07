import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:derk_finance/core/money.dart';
import 'package:derk_finance/data/finance_repository.dart';
import 'package:derk_finance/domain/models.dart';
import 'package:derk_finance/domain/analytics.dart';
import 'package:derk_finance/services/categorizer.dart';
import 'support.dart';

void main() {
  late SqlFinanceRepository repo;
  final date = DateTime(2025, 1, 15, 12);
  setUp(() async {
    repo = await testRepository();
  });
  tearDown(() async {
    await (repo.db as Database).close();
  });
  FinanceTransaction t(
    String id,
    TransactionKind kind,
    int amount, {
    String account = 'card',
    String? to,
    int minutes = 0,
  }) => FinanceTransaction(
    id: id,
    kind: kind,
    amountMinor: amount,
    accountId: account,
    toAccountId: to,
    date: date,
    workMinutes: minutes,
  );
  test('Money parsing is decimal-exact and rejects third decimal', () {
    expect(parseMoney('1 234,56'), 123456);
    expect(parseMoney('0.29'), 29);
    expect(parseMoney('-2,50', allowNegative: true), -250);
    expect(() => parseMoney('1.005'), throwsFormatException);
    expect(() => parseMoney('-1'), throwsFormatException);
    expect(decimalMoney(-29), '-0.29');
  });
  test('Own transfer conserves total and never enters P&L', () async {
    await repo.addTransaction(t('income', TransactionKind.income, 100000));
    await repo.addTransaction(
      t('transfer', TransactionKind.transfer, 30000, to: 'cash'),
    );
    final s = await repo.snapshot();
    expect(s.balance(s.accounts.firstWhere((a) => a.id == 'card')), 70000);
    expect(s.balance(s.accounts.firstWhere((a) => a.id == 'cash')), 30000);
    final summary = Summary(
      s,
      DateWindow(DateTime(2025, 1, 1), DateTime(2025, 2, 1)),
      'RUB',
    );
    expect(summary.income, 100000);
    expect(summary.expense, 0);
    expect(BalanceSummary(s, 'RUB', date).total, 100000);
  });
  test('Savings transfers update goal and conserve balance', () async {
    await repo.addTransaction(t('income', TransactionKind.income, 100000));
    await repo.saveGoal(
      Goal(
        id: 'goal',
        name: 'Цель',
        targetMinor: 200000,
        created: date,
        due: DateTime(2025, 6, 1),
      ),
    );
    await repo.addSavings(30000, 'card', 'savings', date, goalId: 'goal');
    var s = await repo.snapshot();
    expect(s.goalSaved('goal'), 30000);
    expect(BalanceSummary(s, 'RUB', date).total, 100000);
    expect(BalanceSummary(s, 'RUB', date).savings, 30000);
    await repo.addSavings(10000, 'savings', 'card', date, goalId: 'goal');
    s = await repo.snapshot();
    expect(s.goalSaved('goal'), 20000);
    await expectLater(
      repo.addSavings(30000, 'savings', 'card', date, goalId: 'goal'),
      throwsArgumentError,
    );
    expect((await repo.snapshot()).goalSaved('goal'), 20000);
  });
  test('A general savings transfer also has a savings ledger entry', () async {
    await repo.addTransaction(t('income', TransactionKind.income, 100000));
    await repo.addTransaction(
      t('transfer', TransactionKind.transfer, 30000, to: 'savings'),
    );
    expect((await repo.snapshot()).savings.single.amountMinor, 30000);
  });
  test('Cross-currency and same-account transfers roll back', () async {
    await repo.saveAccount(
      const Account(
        id: 'usd',
        name: 'USD',
        kind: AccountKind.bank,
        currency: 'USD',
      ),
    );
    await expectLater(
      repo.addTransaction(t('bad', TransactionKind.transfer, 100, to: 'usd')),
      throwsArgumentError,
    );
    await expectLater(
      repo.addTransaction(t('bad2', TransactionKind.transfer, 100, to: 'card')),
      throwsArgumentError,
    );
    expect((await repo.snapshot()).transactions, isEmpty);
  });
  test('Editing and deletion recalculate balances, no stored drift', () async {
    await repo.addTransaction(t('expense', TransactionKind.expense, 1000));
    await repo.editTransaction(t('expense', TransactionKind.expense, 2500));
    var s = await repo.snapshot();
    expect(s.balance(s.accounts.firstWhere((a) => a.id == 'card')), -2500);
    await repo.deleteTransaction('expense');
    s = await repo.snapshot();
    expect(s.balance(s.accounts.firstWhere((a) => a.id == 'card')), 0);
  });
  test(
    'Debt partial repayment changes cash and principal atomically',
    () async {
      await repo.saveDebt(
        Debt(
          id: 'd',
          name: 'Друг',
          direction: DebtDirection.iOwe,
          initialMinor: 100000,
          remainingMinor: 100000,
          created: date,
          due: DateTime(2025, 2, 1),
        ),
      );
      await repo.repayDebt('d', 25000, 'card', date);
      var s = await repo.snapshot();
      expect(s.debts.single.remainingMinor, 75000);
      expect(s.transactions.single.kind, TransactionKind.debtOut);
      expect((await repo.history('debt_payments', 'd')).length, 1);
      await expectLater(
        repo.repayDebt('d', 80000, 'card', date),
        throwsArgumentError,
      );
      s = await repo.snapshot();
      expect(s.transactions.length, 1);
      expect(s.debts.single.remainingMinor, 75000);
    },
  );
  test('Receivable repayment is cash inflow, not income', () async {
    await repo.saveDebt(
      Debt(
        id: 'd',
        name: 'Друг',
        direction: DebtDirection.owedToMe,
        initialMinor: 50000,
        remainingMinor: 50000,
        created: date,
        due: DateTime(2025, 2, 1),
      ),
    );
    await repo.repayDebt('d', 50000, 'card', date);
    final s = await repo.snapshot();
    expect(s.debts.single.remainingMinor, 0);
    expect(s.transactions.single.kind, TransactionKind.debtIn);
    expect(Summary(s, windowFor(Period.month, date), 'RUB').income, 0);
  });
  test('Credit separates principal from expense interest', () async {
    await repo.saveCredit(
      Credit(
        id: 'c',
        name: 'Кредит',
        bank: 'Банк',
        initialMinor: 1000000,
        remainingMinor: 1000000,
        annualRateBps: 1200,
        monthlyMinor: 100000,
        start: date,
        end: DateTime(2026, 1, 15),
        nextPayment: DateTime(2025, 2, 15),
      ),
    );
    await repo.repayCredit('c', 90000, 10000, 'card', date);
    final s = await repo.snapshot();
    expect(s.credits.single.remainingMinor, 910000);
    expect(s.credits.single.paidInterestMinor, 10000);
    expect(Summary(s, windowFor(Period.month, date), 'RUB').expense, 10000);
    expect(s.balance(s.accounts.firstWhere((a) => a.id == 'card')), -100000);
    expect(s.credits.single.nextPayment, DateTime(2025, 3, 15));
    await repo.repayCredit('c', 10000, 0, 'card', date, early: true);
    expect(
      (await repo.snapshot()).credits.single.nextPayment,
      DateTime(2025, 3, 15),
    );
  });
  test(
    'Invalid repayment account rolls back loan and all ledger rows',
    () async {
      await repo.saveDebt(
        Debt(
          id: 'd',
          name: 'Долг',
          direction: DebtDirection.iOwe,
          initialMinor: 10000,
          remainingMinor: 10000,
          created: date,
          due: DateTime(2025, 3),
        ),
      );
      await expectLater(
        repo.repayDebt('d', 5000, 'missing', date),
        throwsStateError,
      );
      final s = await repo.snapshot();
      expect(s.debts.single.remainingMinor, 10000);
      expect(s.transactions, isEmpty);
    },
  );
  test(
    'Monthly payment preserves January 31 anchor through February',
    () async {
      await repo.savePayment(
        RecurringPayment(
          id: 'p',
          name: 'Аренда',
          amountMinor: 10000,
          due: DateTime(2025, 1, 31),
          accountId: 'card',
          reservedMinor: 5000,
          anchorDay: 31,
        ),
      );
      await repo.payRecurring('p', 'card', DateTime(2025, 1, 31));
      var p = (await repo.snapshot()).payments.single;
      expect(p.due, DateTime(2025, 2, 28));
      expect(p.reservedMinor, 0);
      await repo.payRecurring('p', 'card', DateTime(2025, 2, 28));
      p = (await repo.snapshot()).payments.single;
      expect(p.due, DateTime(2025, 3, 31));
    },
  );
  test('Payment reserves are subtracted exactly once', () async {
    await repo.saveAccount(
      const Account(
        id: 'card',
        name: 'Карта',
        kind: AccountKind.card,
        openingMinor: 100000,
      ),
    );
    await repo.savePayment(
      RecurringPayment(
        id: 'p',
        name: 'Платёж',
        amountMinor: 20000,
        due: DateTime(2025, 1, 20),
        accountId: 'card',
        reservedMinor: 12000,
        anchorDay: 20,
      ),
    );
    final b = BalanceSummary(await repo.snapshot(), 'RUB', date);
    expect(b.available, 88000);
    expect(b.upcomingUnfunded, 8000);
    expect(b.freeToSpend, 80000);
  });
  test('Hourly average only uses transactions with work time', () async {
    await repo.addTransaction(
      t('a', TransactionKind.income, 120000, minutes: 120),
    );
    await repo.addTransaction(t('b', TransactionKind.income, 999000));
    final summary = Summary(
      await repo.snapshot(),
      DateWindow(DateTime(2025, 1, 1), DateTime(2025, 1, 16)),
      'RUB',
    );
    expect(summary.averageHourlyIncome, 60000);
    expect(summary.averageDailyIncome, 74600);
    expect(percentageChange(100, 0), isNull);
  });
  test('ISO week, year and exclusive date boundaries', () {
    final w = windowFor(Period.week, DateTime(2026, 1, 1));
    expect(w.start, DateTime(2025, 12, 29));
    expect(w.contains(w.end), false);
    expect(
      windowFor(Period.year, DateTime(2026, 1, 1)).start,
      DateTime(2026, 1, 1),
    );
    expect(previousWindow(w).end, w.start);
  });
  test('Confirmed merchant categories override MCC and keywords', () {
    final rule = Categorizer({
      'магазин': 'Работа',
    }).predict(merchant: ' Магазин ', mcc: '5411');
    expect(rule.category, 'Работа');
    expect(rule.needsReview, false);
    expect(
      const Categorizer().predict(description: 'неизвестно').needsReview,
      true,
    );
    expect(QuickEntry.parse('+3000 работа').kind, TransactionKind.income);
    expect(QuickEntry.parse('250 еда').amountMinor, 25000);
  });
  test('Zero-interest installment projection and non-amortizing credit', () {
    Credit c(int rate, int payment) => Credit(
      id: 'c',
      name: 'c',
      bank: 'b',
      initialMinor: 100000,
      remainingMinor: 100000,
      annualRateBps: rate,
      monthlyMinor: payment,
      start: date,
      end: date,
      nextPayment: date,
    );
    expect(CreditProjection.estimate(c(0, 25000)).interestMinor, 0);
    expect(CreditProjection.estimate(c(0, 25000)).months, 4);
    expect(CreditProjection.estimate(c(1200, 500)).amortizing, false);
  });
  test(
    'Demo can be entered and exited without destroying initial accounts',
    () async {
      await repo.saveAccount(
        const Account(
          id: 'card',
          name: 'Моя карта',
          kind: AccountKind.card,
          openingMinor: 123456,
        ),
      );
      await repo.seedDemo();
      expect((await repo.snapshot()).demo, true);
      expect((await repo.snapshot()).transactions.length, greaterThan(60));
      await repo.clearDemo();
      final s = await repo.snapshot();
      expect(s.demo, false);
      expect(s.transactions, isEmpty);
      expect(s.accounts.firstWhere((a) => a.id == 'card').openingMinor, 123456);
    },
  );
  test('All weekly occurrences within 30 days reduce free spending', () async {
    await repo.saveAccount(
      const Account(
        id: 'card',
        name: 'Карта',
        kind: AccountKind.card,
        openingMinor: 100000,
      ),
    );
    await repo.savePayment(
      RecurringPayment(
        id: 'weekly',
        name: 'Транспорт',
        amountMinor: 10000,
        due: DateTime(2025, 1, 16),
        frequency: 'weekly',
        accountId: 'card',
        reservedMinor: 3000,
        anchorDay: 16,
      ),
    );
    final b = BalanceSummary(await repo.snapshot(), 'RUB', date);
    expect(b.upcomingUnfunded, 47000);
    expect(b.freeToSpend, 50000);
  });
  test('Credit payment keeps month-end anchor after February', () async {
    await repo.saveCredit(
      Credit(
        id: 'c',
        name: 'Кредит',
        bank: 'Банк',
        initialMinor: 100000,
        remainingMinor: 100000,
        annualRateBps: 0,
        monthlyMinor: 10000,
        start: date,
        end: DateTime(2026, 1, 31),
        nextPayment: DateTime(2025, 1, 31),
      ),
    );
    await repo.repayCredit('c', 10000, 0, 'card', DateTime(2025, 1, 31));
    expect(
      (await repo.snapshot()).credits.single.nextPayment,
      DateTime(2025, 2, 28),
    );
    await repo.repayCredit('c', 10000, 0, 'card', DateTime(2025, 2, 28));
    expect(
      (await repo.snapshot()).credits.single.nextPayment,
      DateTime(2025, 3, 31),
    );
  });
  test(
    'Importing a savings transfer keeps external key for duplicate detection',
    () async {
      await repo.addTransaction(
        FinanceTransaction(
          id: 'imported',
          kind: TransactionKind.transfer,
          amountMinor: 10000,
          accountId: 'card',
          toAccountId: 'savings',
          date: date,
          externalKey: 'bank-key',
        ),
      );
      final s = await repo.snapshot();
      expect(s.transactions.single.id, 'imported');
      expect(s.transactions.single.externalKey, 'bank-key');
      expect(s.savings.single.transactionId, 'imported');
      expect(Summary(s, windowFor(Period.month, date), 'RUB').expense, 0);
    },
  );
}
