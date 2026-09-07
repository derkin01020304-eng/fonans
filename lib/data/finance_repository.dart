import 'dart:convert';
import 'dart:math';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';
import '../core/money.dart';
import '../domain/models.dart';
import '../domain/repository.dart';
import '../services/categorizer.dart';
import 'demo_data.dart';

class SqlFinanceRepository implements FinanceRepository {
  SqlFinanceRepository(this.db);
  final DatabaseExecutor db;
  Future<T> atomic<T>(Future<T> Function(DatabaseExecutor tx) action) =>
      db is Database
      ? (db as Database).transaction((tx) => action(tx))
      : action(db);
  static const uuid = Uuid();
  static const tables = [
    'accounts',
    'categories',
    'transactions',
    'debts',
    'credits',
    'goals',
    'recurring_payments',
    'debt_payments',
    'credit_payments',
    'savings',
    'bank_connections',
    'category_rules',
    'bank_snapshots',
  ];

  Future<void> initialize() async {
    for (final category in expenseCategories) {
      await db.insert('categories', {
        'id': category,
        'name': category,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    if ((await db.query('accounts', limit: 1)).isEmpty) {
      await saveAccount(
        const Account(id: 'cash', name: 'Наличные', kind: AccountKind.cash),
      );
      await saveAccount(
        const Account(
          id: 'card',
          name: 'Основная карта',
          kind: AccountKind.card,
        ),
      );
      await saveAccount(
        const Account(
          id: 'savings',
          name: 'Накопления',
          kind: AccountKind.savings,
        ),
      );
    }
  }

  @override
  Future<FinanceSnapshot> snapshot() => atomic(
    (tx) async => FinanceSnapshot(
      accounts: (await tx.query(
        'accounts',
      )).map((e) => Account.fromJson(e)).toList(),
      transactions: (await tx.query(
        'transactions',
        orderBy: 'date DESC',
      )).map((e) => FinanceTransaction.fromJson(e)).toList(),
      debts: (await tx.query(
        'debts',
        orderBy: 'due',
      )).map((e) => Debt.fromJson(e)).toList(),
      credits: (await tx.query(
        'credits',
        orderBy: 'nextPayment',
      )).map((e) => Credit.fromJson(e)).toList(),
      goals: (await tx.query(
        'goals',
        orderBy: 'due',
      )).map((e) => Goal.fromJson(e)).toList(),
      payments: (await tx.query(
        'recurring_payments',
        orderBy: 'due',
      )).map((e) => RecurringPayment.fromJson(e)).toList(),
      savings: (await tx.query(
        'savings',
      )).map((e) => SavingsEntry.fromJson(e)).toList(),
      demo: (await tx.query(
        'settings',
        where: "key = 'demo' AND value = 'true'",
      )).isNotEmpty,
    ),
  );
  Future<Map<String, Object?>> one(
    DatabaseExecutor tx,
    String table,
    String id,
  ) async {
    final rows = await tx.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Запись не найдена');
    return rows.first;
  }

  Future<void> upsert(
    DatabaseExecutor tx,
    String table,
    Map<String, dynamic> row,
  ) async {
    final exists = (await tx.query(
      table,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [row['id']],
    )).isNotEmpty;
    if (exists) {
      await tx.update(table, row, where: 'id = ?', whereArgs: [row['id']]);
    } else {
      await tx.insert(table, row);
    }
  }

  void _currency(String value) {
    if (!['RUB', 'USD', 'EUR'].contains(value))
      throw ArgumentError('MVP поддерживает RUB, USD и EUR отдельно');
  }

  void _name(String value) {
    if (value.trim().isEmpty || value.length > 200)
      throw ArgumentError('Название должно содержать 1–200 символов');
  }

  @override
  Future<void> saveAccount(Account account) => atomic((tx) async {
    _name(account.name);
    _currency(account.currency);
    if (account.reservedMinor < 0 ||
        (account.kind == AccountKind.savings && account.reservedMinor != 0)) {
      throw ArgumentError('Резерв задаётся только для обычных счетов');
    }
    final old = await tx.query(
      'accounts',
      where: 'id = ?',
      whereArgs: [account.id],
    );
    if (old.isNotEmpty) {
      final hasHistory = (await tx.query(
        'transactions',
        where: 'accountId = ? OR toAccountId = ?',
        whereArgs: [account.id, account.id],
        limit: 1,
      )).isNotEmpty;
      if (hasHistory &&
          (old.first['currency'] != account.currency ||
              old.first['kind'] != account.kind.name)) {
        throw StateError('Нельзя менять валюту или тип счёта с операциями');
      }
    }
    await upsert(tx, 'accounts', account.toJson());
  });
  Future<void> validateTransaction(
    DatabaseExecutor tx,
    FinanceTransaction t,
  ) async {
    if (t.amountMinor <= 0 ||
        t.amountMinor > 99999999999999 ||
        t.workMinutes < 0) {
      throw ArgumentError('Некорректная сумма или рабочее время');
    }
    if (t.date.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      throw ArgumentError('Будущие платежи добавляйте в обязательства');
    }
    final account = await one(tx, 'accounts', t.accountId);
    if (t.currency != account['currency'])
      throw ArgumentError('Валюта не совпадает со счётом');
    if (t.kind == TransactionKind.transfer) {
      if (t.toAccountId == null || t.toAccountId == t.accountId)
        throw ArgumentError('Выберите другой счёт');
      final target = await one(tx, 'accounts', t.toAccountId!);
      if (target['currency'] != t.currency)
        throw ArgumentError(
          'Межвалютный перевод требует обменного курса; пока недоступен',
        );
    } else if (t.toAccountId != null) {
      throw ArgumentError('Счёт назначения допустим только у перевода');
    }
    if (account['kind'] == 'savings' &&
        t.kind != TransactionKind.transfer &&
        ![
          TransactionKind.income,
          TransactionKind.debtIn,
          TransactionKind.creditIn,
        ].contains(t.kind)) {
      throw ArgumentError(
        'Сначала переведите деньги с накопительного счёта на обычный',
      );
    }
    if (t.comment.length > 4000 || t.merchant.length > 500)
      throw ArgumentError('Слишком длинный текст');
  }

  Future<void> insertTransaction(
    DatabaseExecutor tx,
    FinanceTransaction t,
  ) async {
    await validateTransaction(tx, t);
    await tx.insert('transactions', t.toJson());
  }

  @override
  Future<void> addTransaction(FinanceTransaction transaction) =>
      atomic((tx) async {
        if (transaction.linkType != null)
          throw ArgumentError('Используйте специализированную операцию');
        // Savings transfers must create a savings ledger entry as well.
        final source = await one(tx, 'accounts', transaction.accountId);
        final target = transaction.toAccountId == null
            ? null
            : await one(tx, 'accounts', transaction.toAccountId!);
        if (transaction.kind == TransactionKind.transfer &&
            (source['kind'] == 'savings' || target?['kind'] == 'savings')) {
          await _addSavings(
            tx,
            transaction.amountMinor,
            transaction.accountId,
            transaction.toAccountId!,
            transaction.date,
            null,
            imported: transaction,
          );
          return;
        }
        await insertTransaction(tx, transaction);
      });
  @override
  Future<void> editTransaction(FinanceTransaction transaction) => atomic((
    tx,
  ) async {
    final old = await one(tx, 'transactions', transaction.id);
    if (old['linkType'] != null) {
      throw StateError(
        'Связанная операция изменяется через раздел обязательств или накоплений',
      );
    }
    if (transaction.externalKey != old['externalKey'] ||
        transaction.linkType != null) {
      throw ArgumentError('Нельзя менять идентификатор импорта');
    }
    await validateTransaction(tx, transaction);
    if (transaction.kind == TransactionKind.transfer) {
      for (final id in [transaction.accountId, transaction.toAccountId!]) {
        if ((await one(tx, 'accounts', id))['kind'] == 'savings') {
          throw StateError(
            'Перевод в накопления добавляется отдельной операцией',
          );
        }
      }
    }
    await tx.update(
      'transactions',
      transaction.toJson(),
      where: 'id = ?',
      whereArgs: [transaction.id],
    );
    if (transaction.needsReview == 0 &&
        transaction.merchant.trim().isNotEmpty) {
      await tx.insert('category_rules', {
        'merchant': normalizeMerchant(transaction.merchant),
        'category': transaction.category,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });
  @override
  Future<void> deleteTransaction(String id) => atomic((tx) async {
    final t = await one(tx, 'transactions', id);
    if (t['linkType'] != null)
      throw StateError('Связанные платежи нельзя удалять из журнала');
    await tx.delete('transactions', where: 'id = ?', whereArgs: [id]);
  });
  @override
  Future<void> saveDebt(Debt debt) => atomic((tx) async {
    _name(debt.name);
    _currency(debt.currency);
    if (debt.initialMinor <= 0 ||
        debt.remainingMinor < 0 ||
        debt.remainingMinor > debt.initialMinor ||
        debt.due.isBefore(day(debt.created)))
      throw ArgumentError('Проверьте сумму и даты долга');
    final old = await tx.query('debts', where: 'id = ?', whereArgs: [debt.id]);
    if (old.isNotEmpty &&
        (old.first['remainingMinor'] != debt.remainingMinor ||
            old.first['initialMinor'] != debt.initialMinor ||
            old.first['direction'] != debt.direction.name ||
            old.first['currency'] != debt.currency ||
            old.first['created'] != debt.created.toIso8601String())) {
      throw StateError(
        'Сумма и направление после создания меняются через погашение',
      );
    }
    await upsert(tx, 'debts', debt.toJson());
  });
  @override
  Future<void> repayDebt(
    String id,
    int amountMinor,
    String accountId,
    DateTime date,
  ) => atomic((tx) async {
    final d = Debt.fromJson(await one(tx, 'debts', id));
    if (amountMinor <= 0 ||
        amountMinor > d.remainingMinor ||
        date.isBefore(d.created)) {
      throw ArgumentError(
        'Платёж должен быть в пределах остатка и после создания долга',
      );
    }
    final t = FinanceTransaction(
      id: uuid.v4(),
      kind: d.direction == DebtDirection.iOwe
          ? TransactionKind.debtOut
          : TransactionKind.debtIn,
      amountMinor: amountMinor,
      accountId: accountId,
      date: date,
      currency: d.currency,
      category: 'Долги',
      merchant: d.name,
      linkType: 'debt',
      linkId: id,
    );
    await insertTransaction(tx, t);
    await tx.insert('debt_payments', {
      'id': uuid.v4(),
      'parentId': id,
      'amountMinor': amountMinor,
      'date': date.toIso8601String(),
      'transactionId': t.id,
    });
    await tx.update(
      'debts',
      {'remainingMinor': d.remainingMinor - amountMinor},
      where: 'id = ?',
      whereArgs: [id],
    );
  });
  @override
  Future<void> saveCredit(Credit credit) => atomic((tx) async {
    _name(credit.name);
    _currency(credit.currency);
    if (credit.initialMinor <= 0 ||
        credit.remainingMinor < 0 ||
        credit.remainingMinor > credit.initialMinor ||
        credit.annualRateBps < 0 ||
        credit.annualRateBps > 100000 ||
        credit.monthlyMinor <= 0 ||
        credit.end.isBefore(credit.start) ||
        credit.nextPayment.isBefore(credit.start)) {
      throw ArgumentError('Проверьте суммы, ставку и даты кредита');
    }
    final old = await tx.query(
      'credits',
      where: 'id = ?',
      whereArgs: [credit.id],
    );
    if (old.isNotEmpty &&
        (old.first['remainingMinor'] != credit.remainingMinor ||
            old.first['initialMinor'] != credit.initialMinor ||
            old.first['paidInterestMinor'] != credit.paidInterestMinor ||
            old.first['currency'] != credit.currency ||
            old.first['start'] != credit.start.toIso8601String())) {
      throw StateError('Остаток кредита изменяется через погашение');
    }
    await upsert(tx, 'credits', credit.toJson());
  });
  @override
  Future<void> repayCredit(
    String id,
    int principalMinor,
    int interestMinor,
    String accountId,
    DateTime date, {
    bool early = false,
  }) => atomic((tx) async {
    final c = Credit.fromJson(await one(tx, 'credits', id));
    if (principalMinor < 0 ||
        interestMinor < 0 ||
        principalMinor + interestMinor <= 0 ||
        principalMinor > c.remainingMinor ||
        date.isBefore(c.start)) {
      throw ArgumentError('Проверьте основной долг и проценты');
    }
    String? transactionId;
    if (principalMinor > 0) {
      transactionId = uuid.v4();
      await insertTransaction(
        tx,
        FinanceTransaction(
          id: transactionId,
          kind: TransactionKind.creditOut,
          amountMinor: principalMinor,
          accountId: accountId,
          date: date,
          currency: c.currency,
          category: 'Кредиты',
          merchant: c.bank,
          linkType: 'credit',
          linkId: id,
        ),
      );
    }
    if (interestMinor > 0) {
      await insertTransaction(
        tx,
        FinanceTransaction(
          id: uuid.v4(),
          kind: TransactionKind.expense,
          amountMinor: interestMinor,
          accountId: accountId,
          date: date,
          currency: c.currency,
          category: 'Кредиты',
          subcategory: 'Проценты',
          merchant: c.bank,
          linkType: 'credit_interest',
          linkId: id,
        ),
      );
    }
    await tx.insert('credit_payments', {
      'id': uuid.v4(),
      'parentId': id,
      'principalMinor': principalMinor,
      'interestMinor': interestMinor,
      'date': date.toIso8601String(),
      'early': early ? 1 : 0,
      'transactionId': transactionId,
    });
    await tx.update(
      'credits',
      {
        'remainingMinor': c.remainingMinor - principalMinor,
        'paidInterestMinor': c.paidInterestMinor + interestMinor,
        'nextPayment':
            (early ? c.nextPayment : anchoredMonth(c.nextPayment, c.paymentDay))
                .toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  });
  @override
  Future<void> saveGoal(Goal goal) => atomic((tx) async {
    _name(goal.name);
    _currency(goal.currency);
    if (goal.targetMinor <= 0 || goal.due.isBefore(day(goal.created)))
      throw ArgumentError('Проверьте цель');
    final old = await tx.query('goals', where: 'id = ?', whereArgs: [goal.id]);
    if (old.isNotEmpty && old.first['currency'] != goal.currency)
      throw ArgumentError('Валюту цели менять нельзя');
    await upsert(tx, 'goals', goal.toJson());
  });
  @override
  Future<void> addSavings(
    int amountMinor,
    String fromAccountId,
    String toAccountId,
    DateTime date, {
    String? goalId,
  }) => atomic(
    (tx) =>
        _addSavings(tx, amountMinor, fromAccountId, toAccountId, date, goalId),
  );
  Future<void> _addSavings(
    DatabaseExecutor tx,
    int amountMinor,
    String from,
    String to,
    DateTime date,
    String? goalId, {
    FinanceTransaction? imported,
  }) async {
    final source = Account.fromJson(await one(tx, 'accounts', from));
    final target = Account.fromJson(await one(tx, 'accounts', to));
    final depositing =
        target.kind == AccountKind.savings &&
        source.kind != AccountKind.savings;
    final withdrawing =
        source.kind == AccountKind.savings &&
        target.kind != AccountKind.savings;
    if (!depositing && !withdrawing)
      throw ArgumentError('Один из счетов должен быть накопительным');
    final signed = depositing ? amountMinor : -amountMinor;
    if (goalId != null) {
      final goal = await one(tx, 'goals', goalId);
      if (goal['currency'] != source.currency)
        throw ArgumentError('Валюта цели не совпадает');
      final saved =
          (await tx.rawQuery(
                'SELECT COALESCE(SUM(amountMinor),0) AS value FROM savings WHERE goalId = ?',
                [goalId],
              )).first['value']
              as int;
      if (saved + signed < 0)
        throw ArgumentError('В цели недостаточно накоплений');
    }
    // Prevent spending allocations of another goal when withdrawing unallocated funds.
    if (withdrawing) {
      final entries = await tx.query('transactions');
      final balance =
          source.openingMinor +
          entries
              .map((e) => FinanceTransaction.fromJson(e))
              .fold<int>(0, (s, t) => s + t.delta(source.id));
      if (amountMinor > balance)
        throw ArgumentError('На накопительном счёте недостаточно средств');
      if (goalId == null) {
        final allocated =
            (await tx.rawQuery(
                  'SELECT COALESCE(SUM(amountMinor),0) AS value FROM savings WHERE goalId IS NOT NULL AND currency = ?',
                  [source.currency],
                )).first['value']
                as int;
        final accounts = (await tx.query(
          'accounts',
          where: "kind = 'savings' AND currency = ?",
          whereArgs: [source.currency],
        )).map((e) => Account.fromJson(e));
        final total = accounts.fold<int>(
          0,
          (sum, a) =>
              sum +
              a.openingMinor +
              entries
                  .map((e) => FinanceTransaction.fromJson(e))
                  .fold<int>(0, (s, t) => s + t.delta(a.id)),
        );
        if (amountMinor > total - allocated)
          throw ArgumentError('Выберите цель, из которой снимаете накопления');
      }
    }
    final t = FinanceTransaction(
      id: imported?.id ?? uuid.v4(),
      externalKey: imported?.externalKey,
      source: imported?.source ?? '',
      comment: imported?.comment ?? '',
      kind: TransactionKind.transfer,
      amountMinor: amountMinor,
      accountId: from,
      toAccountId: to,
      date: date,
      currency: source.currency,
      category: 'Накопления',
      linkType: 'savings',
      linkId: goalId,
    );
    await insertTransaction(tx, t);
    await tx.insert(
      'savings',
      SavingsEntry(
        id: uuid.v4(),
        amountMinor: signed,
        date: date,
        transactionId: t.id,
        goalId: goalId,
        currency: source.currency,
      ).toJson(),
    );
  }

  @override
  Future<void> savePayment(RecurringPayment p) => atomic((tx) async {
    _name(p.name);
    _currency(p.currency);
    final a = await one(tx, 'accounts', p.accountId);
    if (p.currency != a['currency'] ||
        a['kind'] == 'savings' ||
        p.amountMinor <= 0 ||
        p.reservedMinor < 0 ||
        p.reservedMinor > p.amountMinor) {
      throw ArgumentError('Проверьте сумму, резерв и счёт платежа');
    }
    await upsert(tx, 'recurring_payments', p.toJson());
  });
  @override
  Future<void> payRecurring(String id, String accountId, DateTime date) =>
      atomic((tx) async {
        final p = RecurringPayment.fromJson(
          await one(tx, 'recurring_payments', id),
        );
        await insertTransaction(
          tx,
          FinanceTransaction(
            id: uuid.v4(),
            kind: TransactionKind.expense,
            amountMinor: p.amountMinor,
            accountId: accountId,
            date: date,
            currency: p.currency,
            category: p.category,
            comment: p.name,
            linkType: 'recurring',
            linkId: id,
          ),
        );
        if (p.frequency == 'once') {
          await tx.delete(
            'recurring_payments',
            where: 'id = ?',
            whereArgs: [id],
          );
        } else {
          var next = switch (p.frequency) {
            'weekly' => DateTime(p.due.year, p.due.month, p.due.day + 7),
            'yearly' => nextMonth(p.due, 12),
            _ => nextMonth(p.due),
          };
          if (p.frequency == 'monthly') {
            next = DateTime(
              next.year,
              next.month,
              min(p.anchorDay, DateTime(next.year, next.month + 1, 0).day),
            );
          }
          await tx.update(
            'recurring_payments',
            {'due': next.toIso8601String(), 'reservedMinor': 0},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      });
  @override
  Future<void> deleteEntity(String table, String id) => atomic((tx) async {
    if (![
      'accounts',
      'debts',
      'credits',
      'goals',
      'recurring_payments',
    ].contains(table))
      throw ArgumentError('Недопустимый раздел');
    if (table == 'debts' || table == 'credits') {
      final prefix = table == 'debts' ? 'debt%' : 'credit%';
      if ((await tx.query(
        'transactions',
        columns: ['id'],
        where: 'linkId = ? AND linkType LIKE ?',
        whereArgs: [id, prefix],
        limit: 1,
      )).isNotEmpty) {
        throw StateError(
          'У записи есть движение денег; сохранить историю обязательно',
        );
      }
    }
    if (table == 'accounts') {
      final a = Account.fromJson(await one(tx, table, id));
      if (a.openingMinor != 0)
        throw StateError('Нельзя удалить счёт с начальным балансом');
      if ((await tx.query('accounts')).length <= 1)
        throw StateError('Нужен хотя бы один счёт');
    }
    try {
      await tx.delete(table, where: 'id = ?', whereArgs: [id]);
    } on DatabaseException {
      throw StateError(
        'У записи есть история. Сохраните её для корректного учёта.',
      );
    }
  });
  @override
  Future<List<Map<String, Object?>>> history(String table, String parentId) {
    if (!['debt_payments', 'credit_payments'].contains(table))
      throw ArgumentError('Недопустимый раздел');
    return db.query(
      table,
      where: 'parentId = ?',
      whereArgs: [parentId],
      orderBy: 'date DESC',
    );
  }

  Future<Map<String, String>> categoryRules() async => {
    for (final row in await db.query('category_rules'))
      row['merchant'] as String: row['category'] as String,
  };
  Future<void> audit(String action) => db
      .insert('audit_log', {
        'id': uuid.v4(),
        'action': action,
        'created': DateTime.now().toIso8601String(),
      })
      .then((_) {});
  @override
  Future<Map<String, dynamic>> exportBackup() => atomic(
    (tx) async => {
      'schemaVersion': 2,
      'created': DateTime.now().toUtc().toIso8601String(),
      'tables': {for (final table in tables) table: await tx.query(table)},
    },
  );
  @override
  Future<void> restoreBackup(Map<String, dynamic> data) async {
    if (data['schemaVersion'] != 2 || data['tables'] is! Map)
      throw const FormatException('Неподдерживаемая резервная копия');
    final payload = Map<String, dynamic>.from(data['tables'] as Map);
    if (tables.any((t) => payload[t] is! List))
      throw const FormatException('Неполная резервная копия');
    await atomic((tx) async {
      for (final table in tables.reversed) {
        await tx.delete(table);
      }
      await tx.delete('api_requests');
      await tx.delete('audit_log');
      for (final table in tables) {
        final columns = (await tx.rawQuery(
          'PRAGMA table_info($table)',
        )).map((r) => r['name']).toSet();
        for (final raw in payload[table] as List) {
          final row = Map<String, dynamic>.from(raw as Map);
          if (row.keys.any((k) => !columns.contains(k)))
            throw const FormatException('Неизвестный столбец');
          await tx.insert(table, row);
        }
      }
      for (final row in await tx.query('transactions')) {
        await validateTransaction(tx, FinanceTransaction.fromJson(row));
      }
      if ((await tx.rawQuery('PRAGMA foreign_key_check')).isNotEmpty)
        throw const FormatException('Нарушены связи резервной копии');
      await tx.delete('settings', where: "key = 'demo'");
    });
  }

  @override
  Future<void> seedDemo() =>
      atomic((tx) => SqlFinanceRepository(tx)._seedDemo());

  Future<void> _seedDemo() async {
    if ((await db.query('transactions', limit: 1)).isNotEmpty ||
        (await db.query('debts', limit: 1)).isNotEmpty ||
        (await db.query('goals', limit: 1)).isNotEmpty ||
        (await db.query('credits', limit: 1)).isNotEmpty ||
        (await db.query('recurring_payments', limit: 1)).isNotEmpty ||
        (await db.query('bank_connections', limit: 1)).isNotEmpty) {
      throw StateError('Демо загружается только в пустой учёт');
    }
    final backup = await exportBackup();
    await db.insert('settings', {
      'key': 'before_demo',
      'value': jsonEncode(backup),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await restoreBackup(demoData(DateTime.now()));
    await db.insert('settings', {
      'key': 'demo',
      'value': 'true',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> clearDemo() =>
      atomic((tx) => SqlFinanceRepository(tx)._clearDemo());

  Future<void> _clearDemo() async {
    final rows = await db.query('settings', where: "key = 'before_demo'");
    if (rows.isEmpty) throw StateError('Демо не загружено');
    await restoreBackup(
      jsonDecode(rows.first['value'] as String) as Map<String, dynamic>,
    );
    await db.delete('settings', where: "key = 'before_demo'");
  }
}
