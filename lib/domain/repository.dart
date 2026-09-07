import 'models.dart';

abstract interface class FinanceRepository {
  Future<FinanceSnapshot> snapshot();
  Future<void> saveAccount(Account account);
  Future<void> addTransaction(FinanceTransaction transaction);
  Future<void> editTransaction(FinanceTransaction transaction);
  Future<void> deleteTransaction(String id);
  Future<void> saveDebt(Debt debt);
  Future<void> repayDebt(
    String id,
    int amountMinor,
    String accountId,
    DateTime date,
  );
  Future<void> saveCredit(Credit credit);
  Future<void> repayCredit(
    String id,
    int principalMinor,
    int interestMinor,
    String accountId,
    DateTime date, {
    bool early = false,
  });
  Future<void> saveGoal(Goal goal);
  Future<void> addSavings(
    int amountMinor,
    String fromAccountId,
    String toAccountId,
    DateTime date, {
    String? goalId,
  });
  Future<void> savePayment(RecurringPayment payment);
  Future<void> payRecurring(String id, String accountId, DateTime date);
  Future<void> deleteEntity(String table, String id);
  Future<List<Map<String, Object?>>> history(String table, String parentId);
  Future<Map<String, dynamic>> exportBackup();
  Future<void> restoreBackup(Map<String, dynamic> data);
  Future<void> seedDemo();
  Future<void> clearDemo();
}
