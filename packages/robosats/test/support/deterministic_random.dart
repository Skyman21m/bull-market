import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// A reproducible source of bytes: SHA-256 of a label and a counter, so that generated keys never depend on the Dart version.
///
/// Only `nextInt(256)` is supported, the one call the package makes.
final class DeterministicRandom implements Random {
  final String _label;
  final List<int> _buffer = [];
  int _counter = 0;

  DeterministicRandom(this._label);

  @override
  int nextInt(int max) {
    if (max != 256) throw UnsupportedError('only bytes are drawn');
    if (_buffer.isEmpty) {
      _buffer.addAll(
        sha256.convert(utf8.encode('$_label/${_counter++}')).bytes,
      );
    }
    return _buffer.removeAt(0);
  }

  @override
  bool nextBool() => throw UnsupportedError('only bytes are drawn');

  @override
  double nextDouble() => throw UnsupportedError('only bytes are drawn');
}

/// A source of bytes that first replays [_script], then continues as a [DeterministicRandom].
final class ScriptedRandom implements Random {
  final List<int> _script;
  final Random _then = DeterministicRandom('after the script');
  int _position = 0;

  ScriptedRandom(this._script);

  @override
  int nextInt(int max) =>
      _position < _script.length ? _script[_position++] : _then.nextInt(max);

  @override
  bool nextBool() => throw UnsupportedError('only bytes are drawn');

  @override
  double nextDouble() => throw UnsupportedError('only bytes are drawn');
}
