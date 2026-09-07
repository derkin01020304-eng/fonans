import 'package:intl/intl.dart';

/// Amounts always use currency minor units. No binary floating point parsing.
int parseMoney(String text, {bool allowNegative = false}) {
  final value = text
      .replaceAll(RegExp(r'[\s\u00a0\u202f₽]'), '')
      .replaceAll(',', '.');
  if (!RegExp(r'^[+-]?\d{1,12}(\.\d{1,2})?$').hasMatch(value)) {
    throw const FormatException('Введите сумму: например, 450,50');
  }
  final negative = value.startsWith('-');
  if (negative && !allowNegative)
    throw const FormatException('Сумма должна быть положительной');
  final parts = value.replaceFirst(RegExp(r'^[+-]'), '').split('.');
  final result =
      int.parse(parts.first) * 100 +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  return negative ? -result : result;
}

String money(int minor, [String currency = 'RUB']) => NumberFormat.currency(
  locale: 'ru_RU',
  symbol: currency == 'RUB' ? '₽' : currency,
  decimalDigits: minor % 100 == 0 ? 0 : 2,
).format(minor / 100);

String decimalMoney(int minor) =>
    '${minor < 0 ? '-' : ''}${minor.abs() ~/ 100}.${(minor.abs() % 100).toString().padLeft(2, '0')}';
int ceilDiv(int numerator, int denominator) =>
    numerator <= 0 ? 0 : (numerator + denominator - 1) ~/ denominator;
DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
int calendarDays(DateTime start, DateTime end) => DateTime.utc(
  end.year,
  end.month,
  end.day,
).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
int daysLeft(DateTime target, DateTime now) =>
    calendarDays(day(now), day(target)).clamp(1, 365000);
DateTime nextMonth(DateTime date, [int months = 1]) {
  final first = DateTime(date.year, date.month + months, 1);
  final last = DateTime(first.year, first.month + 1, 0).day;
  return DateTime(first.year, first.month, date.day.clamp(1, last));
}

String dateLabel(DateTime date) => DateFormat('d MMM yyyy', 'ru').format(date);

DateTime anchoredMonth(DateTime value, int anchorDay, [int months = 1]) {
  final first = DateTime(value.year, value.month + months, 1);
  return DateTime(
    first.year,
    first.month,
    anchorDay.clamp(1, DateTime(first.year, first.month + 1, 0).day),
  );
}
