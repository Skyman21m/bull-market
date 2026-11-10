import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:robosats/robosats.dart';
import 'package:robosats/src/pgp/armor.dart';
import 'package:robosats/src/pgp/bytes.dart';
import 'package:robosats/src/pgp/key_packets.dart';
import 'package:robosats/src/pgp/primitives.dart';
import 'package:robosats/src/pgp/signature_packets.dart';
import 'package:test/test.dart';

import '../support/pgp.dart';

/// The Ed25519 seed of the key below: the first 32 bytes its generation draws.
final _seed = Uint8List.fromList(List.generate(32, (i) => i + 1));

final _key = RobotPgpKey.generate(
  interopIdentity,
  now: interopNow,
  random: ScriptedRandom(_seed),
).publicKey;

/// A cleartext message signed by [_key] with a hand-made signature packet, to reach what the package itself never writes.
String _signed(
  String text, {
  int version = 4,
  int type = SignatureType.text,
  int algorithm = KeyAlgorithm.eddsaLegacy,
  int hashId = HashId.sha512,
  crypto.Hash hash = crypto.sha512,
  List<int> hashed = const [5, 2, 0, 0, 0, 1],
  List<int> unhashed = const [],
  List<int> trailing = const [],
}) {
  final hashedPortion = [
    version,
    type,
    algorithm,
    hashId,
    ...u16Bytes(hashed.length),
    ...hashed,
  ];
  final digest = Uint8List.fromList(
    hash.convert([
      ...canonicalText(text),
      ...hashedPortion,
      4,
      0xff,
      ...u32Bytes(hashedPortion.length),
    ]).bytes,
  );
  final signature = ed25519Sign(_seed, digest);
  return cleartextEncode(
    text: text,
    hashName: hashName(hashId) ?? 'SHA1',
    signature: encodePacket(PacketTag.signature, [
      ...hashedPortion,
      ...u16Bytes(unhashed.length),
      ...unhashed,
      digest[0],
      digest[1],
      ...mpiEncode(signature.sublist(0, 32)),
      ...mpiEncode(signature.sublist(32)),
      ...trailing,
    ]),
  );
}

