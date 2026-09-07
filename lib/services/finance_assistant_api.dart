import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../core/money.dart';
import '../data/finance_repository.dart';
import '../domain/analytics.dart';
import '../domain/models.dart';
import '../integrations/mcp/permissions.dart';
import '../integrations/mcp/schema_validator.dart';

abstract interface class FinanceAssistantAPI {
  List<Map<String, dynamic>> get tools;
  Future<Object> call(
    String name,
    Map<String, dynamic> arguments, {
    required String token,
  });
}

class LocalFinanceAssistantAPI implements FinanceAssistantAPI {
  LocalFinanceAssistantAPI(
    this.repository,
    this.permissions,
    this.tools, {
    this.onWrite,
  });
  final SqlFinanceRepository repository;
  final PermissionService permissions;
  @override
  final List<Map<String, dynamic>> tools;
  final void Function()? onWrite;
  static const readTools = {
    'get_balance',
    'get_summary',
    'get_transactions',
    'search_transactions',
    'get_debts',
    'get_credits',
    'get_goals',
    'get_upcoming_payments',
  };
  static const writeTools = {
    'add_income',
    'add_expense',
    'add_debt',
    'update_debt',
    'add_credit',
    'add_savings',
    'create_goal',
    'update_goal',
  };
  @override
  Future<Object> call(
    String name,
    Map<String, dynamic> arguments, {
    required String token,
  }) async {
    permissions.authorize(token, name);
    final schema = tools.where((t) => t['name'] == name).firstOrNull;
    if (schema == null) throw ArgumentError('Неизвестный инструмент');
    validateSchema(
      arguments,
      Map<String, dynamic>.from(schema['inputSchema'] as Map),
    );
    if (readTools.contains(name)) return _read(name, arguments);
    final requestId = arguments['requestId'] as String;
    final ordered = {
      for (final key in arguments.keys.toList()..sort()) key: arguments[key],
    };
    final digest = sha256.convert(utf8.encode(jsonEncode(ordered))).toString();
    final result = await repository.atomic((tx) async {
      permissions.authorize(token, name);
      final previous = await tx.query(
        'api_requests',
        where: 'id = ?',
        whereArgs: [requestId],
      );
      if (previous.isNotEmpty) {
        if (previous.first['tool'] != name ||
            previous.first['payloadHash'] != digest) {
          throw ArgumentError('requestId уже использован для другой команды');
        }
        return jsonDecode(previous.first['result'] as String) as Object;
      }
      final result = await _write(SqlFinanceRepository(tx), name, arguments);
      await tx.insert('api_requests', {
        'id': requestId,
        'tool': name,
        'payloadHash': digest,
        'result': jsonEncode(result),
        'created': DateTime.now().toIso8601String(),
      });
      await tx.insert('audit_log', {
        'id': SqlFinanceRepository.uuid.v4(),
        'action': name,
        'created': DateTime.now().toIso8601String(),
      });
      return result;
    });
    onWrite?.call();
    return result;
  }

  DateTime _date(Map<String, dynamic> a, String key) => a[key] == null
      ? DateTime.now()
      : DateTime.parse(a[key] as String).toLocal();
  Future<Object> _read(String name, Map<String, dynamic> a) async {
    final s = await repository.snapshot();
    final currency = a['currency'] as String? ?? 'RUB';
    final now = DateTime.now();
    final period = Period.values.byName(a['period'] as String? ?? 'month');
    final relevant =
        s.transactions.where((t) => t.currency == currency).toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final window = windowFor(period, now, first: relevant.firstOrNull?.date);
    switch (name) {
      case 'get_balance':
        return {
          ...BalanceSummary(s, currency, now).toJson(),
          'accounts': s.accounts
              .where((a) => a.currency == currency)
              .map((a) => {...a.toJson(), 'balanceMinor': s.balance(a)})
              .toList(),
        };
      case 'get_summary':
        final current = Summary(s, window, currency);
        final previous = Summary(s, previousWindow(window), currency);
        return {
          ...current.toJson(),
          'incomeChangePercent': period == Period.all
              ? null
              : percentageChange(current.income, previous.income),
          'comparison': 'preceding_equal_calendar_days',
          'balance': BalanceSummary(s, currency, now).toJson(),
        };
      case 'get_transactions':
      case 'search_transactions':
        final q = (a['query'] as String? ?? '').toLowerCase();
        final from = a['from'] == null ? null : _date(a, 'from');
        final to = a['to'] == null ? null : _date(a, 'to');
        final matches = s.transactions
            .where(
              (t) =>
                  t.currency == currency &&
                  (from == null || !t.date.isBefore(from)) &&
                  (to == null || t.date.isBefore(to)) &&
                  (a['category'] == null || t.category == a['category']) &&
                  '${t.comment} ${t.merchant} ${t.category} ${t.source}'
                      .toLowerCase()
                      .contains(q),
            )
            .toList();
        final offset = a['offset'] as int? ?? 0;
        return {
          'total': matches.length,
          'transactions': matches
              .skip(offset)
              .take(a['limit'] as int? ?? 100)
              .map((t) => t.toJson())
              .toList(),
        };
      case 'get_debts':
        return {
          'debts': s.debts
              .where((d) => d.currency == currency)
              .map(
                (d) => {
                  ...d.toJson(),
                  'progress': d.progress,
                  'status': d.status(now),
                },
              )
              .toList(),
        };
      case 'get_credits':
        return {
          'credits': s.credits
              .where((c) => c.currency == currency)
              .map(
                (c) => {
                  ...c.toJson(),
                  'progress': c.progress,
                  'estimatedFutureInterestMinor': CreditProjection.estimate(
                    c,
                  ).interestMinor,
                },
              )
              .toList(),
        };
      case 'get_goals':
        return {
          'goals': s.goals.where((g) => g.currency == currency).map((g) {
            final saved = s.goalSaved(g.id);
            return {
              ...g.toJson(),
              'savedMinor': saved,
              'remainingMinor': (g.targetMinor - saved).clamp(0, g.targetMinor),
              'recommendedDailyMinor': ceilDiv(
                g.targetMinor - saved,
                daysLeft(g.due, now),
              ),
            };
          }).toList(),
        };
      case 'get_upcoming_payments':
        final end = now.add(Duration(days: a['days'] as int? ?? 30));
        return {
          'payments': s.payments
              .where((p) => p.currency == currency && p.due.isBefore(end))
              .map((p) => p.toJson())
              .toList(),
          'credits': s.credits
              .where(
                (c) =>
                    c.currency == currency &&
                    c.remainingMinor > 0 &&
                    c.nextPayment.isBefore(end),
              )
              .map((c) => c.toJson())
              .toList(),
          'debts': s.debts
              .where(
                (d) =>
                    d.currency == currency &&
                    d.remainingMinor > 0 &&
                    d.due.isBefore(end),
              )
              .map((d) => d.toJson())
              .toList(),
        };
      default:
        throw ArgumentError('Неизвестный инструмент');
    }
  }

