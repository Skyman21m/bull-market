import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:robosats/src/pgp/armor.dart';
import 'package:robosats/src/pgp/bytes.dart';
import 'package:robosats/src/pgp/key_packets.dart';
import 'package:robosats/src/pgp/limits.dart';
import 'package:robosats/src/pgp/message_cipher.dart';
import 'package:robosats/src/pgp/signature_packets.dart';
import 'package:test/test.dart';

import '../support/craft.dart';
import '../support/pgp.dart';

const _keyDate = CraftedKey.defaultCreatedAt;

DateTime _at(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

final _now = _at(_keyDate + 3600);

final _alice = CraftedKey(label: 'alice');
final _bobKey = CraftedKey(label: 'bob');
final _bob = _bobKey.unlockedFor(interopPeerIdentity);

PublicKeyBody _subkeyOf(CraftedKey key) =>
    PublicKeyBody.read(ByteReader(key.subkeyBody));

/// [inner], any bytes at all, properly encrypted to Alice and to Bob: what a peer who holds a valid key can send.
Uint8List _encrypt(List<int> inner, {List<CraftedKey>? to}) {
  final encrypted = encryptPackets(Uint8List.fromList(inner), [
    for (final key in to ?? [_alice, _bobKey]) _subkeyOf(key),
  ], random: DeterministicRandom('hostile message'));
  if (encrypted == null) fail('encryption refused');
  return encrypted;
}

String _armor(List<int> bytes) => armorEncode(ArmorBlock.message, bytes);

/// A signature packet by Alice over [signedText], dated like her key unless [hashed] says otherwise.
Uint8List _signature(
  String signedText, {
  int type = SignatureType.text,
  List<int>? hashed,
}) => encodePacket(
  PacketTag.signature,
  craftSignature(
    seed: _alice.seed,
    type: type,
    data: utf8.encode(signedText),
    hashed: hashed ?? creationTime(_keyDate),
  ),
);

Result<DecryptedChatMessage, PgpFailure> _read(List<int> message) => _bob
    .decryptChatMessage(_armor(message), sender: _alice.publicKey, now: _now);

void _expectRefused(List<int> message, {String? reason}) => expect(
  expectErr(_read(message)),
  isA<PgpMessageUndecryptable>(),
  reason: reason,
);

Uint8List _deflate(List<int> data, {required bool raw}) =>
    Uint8List.fromList(ZLibEncoder(raw: raw).convert(data));

Uint8List _compressed(List<int> packets, {int algorithm = 1}) => encodePacket(
  PacketTag.compressedData,
  [algorithm, ..._deflate(packets, raw: algorithm == 1)],
);

void main() {
  const text = 'pay to honest';
  final good = [...literalPacket(text), ..._signature(text)];

  group('the contents of a chat message', () {
    test('are a text and its signature', () {
      final decrypted = expectOk(_read(_encrypt(good)));
      expect(decrypted.text, text);
      expect(decrypted.validSignature, isTrue);
      expect(decrypted.signedAt, _at(_keyDate));
    });

    test('may be signed as text over CR LF while stored with LF', () {
      // A text signature covers the canonical form: OpenPGP.js verifies it so whatever the stored line ending.
      final decrypted = expectOk(
        _read(_encrypt([...literalPacket('a\nb'), ..._signature('a\r\nb')])),
      );
      expect(decrypted.text, 'a\nb');
      expect(decrypted.validSignature, isTrue);
      final binary = expectOk(
        _read(
          _encrypt([
            ...literalPacket('a\nb'),
            ..._signature('a\r\nb', type: SignatureType.binary),
          ]),
        ),
      );
      expect(binary.validSignature, isFalse);
    });

    test(
      'show a text whose signature is missing, foreign, expired or from the future, and flag it',
      () {
        for (final MapEntry(key: reason, value: signature) in {
          'none': <int>[],
          'over another text': _signature('pay to ATTACKER'),
          'certification type': _signature(text, type: 0x10),
          'dated after the clock': _signature(
            text,
            hashed: creationTime(_keyDate + 3601),
          ),
          'dated before the key': _signature(
            text,
            hashed: creationTime(_keyDate - 1),
          ),
          'expired': _signature(
            text,
            hashed: [
              ...creationTime(_keyDate),
              ...subpacket(3, u32Bytes(3600), critical: true),
            ],
          ),
          'unknown critical subpacket': _signature(
            text,
            hashed: [
              ...creationTime(_keyDate),
              ...subpacket(99, [1], critical: true),
            ],
          ),
          'not a readable signature': encodePacket(PacketTag.signature, [4, 1]),
        }.entries) {
          final decrypted = expectOk(
            _read(_encrypt([...literalPacket(text), ...signature])),
          );
          expect(decrypted.text, text, reason: reason);
          expect(decrypted.validSignature, isFalse, reason: reason);
          expect(decrypted.signedAt, isNull, reason: reason);
        }
      },
    );

    test('may sit in one compressed data packet, ZIP or ZLIB', () {
      for (final algorithm in [1, 2]) {
        final decrypted = expectOk(
          _read(_encrypt(_compressed(good, algorithm: algorithm))),
        );
        expect(decrypted.text, text);
        expect(decrypted.validSignature, isTrue);
      }
    });

    test('may use the stream lengths GnuPG writes', () {
      final literal = literalPacket('x' * 600).sublist(3);
      final partial = [
        0xc0 | PacketTag.literalData,
        // A first chunk of 512 bytes, then the rest with a definite length.
        0xe9, ...literal.sublist(0, 512),
        literal.length - 512, ...literal.sublist(512),
      ];
      expect(expectOk(_read(_encrypt(partial))).text, 'x' * 600);
      // A compressed data packet of indeterminate length, in the old format.
      final indeterminate = [0xa3, 1, ..._deflate(good, raw: true)];
      expect(expectOk(_read(_encrypt(indeterminate))).validSignature, isTrue);
    });

    test('are refused in any other arrangement', () {
      final onePass = encodePacket(
        PacketTag.onePassSignature,
        List.filled(13, 0),
      );
      for (final MapEntry(key: reason, value: inner) in {
        'no literal data': _signature(text),
        'nothing': <int>[],
        'two texts': [...literalPacket('pay to ATTACKER'), ...good],
        'a text after the signature': [...good, ...literalPacket('more')],
        'a one-pass signature after the text': [...good, ...onePass],
        'a user ID packet': [
          ...good,
          ...encodePacket(PacketTag.userId, [1]),
        ],
        'stray bytes': [..._alice.primaryBody, ...good],
        'a key packet': [
          ...encodePacket(PacketTag.publicKey, _alice.primaryBody),
          ...good,
        ],
        'compressed data next to a text': [..._compressed(good), ...good],
        'compressed data twice': _compressed(_compressed(good)),
        'compression of another kind': _compressed(good, algorithm: 3),
        'damaged compressed data': encodePacket(PacketTag.compressedData, [
          1,
          0xff,
          0xff,
        ]),
        'an unknown literal format': literalPacket(text, format: 0x31),
        'a truncated literal packet': encodePacket(PacketTag.literalData, [
          0x75,
          9,
        ]),
        'too many signatures': [
          ...literalPacket(text),
          for (var i = 0; i <= PgpLimits.signatures; i++) ..._signature(text),
        ],
        'too many one-pass signatures': [
          for (var i = 0; i <= PgpLimits.signatures; i++) ...onePass,
          ...good,
        ],
      }.entries) {
        _expectRefused(_encrypt(inner), reason: reason);
      }
    });

    test(
      'are never inflated beyond the bound, even from an authenticated peer',
      () {
        final small = literalPacket('x' * (PgpLimits.decompressedBytes - 100));
        expect(
          expectOk(_read(_encrypt(_compressed(small)))).text.length,
          PgpLimits.decompressedBytes - 100,
        );
        // 16 MiB of zeros deflate to about 16 KiB: the bomb of the review, inside a properly encrypted message.
        const size = 16 << 20;
        final literal = Uint8List(6 + size + 6)
          ..setAll(0, [
            0xc0 | PacketTag.literalData,
            0xff,
            ...u32Bytes(size + 6),
          ])
          ..[6] = 0x75;
        final bomb = _compressed(literal);
        expect(bomb.length, lessThan(20000));
        final watch = Stopwatch()..start();
        _expectRefused(_encrypt(bomb));
        expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      },
    );
  });

  group('the envelope of a chat message', () {
    final packets = decodePackets(_encrypt(good), maxPackets: 3);
    List<int> frame(List<RawPacket> list) => [
      for (final packet in list) ...encodePacket(packet.tag, packet.body),
    ];

    test('is session keys, then one integrity-protected data packet', () {
      expect(packets.map((packet) => packet.tag), [1, 1, 18]);
      expectOk(_read(frame(packets)));
      expectOk(_read(frame([packets[1], packets[2]])));
    });

    test('is refused with anything before, between or after', () {
      final signature = decodePackets(_signature(text), maxPackets: 1).single;
      final literal = decodePackets(literalPacket(text), maxPackets: 1).single;
      for (final MapEntry(key: reason, value: list) in {
        'a text before': [literal, ...packets],
        'a signature after': [...packets, signature],
        'a text between': [packets[0], literal, packets[1], packets[2]],
        'two data packets': [...packets, packets[2]],
        'no session key': [packets[2]],
        'no data': [packets[0], packets[1]],
        'the data first': [packets[2], packets[0], packets[1]],
        'the session key of the sender only': [packets[0], packets[2]],
        'a password session key': [
          (tag: 3, body: Uint8List.fromList([4, 9, 0, 8])),
          ...packets,
        ],
      }.entries) {
        _expectRefused(frame(list), reason: reason);
      }
      _expectRefused([...literalPacket(text), ..._signature(text)]);
    });

    test('is refused without integrity protection', () {
      // The same bytes relabelled as the old encrypted data packet, tag 9, which carries no modification detection code.
      _expectRefused(
        frame([
          packets[0],
          packets[1],
          (tag: 9, body: Uint8List.sublistView(packets[2].body, 1)),
        ]),
      );
      _expectRefused(
        frame([
          packets[0],
          packets[1],
          (tag: 18, body: Uint8List.fromList([2, ...packets[2].body.skip(1)])),
        ]),
        reason: 'version 2',
      );
      _expectRefused(
        frame([
          packets[0],
          packets[1],
          (tag: 18, body: Uint8List.sublistView(packets[2].body, 0, 30)),
        ]),
        reason: 'too short to hold a modification detection code',
      );
    });

    test('is refused when any byte of the data packet changes', () {
      for (var i = 0; i < packets[2].body.length; i++) {
        final body = Uint8List.fromList(packets[2].body)..[i] ^= 0x01;
        _expectRefused(
          frame([packets[0], packets[1], (tag: 18, body: body)]),
          reason: 'byte $i',
        );
      }
    });

    test('is refused when the session key of the reader changes', () {
      var opened = 0;
      for (var i = 0; i < packets[1].body.length; i++) {
        final body = Uint8List.fromList(packets[1].body)..[i] ^= 0x01;
        final result = _read(
          frame([packets[0], (tag: 1, body: body), packets[2]]),
        );
        if (result is Ok) opened++;
      }
      // Only the low bit of the bit count of the ephemeral point can change without effect: 263 and 262 bits take the same 33 bytes.
      expect(opened, 1);
    });

    test('is opened by a session key packet that hides its recipient', () {
      final anonymous = Uint8List.fromList(packets[1].body)..fillRange(1, 9, 0);
      expectOk(_read(frame([(tag: 1, body: anonymous), packets[2]])));
    });

    test('skips session keys for other keys and of other kinds', () {
      final rsa = (
        tag: 1,
        body: Uint8List.fromList([3, ...List.filled(8, 1), 1, 0, 8, 0xff]),
      );
      final version6 = (tag: 1, body: Uint8List.fromList([6, 0, 25]));
      expectOk(
        _read(frame([rsa, version6, packets[0], packets[1], packets[2]])),
      );
    });

    test('is refused with more session keys than the bound', () {
      _expectRefused(
        frame([
          for (var i = 0; i < PgpLimits.sessionKeyPackets; i++) packets[0],
          packets[1],
          packets[2],
        ]),
      );
      expectOk(
        _read(
          frame([
            for (var i = 0; i < PgpLimits.sessionKeyPackets - 1; i++)
              packets[0],
            packets[1],
            packets[2],
          ]),
        ),
      );
    });

    test('is not read at all beyond its size bound', () {
      expect(
        expectErr(
          _bob.decryptChatMessage(
            '${_armor(_encrypt(good))}${' ' * PgpLimits.messageArmorChars}',
            sender: _alice.publicKey,
          ),
        ),
        isA<PgpInputTooLarge>(),
      );
    });
  });

  group('the denial-of-service messages of the security review', () {
    // None needs a key: before the fix each was handed, unauthenticated, to a parser that inflated compressed data recursively.
    String hostile(String name) =>
        File('test/fixtures/pgp_hostile/$name').readAsStringSync();
    String nested(int depth) => _armor([
      for (var i = 0; i < depth; i++) ...[0xa3, 0x00],
      ...[0xcb, 0x06, 0x75, 0, 0, 0, 0, 0],
    ]);
    String tiny(int kilobytes) => _armor([
      for (var i = 0; i < kilobytes * 512; i++) ...[0xd5, 0x00],
    ]);

    for (final MapEntry(key: name, value: build) in {
      'three deflate layers that inflate to 256 MiB, 366 characters': () =>
          hostile('bomb_256mb.asc'),
      'three deflate layers that inflate to 4 GiB, 415 characters': () =>
          hostile('bomb_4gb.asc'),
      '2 000 nested compressed data packets': () => nested(2000),
      '10 000 nested compressed data packets': () => nested(10000),
      '40 kB of empty packets': () => tiny(40),
    }.entries) {
      test('are refused: $name', () {
        final message = build();
        expect(message.length, lessThan(PgpLimits.messageArmorChars));
        final watch = Stopwatch()..start();
        expect(
          expectErr(_bob.decryptChatMessage(message, sender: _alice.publicKey)),
          isA<PgpMessageUndecryptable>(),
        );
        expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      });
    }

    for (final MapEntry(key: name, value: build) in {
      '50 000 nested compressed data packets': () => nested(50000),
      '50 kB of empty packets': () => tiny(50),
      '100 kB of empty packets': () => tiny(100),
      '400 kB of empty packets': () => tiny(400),
    }.entries) {
      test('are not read: $name', () {
        final watch = Stopwatch()..start();
        expect(
          expectErr(_bob.decryptChatMessage(build(), sender: _alice.publicKey)),
          isA<PgpInputTooLarge>(),
        );
        expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      });
    }
  });

  group('encryptPackets', () {
    test('is a deterministic function of its inputs and its randomness', () {
      expect(_encrypt(good), _encrypt(good));
      expect(_encrypt(good, to: [_bobKey]), isNot(_encrypt(good)));
    });

    test('writes one 94-byte session key per recipient, then the data', () {
      final packets = decodePackets(
        _encrypt(good, to: [_alice, _bobKey, _alice]),
        maxPackets: 4,
      );
      expect(packets.map((packet) => packet.tag), [1, 1, 1, 18]);
      for (final packet in packets.take(3)) {
        expect(packet.body, hasLength(94));
        expect(packet.body[0], 3);
        expect(packet.body[9], 18);
      }
      // A fresh ephemeral key for each recipient, even for the same one twice.
      expect(packets[0].body, isNot(packets[2].body));
      // Version, an 18-byte prefix, the packets, and the 22 bytes of the modification detection code.
      expect(packets[3].body, hasLength(1 + 18 + good.length + 22));
    });
  });
}
