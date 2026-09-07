import '../../core/money.dart';
import 'bank_provider.dart';

/// Fixed operation IDs and dates: repeating sync must never create another entry.
class MockBankProvider implements BankProvider {
  MockBankProvider({DateTime? clock}) : today = day(clock ?? DateTime.now());
  final DateTime today;
  @override
  String get id => 'mock';
  @override
  String get name => 'Демо-банк';
  @override
  Future<void> authorize() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<List<BankAccount>> getAccounts() async => [
    BankAccount(
      id: 'mock-card',
      name: 'Демо-банк • тестовая карта',
      currency: 'RUB',
      balanceMinor: 1345500,
      asOf: today,
    ),
  ];
  @override
  Future<BankPage> getTransactions({String? cursor}) async => BankPage([
    BankOperation(
      id: 'mock-income-v1',
      accountId: 'mock-card',
      signedMinor: 300000,
      date: DateTime(2026, 1, 5),
      currency: 'RUB',
      description: 'Тестовое поступление',
      merchant: 'Демо: работа',
    ),
    BankOperation(
      id: 'mock-food-v1',
      accountId: 'mock-card',
      signedMinor: -54500,
      date: DateTime(2026, 1, 6),
      currency: 'RUB',
      description: 'Тестовая покупка',
      merchant: 'Демо: магазин',
      mcc: '5411',
    ),
  ]);
}
