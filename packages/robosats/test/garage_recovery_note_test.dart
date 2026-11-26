import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:robosats/src/nostr/gift_wrap.dart';
import 'package:robosats/src/nostr/nip44.dart';
import 'package:robosats/src/nostr/nostr_event.dart';
import 'package:test/test.dart';

import 'support/deterministic_random.dart';

/// The recovery note of a Garage Key (#81), checked against the reference (`frontend/src/utils/accountRecovery.ts`, `models/GarageKey.model.ts:89-119`, `services/RoboPool/index.ts:628-728`, `nip59.ts` of `nostr-tools`, commit babf62e) and against the vectors of the design study (`test/fixtures/nostr/garage-recovery-note.json`).
void main() {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/nostr/garage-recovery-note.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final key = switch (GarageKey.fromBytes(
    Uint8List.fromList(hex.decode(fixture['garage_key_hex'] as String)),
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
  final identity = key.recoveryNostrKeyPair;
  final legacy = key.legacyRecoveryNostrKeyPair;
  final stranger = NostrKeyPair.generate(DeterministicRandom('stranger'));
  final pythonNote = fixture['python_note'] as Map<String, dynamic>;
  final nostrToolsNote = fixture['nostr_tools_note'] as Map<String, dynamic>;
  // The rumor `created_at` of the Python vector: 2026-01-01 00:00:00 UTC.
  final vectorTime = DateTime.utc(2026);
  final now = DateTime.utc(2026, 11, 26, 12, 0, 0, 900);

  String jsonOf(Object? value) => jsonEncode(value);

  /// The JSON of the gift wrap of a note composed by [writer] (the recovery identity by default).
  String noteJson(
    int accountIndex, {
    DateTime? at,
    NostrKeyPair? writer,
    String label = 'note',
  }) => switch (GarageRecoveryNote.composeFor(
    writer ?? identity,
    accountIndex: accountIndex,
    now: at ?? now,
    random: DeterministicRandom('$label/$accountIndex/$at'),
  )) {
    Ok(:final value) => value.wrap.toJson(),
    Err(:final failure) => throw StateError('$failure'),
  };

  int? read(List<String> events) =>
      GarageRecoveryNote.latestAccount(key, events);

  final secureRandom = DeterministicRandom('crafted');
  List<int> bytes32() =>
      List<int>.generate(32, (_) => secureRandom.nextInt(256));

  /// A gift wrap of [rumorJson], sealed by [sealer] for [recipient], whose tags are [wrapTags] (`['p', recipient]` by default): what a relay or a third party can send.
  String craftedWrap(
    String rumorJson, {
    NostrKeyPair? sealer,
    String? recipient,
    int sealKind = NostrGiftWrap.sealKind,
    List<List<String>>? wrapTags,
  }) {
    final from = sealer ?? identity;
    final to = recipient ?? identity.publicKeyHex;
    final seal = from.sign(
      kind: sealKind,
      content: Nip44.encrypt(
        rumorJson,
        from.conversationKeyWith(to),
        bytes32(),
      ),
      createdAt: 1767200000,
      tags: const [],
      aux: bytes32(),
    );
    final throwaway = NostrKeyPair.generate(secureRandom);
    return throwaway
        .sign(
          kind: NostrGiftWrap.giftWrapKind,
          content: Nip44.encrypt(
            seal.toJson(),
            throwaway.conversationKeyWith(to),
            bytes32(),
          ),
          createdAt: 1767210000,
          tags:
              wrapTags ??
              [
                ['p', to],
              ],
          aux: bytes32(),
        )
        .toJson();
  }

  /// The JSON of a rumor of [pubkey] (the recovery identity by default) with these fields, written as `createRumor` writes it.
  String rumorJson({
    int kind = GarageRecoveryNote.kind,
    List<List<String>>? tags,
    String content = '',
    int createdAt = 1767225600,
    String? pubkey,
  }) => NostrEvent.rumor(
    kind: kind,
    content: content,
    createdAt: createdAt,
    tags:
        tags ??
        [
          ['d', GarageRecoveryNote.dTagValue],
          ['account', '7'],
        ],
    pubkey: pubkey ?? identity.publicKeyHex,
  ).toJson();

  /// A rumor whose fields are any JSON, for the types `NostrEvent` cannot hold.
  String rawRumorJson(Map<String, Object?> fields) => jsonOf({
    'created_at': 1767225600,
    'content': '',
    'tags': [
      ['d', GarageRecoveryNote.dTagValue],
      ['account', '7'],
    ],
    'kind': GarageRecoveryNote.kind,
    'pubkey': identity.publicKeyHex,
    'id': '0' * 64,
    ...fields,
  });

  /// The wrap of [wrapJson] with [change] applied to its decoded object: the wrap's own signature, which `unwrapEvent` does not check, is left as it was.
  String edited(String wrapJson, void Function(Map<String, dynamic>) change) {
    final wrap = jsonDecode(wrapJson) as Map<String, dynamic>;
    change(wrap);
    return jsonOf(wrap);
  }

  /// The rumor in [wrapJson], decrypted with [recipient]'s key, as the plaintext.
  String rumorTextOf(String wrapJson, NostrKeyPair recipient) {
    final wrap = jsonDecode(wrapJson) as Map<String, dynamic>;
    final sealText = Nip44.decrypt(
      wrap['content'] as String,
      recipient.conversationKeyWith(wrap['pubkey'] as String),
    );
    final seal = jsonDecode(sealText) as Map<String, dynamic>;
    return Nip44.decrypt(
      seal['content'] as String,
      recipient.conversationKeyWith(seal['pubkey'] as String),
    );
  }

  group('the identities of a Garage Key', () {
    test('are the ones both implementations of the study computed', () {
      expect(
        hex.encode(identity.revealSecretKey()),
        fixture['recovery_nostr_secret_key_hex'],
      );
      expect(identity.publicKeyHex, fixture['recovery_nostr_pubkey_hex']);
      expect(legacy.publicKeyHex, fixture['legacy_recovery_nostr_pubkey_hex']);
    });

    test('are asked for with the reference\'s filter, current then legacy', () {
      final filters = GarageRecoveryNote.filters(key);
      expect(filters.map((filter) => filter.toJson()), [
        '{"kinds":[1059],"#p":["${identity.publicKeyHex}"]}',
        '{"kinds":[1059],"#p":["${legacy.publicKeyHex}"]}',
      ]);
      expect(filters.map((filter) => filter.publicKeyHex), [
        fixture['recovery_nostr_pubkey_hex'],
        fixture['legacy_recovery_nostr_pubkey_hex'],
      ]);
    });
  });

  group('writing the note', () {
    test('gives the rumor of the vectors, byte for byte', () {
      final wrap = noteJson(3, at: vectorTime);
      expect(
        rumorTextOf(wrap, identity),
        jsonOf(pythonNote['rumor']),
        reason: 'fields, their order and the id of createRumor',
      );
    });

    test('is a gift wrap to the recovery identity itself', () {
      final wrap = jsonDecode(noteJson(3)) as Map<String, dynamic>;
      expect(wrap['kind'], 1059);
      expect(wrap['tags'], [
        ['p', identity.publicKeyHex],
      ]);
      expect(wrap['pubkey'], isNot(identity.publicKeyHex));
      final seal =
          jsonDecode(
                Nip44.decrypt(
                  wrap['content'] as String,
                  identity.conversationKeyWith(wrap['pubkey'] as String),
                ),
              )
              as Map<String, dynamic>;
      expect(seal['kind'], 13);
      expect(seal['pubkey'], identity.publicKeyHex);
      expect(seal['tags'], isEmpty);
      final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
      for (final date in [wrap['created_at'], seal['created_at']]) {
        expect(date, lessThanOrEqualTo(nowSeconds));
        expect(date, greaterThanOrEqualTo(nowSeconds - 2 * 24 * 60 * 60));
      }
      final rumor = jsonDecode(rumorTextOf(noteJson(3), identity)) as Map;
      expect(rumor['created_at'], nowSeconds, reason: 'rounded down');
    });

    test('has the size of the vectors, whatever the index', () {
      for (final index in [0, 3, 2147483647]) {
        expect(
          utf8.encode(noteJson(index)).length,
          fixture['wrap_bytes'],
          reason: 'index $index',
        );
      }
    });

    test('is one EVENT message', () {
      final note = switch (GarageRecoveryNote.compose(
        key,
        accountIndex: 3,
        now: now,
        random: DeterministicRandom('one message'),
      )) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };
      final wrap = note.wrap.toJson();
      expect(note.relayMessages, ['["EVENT",$wrap]']);
      expect(note.eventIds, [note.wrap.id]);
      expect(read([wrap]), 3);
    });

    test('refuses what is not a robot index, as the reference throws', () {
      for (final index in [-1, 2147483648, 1 << 40]) {
        expect(
          GarageRecoveryNote.compose(
            key,
            accountIndex: index,
            now: now,
            random: DeterministicRandom('refused'),
          ),
          isA<Err<OutgoingGarageRecoveryNote, AccountIndexOutOfRange>>(),
          reason: 'index $index',
        );
      }
    });
  });

  group('reading the notes', () {
    test('reads a note written here', () {
      expect(read([noteJson(0)]), 0);
      expect(read([noteJson(41)]), 41);
      expect(read([noteJson(2147483647)]), 2147483647);
    });

    test('reads the note built by the Python implementation', () {
      expect(read([jsonOf(pythonNote['wrap'])]), pythonNote['account']);
    });

    test('reads the note built by nostr-tools', () {
      expect(read([jsonOf(nostrToolsNote['wrap'])]), nostrToolsNote['account']);
    });

    test('reads the legacy identity\'s notes too', () {
      expect(read([noteJson(12, writer: legacy)]), 12);
      final earlier = DateTime.utc(2026, 11);
      expect(read([noteJson(12, writer: legacy, at: earlier), noteJson(5)]), 5);
      expect(
        read([noteJson(5, at: earlier), noteJson(12, writer: legacy)]),
        12,
      );
    });

    test('gives nothing without a note', () {
      expect(read(const []), isNull);
    });

    test('reads a note whatever its content, as the reference', () {
      expect(read([craftedWrap(rumorJson(content: 'anything'))]), 7);
    });

    test('takes the first of two account tags, as find does', () {
      expect(
        read([
          craftedWrap(
            rumorJson(
              tags: [
                ['d', GarageRecoveryNote.dTagValue],
                ['account', '5'],
                ['account', '9'],
              ],
            ),
          ),
        ]),
        5,
      );
    });

    test('takes the first d tag, as find does', () {
      expect(
        read([
          craftedWrap(
            rumorJson(
              tags: [
                ['d', GarageRecoveryNote.dTagValue],
                ['d', 'something else'],
                ['account', '5'],
              ],
            ),
          ),
        ]),
        5,
      );
      expect(
        read([
          craftedWrap(
            rumorJson(
              tags: [
                ['d', 'something else'],
                ['d', GarageRecoveryNote.dTagValue],
                ['account', '5'],
              ],
            ),
          ),
        ]),
        isNull,
      );
    });

    test('accepts extra values in a tag and extra tags, as the reference', () {
      expect(
        read([
          craftedWrap(
            rumorJson(
              tags: [
                ['t', 'x'],
                ['d', GarageRecoveryNote.dTagValue, 'extra'],
                ['account', '8', 'extra'],
              ],
            ),
          ),
        ]),
        8,
      );
    });

    test('accepts the wrap a relay re-sent with another p tag besides', () {
      expect(
        read([
          craftedWrap(
            rumorJson(),
            wrapTags: [
              ['p', stranger.publicKeyHex],
              ['p', identity.publicKeyHex],
            ],
          ),
        ]),
        7,
      );
    });
  });

  group('the choice among notes', () {
    final older = DateTime.utc(2026, 11, 20);
    final newer = DateTime.utc(2026, 11, 21);

    test('is the latest rumor, whatever the order', () {
      final a = noteJson(9, at: older);
      final b = noteJson(4, at: newer);
      expect(read([a, b]), 4);
      expect(read([b, a]), 4);
    });

    test('is the larger index on a tie, whatever the order', () {
      final a = noteJson(4, at: newer);
      final b = noteJson(9, at: newer);
      expect(read([a, b]), 9);
      expect(read([b, a]), 9);
    });

    test('is made across the two identities', () {
      final current = noteJson(4, at: older);
      final old = noteJson(6, writer: legacy, at: newer);
      expect(read([current, old]), 6);
      final tie = noteJson(3, writer: legacy, at: older);
      expect(read([tie, current]), 4);
    });

    test('takes a note dated in the future, as the reference does', () {
      final future = noteJson(2, at: DateTime.utc(2100));
      expect(read([noteJson(7), future]), 2);
    });

    test('counts a note sent by several relays once', () {
      final a = noteJson(4, at: older);
      expect(read([a, a, a]), 4);
    });

    test('ignores a relay\'s dates: only the rumor\'s count', () {
      final a = noteJson(9, at: older);
      final b = noteJson(4, at: newer);
      final lateWrap = edited(a, (wrap) => wrap['created_at'] = 4102444800);
      expect(read([lateWrap, b]), 4);
    });
  });

  group('ignores, without throwing', () {
    // Older than every hostile rumor (2026-01-01), so that a hostile one, were it accepted, would be chosen.
    final good = noteJson(1, at: DateTime.utc(2025, 6));

    void ignored(String reason, String event) {
      test(reason, () {
        expect(read([event]), isNull, reason: 'alone');
        expect(read([good, event]), 1, reason: 'beside an older note');
        expect(read([event, good]), 1, reason: 'before an older note');
      });
    }

    ignored(
      'a note of another author, wrapped to the identity',
      NostrGiftWrap.wrap(
        NostrEvent.rumor(
          kind: GarageRecoveryNote.kind,
          content: '',
          createdAt: 1767225600,
          tags: [
            ['d', GarageRecoveryNote.dTagValue],
            ['account', '9'],
          ],
          pubkey: stranger.publicKeyHex,
        ),
        stranger,
        identity.publicKeyHex,
        nowSeconds: 1767225600,
        random: DeterministicRandom('other author'),
      ).toJson(),
    );
    ignored(
      'a rumor of the identity in a seal of another key',
      craftedWrap(rumorJson(), sealer: stranger),
    );
    ignored(
      'a seal that is not of kind 13',
      craftedWrap(rumorJson(), sealKind: 14),
    );
    ignored(
      'a note wrapped to another key',
      craftedWrap(rumorJson(), recipient: stranger.publicKeyHex),
    );
    ignored(
      'a note to the identity whose p tag names another key',
      craftedWrap(
        rumorJson(),
        wrapTags: [
          ['p', stranger.publicKeyHex],
        ],
      ),
    );
    ignored(
      'a note to the identity without a p tag',
      craftedWrap(rumorJson(), wrapTags: const []),
    );
    ignored(
      'a wrap that is not of kind 1059',
      edited(craftedWrap(rumorJson()), (wrap) => wrap['kind'] = 1060),
    );
    ignored(
      'a wrap whose pubkey is no curve point',
      edited(craftedWrap(rumorJson()), (wrap) => wrap['pubkey'] = 'f' * 64),
    );
    ignored(
      'a wrap whose content is not a string',
      edited(craftedWrap(rumorJson()), (wrap) => wrap['content'] = 7),
    );
    ignored(
      'a wrap whose content is not NIP-44',
      edited(craftedWrap(rumorJson()), (wrap) => wrap['content'] = 'AAAA'),
    );
    ignored('a rumor of another kind', craftedWrap(rumorJson(kind: 30079)));
    ignored('a rumor of kind 1059', craftedWrap(rumorJson(kind: 1059)));
    ignored(
      'a rumor with another d tag',
      craftedWrap(
        rumorJson(
          tags: [
            ['d', 'robosats-garage-accounts'],
            ['account', '7'],
          ],
        ),
      ),
    );
    ignored(
      'a rumor without a d tag',
      craftedWrap(
        rumorJson(
          tags: [
            ['account', '7'],
          ],
        ),
      ),
    );
    for (final (reason, tags) in [
      ('without an account tag', <List<String>>[]),
      (
        'with an account tag without a value',
        [
          ['account'],
        ],
      ),
      (
        'with an empty account',
        [
          ['account', ''],
        ],
      ),
      (
        'with a negative account',
        [
          ['account', '-1'],
        ],
      ),
      (
        'with a signed account',
        [
          ['account', '+1'],
        ],
      ),
      (
        'with a leading zero',
        [
          ['account', '01'],
        ],
      ),
      (
        'with two zeros',
        [
          ['account', '00'],
        ],
      ),
      (
        'with a decimal point',
        [
          ['account', '1.0'],
        ],
      ),
      (
        'with an exponent',
        [
          ['account', '1e3'],
        ],
      ),
      (
        'with a hexadecimal account',
        [
          ['account', '0x10'],
        ],
      ),
      (
        'with letters',
        [
          ['account', 'abc'],
        ],
      ),
      (
        'with a space before',
        [
          ['account', ' 1'],
        ],
      ),
      (
        'with a space after',
        [
          ['account', '1 '],
        ],
      ),
      (
        'with a line feed after',
        [
          ['account', '1\n'],
        ],
      ),
      (
        'with Arabic-Indic digits',
        [
          ['account', '٣'],
        ],
      ),
      (
        'with fullwidth digits',
        [
          ['account', '３'],
        ],
      ),
      (
        'just past the last index',
        [
          ['account', '2147483648'],
        ],
      ),
      (
        'with an account of 2^32',
        [
          ['account', '4294967296'],
        ],
      ),
      (
        'with an enormous account',
        [
          ['account', '9' * 400],
        ],
      ),
      (
        'with a leading zero first, then a valid account',
        [
          ['account', '07'],
          ['account', '7'],
        ],
      ),
    ]) {
      ignored(
        'a rumor $reason',
        craftedWrap(
          rumorJson(
            tags: [
              ['d', GarageRecoveryNote.dTagValue],
              ...tags,
            ],
          ),
        ),
      );
    }
    ignored(
      'a rumor whose account is a number (stricter than the reference)',
      craftedWrap(
        rawRumorJson({
          'tags': [
            ['d', GarageRecoveryNote.dTagValue],
            ['account', 7],
          ],
        }),
      ),
    );
    ignored(
      'a rumor with a tag that is no list (stricter than the reference)',
      craftedWrap(
        rawRumorJson({
          'tags': [
            ['d', GarageRecoveryNote.dTagValue],
            ['account', '7'],
            'p',
          ],
        }),
      ),
    );
    ignored(
      'a rumor whose tags are no list',
      craftedWrap(rawRumorJson({'tags': 'd'})),
    );
    ignored(
      'a rumor dated before 1970 (stricter than the reference)',
      craftedWrap(rumorJson(createdAt: -5)),
    );
    ignored(
      'a rumor whose date is a decimal (stricter than the reference)',
      craftedWrap(rawRumorJson({'created_at': 1767225600.5})),
    );
    ignored(
      'a rumor whose date is a string (stricter than the reference)',
      craftedWrap(rawRumorJson({'created_at': '1767225600'})),
    );
    ignored(
      'a rumor without a date',
      craftedWrap(rawRumorJson({'created_at': null})),
    );
    ignored('a rumor that is not an object', craftedWrap('[1,2,3]'));
    ignored('a rumor that is not JSON', craftedWrap('{"kind":30078,'));
    for (final (reason, text) in [
      ('broken JSON', '{"kind":1059,'),
      ('not JSON at all', 'EVENT'),
      ('a JSON list', '[]'),
      ('null', 'null'),
      ('an empty text', ''),
      ('an object without fields', '{}'),
      ('a wrap without content', '{"kind":1059,"tags":[["p","${'a' * 64}"]]}'),
    ]) {
      ignored(reason, text);
    }
  });

  group('ignores a seal that does not verify', () {
    final wrapJson = craftedWrap(rumorJson());

    /// [wrapJson] whose seal is changed by [change] and wrapped again for the identity.
    String withSeal(void Function(Map<String, dynamic>) change) {
      final wrap = jsonDecode(wrapJson) as Map<String, dynamic>;
      final throwaway = NostrKeyPair.generate(DeterministicRandom('rewrap'));
      final seal =
          jsonDecode(
                Nip44.decrypt(
                  wrap['content'] as String,
                  identity.conversationKeyWith(wrap['pubkey'] as String),
                ),
              )
              as Map<String, dynamic>;
      change(seal);
      return throwaway
          .sign(
            kind: NostrGiftWrap.giftWrapKind,
            content: Nip44.encrypt(
              jsonOf(seal),
              throwaway.conversationKeyWith(identity.publicKeyHex),
              bytes32(),
            ),
            createdAt: 1767210000,
            tags: [
              ['p', identity.publicKeyHex],
            ],
            aux: bytes32(),
          )
          .toJson();
    }

    test('read again unchanged, it counts', () {
      expect(read([withSeal((_) {})]), 7);
    });

    for (final (reason, change)
        in <(String, void Function(Map<String, dynamic>))>[
          (
            'another signature',
            (seal) => seal['sig'] = (seal['sig'] as String).replaceRange(
              0,
              2,
              (seal['sig'] as String).startsWith('00') ? '01' : '00',
            ),
          ),
          (
            'an uppercase signature',
            (seal) => seal['sig'] = (seal['sig'] as String).toUpperCase(),
          ),
          ('no signature', (seal) => seal.remove('sig')),
          ('a signature of zeros', (seal) => seal['sig'] = '0' * 128),
          ('a signature of ones', (seal) => seal['sig'] = 'f' * 128),
          (
            'a signature whose s is zero',
            (seal) => seal['sig'] =
                '${(seal['sig'] as String).substring(0, 64)}${'0' * 64}',
          ),
          ('a short signature', (seal) => seal['sig'] = 'ab' * 32),
          ('another id', (seal) => seal['id'] = '0' * 64),
          ('another date', (seal) => seal['created_at'] = 1767200001),
          ('a decimal date', (seal) => seal['created_at'] = 1767200000.5),
          (
            'a tag added',
            (seal) => seal['tags'] = [
              ['p', identity.publicKeyHex],
            ],
          ),
          (
            'an uppercase pubkey',
            (seal) => seal['pubkey'] = (seal['pubkey'] as String).toUpperCase(),
          ),
        ]) {
      test(reason, () {
        expect(read([withSeal(change)]), isNull);
      });
    }
  });

  group('bounds what it reads', () {
    test('reads an event of the largest length, not a longer one', () {
      final note = noteJson(5);
      String padded(int length) =>
          '${note.substring(0, note.length - 1)}${' ' * (length - note.length)}}';
      expect(read([padded(GarageRecoveryNote.maxEventLength)]), 5);
      expect(read([padded(GarageRecoveryNote.maxEventLength + 1)]), isNull);
      expect(read([padded(1 << 20)]), isNull, reason: 'an event of 1 MiB');
    });

    test('looks at the first thousand events only', () {
      final good = noteJson(5);
      final junk = [
        for (var i = 0; i < GarageRecoveryNote.maxEvents - 1; i++)
          '{"kind":1059,"n":$i}',
      ];
      expect(read([...junk, good]), 5, reason: 'the thousandth');
      expect(read([...junk, '{}', good]), isNull, reason: 'the 1001st');
      expect(
        read([...junk.take(10), good, ...junk]),
        5,
        reason: 'one good among a thousand',
      );
    });

    test('counts duplicates in the thousand', () {
      final good = noteJson(5);
      expect(
        read([
          for (var i = 0; i < GarageRecoveryNote.maxEvents; i++) '{}',
          good,
        ]),
        isNull,
      );
    });

    test(
      'reads a thousand hostile events addressed to both identities',
      () {
        // The costliest events a third party can make: each decrypts with the identity's key, holds a seal of the third party that verifies, and names the legacy identity too, so that it is tried with both keys.
        final attackerConversation = stranger.conversationKeyWith(
          identity.publicKeyHex,
        );
        final throwaway = NostrKeyPair.generate(DeterministicRandom('flood'));
        final wrapConversation = throwaway.conversationKeyWith(
          identity.publicKeyHex,
        );
        final seal = stranger.sign(
          kind: NostrGiftWrap.sealKind,
          content: Nip44.encrypt(
            rumorJson(pubkey: stranger.publicKeyHex),
            attackerConversation,
            bytes32(),
          ),
          createdAt: 1767200000,
          tags: const [],
          aux: bytes32(),
        );
        final flood = [
          for (var i = 0; i < GarageRecoveryNote.maxEvents - 1; i++)
            jsonOf({
              'kind': 1059,
              'content': Nip44.encrypt(
                seal.toJson(),
                wrapConversation,
                bytes32(),
              ),
              'created_at': 1767210000,
              'tags': [
                ['p', identity.publicKeyHex],
                ['p', legacy.publicKeyHex],
              ],
              'pubkey': throwaway.publicKeyHex,
              'id': '0' * 64,
              'sig': '0' * 128,
            }),
        ];
        expect(read([...flood, noteJson(5)]), 5);
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });

  group('secrecy', () {
    test('prints nothing of the note, the filter or the identity', () {
      final note = switch (GarageRecoveryNote.compose(
        key,
        accountIndex: 3,
        now: now,
        random: DeterministicRandom('print'),
      )) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };
      final texts = [
        '$note',
        for (final filter in GarageRecoveryNote.filters(key)) '$filter',
      ];
      for (final text in texts) {
        expect(text, isNot(contains(identity.publicKeyHex)));
        expect(text, isNot(contains(legacy.publicKeyHex)));
        expect(text, isNot(contains(fixture['recovery_nostr_secret_key_hex'])));
        expect(text, isNot(contains(fixture['garage_key_hex'])));
      }
      for (final message in note.relayMessages) {
        expect(
          message,
          isNot(contains(fixture['recovery_nostr_secret_key_hex'])),
        );
        expect(message, isNot(contains(fixture['garage_key_hex'])));
      }
    });
  });
}
