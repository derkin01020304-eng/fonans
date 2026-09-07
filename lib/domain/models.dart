import 'package:json_annotation/json_annotation.dart';
part 'models.g.dart';

enum TransactionKind {
  income,
  expense,
  transfer,
  debtIn,
  debtOut,
  creditIn,
  creditOut,
}

enum AccountKind { card, bank, cash, savings, virtual, wallet }

enum DebtDirection { iOwe, owedToMe }

enum Period { day, week, month, year, all }

@JsonSerializable()
class FinanceTransaction {
  const FinanceTransaction({
    required this.id,
    required this.kind,
    required this.amountMinor,
    required this.accountId,
    required this.date,
    this.currency = 'RUB',
    this.category = 'Прочее',
    this.subcategory = '',
    this.comment = '',
    this.merchant = '',
    this.source = '',
    this.paymentMethod = '',
    this.workMinutes = 0,
    this.toAccountId,
    this.mcc,
    this.externalKey,
    this.needsReview = 0,
    this.linkType,
    this.linkId,
  });
  final String id,
      accountId,
      currency,
      category,
      subcategory,
      comment,
      merchant,
      source,
      paymentMethod;
  final String? toAccountId, mcc, externalKey, linkType, linkId;
  final TransactionKind kind;
  final int amountMinor, workMinutes, needsReview;
  final DateTime date;
  factory FinanceTransaction.fromJson(Map<String, dynamic> json) =>
      _$FinanceTransactionFromJson(json);
  Map<String, dynamic> toJson() => _$FinanceTransactionToJson(this);
  int delta(String account) {
    if (kind == TransactionKind.transfer) {
      return (toAccountId == account ? amountMinor : 0) -
          (accountId == account ? amountMinor : 0);
    }
    if (accountId != account) return 0;
    return [
          TransactionKind.income,
          TransactionKind.debtIn,
          TransactionKind.creditIn,
        ].contains(kind)
        ? amountMinor
        : -amountMinor;
  }
}

@JsonSerializable()
class Account {
  const Account({
    required this.id,
    required this.name,
    required this.kind,
    this.currency = 'RUB',
    this.openingMinor = 0,
    this.reservedMinor = 0,
    this.bankId,
    this.externalId,
  });
  final String id, name, currency;
  final AccountKind kind;
  final int openingMinor, reservedMinor;
  final String? bankId, externalId;
  factory Account.fromJson(Map<String, dynamic> json) =>
      _$AccountFromJson(json);
  Map<String, dynamic> toJson() => _$AccountToJson(this);
}

@JsonSerializable()
class Debt {
  const Debt({
    required this.id,
    required this.name,
    required this.direction,
    required this.initialMinor,
    required this.remainingMinor,
    required this.created,
    required this.due,
    this.currency = 'RUB',
    this.comment = '',
  });
  final String id, name, currency, comment;
  final DebtDirection direction;
  final int initialMinor, remainingMinor;
  final DateTime created, due;
  double get progress =>
      initialMinor == 0 ? 0 : (1 - remainingMinor / initialMinor).clamp(0, 1);
  String status(DateTime now) => remainingMinor == 0
      ? 'Погашен'
      : dayOnly(due).isBefore(dayOnly(now))
      ? 'Просрочен'
      : 'Активен';
  factory Debt.fromJson(Map<String, dynamic> json) => _$DebtFromJson(json);
  Map<String, dynamic> toJson() => _$DebtToJson(this);
}

@JsonSerializable()
class Credit {
  Credit({
    required this.id,
    required this.name,
    required this.bank,
    required this.initialMinor,
    required this.remainingMinor,
    required this.annualRateBps,
    required this.monthlyMinor,
    required this.start,
    required this.end,
    required this.nextPayment,
    this.currency = 'RUB',
    this.paidInterestMinor = 0,
    this.comment = '',
    int? paymentDay,
  }) : paymentDay = paymentDay ?? nextPayment.day;
  final String id, name, bank, currency, comment;
  final int initialMinor,
      remainingMinor,
      annualRateBps,
      monthlyMinor,
      paidInterestMinor;
  final int paymentDay;
  final DateTime start, end, nextPayment;
  double get progress =>
      initialMinor == 0 ? 0 : (1 - remainingMinor / initialMinor).clamp(0, 1);
  factory Credit.fromJson(Map<String, dynamic> json) => _$CreditFromJson(json);
  Map<String, dynamic> toJson() => _$CreditToJson(this);
}

@JsonSerializable()
class Goal {
  const Goal({
    required this.id,
    required this.name,
    required this.targetMinor,
    required this.created,
    required this.due,
    this.currency = 'RUB',
  });
  final String id, name, currency;
  final int targetMinor;
  final DateTime created, due;
  factory Goal.fromJson(Map<String, dynamic> json) => _$GoalFromJson(json);
  Map<String, dynamic> toJson() => _$GoalToJson(this);
}

@JsonSerializable()
class RecurringPayment {
  const RecurringPayment({
    required this.id,
    required this.name,
    required this.amountMinor,
    required this.due,
    required this.accountId,
    this.currency = 'RUB',
    this.frequency = 'monthly',
    this.reservedMinor = 0,
    this.category = 'Обязательные платежи',
    this.anchorDay = 1,
  });
  final String id, name, currency, frequency, accountId, category;
  final int amountMinor, reservedMinor, anchorDay;
  final DateTime due;
  factory RecurringPayment.fromJson(Map<String, dynamic> json) =>
      _$RecurringPaymentFromJson(json);
  Map<String, dynamic> toJson() => _$RecurringPaymentToJson(this);
}

@JsonSerializable()
class SavingsEntry {
  const SavingsEntry({
    required this.id,
    required this.amountMinor,
    required this.date,
    required this.transactionId,
    this.goalId,
    this.currency = 'RUB',
  });
  final String id, transactionId, currency;
  final String? goalId;
  final int amountMinor;
  final DateTime date;
  factory SavingsEntry.fromJson(Map<String, dynamic> json) =>
      _$SavingsEntryFromJson(json);
  Map<String, dynamic> toJson() => _$SavingsEntryToJson(this);
}

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class FinanceSnapshot {
  const FinanceSnapshot({
    this.accounts = const [],
    this.transactions = const [],
    this.debts = const [],
    this.credits = const [],
    this.goals = const [],
    this.payments = const [],
    this.savings = const [],
    this.demo = false,
  });
  final List<Account> accounts;
  final List<FinanceTransaction> transactions;
  final List<Debt> debts;
  final List<Credit> credits;
  final List<Goal> goals;
  final List<RecurringPayment> payments;
  final List<SavingsEntry> savings;
  final bool demo;
  int balance(Account account, {DateTime? until}) =>
      account.openingMinor +
      transactions
          .where((t) => until == null || !t.date.isAfter(until))
          .fold<int>(0, (sum, t) => sum + t.delta(account.id));
  int goalSaved(String id) => savings
      .where((s) => s.goalId == id)
      .fold<int>(0, (sum, s) => sum + s.amountMinor);
}
