/// Reads the fields of one JSON object received from a coordinator, without trusting their presence, type or range.
///
/// A getter never throws: it records the first field that is invalid in [rejected] and returns a placeholder, so the caller reads every field it needs and then checks [rejected] once before building anything from the values.
/// A field that is missing and one that is `null` are the same for an optional getter, and both invalid for a required one.
final class JsonFields {
  final Map<String, Object?> _object;

  /// The name of the first invalid field, or `null` while all are valid.
  String? rejected;

  JsonFields(this._object);

  T _reject<T>(String key, T placeholder) {
    rejected ??= key;
    return placeholder;
  }

  /// An integer between [min] and [max].
  int requiredInt(String key, {required int min, required int max}) =>
      optionalInt(key, min: min, max: max) ?? _reject(key, 0);

  int? optionalInt(String key, {required int min, required int max}) =>
      switch (_object[key]) {
        null => null,
        final int value when value >= min && value <= max => value,
        _ => _reject(key, null),
      };

  /// A finite number between [min] and [max], written with or without a fractional part.
  double requiredDouble(
    String key, {
    required double min,
    required double max,
  }) => optionalDouble(key, min: min, max: max) ?? _reject(key, 0);

  double? optionalDouble(
    String key, {
    required double min,
    required double max,
  }) => switch (_object[key]) {
    null => null,
    final num value when value.isFinite && value >= min && value <= max =>
      value.toDouble(),
    _ => _reject(key, null),
  };

  bool requiredBool(String key) => optionalBool(key) ?? _reject(key, false);

  bool? optionalBool(String key) => switch (_object[key]) {
    null => null,
    final bool value => value,
    _ => _reject(key, null),
  };

  /// A string of at most [maxLength] UTF-16 code units.
  String requiredString(String key, {required int maxLength}) =>
      optionalString(key, maxLength: maxLength) ?? _reject(key, '');

  String? optionalString(String key, {required int maxLength}) =>
      switch (_object[key]) {
        null => null,
        final String value when value.length <= maxLength => value,
        _ => _reject(key, null),
      };

  /// Free text for display: a string of at most [maxCodePoints] Unicode code points, as Django counts the `max_length` of a text field, cleaned by [displayText].
  String requiredText(String key, {required int maxCodePoints}) =>
      optionalText(key, maxCodePoints: maxCodePoints) ?? _reject(key, '');

  String? optionalText(
    String key, {
    required int maxCodePoints,
  }) => switch (_object[key]) {
    null => null,
    // A code point takes one or two UTF-16 units: the length bounds the count before it is computed.
    final String value
        when value.length <= 2 * maxCodePoints &&
            value.runes.length <= maxCodePoints =>
      displayText(value),
    _ => _reject(key, null),
  };

  /// A JSON object.
  Map<String, Object?>? requiredObject(String key) => switch (_object[key]) {
    final Map<String, Object?> value => value,
    _ => _reject(key, null),
  };

  /// A decimal number sent as a string, as the coordinator serializes its `DecimalField`s: see [parseDecimal].
  double? optionalDecimal(
    String key, {
    required double min,
    required double max,
  }) => switch (_object[key]) {
    null => null,
    final String text => switch (parseDecimal(text)) {
      final double value when value >= min && value <= max => value,
      _ => _reject(key, null),
    },
    _ => _reject(key, null),
  };

  double requiredDecimal(
    String key, {
    required double min,
    required double max,
  }) => optionalDecimal(key, min: min, max: max) ?? _reject(key, 0);
}

final RegExp _decimal = RegExp(r'^-?\d{1,12}(\.\d{1,12})?$');

/// Parses a plain decimal string such as `-0.05` or `0.00210000`, and nothing else: no exponent, sign `+`, whitespace, `NaN` or `Infinity`.
double? parseDecimal(String text) =>
    _decimal.hasMatch(text) ? double.parse(text) : null;

/// Free text from a coordinator, made safe to display and to put on one line.
///
/// C0 and C1 control characters and DEL are removed, except tab, line feed, vertical tab, form feed, carriage return and next line, which become a space, as do the line and paragraph separators.
/// Unicode bidirectional controls (U+061C, U+200E, U+200F, U+202A to U+202E, U+2066 to U+2069) and unpaired surrogates are removed.
/// Everything else, accented letters and emoji included, is kept.
String displayText(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    if ((rune >= 0x09 && rune <= 0x0D) ||
        rune == 0x85 ||
        rune == 0x2028 ||
        rune == 0x2029) {
      buffer.write(' ');
    } else if (rune < 0x20 ||
        (rune >= 0x7F && rune <= 0x9F) ||
        rune == 0x061C ||
        rune == 0x200E ||
        rune == 0x200F ||
        (rune >= 0x202A && rune <= 0x202E) ||
        (rune >= 0x2066 && rune <= 0x2069) ||
        (rune >= 0xD800 && rune <= 0xDFFF)) {
      continue;
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}