  Future<Object> _write(
    SqlFinanceRepository repo,
    String name,
    Map<String, dynamic> a,
  ) async {
    final id = SqlFinanceRepository.uuid.v4();
    final currency = a['currency'] as String? ?? 'RUB';
    switch (name) {
      case 'add_income':
      case 'add_expense':
        final t = FinanceTransaction(
          id: id,
          kind: name == 'add_income'
              ? TransactionKind.income
              : TransactionKind.expense,
          amountMinor: a['amountMinor'] as int,
          accountId: a['accountId'] as String,
          date: _date(a, 'date'),
          currency: currency,
          category: a['category'] as String? ?? 'Прочее',
          comment: a['comment'] as String? ?? '',
          merchant: a['merchant'] as String? ?? '',
          source: a['source'] as String? ?? '',
          workMinutes: a['workMinutes'] as int? ?? 0,
        );
        await repo.addTransaction(t);
        return {'id': id, 'created': true};
      case 'add_debt':
        await repo.saveDebt(
          Debt(
            id: id,
            name: a['name'] as String,
            direction: DebtDirection.values.byName(a['direction'] as String),
            initialMinor: a['amountMinor'] as int,
            remainingMinor: a['amountMinor'] as int,
            created: _date(a, 'created'),
            due: _date(a, 'due'),
            currency: currency,
            comment: a['comment'] as String? ?? '',
          ),
        );
        return {'id': id, 'created': true, 'cashBalanceChanged': false};
      case 'update_debt':
        final debt = (await repo.snapshot()).debts.firstWhere(
          (d) => d.id == a['id'],
        );
        await repo.saveDebt(
          Debt(
            id: debt.id,
            name: a['name'] as String? ?? debt.name,
            direction: debt.direction,
            initialMinor: debt.initialMinor,
            remainingMinor: debt.remainingMinor,
            created: debt.created,
            due: a['due'] == null ? debt.due : _date(a, 'due'),
            currency: debt.currency,
            comment: a['comment'] as String? ?? debt.comment,
          ),
        );
        if (a['paymentMinor'] != null) {
          if (a['accountId'] == null)
            throw ArgumentError('Для погашения нужен accountId');
          await repo.repayDebt(
            debt.id,
            a['paymentMinor'] as int,
            a['accountId'] as String,
            _date(a, 'date'),
          );
        }
        return {'id': debt.id, 'updated': true};
      case 'add_credit':
        await repo.saveCredit(
          Credit(
            id: id,
            name: a['name'] as String,
            bank: a['bank'] as String,
            initialMinor: a['amountMinor'] as int,
            remainingMinor:
                a['remainingMinor'] as int? ?? a['amountMinor'] as int,
            annualRateBps: a['annualRateBps'] as int,
            monthlyMinor: a['monthlyMinor'] as int,
            start: _date(a, 'start'),
            end: _date(a, 'end'),
            nextPayment: _date(a, 'nextPayment'),
            currency: currency,
          ),
        );
        return {'id': id, 'created': true, 'cashBalanceChanged': false};
      case 'add_savings':
        await repo.addSavings(
          a['amountMinor'] as int,
          a['fromAccountId'] as String,
          a['toAccountId'] as String,
          _date(a, 'date'),
          goalId: a['goalId'] as String?,
        );
        return {'created': true};
      case 'create_goal':
        await repo.saveGoal(
          Goal(
            id: id,
            name: a['name'] as String,
            targetMinor: a['targetMinor'] as int,
            created: DateTime.now(),
            due: _date(a, 'due'),
            currency: currency,
          ),
        );
        return {'id': id, 'created': true};
      case 'update_goal':
        final g = (await repo.snapshot()).goals.firstWhere(
          (g) => g.id == a['id'],
        );
        await repo.saveGoal(
          Goal(
            id: g.id,
            name: a['name'] as String? ?? g.name,
            targetMinor: a['targetMinor'] as int? ?? g.targetMinor,
            created: g.created,
            due: a['due'] == null ? g.due : _date(a, 'due'),
            currency: g.currency,
          ),
        );
        return {'id': g.id, 'updated': true};
      default:
        throw ArgumentError('Неизвестный инструмент');
    }
  }
}
