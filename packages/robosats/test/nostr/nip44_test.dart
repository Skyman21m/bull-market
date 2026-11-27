import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:robosats/src/nostr/nip44.dart';
import 'package:robosats/src/secp256k1.dart';
import 'package:test/test.dart';

/// Every section of the official NIP-44 vector file (`test/fixtures/nostr/README.md`).
void main() {
  final file = File('test/fixtures/nostr/nip44.vectors.json');
  final vectors =
      (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)['v2']
          as Map<String, dynamic>;
  final valid = vectors['valid'] as Map<String, dynamic>;
  final invalid = vectors['invalid'] as Map<String, dynamic>;
  List<Map<String, dynamic>> maps(Object? list) =>
      (list as List<dynamic>).cast<Map<String, dynamic>>();

  test('the file is the one whose checksum NIP-44 publishes', () {
    expect(
      sha256.convert(file.readAsBytesSync()).toString(),
      '269ed0f69e4c192512cc779e78c555090cebc7c785b609e338a62afc3ce25040',
    );
  });

  test('valid get_conversation_key: all 35', () {
    final cases = maps(valid['get_conversation_key']);
    expect(cases, hasLength(35));
    for (final c in cases) {
      expect(
        hex.encode(
          Nip44.conversationKey(
            hex.decode(c['sec1'] as String),
            c['pub2'] as String,
          ),
        ),
        c['conversation_key'],
      );
    }
  });

  test('valid get_message_keys: all', () {
    final section = valid['get_message_keys'] as Map<String, dynamic>;
    final conversationKey = hex.decode(section['conversation_key'] as String);
    final cases = maps(section['keys']);
    expect(cases, isNotEmpty);
    for (final c in cases) {
      final keys = Nip44.messageKeys(
        conversationKey,
        hex.decode(c['nonce'] as String),
      );
      expect(hex.encode(keys.chachaKey), c['chacha_key']);
      expect(hex.encode(keys.chachaNonce), c['chacha_nonce']);
      expect(hex.encode(keys.hmacKey), c['hmac_key']);
    }
  });

  test('valid calc_padded_len: all', () {
    final cases = valid['calc_padded_len'] as List<dynamic>;
    expect(cases, hasLength(24));
    for (final c in cases.cast<List<dynamic>>()) {
      expect(Nip44.paddedLength(c[0] as int), c[1], reason: 'length ${c[0]}');
    }
  });

  test('valid encrypt_decrypt: all, both ways, from both secret keys', () {
    final cases = maps(valid['encrypt_decrypt']);
    expect(cases, hasLength(10));
    for (final c in cases) {
      final sec1 = hex.decode(c['sec1'] as String);
      final sec2 = hex.decode(c['sec2'] as String);
      final pub1 = hex.encode(xOnlyPublicKey(bigIntFromBytes(sec1)));
      final pub2 = hex.encode(xOnlyPublicKey(bigIntFromBytes(sec2)));
      final key = Nip44.conversationKey(sec1, pub2);
      expect(hex.encode(key), c['conversation_key']);
      expect(
        hex.encode(Nip44.conversationKey(sec2, pub1)),
        c['conversation_key'],
      );
      final payload = Nip44.encrypt(
        c['plaintext'] as String,
        key,
        hex.decode(c['nonce'] as String),
      );
      expect(payload, c['payload']);
      expect(Nip44.decrypt(payload, key), c['plaintext']);
    }
  });

  test('valid encrypt_decrypt_long_msg: all', () {
    final cases = maps(valid['encrypt_decrypt_long_msg']);
    expect(cases, hasLength(3));
    for (final c in cases) {
      final plaintext = (c['pattern'] as String) * (c['repeat'] as int);
      expect(
        sha256.convert(utf8.encode(plaintext)).toString(),
        c['plaintext_sha256'],
      );
      final key = hex.decode(c['conversation_key'] as String);
      final payload = Nip44.encrypt(
        plaintext,
        key,
        hex.decode(c['nonce'] as String),
      );
      expect(
        sha256.convert(utf8.encode(payload)).toString(),
        c['payload_sha256'],
      );
      expect(Nip44.decrypt(payload, key), plaintext);
    }
  });

  test('invalid encrypt_msg_lengths: all refused', () {
    final key = List<int>.filled(32, 1);
    final nonce = List<int>.filled(32, 2);
    final lengths = (invalid['encrypt_msg_lengths'] as List<dynamic>)
        .cast<int>();
    expect(lengths, hasLength(4));
    for (final length in lengths) {
      expect(
        () => Nip44.encrypt('a' * length, key, nonce),
        throwsArgumentError,
        reason: 'length $length',
      );
    }
  });

  test('invalid get_conversation_key: all 8 refused', () {
    final cases = maps(invalid['get_conversation_key']);
    expect(cases, hasLength(8));
    for (final c in cases) {
      expect(
        () => Nip44.conversationKey(
          hex.decode(c['sec1'] as String),
          c['pub2'] as String,
        ),
        throwsArgumentError,
        reason: c['note'] as String,
      );
    }
  });

  test('invalid decrypt: all 12 refused', () {
    final cases = maps(invalid['decrypt']);
    expect(cases, hasLength(12));
    for (final c in cases) {
      expect(
        () => Nip44.decrypt(
          c['payload'] as String,
          hex.decode(c['conversation_key'] as String),
        ),
        throwsFormatException,
        reason: c['note'] as String,
      );
    }
  });

  test('only the canonical base64 of @scure/base is decrypted', () {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    var urlSafe = 0;
    var unpadded = 0;
    var paddingBits = 0;
    for (final c in [
      ...maps(valid['encrypt_decrypt']),
      ...maps(valid['encrypt_decrypt_long_msg']),
    ]) {
      final payload = c['payload'] as String?;
      if (payload == null) continue;
      final key = hex.decode(c['conversation_key'] as String);
      expect(Nip44.decrypt(payload, key), isNotEmpty);
      final variants = <String>[' $payload', '$payload\n'];
      if (payload.contains(RegExp('[+/]'))) {
        urlSafe++;
        variants.add(payload.replaceAll('+', '-').replaceAll('/', '_'));
      }
      if (payload.endsWith('=')) {
        unpadded++;
        variants.add(payload.replaceAll('=', ''));
        // The last character before the padding with its lowest bit flipped: the same bytes for a lenient decoder, non-zero padding bits for @scure/base.
        final last = payload.indexOf('=') - 1;
        final flipped = alphabet[alphabet.indexOf(payload[last]) ^ 1];
        variants.add(payload.replaceRange(last, last + 1, flipped));
        paddingBits++;
      }
      for (final variant in variants) {
        expect(
          () => Nip44.decrypt(variant, key),
          throwsFormatException,
          reason: 'a payload @scure/base refuses',
        );
      }
    }
    expect(urlSafe, greaterThan(0));
    expect(unpadded, greaterThan(0));
    expect(paddingBits, greaterThan(0));
  });

  test('isPublicKey agrees with the invalid public keys of the vectors', () {
    for (final c in maps(invalid['get_conversation_key'])) {
      if ((c['note'] as String).startsWith('pub2')) {
        expect(
          Nip44.isPublicKey(c['pub2'] as String),
          isFalse,
          reason: c['note'] as String,
        );
      }
    }
    for (final c in maps(valid['get_conversation_key'])) {
      expect(Nip44.isPublicKey(c['pub2'] as String), isTrue);
    }
    expect(Nip44.isPublicKey('0' * 64), isFalse);
    expect(Nip44.isPublicKey('xyz'), isFalse);
  });
}
