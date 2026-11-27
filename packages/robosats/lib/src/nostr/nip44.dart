import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/stream/chacha7539.dart';
import 'package:robosats/src/secp256k1.dart';

/// NIP-44 version 2, the encryption of the seals and gift wraps of NIP-59, as `nip44.ts` of `nostr-tools` 2.25.2 (the version the official client locks at RoboSats commit ff1998c; the same file in 2.26.0, which it locks at commit babf62e) and the text of NIP-44 describe it.
///
/// Checked against every section of the official vector file of NIP-44 (`test/fixtures/nostr/nip44.vectors.json`).
/// Nothing here draws randomness: the caller passes the 32-byte nonce, drawn from a secure source.
abstract final class Nip44 {
  static const int _version = 2;
  static const int minPlaintextBytes = 1;
  static const int maxPlaintextBytes = 65535;
  static final Uint8List _salt = Uint8List.fromList(utf8.encode('nip44-v2'));
  static final ECDomainParameters _curve = ECCurve_secp256k1();
  static final BigInt _fieldPrime = BigInt.parse(
    'fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f',
    radix: 16,
  );

  /// The conversation key of [secretKey] and the x-only public key [publicKeyHex]: HKDF-extract, salt `nip44-v2`, of the X coordinate of their ECDH point, unhashed.
  ///
  /// Throws [ArgumentError] for a secret key outside `1..n-1` or a public key that is not the X coordinate of a curve point (the invalid vectors).
  static Uint8List conversationKey(List<int> secretKey, String publicKeyHex) {
    final scalar = bigIntFromBytes(secretKey);
    if (secretKey.length != 32 || !isValidSecretScalar(scalar)) {
      throw ArgumentError('not a secp256k1 secret key');
    }
    final point = _liftX(publicKeyHex);
    final shared = point * scalar;
    final x = shared?.x?.toBigInteger();
    if (shared == null || shared.isInfinity || x == null) {
      throw ArgumentError('no shared point');
    }
    return _hmac(_salt, bigIntToBytes32(x));
  }

  /// Whether [publicKeyHex] is an x-only public key: 64 hexadecimal characters, the X coordinate of a curve point.
  static bool isPublicKey(String publicKeyHex) =>
      _liftXOrNull(publicKeyHex) != null;

  /// The ChaCha20 key, ChaCha20 nonce and HMAC key of one message: HKDF-expand of [conversationKey] with [nonce] as info, 76 bytes.
  static ({Uint8List chachaKey, Uint8List chachaNonce, Uint8List hmacKey})
  messageKeys(List<int> conversationKey, List<int> nonce) {
    if (conversationKey.length != 32) {
      throw ArgumentError('conversation key must be 32 bytes');
    }
    if (nonce.length != 32) throw ArgumentError('nonce must be 32 bytes');
    final okm = BytesBuilder(copy: false);
    var previous = Uint8List(0);
    for (var block = 1; okm.length < 76; block++) {
      previous = _hmac(
        Uint8List.fromList(conversationKey),
        Uint8List.fromList([...previous, ...nonce, block]),
      );
      okm.add(previous);
    }
    final keys = okm.toBytes();
    return (
      chachaKey: Uint8List.sublistView(keys, 0, 32),
      chachaNonce: Uint8List.sublistView(keys, 32, 44),
      hmacKey: Uint8List.sublistView(keys, 44, 76),
    );
  }

  /// The padded length of a plaintext of [unpaddedLength] bytes.
  static int paddedLength(int unpaddedLength) {
    if (unpaddedLength <= 32) return 32;
    final nextPower = 1 << (unpaddedLength - 1).bitLength;
    final chunk = nextPower <= 256 ? 32 : nextPower ~/ 8;
    return chunk * ((unpaddedLength - 1) ~/ chunk + 1);
  }

  /// [plaintext] encrypted with [conversationKey] and the 32-byte [nonce], as base64.
  ///
  /// Throws [ArgumentError] for a plaintext outside 1 to 65,535 UTF-8 bytes.
  static String encrypt(
    String plaintext,
    List<int> conversationKey,
    List<int> nonce,
  ) {
    final keys = messageKeys(conversationKey, nonce);
    final padded = _pad(utf8.encode(plaintext));
    final ciphertext = _chacha(keys.chachaKey, keys.chachaNonce, padded);
    final mac = _hmac(
      keys.hmacKey,
      Uint8List.fromList([...nonce, ...ciphertext]),
    );
    return base64.encode([_version, ...nonce, ...ciphertext, ...mac]);
  }

