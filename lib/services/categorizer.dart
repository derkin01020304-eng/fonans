import '../core/money.dart';
import '../domain/models.dart';

const expenseCategories = [
  'Еда',
  'Напитки',
  'Транспорт',
  'Работа',
  'Учёба',
  'Развлечения',
  'Покупки',
  'Здоровье',
  'Жильё',
  'Связь',
  'Подписки',
  'Кредиты',
  'Обязательные платежи',
  'Переводы',
  'Прочее',
];
String normalizeMerchant(String merchant) =>
    merchant.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

class CategoryPrediction {
  const CategoryPrediction(this.category, this.confidence);
  final String category;
  final double confidence;
  bool get needsReview => confidence < .85;
}

class Categorizer {
  const Categorizer([this.confirmed = const {}]);
  final Map<String, String> confirmed;
  CategoryPrediction predict({
    String merchant = '',
    String description = '',
    String? mcc,
  }) {
    final key = normalizeMerchant(merchant);
    if (key.isNotEmpty && confirmed.containsKey(key))
      return CategoryPrediction(confirmed[key]!, 1);
    final code = {
      '5411': 'Еда',
      '5499': 'Еда',
      '5812': 'Еда',
      '5814': 'Еда',
      '4121': 'Транспорт',
      '4111': 'Транспорт',
      '5541': 'Транспорт',
      '5912': 'Здоровье',
      '8011': 'Здоровье',
      '8021': 'Здоровье',
      '4814': 'Связь',
      '4900': 'Жильё',
      '8211': 'Учёба',
      '8220': 'Учёба',
      '7832': 'Развлечения',
      '5732': 'Покупки',
    }[mcc];
    if (code != null) return CategoryPrediction(code, .91);
    final text = '$merchant $description'.toLowerCase();
    const words = {
      'Еда': [
        'еда',
        'продукт',
        'пятёроч',
        'пятероч',
        'магнит',
        'перекрёст',
        'вкусвилл',
        'lenta',
      ],
      'Напитки': ['напит', 'кофе', 'coffee', 'вода', 'чай'],
      'Транспорт': ['транспорт', 'метро', 'автобус', 'такси', 'бензин'],
      'Работа': ['работа', 'ремонт велосипеда', 'доставка'],
      'Учёба': ['учёба', 'учеба', 'колледж', 'учебник'],
      'Подписки': ['подписк', 'subscription'],
      'Связь': ['связь', 'мобильный', 'интернет'],
      'Здоровье': ['аптека', 'лекарств', 'врач'],
      'Жильё': ['аренда', 'квартира', 'коммунал'],
      'Развлечения': ['кино', 'игра', 'развлеч'],
      'Покупки': ['покупки', 'одежда', 'ozon', 'wildberries'],
    };
    for (final entry in words.entries) {
      if (entry.value.any(text.contains))
        return CategoryPrediction(entry.key, .75);
    }
    return const CategoryPrediction('Прочее', .2);
  }
}

class QuickEntry {
  const QuickEntry(this.kind, this.amountMinor, this.category, this.comment);
  final TransactionKind kind;
  final int amountMinor;
  final String category, comment;
  static QuickEntry parse(String input) {
    final text = input.trim().toLowerCase();
    final match = RegExp(
      r'([+-]?\d+(?:[ \u00a0\u202f]\d{3})*(?:[.,]\d+)?)',
    ).firstMatch(text);
    if (match == null)
      throw const FormatException('Пример: 250 еда или +3000 работа');
    final kind =
        match.group(1)!.startsWith('+') ||
            RegExp(r'заработ|доход|получил|зарплат').hasMatch(text)
        ? TransactionKind.income
        : TransactionKind.expense;
    final amount = parseMoney(match.group(1)!.replaceFirst('-', ''));
    if (amount <= 0)
      throw const FormatException('Сумма должна быть больше нуля');
    final comment = input.replaceRange(match.start, match.end, '').trim();
    final category = kind == TransactionKind.income
        ? 'Работа'
        : Categorizer().predict(description: comment).category;
    return QuickEntry(kind, amount, category, comment);
  }
}
