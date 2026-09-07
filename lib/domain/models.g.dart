// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FinanceTransaction _$FinanceTransactionFromJson(Map<String, dynamic> json) =>
    FinanceTransaction(
      id: json['id'] as String,
      kind: $enumDecode(_$TransactionKindEnumMap, json['kind']),
      amountMinor: (json['amountMinor'] as num).toInt(),
      accountId: json['accountId'] as String,
      date: DateTime.parse(json['date'] as String),
      currency: json['currency'] as String? ?? 'RUB',
      category: json['category'] as String? ?? 'Прочее',
      subcategory: json['subcategory'] as String? ?? '',
      comment: json['comment'] as String? ?? '',
      merchant: json['merchant'] as String? ?? '',
      source: json['source'] as String? ?? '',
      paymentMethod: json['paymentMethod'] as String? ?? '',
      workMinutes: (json['workMinutes'] as num?)?.toInt() ?? 0,
      toAccountId: json['toAccountId'] as String?,
      mcc: json['mcc'] as String?,
      externalKey: json['externalKey'] as String?,
      needsReview: (json['needsReview'] as num?)?.toInt() ?? 0,
      linkType: json['linkType'] as String?,
      linkId: json['linkId'] as String?,
    );

Map<String, dynamic> _$FinanceTransactionToJson(FinanceTransaction instance) =>
    <String, dynamic>{
      'id': instance.id,
      'accountId': instance.accountId,
      'currency': instance.currency,
      'category': instance.category,
      'subcategory': instance.subcategory,
      'comment': instance.comment,
      'merchant': instance.merchant,
      'source': instance.source,
      'paymentMethod': instance.paymentMethod,
      'toAccountId': instance.toAccountId,
      'mcc': instance.mcc,
      'externalKey': instance.externalKey,
      'linkType': instance.linkType,
      'linkId': instance.linkId,
      'kind': _$TransactionKindEnumMap[instance.kind]!,
      'amountMinor': instance.amountMinor,
      'workMinutes': instance.workMinutes,
      'needsReview': instance.needsReview,
      'date': instance.date.toIso8601String(),
    };

const _$TransactionKindEnumMap = {
  TransactionKind.income: 'income',
  TransactionKind.expense: 'expense',
  TransactionKind.transfer: 'transfer',
  TransactionKind.debtIn: 'debtIn',
  TransactionKind.debtOut: 'debtOut',
  TransactionKind.creditIn: 'creditIn',
  TransactionKind.creditOut: 'creditOut',
};

Account _$AccountFromJson(Map<String, dynamic> json) => Account(
  id: json['id'] as String,
  name: json['name'] as String,
  kind: $enumDecode(_$AccountKindEnumMap, json['kind']),
  currency: json['currency'] as String? ?? 'RUB',
  openingMinor: (json['openingMinor'] as num?)?.toInt() ?? 0,
  reservedMinor: (json['reservedMinor'] as num?)?.toInt() ?? 0,
  bankId: json['bankId'] as String?,
  externalId: json['externalId'] as String?,
);

Map<String, dynamic> _$AccountToJson(Account instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'currency': instance.currency,
  'kind': _$AccountKindEnumMap[instance.kind]!,
  'openingMinor': instance.openingMinor,
  'reservedMinor': instance.reservedMinor,
  'bankId': instance.bankId,
  'externalId': instance.externalId,
};

const _$AccountKindEnumMap = {
  AccountKind.card: 'card',
  AccountKind.bank: 'bank',
  AccountKind.cash: 'cash',
  AccountKind.savings: 'savings',
  AccountKind.virtual: 'virtual',
  AccountKind.wallet: 'wallet',
};

Debt _$DebtFromJson(Map<String, dynamic> json) => Debt(
  id: json['id'] as String,
  name: json['name'] as String,
  direction: $enumDecode(_$DebtDirectionEnumMap, json['direction']),
  initialMinor: (json['initialMinor'] as num).toInt(),
  remainingMinor: (json['remainingMinor'] as num).toInt(),
  created: DateTime.parse(json['created'] as String),
  due: DateTime.parse(json['due'] as String),
  currency: json['currency'] as String? ?? 'RUB',
  comment: json['comment'] as String? ?? '',
);

