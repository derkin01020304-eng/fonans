import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite_common/sqlite_api.dart';
import '../../data/finance_repository.dart';
import '../../domain/models.dart';
import '../../services/categorizer.dart';
import 'bank_provider.dart';

String externalKey(String accountId, String externalId) =>
    sha256.convert(utf8.encode('$accountId|id:$externalId')).toString();

class SyncResult {
  const SyncResult(this.added, this.duplicates, this.review);
  final int added, duplicates, review;
}

class BankSyncService {
  BankSyncService(this.repository);
  final SqlFinanceRepository repository;
  bool _busy = false;
  Future<SyncResult> sync(BankProvider provider) async {
    if (_busy) throw StateError('Синхронизация уже выполняется');
    _busy = true;
    try {
      final accounts = await provider.getAccounts();
      final operations = <BankOperation>[];
      String? cursor;
      final seenCursors = <String>{};
      do {
        final page = await provider.getTransactions(cursor: cursor);
        operations.addAll(page.operations);
        cursor = page.nextCursor;
        if (cursor != null && !seenCursors.add(cursor))
          throw StateError('Банк повторил страницу');
        if (seenCursors.length > 1000)
          throw StateError('Слишком большая история банка');
      } while (cursor != null);
      final categorizer = Categorizer(await repository.categoryRules());
      return await repository.atomic((tx) async {
        final mapping = <String, String>{};
        for (final a in accounts) {
          final localId = '${provider.id}:${a.id}';
          mapping[a.id] = localId;
          final existing = await tx.query(
            'accounts',
            where: 'id = ?',
            whereArgs: [localId],
          );
          if (existing.isEmpty) {
            // Opening balance is the snapshot minus the supplied complete ledger.
            // Credit legs of own transfers are represented by the source debit leg.
            final delta = operations
                .where((t) => !t.date.isAfter(a.asOf))
                .fold<int>(0, (sum, t) {
                  if (t.ownAccountId != null) {
                    if (t.signedMinor >= 0) return sum;
                    return sum +
                        (t.ownAccountId == a.id ? -t.signedMinor : 0) +
                        (t.accountId == a.id ? t.signedMinor : 0);
                  }
                  return sum + (t.accountId == a.id ? t.signedMinor : 0);
                });
            await tx.insert(
              'accounts',
              Account(
                id: localId,
                name: a.name,
                kind: AccountKind.card,
                currency: a.currency,
                openingMinor: a.balanceMinor - delta,
                bankId: provider.id,
                externalId: a.id,
              ).toJson(),
            );
          }
          await tx.insert('bank_snapshots', {
            'accountId': localId,
            'balanceMinor': a.balanceMinor,
            'asOf': a.asOf.toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        var added = 0, duplicates = 0, review = 0;
        for (final op in operations) {
          if (op.signedMinor == 0 ||
              (op.ownAccountId != null && op.signedMinor > 0))
            continue;
          final accountId = mapping[op.accountId];
          if (accountId == null) throw StateError('Неизвестный счёт банка');
          final key = externalKey(accountId, op.id);
          if ((await tx.query(
            'transactions',
            columns: ['id'],
            where: 'externalKey = ?',
            whereArgs: [key],
          )).isNotEmpty) {
            duplicates++;
            continue;
          }
          final prediction = categorizer.predict(
            merchant: op.merchant,
            description: op.description,
            mcc: op.mcc,
          );
          final isTransfer = op.ownAccountId != null;
          final kind = isTransfer
              ? TransactionKind.transfer
              : op.kind ??
                    (op.signedMinor > 0
                        ? TransactionKind.income
                        : TransactionKind.expense);
          final to = isTransfer ? mapping[op.ownAccountId] : null;
          if (isTransfer && to == null)
            throw StateError('Неизвестен собственный счёт назначения');
          final needsReview =
              !isTransfer &&
              kind == TransactionKind.expense &&
              prediction.needsReview;
          final transaction = FinanceTransaction(
            id: SqlFinanceRepository.uuid.v4(),
            kind: kind,
            amountMinor: op.signedMinor.abs(),
            accountId: accountId,
            toAccountId: to,
            date: op.date,
            currency: op.currency,
            category: isTransfer
                ? 'Переводы'
                : kind == TransactionKind.income
                ? 'Прочее'
                : prediction.category,
            merchant: op.merchant,
            comment: op.description,
            mcc: op.mcc,
            externalKey: key,
            needsReview: needsReview ? 1 : 0,
            source: provider.name,
            paymentMethod: 'Банк',
          );
          await repository.insertTransaction(tx, transaction);
          added++;
          if (needsReview) review++;
        }
        await repository.upsert(tx, 'bank_connections', {
          'id': provider.id,
          'provider': provider.name,
          'status': 'connected',
          'lastSync': DateTime.now().toIso8601String(),
          'cursor': null,
        });
        return SyncResult(added, duplicates, review);
      });
    } finally {
      _busy = false;
    }
  }
}
