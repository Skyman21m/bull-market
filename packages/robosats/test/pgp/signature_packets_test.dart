import 'dart:typed_data';

import 'package:robosats/robosats.dart';
import 'package:robosats/src/pgp/armor.dart';
import 'package:robosats/src/pgp/bytes.dart';
import 'package:robosats/src/pgp/primitives.dart';
import 'package:robosats/src/pgp/signature_packets.dart';
import 'package:test/test.dart';

import '../support/craft.dart';
import '../support/pgp.dart';

const _keyDate = CraftedKey.defaultCreatedAt;

DateTime _at(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

/// One hour after the key and every default signature were made.
final _now = _at(_keyDate + 3600);

final _crafted = CraftedKey();
final _key = _crafted.publicKey;

/// A cleartext message with a hand-made text signature of [_crafted], dated like the key unless [hashed] says otherwise.
String _signed(
  String text, {
  int type = SignatureType.text,
  int version = 4,
  int algorithm = 22,
  int hashId = HashId.sha512,
  List<int>? hashed,
  List<int> unhashed = const [],
  List<int> trailing = const [],
  bool breakDigestPrefix = false,
}) => craftCleartext(
  text,
  craftSignature(
    seed: _crafted.seed,
    type: type,
    version: version,
    algorithm: algorithm,
    hashId: hashId,
    data: canonicalText(text),
    hashed: hashed ?? creationTime(_keyDate),
    unhashed: unhashed,
    trailing: trailing,
    breakDigestPrefix: breakDigestPrefix,
  ),
  hash: hashName(hashId) ?? 'SHA1',
);

void _expectValid(String signed, {DateTime? now}) =>
    expectOk(_key.verifyCleartext(signed, now: now ?? _now));

void _expectInvalid(String signed, {DateTime? now, String? reason}) => expect(
  expectErr(_key.verifyCleartext(signed, now: now ?? _now)),
  isA<PgpSignatureInvalid>(),
  reason: reason,
);

void main() {
  group('a hand-made text signature', () {
    test('is accepted in its plain form', () {
      expect(
        expectOk(_key.verifyCleartext(_signed('text'), now: _now)),
        'text',
      );
    });

    test('is accepted over SHA-256, SHA-384 and SHA-224, not over SHA-1', () {
      for (final hashId in [HashId.sha256, HashId.sha384, HashId.sha224]) {
        _expectValid(_signed('text', hashId: hashId));
      }
      _expectInvalid(_signed('text', hashId: HashId.sha1));
    });

    test('is accepted with subpackets it does not know, unless critical', () {
      // Subpacket 99 is unassigned; 20 is notation data, which dart_pg 2.0.0 adds to every signature.
      for (final type in [99, 20]) {
        _expectValid(
          _signed(
            'text',
            hashed: [
              ...creationTime(_keyDate),
              ...subpacket(type, [1, 2]),
            ],
          ),
        );
        _expectInvalid(
          _signed(
            'text',
            hashed: [
              ...creationTime(_keyDate),
              ...subpacket(type, [1, 2], critical: true),
            ],
          ),
          reason: 'critical subpacket $type',
        );
      }
    });

    test(
      'is accepted with the issuer in the unhashed area, as GnuPG writes',
      () {
        _expectValid(
          _signed('text', unhashed: subpacket(16, [1, 2, 3, 4, 5, 6, 7, 8])),
        );
      },
    );

    test('is accepted with two-byte and five-byte subpacket lengths', () {
      for (final (length, header) in [
        // 301 = ((192 - 192) << 8) + 109 + 192.
        (300, [192, 109]),
        // 8401 = ((224 - 192) << 8) + 17 + 192: a first byte that would mean a partial length on a packet.
        (8400, [224, 17]),
        (300, [255, 0, 0, 1, 45]),
      ]) {
        _expectValid(
          _signed(
            'text',
            hashed: [
              ...header,
              20,
              ...List.filled(length, 0x61),
              ...creationTime(_keyDate),
            ],
          ),
        );
      }
    });

    test('is refused when the two digest bytes it carries are wrong', () {
      _expectInvalid(_signed('text', breakDigestPrefix: true));
    });

    test('is refused when it is not a text signature', () {
      for (final type in [SignatureType.binary, 0x10]) {
        _expectInvalid(_signed('text', type: type));
      }
    });

    test('is refused in another version, algorithm or with trailing bytes', () {
      for (final signed in [
        _signed('text', version: 5),
        _signed('text', algorithm: 1),
        _signed('text', trailing: [0]),
        _signed('text', hashed: [9, 2, 0]),
        _signed('text', hashed: [0]),
      ]) {
        _expectInvalid(signed);
      }
    });

    test('is found behind packets that are not readable signatures', () {
      final good = encodePacket(
        PacketTag.signature,
        craftSignature(
          seed: _crafted.seed,
          type: SignatureType.text,
          data: canonicalText('text'),
          hashed: creationTime(_keyDate),
        ),
      );
      for (final first in [
        encodePacket(PacketTag.signature, [4, 1, 1, 10, 0, 0, 0, 0, 0, 0]),
        encodePacket(PacketTag.signature, [4, 1, 22]),
        encodePacket(PacketTag.userId, [1, 2, 3]),
      ]) {
        _expectValid(
          cleartextEncode(
            text: 'text',
            hashName: 'SHA512',
            signature: [...first, ...good],
          ),
        );
      }
      _expectInvalid(
        cleartextEncode(
          text: 'text',
          hashName: 'SHA512',
          signature: [for (var i = 0; i < 8; i++) ...first8(i), ...good],
        ),
        reason: 'more packets than a signed text may carry',
      );
    });
  });

  group('the dates of a signature', () {
    test('must be stated', () {
      _expectInvalid(_signed('text', hashed: const []));
    });

    test('must not be after the clock, to the second', () {
      final signed = _signed('text', hashed: creationTime(_keyDate + 100));
      _expectValid(signed, now: _at(_keyDate + 100));
      _expectInvalid(signed, now: _at(_keyDate + 99));
      // The year 2100, as in the review.
      _expectInvalid(_signed('text', hashed: creationTime(4102444800)));
    });

    test('must not be before the key was made', () {
      _expectInvalid(_signed('text', hashed: creationTime(_keyDate - 1)));
    });

    test('must not be past its own expiration', () {
      final signed = _signed(
        'text',
        hashed: [
          ...creationTime(_keyDate),
          ...subpacket(3, u32Bytes(60), critical: true),
        ],
      );
      _expectValid(signed, now: _at(_keyDate + 59));
      _expectInvalid(signed, now: _at(_keyDate + 60));
      _expectInvalid(signed);
    });

    test('must fall while the key was valid', () {
      final expiring = CraftedKey(
        certificationHashed: [
          ...creationTime(_keyDate),
          ...subpacket(9, u32Bytes(1000)),
        ],
      );
      String signedAt(int seconds) => craftCleartext(
        'text',
        craftSignature(
          seed: expiring.seed,
          type: SignatureType.text,
          data: canonicalText('text'),
          hashed: creationTime(seconds),
        ),
      );
      final key = expiring.publicKey;
      // A signature made in time stays valid after the key has expired, as in OpenPGP.js.
      expectOk(key.verifyCleartext(signedAt(_keyDate + 999), now: _now));
      expect(
        expectErr(key.verifyCleartext(signedAt(_keyDate + 1000), now: _now)),
        isA<PgpSignatureInvalid>(),
      );
    });

    test(
      'must not be before the key even when its self-certification is older',
      () {
        // A certification dated before the key it certifies: the date of the key is what counts.
        final certifiedEarlier = CraftedKey(
          certificationHashed: creationTime(_keyDate - 1000),
        );
        String signedAt(int seconds) => craftCleartext(
          'text',
          craftSignature(
            seed: certifiedEarlier.seed,
            type: SignatureType.text,
            data: canonicalText('text'),
            hashed: creationTime(seconds),
          ),
        );
        final key = certifiedEarlier.publicKey;
        expectOk(key.verifyCleartext(signedAt(_keyDate), now: _now));
        expect(
          expectErr(key.verifyCleartext(signedAt(_keyDate - 500), now: _now)),
          isA<PgpSignatureInvalid>(),
        );
      },
    );

    test(
      'are never accepted from a key whose self-certification states no date',
      () {
        final undated = CraftedKey(certificationHashed: const []);
        expect(
          expectErr(
            undated.publicKey.verifyCleartext(
              craftCleartext(
                'text',
                craftSignature(
                  seed: undated.seed,
                  type: SignatureType.text,
                  data: canonicalText('text'),
                  hashed: creationTime(_keyDate),
                ),
              ),
              now: _now,
            ),
          ),
          isA<PgpSignatureInvalid>(),
        );
      },
    );

    test('must not be before the self-certification of the key', () {
      final certifiedLater = CraftedKey(
        certificationHashed: creationTime(_keyDate + 500),
      );
      String signedAt(int seconds) => craftCleartext(
        'text',
        craftSignature(
          seed: certifiedLater.seed,
          type: SignatureType.text,
          data: canonicalText('text'),
          hashed: creationTime(seconds),
        ),
      );
      final key = certifiedLater.publicKey;
      expectOk(key.verifyCleartext(signedAt(_keyDate + 500), now: _now));
      expect(
        expectErr(key.verifyCleartext(signedAt(_keyDate + 499), now: _now)),
        isA<PgpSignatureInvalid>(),
      );
    });
  });

  group('SignatureBody.parse', () {
    test('reads the dates and flags of the hashed area only', () {
      final body = craftSignature(
        seed: _crafted.seed,
        type: SignatureType.subkeyBinding,
        data: const [1],
        hashed: [
          ...creationTime(1000),
          ...subpacket(3, u32Bytes(60)),
          ...subpacket(9, u32Bytes(70)),
          ...subpacket(27, [0x0c]),
        ],
        unhashed: creationTime(5),
      );
      final signature = SignatureBody.parse(body);
      expect(signature.createdAt, 1000);
      expect(signature.expiresAfter, 60);
      expect(signature.keyExpiresAfter, 70);
      expect(signature.keyFlags, 0x0c);
      expect(signature.isCurrentAt(999), isFalse);
      expect(signature.isCurrentAt(1059), isTrue);
      expect(signature.isCurrentAt(1060), isFalse);
      expect(
        signature.verify(Uint8List.fromList([1]), _crafted.primaryPoint),
        isTrue,
      );
      expect(
        signature.verify(Uint8List.fromList([2]), _crafted.primaryPoint),
        isFalse,
      );
    });
  });
}

/// A different unreadable packet each time, so that the bound on their number is what refuses the message.
List<int> first8(int index) => encodePacket(PacketTag.userId, [index]);
