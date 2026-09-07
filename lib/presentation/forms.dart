import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/money.dart';
import '../data/finance_repository.dart';
import '../domain/models.dart';
import '../services/categorizer.dart';
import 'editor.dart';
import 'providers.dart';

Map<String, String> accountChoices(FinanceSnapshot s) => {
  for (final a in s.accounts) a.id: '${a.name} · ${a.currency}',
};
String preferredAccount(FinanceSnapshot s) =>
    s.accounts.where((a) => a.kind == AccountKind.card).firstOrNull?.id ??
    s.accounts.first.id;
const accountKinds = {
  'card': 'Карта',
  'bank': 'Банковский счёт',
  'cash': 'Наличные',
  'savings': 'Накопительный',
  'virtual': 'Виртуальный',
  'wallet': 'Кошелёк',
};

Future<void> transactionForm(
  BuildContext context,
  WidgetRef ref,
  FinanceSnapshot s, {
  TransactionKind kind = TransactionKind.expense,
  FinanceTransaction? existing,
  QuickEntry? quick,
}) async {
  kind = existing?.kind ?? quick?.kind ?? kind;
  if (existing?.linkType != null) {
    message(
      context,
      'Этот платёж связан с обязательством или накоплением. Откройте соответствующий раздел.',
    );
    return;
  }
  final initialAccount = existing?.accountId ?? preferredAccount(s);
  final fields = <FieldSpec>[
    FieldSpec(
      'amount',
      'Сумма',
      kind: InputKind.money,
      initial: existing != null
          ? decimalMoney(existing.amountMinor)
          : quick != null
          ? decimalMoney(quick.amountMinor)
          : '',
    ),
    FieldSpec(
      'account',
      'Счёт',
      kind: InputKind.choice,
      initial: initialAccount,
      choices: accountChoices(s),
    ),
    if (kind == TransactionKind.transfer)
      FieldSpec(
        'to',
        'Куда',
        kind: InputKind.choice,
        initial:
            existing?.toAccountId ??
            s.accounts.where((a) => a.id != initialAccount).firstOrNull?.id ??
            initialAccount,
        choices: accountChoices(s),
      ),
    FieldSpec(
      'date',
      'Дата и время',
      kind: InputKind.dateTime,
      initial: existing?.date ?? DateTime.now(),
    ),
    if (kind != TransactionKind.transfer)
      FieldSpec(
        'category',
        'Категория',
        kind: InputKind.choice,
        initial: existing?.category ?? quick?.category ?? 'Прочее',
        choices: {
          for (final c in {
            ...expenseCategories,
            existing?.category ?? 'Прочее',
          })
            c: c,
        },
      ),
    if (kind != TransactionKind.transfer)
      FieldSpec(
        'subcategory',
        'Подкатегория',
        initial: existing?.subcategory ?? '',
        required: false,
      ),
    if (kind == TransactionKind.income)
      FieldSpec(
        'source',
        'Источник дохода',
        initial: existing?.source ?? quick?.comment ?? '',
        required: false,
      ),
    if (kind == TransactionKind.income)
      FieldSpec(
        'hours',
        'Рабочих часов',
        kind: InputKind.number,
        initial: existing == null
            ? '0'
            : (existing.workMinutes / 60).toString(),
        required: false,
      ),
    if (kind == TransactionKind.expense)
      FieldSpec(
        'merchant',
        'Магазин / получатель',
        initial: existing?.merchant ?? '',
        required: false,
      ),
    FieldSpec(
      'method',
      'Способ оплаты / поступления',
      initial: existing?.paymentMethod ?? '',
      required: false,
    ),
    FieldSpec(
      'comment',
      'Комментарий',
      initial: existing?.comment ?? quick?.comment ?? '',
      required: false,
    ),
  ];
  final selectedKind = kind;
  await showEditor(
    context,
    title: existing != null
        ? 'Изменить операцию'
        : kind == TransactionKind.income
        ? 'Доход'
        : kind == TransactionKind.transfer
        ? 'Перевод'
        : 'Расход',
    fields: fields,
    onSave: (v) async {
      final account = s.accounts.firstWhere((a) => a.id == v['account']);
      final t = FinanceTransaction(
        id: existing?.id ?? SqlFinanceRepository.uuid.v4(),
        kind: selectedKind,
        amountMinor: parseMoney(v['amount'] as String),
        accountId: account.id,
        currency: account.currency,
        date: v['date'] as DateTime,
        toAccountId: v['to'] as String?,
        category: v['category'] as String? ?? 'Переводы',
        subcategory: v['subcategory'] as String? ?? '',
        source: v['source'] as String? ?? '',
        merchant: v['merchant'] as String? ?? '',
        comment: v['comment'] as String? ?? '',
        paymentMethod: v['method'] as String? ?? '',
        workMinutes:
            ((double.tryParse(
                          (v['hours'] as String? ?? '').replaceAll(',', '.'),
                        ) ??
                        0) *
                    60)
                .round(),
        externalKey: existing?.externalKey,
        mcc: existing?.mcc,
        needsReview: 0,
      );
      final repo = ref.read(runtimeProvider).repository;
      if (existing == null) {
        await repo.addTransaction(t);
      } else {
        await repo.editTransaction(t);
      }
      await refresh(ref);
    },
  );
}

