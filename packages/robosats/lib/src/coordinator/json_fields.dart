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

  /// A JSON object, or `null` for anything else, without rejecting: for a part of an answer that is dropped alone when it is invalid.
  Map<String, Object?>? objectOrNull(String key) => switch (_object[key]) {
    final Map<String, Object?> value => value,
    _ => null,
  };

  /// Whether the field is present with a value other than `null`.
  bool has(String key) => _object[key] != null;

  /// An ISO 8601 date and time with a time zone, as the coordinator serializes it, between 2020 and 2100.
  ///
  /// Every part must be in range, so the text means the date it is read as: `DateTime.tryParse` alone would turn `25:61` into the next day.
  /// A date without a zone would be read in local time, so it is rejected.
  DateTime? optionalDate(String key) {
    final text = optionalString(key, maxLength: 40);
    if (text == null) return null;
    final match = _isoDate.firstMatch(text);
    final date = match == null ? null : DateTime.tryParse(text);
    if (match == null || date == null || !_dateInRange(match)) {
      return _reject(key, null);
    }
    return date;
  }

  /// [optionalDate], required: `null` only when the field is rejected.
  DateTime? requiredDate(String key) => optionalDate(key) ?? _reject(key, null);

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

  /// A decimal number sent either as a string, as a serializer's `DecimalField`, or as a JSON number, as Django REST framework's encoder writes a raw `Decimal` a view puts in its answer.
  double? optionalDecimalOrNumber(
    String key, {
    required double min,
    required double max,
  }) => switch (_object[key]) {
    String() => optionalDecimal(key, min: min, max: max),
    _ => optionalDouble(key, min: min, max: max),
  };

  double requiredDecimal(
    String key, {
    required double min,
    required double max,
  }) => optionalDecimal(key, min: min, max: max) ?? _reject(key, 0);
}

final RegExp _isoDate = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(?:Z|[+-](\d{2}):(\d{2}))$',
);

bool _dateInRange(RegExpMatch match) {
  int part(int group) => int.parse(match[group] ?? '0');
  final year = part(1);
  final month = part(2);
  final day = part(3);
  return year >= 2020 &&
      year <= 2100 &&
      month >= 1 &&
      month <= 12 &&
      day >= 1 &&
      day <= DateTime.utc(year, month + 1, 0).day &&
      part(4) <= 23 &&
      part(5) <= 59 &&
      part(6) <= 59 &&
      part(7) <= 14 &&
      part(8) <= 59;
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