void main() {
  group('a hand-made text signature', () {
    test('is accepted in its plain form', () {
      expect(expectOk(_key.verifyCleartext(_signed('text'))), 'text');
    });

    test('is accepted over SHA-256, SHA-384 and SHA-224', () {
      for (final (hashId, hash) in [
        (HashId.sha256, crypto.sha256),
        (HashId.sha384, crypto.sha384),
        (HashId.sha224, crypto.sha224),
      ]) {
        expectOk(
          _key.verifyCleartext(_signed('text', hashId: hashId, hash: hash)),
        );
      }
    });

    test('is refused over SHA-1', () {
      expect(
        expectErr(
          _key.verifyCleartext(
            _signed('text', hashId: HashId.sha1, hash: crypto.sha1),
          ),
        ),
        isA<PgpSignatureInvalid>(),
      );
    });

    test('is accepted with subpackets it does not know, unless critical', () {
      // Subpacket 99 is unassigned; 20 is notation data, which dart_pg 2.0.0 adds to every signature.
      for (final type in [99, 20]) {
        final subpacket = [3, type, 1, 2];
        expectOk(
          _key.verifyCleartext(
            _signed('text', hashed: [5, 2, 0, 0, 0, 1, ...subpacket]),
          ),
        );
        expect(
          expectErr(
            _key.verifyCleartext(
              _signed('text', hashed: [5, 2, 0, 0, 0, 1, 3, type | 0x80, 1, 2]),
            ),
          ),
          isA<PgpSignatureInvalid>(),
          reason: 'critical subpacket $type',
        );
      }
    });

    test(
      'is accepted with the issuer in the unhashed area, as GnuPG writes',
      () {
        expectOk(
          _key.verifyCleartext(
            _signed('text', unhashed: [9, 16, 1, 2, 3, 4, 5, 6, 7, 8]),
          ),
        );
      },
    );

    test('is accepted with long subpacket lengths', () {
      final notation = List.filled(300, 0x61);
      expectOk(
        _key.verifyCleartext(
          _signed(
            'text',
            hashed: [
              // Two-byte length: 301 = ((192 - 192) << 8) + 109 + 192.
              192, 109, 20, ...notation,
              // Five-byte length.
              255, 0, 0, 0, 5, 2, 0, 0, 0, 1,
            ],
          ),
        ),
      );
    });

    test('is refused when it is not a text signature', () {
      expect(
        expectErr(
          _key.verifyCleartext(_signed('text', type: SignatureType.binary)),
        ),
        isA<PgpSignatureInvalid>(),
      );
    });

    test('is refused in another version, algorithm or with trailing bytes', () {
      for (final signed in [
        _signed('text', version: 5),
        _signed('text', algorithm: 1),
        _signed('text', trailing: [0]),
        _signed('text', hashed: [9, 2, 0]),
        _signed('text', hashed: [0]),
      ]) {
        expect(
          expectErr(_key.verifyCleartext(signed)),
          isA<PgpSignatureInvalid>(),
        );
      }
    });
  });

  group('a key that carries more than a robot key', () {
    final packets = packetsOf(ArmorBlock.publicKey, _key.armored);

    String withExtra(int afterIndex, RawPacket extra) =>
        armorEncode(ArmorBlock.publicKey, [
          for (final (index, packet) in packets.indexed) ...[
            ...encodePacket(packet.tag, packet.body),
            if (index == afterIndex) ...encodePacket(extra.tag, extra.body),
          ],
        ]);

    test('is read despite a certification by another kind of key', () {
      // A version 4 RSA certification, as a third party could add.
      final rsaSignature = Uint8List.fromList([
        4,
        0x10,
        1,
        8,
        0,
        0,
        0,
        0,
        1,
        2,
      ]);
      final key = expectOk(
        PgpPublicKey.parse(
          withExtra(2, (tag: PacketTag.signature, body: rsaSignature)),
        ),
      );
      expect(key, _key);
    });

    test('is read despite a signature packet that is cut short', () {
      final key = expectOk(
        PgpPublicKey.parse(
          withExtra(2, (
            tag: PacketTag.signature,
            body: Uint8List.fromList([4, 0x10, 22, 10, 0, 9]),
          )),
        ),
      );
      expect(key, _key);
    });

    test('is read despite packets of an unknown kind and other subkeys', () {
      final rsaSubkey = Uint8List.fromList([4, 0, 0, 0, 1, 1, 0, 8, 0xff]);
      for (final extra in [
        (tag: 17, body: Uint8List.fromList([1, 2, 3])),
        (tag: 61, body: Uint8List(0)),
        (tag: PacketTag.publicSubkey, body: rsaSubkey),
      ]) {
        final key = expectOk(PgpPublicKey.parse(withExtra(4, extra)));
        expect(key, _key, reason: 'tag ${extra.tag}');
      }
    });

    test('keeps the first certified user ID', () {
      final key = expectOk(
        PgpPublicKey.parse(
          withExtra(2, (
            tag: PacketTag.userId,
            body: Uint8List.fromList('uncertified'.codeUnits),
          )),
        ),
      );
      expect(key.userId, _key.userId);
    });

    test('is refused when its subkey binding does not allow encryption', () {
      // The key-flags subpacket sits at a fixed place in the binding OpenPGP.js lays out: turning 0x0c into 0x02 also breaks the signature, so the subkey is dropped either way.
      final binding = Uint8List.fromList(packets[4].body);
      final flagsAt = binding.indexOf(0x9b) + 1;
      binding[flagsAt] = 0x02;
      expect(
        expectErr(
          PgpPublicKey.parse(
            armorEncode(ArmorBlock.publicKey, [
              for (final packet in packets.take(4))
                ...encodePacket(packet.tag, packet.body),
              ...encodePacket(PacketTag.signature, binding),
            ]),
          ),
        ),
        isA<PgpKeyUnsupported>(),
      );
    });
  });
}