Future<void> accountForm(
  BuildContext context,
  WidgetRef ref, {
  Account? existing,
}) => showEditor(
  context,
  title: existing == null ? 'Новый счёт' : 'Изменить счёт',
  note:
      'Начальный остаток — сумма на начало ведения учёта, до внесённых операций. Валюты учитываются отдельно.',
  fields: [
    FieldSpec('name', 'Название', initial: existing?.name ?? ''),
    FieldSpec(
      'kind',
      'Тип',
      kind: InputKind.choice,
      initial: existing?.kind.name ?? 'card',
      choices: accountKinds,
    ),
    FieldSpec(
      'currency',
      'Валюта',
      kind: InputKind.choice,
      initial: existing?.currency ?? 'RUB',
      choices: const {'RUB': 'Рубли', 'USD': 'Доллары', 'EUR': 'Евро'},
    ),
    FieldSpec(
      'opening',
      'Начальный остаток',
      kind: InputKind.money,
      initial: decimalMoney(existing?.openingMinor ?? 0),
      allowNegative: true,
    ),
    FieldSpec(
      'reserved',
      'Отдельный резерв',
      kind: InputKind.money,
      initial: decimalMoney(existing?.reservedMinor ?? 0),
    ),
  ],
  onSave: (v) async {
    await ref
        .read(runtimeProvider)
        .repository
        .saveAccount(
          Account(
            id: existing?.id ?? SqlFinanceRepository.uuid.v4(),
            name: v['name'] as String,
            kind: AccountKind.values.byName(v['kind'] as String),
            currency: v['currency'] as String,
            openingMinor: parseMoney(
              v['opening'] as String,
              allowNegative: true,
            ),
            reservedMinor: parseMoney(v['reserved'] as String),
            bankId: existing?.bankId,
            externalId: existing?.externalId,
          ),
        );
    await refresh(ref);
  },
);
Future<void> debtForm(
  BuildContext context,
  WidgetRef ref,
  FinanceSnapshot s, {
  Debt? existing,
}) => showEditor(
  context,
  title: existing == null ? 'Новый долг' : 'Изменить долг',
  note:
      'Запись уже существующего долга не меняет баланс счетов. Для нового займа можно отдельно отметить движение денег.',
  fields: [
    FieldSpec('name', 'Человек / организация', initial: existing?.name ?? ''),
    if (existing == null)
      const FieldSpec(
        'direction',
        'Направление',
        kind: InputKind.choice,
        initial: 'iOwe',
        choices: {'iOwe': 'Я должен', 'owedToMe': 'Мне должны'},
      ),
    if (existing == null)
      const FieldSpec('initial', 'Первоначальная сумма', kind: InputKind.money),
    if (existing == null)
      const FieldSpec('remaining', 'Текущий остаток', kind: InputKind.money),
    if (existing == null)
      FieldSpec(
        'created',
        'Дата создания',
        kind: InputKind.date,
        initial: day(DateTime.now()),
      ),
    FieldSpec(
      'due',
      'Срок возврата',
      kind: InputKind.date,
      initial:
          existing?.due ?? day(DateTime.now()).add(const Duration(days: 30)),
    ),
    FieldSpec(
      'comment',
      'Комментарий',
      initial: existing?.comment ?? '',
      required: false,
    ),
    if (existing == null)
      const FieldSpec(
        'currency',
        'Валюта',
        kind: InputKind.choice,
        initial: 'RUB',
        choices: {'RUB': 'RUB', 'USD': 'USD', 'EUR': 'EUR'},
      ),
    if (existing == null)
      const FieldSpec(
        'cash',
        'Учесть получение / выдачу денег',
        kind: InputKind.toggle,
        initial: false,
      ),
    if (existing == null)
      FieldSpec(
        'account',
        'Счёт для движения денег',
        kind: InputKind.choice,
        initial: preferredAccount(s),
        choices: accountChoices(s),
      ),
  ],
  onSave: (v) async {
    final d = Debt(
      id: existing?.id ?? SqlFinanceRepository.uuid.v4(),
      name: v['name'] as String,
      direction:
          existing?.direction ??
          DebtDirection.values.byName(v['direction'] as String),
      initialMinor:
          existing?.initialMinor ?? parseMoney(v['initial'] as String),
      remainingMinor:
          existing?.remainingMinor ?? parseMoney(v['remaining'] as String),
      created: existing?.created ?? v['created'] as DateTime,
      due: v['due'] as DateTime,
      currency: existing?.currency ?? v['currency'] as String,
      comment: v['comment'] as String,
    );
    final repo = ref.read(runtimeProvider).repository;
    await repo.atomic((tx) async {
      final scoped = SqlFinanceRepository(tx);
      await scoped.saveDebt(d);
      if (v['cash'] == true) {
        if (d.initialMinor != d.remainingMinor)
          throw ArgumentError(
            'Для нового займа остаток должен равняться первоначальной сумме',
          );
        await scoped.insertTransaction(
          tx,
          FinanceTransaction(
            id: SqlFinanceRepository.uuid.v4(),
            kind: d.direction == DebtDirection.iOwe
                ? TransactionKind.debtIn
                : TransactionKind.debtOut,
            amountMinor: d.initialMinor,
            accountId: v['account'] as String,
            date: d.created,
            currency: d.currency,
            category: 'Долги',
            merchant: d.name,
            linkType: 'debt_opening',
            linkId: d.id,
          ),
        );
      }
    });
    await refresh(ref);
  },
);
Future<void> repayDebtForm(
  BuildContext context,
  WidgetRef ref,
  FinanceSnapshot s,
  Debt d,
) => showEditor(
  context,
  title: d.direction == DebtDirection.iOwe
      ? 'Погасить долг'
      : 'Получить возврат',
  note:
      'Остаток: ${money(d.remainingMinor, d.currency)}. Возврат основной суммы не считается доходом или расходом.',
  fields: [
    FieldSpec(
      'amount',
      'Сумма возврата',
      kind: InputKind.money,
      initial: decimalMoney(d.remainingMinor),
    ),
    FieldSpec(
      'account',
      'Счёт',
      kind: InputKind.choice,
      initial: preferredAccount(s),
      choices: accountChoices(s),
    ),
    FieldSpec(
      'date',
      'Дата платежа',
      kind: InputKind.dateTime,
      initial: DateTime.now(),
    ),
  ],
  onSave: (v) async {
    await ref
        .read(runtimeProvider)
        .repository
        .repayDebt(
          d.id,
          parseMoney(v['amount'] as String),
          v['account'] as String,
          v['date'] as DateTime,
        );
    await refresh(ref);
  },
);
Future<void> creditForm(
  BuildContext context,
  WidgetRef ref, {
  Credit? existing,
}) => showEditor(
  context,
  title: existing == null ? 'Кредит или рассрочка' : 'Изменить кредит',
  note:
      'Добавляется существующее обязательство. Баланс счетов не меняется. Для рассрочки укажите ставку 0.',
  fields: [
    FieldSpec('name', 'Название', initial: existing?.name ?? ''),
    FieldSpec('bank', 'Банк / организация', initial: existing?.bank ?? ''),
    if (existing == null)
      const FieldSpec('initial', 'Первоначальная сумма', kind: InputKind.money),
    if (existing == null)
      const FieldSpec(
        'remaining',
        'Остаток основного долга',
        kind: InputKind.money,
      ),
    FieldSpec(
      'rate',
      'Ставка, % годовых',
      kind: InputKind.number,
      initial: ((existing?.annualRateBps ?? 0) / 100).toString(),
    ),
    FieldSpec(
      'monthly',
      'Ежемесячный платёж',
      kind: InputKind.money,
      initial: existing == null ? '' : decimalMoney(existing.monthlyMinor),
    ),
    if (existing == null)
      FieldSpec(
        'start',
        'Дата начала',
        kind: InputKind.date,
        initial: day(DateTime.now()),
      ),
    FieldSpec(
      'end',
      'Дата окончания',
      kind: InputKind.date,
      initial: existing?.end ?? nextMonth(DateTime.now(), 12),
    ),
    FieldSpec(
      'next',
      'Следующий платёж',
      kind: InputKind.date,
      initial: existing?.nextPayment ?? nextMonth(DateTime.now()),
    ),
    FieldSpec(
      'comment',
      'Комментарий',
      initial: existing?.comment ?? '',
      required: false,
    ),
    if (existing == null)
      const FieldSpec(
        'currency',
        'Валюта',
        kind: InputKind.choice,
        initial: 'RUB',
        choices: {'RUB': 'RUB', 'USD': 'USD', 'EUR': 'EUR'},
      ),
  ],
  onSave: (v) async {
    await ref
        .read(runtimeProvider)
        .repository
        .saveCredit(
          Credit(
            id: existing?.id ?? SqlFinanceRepository.uuid.v4(),
            name: v['name'] as String,
            bank: v['bank'] as String,
            initialMinor:
                existing?.initialMinor ?? parseMoney(v['initial'] as String),
            remainingMinor:
                existing?.remainingMinor ??
                parseMoney(v['remaining'] as String),
            annualRateBps:
                (double.parse((v['rate'] as String).replaceAll(',', '.')) * 100)
                    .round(),
            monthlyMinor: parseMoney(v['monthly'] as String),
            start: existing?.start ?? v['start'] as DateTime,
            end: v['end'] as DateTime,
            nextPayment: v['next'] as DateTime,
            paymentDay: existing != null && v['next'] == existing.nextPayment
                ? existing.paymentDay
                : (v['next'] as DateTime).day,
            currency: existing?.currency ?? v['currency'] as String,
            paidInterestMinor: existing?.paidInterestMinor ?? 0,
            comment: v['comment'] as String,
          ),
        );
    await refresh(ref);
  },
);
Future<void> repayCreditForm(
  BuildContext context,
  WidgetRef ref,
  FinanceSnapshot s,
  Credit c,
) => showEditor(
  context,
  title: 'Платёж по кредиту',
  note:
      'Разделите сумму по данным банка. Только проценты входят в расходы. Досрочный платёж не переносит следующую дату.',
  fields: [
    FieldSpec(
      'principal',
      'Основной долг',
      kind: InputKind.money,
      initial: decimalMoney(c.monthlyMinor.clamp(0, c.remainingMinor)),
    ),
    const FieldSpec(
      'interest',
      'Проценты / комиссия',
      kind: InputKind.money,
      initial: '0',
    ),
    FieldSpec(
      'account',
      'Счёт',
      kind: InputKind.choice,
      initial: preferredAccount(s),
      choices: accountChoices(s),
    ),
    FieldSpec(
      'date',
      'Дата платежа',
      kind: InputKind.dateTime,
      initial: DateTime.now(),
    ),
    const FieldSpec(
      'early',
      'Досрочное погашение',
      kind: InputKind.toggle,
      initial: false,
    ),
  ],
  onSave: (v) async {
    await ref
        .read(runtimeProvider)
        .repository
        .repayCredit(
          c.id,
          parseMoney(v['principal'] as String),
          parseMoney(v['interest'] as String),
          v['account'] as String,
          v['date'] as DateTime,
          early: v['early'] as bool,
        );
    await refresh(ref);
  },
);
Future<void> goalForm(BuildContext context, WidgetRef ref, {Goal? existing}) =>
    showEditor(
      context,
      title: existing == null ? 'Финансовая цель' : 'Изменить цель',
      fields: [
        FieldSpec('name', 'Название', initial: existing?.name ?? ''),
        FieldSpec(
          'target',
          'Нужная сумма',
          kind: InputKind.money,
          initial: existing == null ? '' : decimalMoney(existing.targetMinor),
        ),
        FieldSpec(
          'due',
          'Дата цели',
          kind: InputKind.date,
          initial: existing?.due ?? nextMonth(DateTime.now(), 3),
        ),
        if (existing == null)
          const FieldSpec(
            'currency',
            'Валюта',
            kind: InputKind.choice,
            initial: 'RUB',
            choices: {'RUB': 'RUB', 'USD': 'USD', 'EUR': 'EUR'},
          ),
      ],
      onSave: (v) async {
        await ref
            .read(runtimeProvider)
            .repository
            .saveGoal(
              Goal(
                id: existing?.id ?? SqlFinanceRepository.uuid.v4(),
                name: v['name'] as String,
                targetMinor: parseMoney(v['target'] as String),
                created: existing?.created ?? day(DateTime.now()),
                due: v['due'] as DateTime,
                currency: existing?.currency ?? v['currency'] as String,
              ),
            );
        await refresh(ref);
      },
    );
