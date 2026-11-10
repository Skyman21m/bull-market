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
  double requiredDouble(String key, {required double min, required double max}) =>
      optionalDouble(key, min: min, max: max) ?? _reject(key, 0);

  double? optionalDouble(
    String key, {
    required double min,
    required double max,
  }) => switch (_object[key]) {
    null => null,
    final num value
        when value.isFinite && value >= min && value <= max =>
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

  /// A JSON object.
  Map<String, Object?>? requiredObject(String key) => switch (_object[key]) {
    final Map<String, Object?> value => value,
    _ => _reject(key, null),
  };

  /// A decimal number sent as a string, as the coordinator serializes its `DecimalField`s: see [parseDecimal].
  double? optionalDecimal(String key, {required double min, required double max}) =>
      switch (_object[key]) {
        null => null,
        final String text => switch (parseDecimal(text)) {
          final double value when value >= min && value <= max => value,
          _ => _reject(key, null),
        },
        _ => _reject(key, null),
      };

  double requiredDecimal(String key, {required double min, required double max}) =>
      optionalDecimal(key, min: min, max: max) ?? _reject(key, 0);
}

final RegExp _decimal = RegExp(r'^-?\d{1,12}(\.\d{1,12})?$');

/// Parses a plain decimal string such as `-0.05` or `0.00210000`, and nothing else: no exponent, sign `+`, whitespace, `NaN` or `Infinity`.
double? parseDecimal(String text) =>
    _decimal.hasMatch(text) ? double.parse(text) : null;