  /// The plaintext of [payload], or a [FormatException] for any payload that is not a well-formed version 2 payload of [conversationKey]: unknown version, bad size, bad base64 (anything but the canonical standard alphabet with its padding, as `@scure/base` reads it), bad MAC, bad padding.
  static String decrypt(String payload, List<int> conversationKey) {
    if (payload.isEmpty || payload.startsWith('#')) {
      throw const FormatException('unknown encryption version');
    }
    if (payload.length < 132 || payload.length > 87472) {
      throw const FormatException('invalid payload size');
    }
    final Uint8List data;
    try {
      data = base64.decode(payload);
    } on FormatException {
      throw const FormatException('invalid base64');
    }
    // `base64.decode` also takes the URL-safe alphabet, a missing padding and non-zero padding bits, which `base64.decode` of `@scure/base`, the decoder of `nip44.ts`, refuses: only the canonical form, which encodes back to the very payload, is read.
    if (base64.encode(data) != payload) {
      throw const FormatException('invalid base64');
    }
    if (data.length < 99 || data.length > 65603) {
      throw const FormatException('invalid data size');
    }
    if (data[0] != _version) {
      throw const FormatException('unknown encryption version');
    }
    final nonce = Uint8List.sublistView(data, 1, 33);
    final ciphertext = Uint8List.sublistView(data, 33, data.length - 32);
    final mac = Uint8List.sublistView(data, data.length - 32);
    final keys = messageKeys(conversationKey, nonce);
    final expected = _hmac(
      keys.hmacKey,
      Uint8List.fromList([...nonce, ...ciphertext]),
    );
    if (!_equalInConstantTime(expected, mac)) {
      throw const FormatException('invalid MAC');
    }
    final padded = _chacha(keys.chachaKey, keys.chachaNonce, ciphertext);
    return utf8.decode(_unpad(padded));
  }

  static Uint8List _pad(List<int> plaintext) {
    final length = plaintext.length;
    if (length < minPlaintextBytes || length > maxPlaintextBytes) {
      throw ArgumentError('invalid plaintext length');
    }
    final padded = Uint8List(2 + paddedLength(length));
    padded[0] = length >> 8;
    padded[1] = length & 0xff;
    padded.setRange(2, 2 + length, plaintext);
    return padded;
  }

  static Uint8List _unpad(Uint8List padded) {
    if (padded.length < 2) throw const FormatException('invalid padding');
    final length = (padded[0] << 8) | padded[1];
    if (length < minPlaintextBytes ||
        2 + length > padded.length ||
        padded.length != 2 + paddedLength(length)) {
      throw const FormatException('invalid padding');
    }
    return Uint8List.sublistView(padded, 2, 2 + length);
  }

  static Uint8List _chacha(List<int> key, List<int> nonce, Uint8List data) {
    final engine = ChaCha7539Engine()
      ..init(
        true,
        ParametersWithIV<KeyParameter>(
          KeyParameter(Uint8List.fromList(key)),
          Uint8List.fromList(nonce),
        ),
      );
    return engine.process(data);
  }

  static Uint8List _hmac(Uint8List key, Uint8List message) {
    final mac = HMac(SHA256Digest(), 64)..init(KeyParameter(key));
    return mac.process(message);
  }

  static bool _equalInConstantTime(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }

  /// The curve point of even Y whose X coordinate is [publicKeyHex], as `secp256k1.getSharedSecret(sk, '02' + pub)` reads it.
  static ECPoint _liftX(String publicKeyHex) {
    final point = _liftXOrNull(publicKeyHex);
    if (point == null) throw ArgumentError('not an x-only public key');
    return point;
  }

  static ECPoint? _liftXOrNull(String publicKeyHex) {
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(publicKeyHex)) return null;
    final x = bigIntFromBytes(hex.decode(publicKeyHex));
    final p = _fieldPrime;
    if (x >= p) return null;
    final c = (x.modPow(BigInt.from(3), p) + BigInt.from(7)) % p;
    final y = c.modPow((p + BigInt.one) >> 2, p);
    if (y.modPow(BigInt.two, p) != c) return null;
    final evenY = y.isEven ? y : p - y;
    return _curve.curve.createPoint(x, evenY);
  }
}