Future<void> savingsForm(
  BuildContext context,
  WidgetRef ref,
  FinanceSnapshot s, {
  Goal? goal,
}) async {
  final saving = s.accounts
      .where((a) => a.kind == AccountKind.savings)
      .firstOrNull;
  if (saving == null) {
    message(context, 'Сначала создайте накопительный счёт');
    return;
  }
  await showEditor(
    context,
    title: 'Пополнить или снять накопления',
    note:
        'Для снятия поменяйте счета местами и выберите цель, из которой берёте деньги.',
    fields: [
      const FieldSpec('amount', 'Сумма', kind: InputKind.money),
      FieldSpec(
        'from',
        'Откуда',
        kind: InputKind.choice,
        initial: preferredAccount(s),
        choices: accountChoices(s),
      ),
      FieldSpec(
        'to',
        'Куда',
        kind: InputKind.choice,
        initial: saving.id,
        choices: accountChoices(s),
      ),
      FieldSpec(
        'goal',
        'Цель',
        kind: InputKind.choice,
        initial: goal?.id ?? '',
        choices: {'': 'Без цели', for (final g in s.goals) g.id: g.name},
      ),
      FieldSpec(
        'date',
        'Дата',
        kind: InputKind.dateTime,
        initial: DateTime.now(),
      ),
    ],
    onSave: (v) async {
      await ref
          .read(runtimeProvider)
          .repository
          .addSavings(
            parseMoney(v['amount'] as String),
            v['from'] as String,
            v['to'] as String,
            v['date'] as DateTime,
            goalId: v['goal'] == '' ? null : v['goal'] as String,
          );
      await refresh(ref);
    },
  );
}

