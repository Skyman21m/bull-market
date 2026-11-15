import 'package:robosats/src/nostr/nostr_event.dart';
import 'package:test/test.dart';

/// The expected strings were written by `JSON.stringify` of Node.js 24 (the function `serializeEvent` of `nostr-tools` calls), on 2026-11-15.
void main() {
  group('stringify writes what JSON.stringify writes', () {
    const cases = {
      'a"b\\c': r'"a\"b\\c"',
      '\b\f\n\r\t': r'"\b\f\n\r\t"',
      '\u0000\u0001\u001f\u007f': '"\\u0000\\u0001\\u001f\u007f"',
      'é😀': '"é😀"',
      '\ud800x': r'"\ud800x"',
      'x\udc00': r'"x\udc00"',
      '  ': '"  "',
      '</script>': '"</script>"',
    };
    cases.forEach((input, expected) {
      test(expected, () => expect(NostrEvent.stringify(input), expected));
    });
  });

  test(
    'the id of an event is the SHA-256 of its NIP-01 serialization, as nostr-tools computes it',
    () {
      const pubkey =
          '79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798';
      final tags = [
        ['order_id', 'temple/42'],
        ['p', 'aa', 'ws://x.onion/relay/'],
      ];
      const content = 'é😀\n"x\ud800\u0001\u007f';
      expect(
        NostrEvent.stringify([0, pubkey, 1763200000, 14, tags, content]),
        '[0,"$pubkey",1763200000,14,[["order_id","temple/42"],["p","aa","ws://x.onion/relay/"]],"é😀\\n\\"x\\ud800\\u0001\u007f"]',
      );
      expect(
        NostrEvent.idOf(pubkey, 1763200000, 14, tags, content),
        '19ecac6342b1adb526bdefd41673a6512c275089d7d9dbd0d28348c919bff419',
      );
    },
  );

  test(
    'a rumor keeps the field order of createRumor, and prints neither its content nor its tags',
    () {
      final rumor = NostrEvent.rumor(
        kind: 14,
        content: 'secret text',
        createdAt: 1763200000,
        tags: [
          ['order_id', 'temple/42'],
        ],
        pubkey: 'ab' * 32,
      );
      expect(
        rumor.toJson(),
        '{"created_at":1763200000,"content":"secret text","tags":[["order_id","temple/42"]],"kind":14,"pubkey":"${'ab' * 32}","id":"${rumor.id}"}',
      );
      expect(rumor.toString(), isNot(contains('secret')));
      expect(rumor.toString(), isNot(contains('temple')));
      expect(rumor.sig, isNull);
    },
  );
}
