import 'dart:math';
import '../core/money.dart';
import 'models.dart';

class DateWindow {
  const DateWindow(this.start, this.end);
  final DateTime start, end;
  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);
  int get days => max(1, calendarDays(start, end));
}

DateWindow windowFor(Period period, DateTime now, {DateTime? first}) {
  final today = day(now);
  final end = DateTime(today.year, today.month, today.day + 1);
  final start = switch (period) {
    Period.day => today,
    Period.week => DateTime(
      today.year,
      today.month,
      today.day - today.weekday + 1,
    ),
    Period.month => DateTime(today.year, today.month, 1),
    Period.year => DateTime(today.year, 1, 1),
    Period.all => first == null || first.isAfter(today) ? today : day(first),
  };
  return DateWindow(start, end);
}

/// Same elapsed number of calendar days immediately before the current window.
DateWindow previousWindow(DateWindow w) => DateWindow(
  DateTime(w.start.year, w.start.month, w.start.day - w.days),
  w.start,
);

class Summary {
  Summary(this.snapshot, this.window, this.currency);
  final FinanceSnapshot snapshot;
  final DateWindow window;
  final String currency;
  List<FinanceTransaction> get operations => snapshot.transactions
      .where((t) => t.currency == currency && window.contains(t.date))
      .toList();
  int total(TransactionKind kind) => operations
      .where((t) => t.kind == kind)
      .fold<int>(0, (sum, t) => sum + t.amountMinor);
  int get income => total(TransactionKind.income);
  int get expense => total(TransactionKind.expense);
  int get net => income - expense;
  int get saved => snapshot.savings
      .where((s) => s.currency == currency && window.contains(s.date))
      .fold<int>(0, (sum, s) => sum + s.amountMinor);
  int get averageDailyIncome => (income / window.days).round();
  int? get averageHourlyIncome {
    final timed = operations.where(
      (t) => t.kind == TransactionKind.income && t.workMinutes > 0,
    );
    final minutes = timed.fold<int>(0, (s, t) => s + t.workMinutes);
    if (minutes == 0) return null;
    return (timed.fold<int>(0, (s, t) => s + t.amountMinor) * 60 / minutes)
        .round();
  }

  Map<String, int> get categories {
    final values = <String, int>{};
    for (final t in operations.where(
      (t) => t.kind == TransactionKind.expense,
    )) {
      values.update(
        t.category,
        (v) => v + t.amountMinor,
        ifAbsent: () => t.amountMinor,
      );
    }
    final sorted = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted);
  }

  Map<String, dynamic> toJson() => {
    'currency': currency,
    'start': window.start.toIso8601String(),
    'endExclusive': window.end.toIso8601String(),
    'incomeMinor': income,
    'expenseMinor': expense,
    'netMinor': net,
    'savedMinor': saved,
    'averageDailyIncomeMinor': averageDailyIncome,
    'averageHourlyIncomeMinor': averageHourlyIncome,
    'categories': categories,
  };
}

class BalanceSummary {
  BalanceSummary(this.snapshot, this.currency, this.now);
  final FinanceSnapshot snapshot;
  final String currency;
  final DateTime now;
  Iterable<Account> get accounts =>
      snapshot.accounts.where((a) => a.currency == currency);
  int get total =>
      accounts.fold<int>(0, (s, a) => s + snapshot.balance(a, until: now));
  int get savings => accounts
      .where((a) => a.kind == AccountKind.savings)
      .fold<int>(0, (s, a) => s + snapshot.balance(a, until: now));
  int get reserved => accounts
      .where((a) => a.kind != AccountKind.savings)
      .fold<int>(0, (s, a) => s + a.reservedMinor);
  int get paymentReserves => snapshot.payments
      .where((p) => p.currency == currency)
      .fold<int>(0, (s, p) => s + p.reservedMinor);
  int get debt => snapshot.debts
      .where((d) => d.currency == currency && d.direction == DebtDirection.iOwe)
      .fold<int>(0, (s, d) => s + d.remainingMinor);
  int get owedToMe => snapshot.debts
      .where(
        (d) => d.currency == currency && d.direction == DebtDirection.owedToMe,
      )
      .fold<int>(0, (s, d) => s + d.remainingMinor);
  int get credit => snapshot.credits
      .where((c) => c.currency == currency)
      .fold<int>(0, (s, c) => s + c.remainingMinor);
  int get monthlyObligations =>
      snapshot.credits
          .where((c) => c.currency == currency && c.remainingMinor > 0)
          .fold<int>(0, (s, c) => s + c.monthlyMinor) +
      snapshot.payments
          .where((p) => p.currency == currency && p.frequency == 'monthly')
          .fold<int>(0, (s, p) => s + p.amountMinor);
  int get upcomingUnfunded {
    final end = DateTime(now.year, now.month, now.day + 30);
    var due = 0;
    for (final p in snapshot.payments.where((p) => p.currency == currency)) {
      var date = p.due;
      var first = true;
      while (date.isBefore(end)) {
        due += p.amountMinor - (first ? p.reservedMinor : 0);
        first = false;
        if (p.frequency == 'once') break;
        date = p.frequency == 'weekly'
            ? DateTime(date.year, date.month, date.day + 7)
            : anchoredMonth(
                date,
                p.anchorDay,
                p.frequency == 'yearly' ? 12 : 1,
              );
      }
    }
    for (final c in snapshot.credits.where(
      (c) => c.currency == currency && c.remainingMinor > 0,
    )) {
      var date = c.nextPayment;
      var balance = c.remainingMinor;
      while (date.isBefore(end) && balance > 0) {
        final interest = (balance * c.annualRateBps / 120000).round();
        final payment = min(c.monthlyMinor, balance + interest);
        due += payment;
        balance -= max(0, payment - interest);
        date = anchoredMonth(date, c.paymentDay);
      }
    }
    due += snapshot.debts
        .where(
          (d) =>
              d.currency == currency &&
              d.direction == DebtDirection.iOwe &&
              d.due.isBefore(end),
        )
        .fold<int>(0, (s, d) => s + d.remainingMinor);
    return due;
  }

