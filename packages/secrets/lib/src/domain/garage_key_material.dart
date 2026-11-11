import 'dart:typed_data';

import 'package:meta/meta.dart';

/// The 32 bytes of a RoboSats Garage Key, as the package keeps them for the P2P feature.
///
/// Random, never derived from a wallet seed and never part of a wallet backup.
/// Whoever holds them controls every robot derived from them, so they are key material: never log them, and read [bytes] only where the custody gate allows it.
///
/// No hex getter and no equality: the only way out is [bytes], which the custody gate restricts to named files of the P2P feature.
@immutable
final class GarageKeyMaterial {
  static const lengthInBytes = 32;

  /// The key's own copy, so that whoever passed the bytes in cannot change them afterwards.
  final Uint8List _bytes;

  /// A read-only view on the key's own copy.
  Uint8List get bytes => _bytes.asUnmodifiableView();

  /// Refuses any other length in every build mode, and copies the bytes before anything can await.
  @internal
  factory GarageKeyMaterial(Uint8List bytes) {
    if (bytes.length != lengthInBytes) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'a Garage Key is $lengthInBytes bytes',
      );
    }
    return GarageKeyMaterial._(Uint8List.fromList(bytes));
  }

  const GarageKeyMaterial._(this._bytes);

  /// Never widen this: a key that prints itself ends up in a log.
  @override
  String toString() => 'GarageKeyMaterial(•••)';
}
