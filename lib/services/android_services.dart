import 'package:flutter/services.dart';
import '../core/money.dart';
import '../domain/models.dart';

class AndroidServices {
  static const channel = MethodChannel('app.derk.finance/platform');
  static const notifications = EventChannel(
    'app.derk.finance/bank_notifications',
  );
  Future<bool> requestReminders() async =>
      await channel.invokeMethod<bool>('requestNotificationPermission') ??
      false;
  Future<void> reschedule(FinanceSnapshot data, {required bool enabled}) async {
    final now = DateTime.now();
    final dates = <DateTime>{
      ...data.payments.map((p) => p.due),
      ...data.debts.where((d) => d.remainingMinor > 0).map((d) => d.due),
      ...data.credits
          .where((c) => c.remainingMinor > 0)
          .map((c) => c.nextPayment),
      ...data.goals
          .where((g) => data.goalSaved(g.id) < g.targetMinor)
          .map((g) => g.due),
    };
    final reminders = <int>{};
    if (enabled) {
      for (final due in dates) {
        var date = day(due).subtract(const Duration(days: 1));
        if (date.isBefore(day(now))) date = day(now);
        var time = DateTime(date.year, date.month, date.day, 10);
        if (!time.isAfter(now))
          time = DateTime(date.year, date.month, date.day + 1, 10);
        if (time.difference(now).inDays <= 90)
          reminders.add(time.millisecondsSinceEpoch);
      }
    }
    await channel.invokeMethod('scheduleReminders', reminders.toList()..sort());
  }

  Future<void> configureNotificationImport(
    List<String> packages,
    bool enabled,
  ) => channel.invokeMethod('configureNotificationImport', {
    'packages': packages,
    'enabled': enabled,
  });
  Future<void> openNotificationAccess() =>
      channel.invokeMethod('openNotificationAccess');
  Future<void> setUnlocked(bool unlocked) =>
      channel.invokeMethod('setUnlocked', unlocked);
}
