import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:robosats/src/pgp/primitives.dart';
import 'package:test/test.dart';

Uint8List _bytes(String hexString) => Uint8List.fromList(hex.decode(hexString));

void main() {
  group('Ed25519', () {
    // RFC 8032 section 7.1, test 1 and test 2.
    const vectors = [
      (
        seed:
            '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60',
        publicKey:
            'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
        message: '',
        signature:
            'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155'
            '5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b',
      ),
      (
        seed:
            '4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb',
        publicKey:
            '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c',
        message: '72',
        signature:
            '92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da'
            '085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00',
      ),
    ];

    for (final vector in vectors) {
      test('reproduces RFC 8032 for the message "${vector.message}"', () {
        final seed = _bytes(vector.seed);
        final message = _bytes(vector.message);
        expect(hex.encode(ed25519PublicKey(seed)), vector.publicKey);
        expect(hex.encode(ed25519Sign(seed, message)), vector.signature);
        expect(
          ed25519Verify(
            _bytes(vector.publicKey),
            message,
            _bytes(vector.signature),
          ),
          isTrue,
        );
      });
    }

    test('rejects a forged or malformed signature', () {
      final publicKey = _bytes(vectors[0].publicKey);
      final signature = _bytes(vectors[0].signature);
      expect(
        ed25519Verify(publicKey, Uint8List.fromList([1]), signature),
        isFalse,
      );
      expect(
        ed25519Verify(publicKey, Uint8List(0), signature.sublist(1)),
        isFalse,
      );
      expect(
        ed25519Verify(publicKey.sublist(1), Uint8List(0), signature),
        isFalse,
      );
      expect(
        ed25519Verify(_bytes(vectors[1].publicKey), Uint8List(0), signature),
        isFalse,
      );
    });
  });

  group('X25519', () {
    test('reproduces the key pairs of RFC 7748 section 6.1', () {
      expect(
        hex.encode(
          x25519PublicKey(
            _bytes(
              '77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a',
            ),
          ),
        ),
        '8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a',
      );
      expect(
        hex.encode(
          x25519PublicKey(
            _bytes(
              '5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb',
            ),
          ),
        ),
        'de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f',
      );
    });

    test('reproduces the shared secret of RFC 7748 section 6.1', () {
      final alice = _bytes(
        '77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a',
      );
      final bobPublic = _bytes(
        'de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f',
      );
      expect(
        hex.encode(x25519SharedSecret(alice, bobPublic) ?? const []),
        '4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742',
      );
    });

    test('gives no shared secret with a low-order point or a wrong length', () {
      final scalar = clampX25519Scalar(Uint8List(32)..[5] = 9);
      expect(x25519SharedSecret(scalar, Uint8List(32)), isNull);
      expect(x25519SharedSecret(scalar, Uint8List(32)..[0] = 1), isNull);
      expect(x25519SharedSecret(scalar, Uint8List(31)..[0] = 9), isNull);
      expect(x25519SharedSecret(Uint8List(31), Uint8List(32)..[0] = 9), isNull);
      expect(x25519SharedSecret(scalar, Uint8List(32)..[0] = 9), isNotNull);
    });

    test('clamps a scalar as RFC 7748 section 5 requires', () {
      final clamped = clampX25519Scalar(Uint8List(32)..fillRange(0, 32, 0xff));
      expect(clamped[0], 0xf8);
      expect(clamped[31], 0x7f);
      expect(clamped.sublist(1, 31), everyElement(0xff));
      expect(clampX25519Scalar(Uint8List(32))[31], 0x40);
    });
  });

  group('AES key wrap', () {
    // RFC 3394 sections 4.1, 4.3 and 4.6.
    const vectors = [
      (
        kek: '000102030405060708090a0b0c0d0e0f',
        data: '00112233445566778899aabbccddeeff',
        wrapped: '1fa68b0a8112b447aef34bd8fb5a7b829d3e862371d2cfe5',
      ),
      (
        kek: '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f',
        data: '00112233445566778899aabbccddeeff',
        wrapped: '64e8c3f9ce0f5ba263e9777905818a2a93c8191e7d6e8ae7',
      ),
      (
        kek: '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f',
        data:
            '00112233445566778899aabbccddeeff000102030405060708090a0b0c0d0e0f',
        wrapped:
            '28c9f404c4b810f4cbccb35cfb87f8263f5786e2d80ed326'
            'cbc7f0e71a99f43bfb988b9b7a02dd21',
      ),
    ];

    for (final vector in vectors) {
      test(
        'reproduces RFC 3394 for ${vector.kek.length * 4}-bit keys and ${vector.data.length * 4} bits',
        () {
          final kek = _bytes(vector.kek);
          expect(
            hex.encode(aesKeyWrap(kek, _bytes(vector.data))),
            vector.wrapped,
          );
          expect(
            aesKeyUnwrap(kek, _bytes(vector.wrapped)),
            _bytes(vector.data),
          );
        },
      );
    }

    test('refuses to unwrap what was changed, or under another key', () {
      final kek = _bytes(vectors[0].kek);
      final wrapped = _bytes(vectors[0].wrapped);
      for (var i = 0; i < wrapped.length; i++) {
        expect(
          aesKeyUnwrap(kek, Uint8List.fromList(wrapped)..[i] ^= 1),
          isNull,
          reason: 'byte $i',
        );
      }
      expect(aesKeyUnwrap(Uint8List.fromList(kek)..[0] ^= 1, wrapped), isNull);
      expect(aesKeyUnwrap(kek, wrapped.sublist(0, 16)), isNull);
      expect(aesKeyUnwrap(kek, wrapped.sublist(0, 23)), isNull);
    });
  });

  group('AES in CFB mode', () {
    // NIST SP 800-38A, F.3.17 CFB128-AES256.Encrypt, the first two blocks.
    final key = _bytes(
      '603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4',
    );
    final iv = _bytes('000102030405060708090a0b0c0d0e0f');
    final plain = _bytes(
      '6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51',
    );
    const cipher =
        'dc7e84bfda79164b7ecd8486985d386039ffed143b28b1c832113c6331e5407b';

    test('reproduces NIST SP 800-38A', () {
      expect(
        hex.encode(aesCfb(encrypt: true, key: key, iv: iv, data: plain)),
        cipher,
      );
      expect(
        aesCfb(encrypt: false, key: key, iv: iv, data: _bytes(cipher)),
        plain,
      );
    });

    test('handles a length that is not a multiple of the block size', () {
      final short = Uint8List.sublistView(plain, 0, 21);
      final encrypted = aesCfb(encrypt: true, key: key, iv: iv, data: short);
      expect(hex.encode(encrypted), cipher.substring(0, 42));
      expect(aesCfb(encrypt: false, key: key, iv: iv, data: encrypted), short);
    });
  });

  group('iterated and salted S2K', () {
    final salt = _bytes('0102030405060708');
    final passphrase = utf8.encode('correct horse');

    test('decodes the byte count', () {
      expect(s2kByteCount(224), 16777216);
      expect(s2kByteCount(96), 65536);
      expect(s2kByteCount(0), 1024);
      expect(s2kByteCount(255), 65011712);
    });

    test('hashes salt and passphrase repeated up to the byte count', () {
      final unit = [...salt, ...passphrase];
      final repeated = [
        for (var i = 0; i < 1024 ~/ unit.length + 1; i++) ...unit,
      ].sublist(0, 1024);
      expect(
        s2kIteratedSalted(
          hash: crypto.sha256,
          passphrase: passphrase,
          salt: salt,
          codedCount: 0,
          keyLength: 32,
        ),
        crypto.sha256.convert(repeated).bytes,
      );
      // A key longer than the digest takes a second pass over the same data, prefixed with a zero byte.
      expect(
        s2kIteratedSalted(
          hash: crypto.sha1,
          passphrase: passphrase,
          salt: salt,
          codedCount: 0,
          keyLength: 32,
        ),
        [
          ...crypto.sha1.convert(repeated).bytes,
          ...crypto.sha1.convert([0, ...repeated]).bytes,
        ].sublist(0, 32),
      );
    });

    test(
      'hashes the whole input once when it is longer than the byte count',
      () {
        final long = List.filled(2000, 0x61);
        expect(
          s2kIteratedSalted(
            hash: crypto.sha256,
            passphrase: long,
            salt: salt,
            codedCount: 0,
            keyLength: 16,
          ),
          crypto.sha256.convert([...salt, ...long]).bytes.sublist(0, 16),
        );
      },
    );

    test('streams 65 536 bytes exactly, across chunk boundaries', () {
      final unit = [...salt, ...passphrase];
      final repeated = Uint8List(65536);
      for (var i = 0; i < repeated.length; i++) {
        repeated[i] = unit[i % unit.length];
      }
      expect(
        s2kIteratedSalted(
          hash: crypto.sha256,
          passphrase: passphrase,
          salt: salt,
          codedCount: 96,
          keyLength: 32,
        ),
        crypto.sha256.convert(repeated).bytes,
      );
    });
  });

  test('hash identifiers map to the names of armor headers', () {
    expect(hashName(HashId.sha512), 'SHA512');
    expect(hashName(HashId.sha256), 'SHA256');
    expect(hashName(HashId.sha384), 'SHA384');
    expect(hashName(HashId.sha224), 'SHA224');
    // SHA-1 and MD5 are not accepted in signatures.
    expect(hashName(HashId.sha1), isNull);
    expect(signatureHash(HashId.sha1), isNull);
    expect(signatureHash(1), isNull);
    expect(aesKeyLength(CipherId.aes128), 16);
    expect(aesKeyLength(CipherId.aes192), 24);
    expect(aesKeyLength(CipherId.aes256), 32);
    expect(aesKeyLength(2), isNull);
    // RFC 6637 section 12: an ECDH key derives with SHA-256, SHA-384 or SHA-512.
    expect(ecdhKdfHash(HashId.sha256), isNotNull);
    expect(ecdhKdfHash(HashId.sha384), isNotNull);
    expect(ecdhKdfHash(HashId.sha512), isNotNull);
    expect(ecdhKdfHash(HashId.sha224), isNull);
    expect(ecdhKdfHash(HashId.sha1), isNull);
  });
}
