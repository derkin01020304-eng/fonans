/// Implements the JSON Schema subset used by assets/mcp_tools.json.
void validateSchema(
  Object? value,
  Map<String, dynamic> schema, [
  String path = 'arguments',
]) {
  final type = schema['type'];
  final valid = switch (type) {
    'object' => value is Map<String, dynamic>,
    'string' => value is String,
    'integer' => value is int,
    'boolean' => value is bool,
    'array' => value is List,
    _ => false,
  };
  if (!valid) throw FormatException('$path: ожидается $type');
  if (schema['enum'] is List && !(schema['enum'] as List).contains(value))
    throw FormatException('$path: недопустимое значение');
  if (value is int) {
    if ((schema['minimum'] != null && value < (schema['minimum'] as num)) ||
        (schema['maximum'] != null && value > (schema['maximum'] as num)))
      throw FormatException('$path: вне диапазона');
  }
  if (value is String) {
    if (value.length < (schema['minLength'] as int? ?? 0) ||
        value.length > (schema['maxLength'] as int? ?? 4000)) {
      throw FormatException('$path: недопустимая длина');
    }
    if (schema['format'] == 'date-time') {
      final d = DateTime.tryParse(value);
      final prefix = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T').firstMatch(value);
      if (d == null || prefix == null)
        throw FormatException('$path: нужен ISO 8601');
      final local = DateTime(
        int.parse(prefix[1]!),
        int.parse(prefix[2]!),
        int.parse(prefix[3]!),
      );
      if (local.year != int.parse(prefix[1]!) ||
          local.month != int.parse(prefix[2]!) ||
          local.day != int.parse(prefix[3]!)) {
        throw FormatException('$path: неверная дата');
      }
    }
  }
  if (value is Map<String, dynamic>) {
    final properties =
        (schema['properties'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final required in schema['required'] as List? ?? []) {
      if (!value.containsKey(required))
        throw FormatException('$path: отсутствует $required');
    }
    if (schema['additionalProperties'] == false &&
        value.keys.any((k) => !properties.containsKey(k))) {
      throw FormatException('$path: неизвестный параметр');
    }
    for (final key in value.keys) {
      if (properties[key] is Map)
        validateSchema(
          value[key],
          Map<String, dynamic>.from(properties[key] as Map),
          '$path.$key',
        );
    }
  }
}