Future<void> paymentForm(
  BuildContext context,
  WidgetRef ref,
  FinanceSnapshot s, {
  RecurringPayment? existing,
}) => showEditor(
  context,
  title: existing == null ? 'Обязательный платёж' : 'Изменить платёж',
  note:
      'Резерв уменьшает доступные деньги, но не баланс. Кредит из раздела «Кредиты» не нужно дублировать здесь.',
  fields: [
    FieldSpec('name', 'Название', initial: existing?.name ?? ''),
    FieldSpec(
      'amount',
      'Сумма',
      kind: InputKind.money,
      initial: existing == null ? '' : decimalMoney(existing.amountMinor),
    ),
    FieldSpec(
      'reserved',
      'Уже отложено',
      kind: InputKind.money,
      initial: decimalMoney(existing?.reservedMinor ?? 0),
    ),
    FieldSpec(
      'account',
      'Счёт',
      kind: InputKind.choice,
      initial: existing?.accountId ?? preferredAccount(s),
      choices: accountChoices(s),
    ),
    FieldSpec(
      'due',
      'Дата платежа',
      kind: InputKind.date,
      initial:
          existing?.due ?? day(DateTime.now()).add(const Duration(days: 7)),
    ),
    FieldSpec(
      'frequency',
      'Повторение',
      kind: InputKind.choice,
      initial: existing?.frequency ?? 'monthly',
      choices: const {
        'once': 'Один раз',
        'weekly': 'Еженедельно',
        'monthly': 'Ежемесячно',
        'yearly': 'Ежегодно',
      },
    ),
    FieldSpec(
      'category',
      'Категория',
      kind: InputKind.choice,
      initial: existing?.category ?? 'Обязательные платежи',
      choices: {for (final c in expenseCategories) c: c},
    ),
  ],
  onSave: (v) async {
    final a = s.accounts.firstWhere((a) => a.id == v['account']);
    await ref
        .read(runtimeProvider)
        .repository
        .savePayment(
          RecurringPayment(
            id: existing?.id ?? SqlFinanceRepository.uuid.v4(),
            name: v['name'] as String,
            amountMinor: parseMoney(v['amount'] as String),
            reservedMinor: parseMoney(v['reserved'] as String),
            accountId: a.id,
            currency: a.currency,
            due: v['due'] as DateTime,
            frequency: v['frequency'] as String,
            category: v['category'] as String,
            anchorDay: existing != null && v['due'] == existing.due
                ? existing.anchorDay
                : (v['due'] as DateTime).day,
          ),
        );
    await refresh(ref);
  },
);