Map<String, dynamic> _$DebtToJson(Debt instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'currency': instance.currency,
  'comment': instance.comment,
  'direction': _$DebtDirectionEnumMap[instance.direction]!,
  'initialMinor': instance.initialMinor,
  'remainingMinor': instance.remainingMinor,
  'created': instance.created.toIso8601String(),
  'due': instance.due.toIso8601String(),
};

const _$DebtDirectionEnumMap = {
  DebtDirection.iOwe: 'iOwe',
  DebtDirection.owedToMe: 'owedToMe',
};

Credit _$CreditFromJson(Map<String, dynamic> json) => Credit(
  id: json['id'] as String,
  name: json['name'] as String,
  bank: json['bank'] as String,
  initialMinor: (json['initialMinor'] as num).toInt(),
  remainingMinor: (json['remainingMinor'] as num).toInt(),
  annualRateBps: (json['annualRateBps'] as num).toInt(),
  monthlyMinor: (json['monthlyMinor'] as num).toInt(),
  start: DateTime.parse(json['start'] as String),
  end: DateTime.parse(json['end'] as String),
  nextPayment: DateTime.parse(json['nextPayment'] as String),
  currency: json['currency'] as String? ?? 'RUB',
  paidInterestMinor: (json['paidInterestMinor'] as num?)?.toInt() ?? 0,
  comment: json['comment'] as String? ?? '',
  paymentDay: (json['paymentDay'] as num?)?.toInt(),
);

Map<String, dynamic> _$CreditToJson(Credit instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'bank': instance.bank,
  'currency': instance.currency,
  'comment': instance.comment,
  'initialMinor': instance.initialMinor,
  'remainingMinor': instance.remainingMinor,
  'annualRateBps': instance.annualRateBps,
  'monthlyMinor': instance.monthlyMinor,
  'paidInterestMinor': instance.paidInterestMinor,
  'paymentDay': instance.paymentDay,
  'start': instance.start.toIso8601String(),
  'end': instance.end.toIso8601String(),
  'nextPayment': instance.nextPayment.toIso8601String(),
};

Goal _$GoalFromJson(Map<String, dynamic> json) => Goal(
  id: json['id'] as String,
  name: json['name'] as String,
  targetMinor: (json['targetMinor'] as num).toInt(),
  created: DateTime.parse(json['created'] as String),
  due: DateTime.parse(json['due'] as String),
  currency: json['currency'] as String? ?? 'RUB',
);

Map<String, dynamic> _$GoalToJson(Goal instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'currency': instance.currency,
  'targetMinor': instance.targetMinor,
  'created': instance.created.toIso8601String(),
  'due': instance.due.toIso8601String(),
};

RecurringPayment _$RecurringPaymentFromJson(Map<String, dynamic> json) =>
    RecurringPayment(
      id: json['id'] as String,
      name: json['name'] as String,
      amountMinor: (json['amountMinor'] as num).toInt(),
      due: DateTime.parse(json['due'] as String),
      accountId: json['accountId'] as String,
      currency: json['currency'] as String? ?? 'RUB',
      frequency: json['frequency'] as String? ?? 'monthly',
      reservedMinor: (json['reservedMinor'] as num?)?.toInt() ?? 0,
      category: json['category'] as String? ?? 'Обязательные платежи',
      anchorDay: (json['anchorDay'] as num?)?.toInt() ?? 1,
    );

Map<String, dynamic> _$RecurringPaymentToJson(RecurringPayment instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'currency': instance.currency,
      'frequency': instance.frequency,
      'accountId': instance.accountId,
      'category': instance.category,
      'amountMinor': instance.amountMinor,
      'reservedMinor': instance.reservedMinor,
      'anchorDay': instance.anchorDay,
      'due': instance.due.toIso8601String(),
    };

SavingsEntry _$SavingsEntryFromJson(Map<String, dynamic> json) => SavingsEntry(
  id: json['id'] as String,
  amountMinor: (json['amountMinor'] as num).toInt(),
  date: DateTime.parse(json['date'] as String),
  transactionId: json['transactionId'] as String,
  goalId: json['goalId'] as String?,
  currency: json['currency'] as String? ?? 'RUB',
);

Map<String, dynamic> _$SavingsEntryToJson(SavingsEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'transactionId': instance.transactionId,
      'currency': instance.currency,
      'goalId': instance.goalId,
      'amountMinor': instance.amountMinor,
      'date': instance.date.toIso8601String(),
    };
