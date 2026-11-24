/// Small helpers shared by the model classes.

/// Finds the enum value called [name], or returns [fallback] when [name] is
/// null or unknown (e.g. data written by a newer app version).
T enumFromName<T extends Enum>(List<T> values, String? name, T fallback) {
  if (name == null) return fallback;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

/// Serialises a [DateTime] as a UTC ISO-8601 string.
String dateToJson(DateTime value) => value.toUtc().toIso8601String();

/// Parses a string written by [dateToJson]. Returns a local [DateTime].
DateTime dateFromJson(Object? value) {
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toLocal();
  }
  throw FormatException('Invalid date value: $value');
}

DateTime? dateFromJsonOrNull(Object? value) =>
    value == null ? null : dateFromJson(value);

/// Parses a price typed by the user (accepts "1.08500" and "1,08500").
/// Returns null when the text is not a finite number greater than zero.
double? tryParsePrice(String input) {
  final cleaned = input.trim().replaceAll(',', '.');
  if (cleaned.isEmpty) return null;
  final value = double.tryParse(cleaned);
  if (value == null || value.isNaN || value.isInfinite || value <= 0) {
    return null;
  }
  return value;
}