  int get available => total - savings - reserved - paymentReserves;
  int get freeToSpend => available - upcomingUnfunded;
  Map<String, dynamic> toJson() => {
    'currency': currency,
    'balanceMinor': total,
    'savingsMinor': savings,
    'reservedMinor': reserved,
    'paymentReservesMinor': paymentReserves,
    'availableMinor': available,
    'freeToSpendMinor': freeToSpend,
    'debtMinor': debt,
    'owedToMeMinor': owedToMe,
    'creditMinor': credit,
    'monthlyObligationsMinor': monthlyObligations,
    'horizonDays': 30,
  };
}

double? percentageChange(int current, int previous) =>
    previous == 0 ? null : (current - previous) * 100 / previous.abs();

class CreditProjection {
  const CreditProjection(this.interestMinor, this.months, this.amortizing);
  final int interestMinor, months;
  final bool amortizing;
  static CreditProjection estimate(Credit c) {
    var balance = c.remainingMinor;
    var totalInterest = 0;
    var months = 0;
    while (balance > 0 && months < 1200) {
      final interest = (balance * c.annualRateBps / 120000).round();
      final principal = c.monthlyMinor - interest;
      if (principal <= 0) return CreditProjection(totalInterest, months, false);
      balance -= min(balance, principal);
      totalInterest += interest;
      months++;
    }
    return CreditProjection(totalInterest, months, balance == 0);
  }
}

class ChartPoint {
  const ChartPoint(
    this.date,
    this.income,
    this.expense,
    this.balance,
    this.savings,
    this.debt,
  );
  final DateTime date;
  final int income, expense, balance, savings, debt;
}

List<ChartPoint> timeline(
  FinanceSnapshot s,
  DateWindow w,
  String currency, {
  String grouping = 'day',
}) {
  final result = <ChartPoint>[];
  var cursor = w.start;
  while (cursor.isBefore(w.end)) {
    final proposed = grouping == 'month'
        ? DateTime(cursor.year, cursor.month + 1, 1)
        : DateTime(
            cursor.year,
            cursor.month,
            cursor.day + (grouping == 'week' ? 7 : 1),
          );
    final next = proposed.isAfter(w.end) ? w.end : proposed;
    final summary = Summary(s, DateWindow(cursor, next), currency);
    final cutoff = next.subtract(const Duration(microseconds: 1));
    final accounts = s.accounts.where((a) => a.currency == currency);
    final balance = accounts.fold<int>(
      0,
      (v, a) => v + s.balance(a, until: cutoff),
    );
    final savings = accounts
        .where((a) => a.kind == AccountKind.savings)
        .fold<int>(0, (v, a) => v + s.balance(a, until: cutoff));
    final debt = s.debts
        .where(
          (d) =>
              d.currency == currency &&
              d.direction == DebtDirection.iOwe &&
              !d.created.isAfter(cutoff),
        )
        .fold<int>(
          0,
          (v, d) =>
              v +
              d.remainingMinor +
              s.transactions
                  .where(
                    (t) =>
                        t.linkType == 'debt' &&
                        t.linkId == d.id &&
                        t.date.isAfter(cutoff),
                  )
                  .fold<int>(0, (v, t) => v + t.amountMinor),
        );
    result.add(
      ChartPoint(
        cursor,
        summary.income,
        summary.expense,
        balance,
        savings,
        debt,
      ),
    );
    cursor = next;
  }
  return result;
}
