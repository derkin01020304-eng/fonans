import '../../domain/models.dart';

class BankAccount {
  const BankAccount({
    required this.id,
    required this.name,
    required this.currency,
    required this.balanceMinor,
    required this.asOf,
  });
  final String id, name, currency;
  final int balanceMinor;
  final DateTime asOf;
}

class BankOperation {
  const BankOperation({
    required this.id,
    required this.accountId,
    required this.signedMinor,
    required this.date,
    required this.currency,
    this.description = '',
    this.merchant = '',
    this.mcc,
    this.ownAccountId,
    this.kind,
  });
  final String id, accountId, currency, description, merchant;
  final String? mcc, ownAccountId;
  final TransactionKind? kind;
  final int signedMinor;
  final DateTime date;
}

class BankPage {
  const BankPage(this.operations, {this.nextCursor});
  final List<BankOperation> operations;
  final String? nextCursor;
}

abstract interface class BankProvider {
  String get id;
  String get name;
  Future<void> authorize();
  Future<List<BankAccount>> getAccounts();
  Future<BankPage> getTransactions({String? cursor});
  Future<void> disconnect();
}
