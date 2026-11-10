import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:bech32/bech32.dart';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/src/base62.dart';
import 'package:robosats/src/bip32.dart';
import 'package:robosats/src/nostr_key_pair.dart';
import 'package:robosats/src/robosats_failure.dart';
import 'package:robosats/src/robot_token.dart';
import 'package:robosats/src/secp256k1.dart';

/// A RoboSats Garage Key: 32 random bytes from which one robot token per index is derived.
///
/// It reproduces `frontend/src/utils/garageKey.ts` of RoboSats (commit ff1998c).
/// Its text form is bech32 (BIP173, not bech32m) with the human-readable part `robo`: `robo1` followed by 58 characters.
/// Whoever holds it controls every robot derived from it: never log, display by accident or send it.
@immutable
final class GarageKey {
  /// The length of the key material, in bytes.
  static const int byteLength = 32;

  /// The highest robot index: the index is a hardened BIP32 child number.
  static const int maxAccountIndex = 0x7fffffff;

  static const String _humanReadablePart = 'robo';
  static const int _coinType = 88;
  static const int _tokenLength = 36;

  final Uint8List _bytes;

  const GarageKey._(this._bytes);

  /// Draws a new key from the platform's cryptographically secure generator.
  factory GarageKey.generate() => GarageKey.generateWith(Random.secure());

  /// Draws a new key from [random].
  ///
  /// For tests only: a Garage Key is only as strong as [random].
  @visibleForTesting
  factory GarageKey.generateWith(Random random) {
    final bytes = Uint8List(byteLength);
    for (var i = 0; i < byteLength; i++) {
      bytes[i] = random.nextInt(256);
    }
    return GarageKey._(bytes);
  }

  /// Wraps 32 bytes of key material.
  static Result<GarageKey, GarageKeyFailure> fromBytes(Uint8List bytes) {
    if (bytes.length != byteLength) {
      return const Err(GarageKeyWrongByteLength());
    }
    return Ok(GarageKey._(Uint8List.fromList(bytes)));
  }

  /// Parses the `robo1…` text form, with the checks of `validateGarageKey`, in the same order.
  ///
  /// An all-uppercase string is accepted, as bech32 allows; surrounding whitespace is not.
  static Result<GarageKey, GarageKeyFailure> parse(String encoded) {
    if (encoded.isEmpty) return const Err(GarageKeyEmpty());
    if (!encoded.toLowerCase().startsWith('${_humanReadablePart}1')) {
      return const Err(GarageKeyWrongPrefix());
    }
    if (encoded.length < 55 || encoded.length > 65) {
      return const Err(GarageKeyWrongLength());
    }
    final Bech32 decoded;
    try {
      decoded = bech32.decode(encoded);
    } on InvalidChecksum {
      return const Err(GarageKeyBadChecksum());
    } on Exception {
      // The messages of the codec's exceptions quote the input, so they are dropped.
      return const Err(GarageKeyMalformed());
    }
    if (decoded.hrp != _humanReadablePart) {
      return const Err(GarageKeyWrongPrefix());
    }
    final bytes = _bytesFromWords(decoded.data);
    if (bytes == null) return const Err(GarageKeyMalformed());
    return fromBytes(bytes);
  }

  /// A copy of the 32 bytes of key material: never log it.
  Uint8List revealBytes() => Uint8List.fromList(_bytes);

  /// The canonical lowercase `robo1…` text form: never log it.
  String revealBech32() =>
      bech32.encode(Bech32(_humanReadablePart, _wordsFromBytes(_bytes)));

  /// The token of the robot number [accountIndex].
  ///
  /// The seed is the SHA-512 of the key bytes, the BIP32 path is `m/44'/88'/{accountIndex}'/0`, and the token is made of the 36 low-order base62 digits of the derived private key.
  /// Fails with [AccountIndexOutOfRange], or with [TokenEntropyTooLow] in the very unlikely case where the derived token fails the client-side entropy rule: the official client would hold such a robot but never contact a coordinator with it, so skip to the next index.
  Result<RobotToken, RobosatsFailure> deriveToken(int accountIndex) {
    if (accountIndex < 0 || accountIndex > maxAccountIndex) {
      return const Err(AccountIndexOutOfRange());
    }
    final derivedKey = deriveBip32PrivateKey(sha512.convert(_bytes).bytes, [
      44 | bip32Hardened,
      _coinType | bip32Hardened,
      accountIndex | bip32Hardened,
      0,
    ]);
    final token = base62LowDigits(bigIntFromBytes(derivedKey), _tokenLength);
    return RobotToken.parse(token).mapErr((failure) => failure);
  }

  /// The Nostr identity of the Garage Key itself, used by RoboSats to publish and recover the current robot index.
  ///
  /// Its secret key is `sha256(sha512(key bytes))` (`getNostrSecKeyFromGarageKey`), not to be confused with the Nostr key of a robot.
  NostrKeyPair get recoveryNostrKeyPair => NostrKeyPair.fromSecretKey(
    sha256.convert(sha512.convert(_bytes).bytes).bytes,
  );

  /// The older Nostr identity of the Garage Key, which hashed the hexadecimal string of the key instead of its bytes.
  ///
  /// RoboSats still reads recovery events published with it (`getLegacyNostrSecKeyFromGarageKey`).
  NostrKeyPair get legacyRecoveryNostrKeyPair => NostrKeyPair.fromSecretKey(
    sha256.convert(sha512.convert(utf8.encode(hex.encode(_bytes))).bytes).bytes,
  );

  @override
  bool operator ==(Object other) {
    if (other is! GarageKey) return false;
    var difference = 0;
    for (var i = 0; i < byteLength; i++) {
      difference |= _bytes[i] ^ other._bytes[i];
    }
    return difference == 0;
  }

  @override
  int get hashCode => Object.hashAll(_bytes);

  @override
  String toString() => 'GarageKey(<redacted>)';
}

/// Regroups 8-bit bytes into 5-bit bech32 words, padding the last word with zero bits.
List<int> _wordsFromBytes(List<int> bytes) {
  final words = <int>[];
  var accumulator = 0;
  var bits = 0;
  for (final byte in bytes) {
    accumulator = (accumulator << 8 | byte) & 0xfff;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      words.add(accumulator >> bits & 31);
    }
  }
  if (bits > 0) words.add(accumulator << (5 - bits) & 31);
  return words;
}

/// Regroups 5-bit bech32 words into bytes, or returns `null` on excess or non-zero padding, as `bech32.fromWords` of `@scure/base` rejects them.
Uint8List? _bytesFromWords(List<int> words) {
  final bytes = BytesBuilder(copy: false);
  var accumulator = 0;
  var bits = 0;
  for (final word in words) {
    accumulator = (accumulator << 5 | word) & 0xfff;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      bytes.addByte(accumulator >> bits & 0xff);
    }
  }
  if (bits >= 5 || accumulator & ((1 << bits) - 1) != 0) return null;
  return bytes.takeBytes();
}
