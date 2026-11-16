import 'dart:convert';
import 'dart:math';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import '../support/coordinator.dart';
import '../support/nip59.dart';
import '../support/order_answers.dart';
import '../support/pgp.dart';

/// The chat message over Nostr, checked against `sendToNostr` and `wrapEvent` of the reference (`EncryptedChat/index.tsx:211-239`, `nip59.ts` of `nostr-tools` 2.25.2) and against what the official client requires to show it (`EncryptedNostrChat/index.tsx:113-122`).
void main() {
  final us = interopIdentity;
  final peer = interopPeerIdentity;
  final ourKey = us.nostrKeyPair();
  final peerKey = peer.nostrKeyPair();
  final temple = coordinatorNamed('temple');
  const network = RobosatsNetwork.testnet;
  // A quarter of a second past a second: the rumor is dated at the next second, the wraps never after this one.
  final now = DateTime.utc(2026, 11, 15, 18, 0, 0, 250);
  final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
  final relay = 'ws://${Uri.parse(temple.testnet.onion ?? '').host}/relay/';

  OutgoingNostrChatMessage composeOk({
    String text = 'Hello, the fiat is sent',
    Random? random,
    CoordinatorOrder? order,
  }) => switch (OutgoingNostrChatMessage.compose(
    identity: us,
    order: order ?? readOrderAt(9),
    coordinator: temple,
    network: network,
    text: text,
    now: now,
    random: random ?? DeterministicRandom('nostr chat'),
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  // The wrap exactly as sent: `["EVENT",<wrap>]`, what `JSON.stringify(['EVENT', event])` writes in `RoboPool.sendEvent`.
  String wrapOf(String relayMessage) {
    final message = jsonDecode(relayMessage) as List<dynamic>;
    expect(message, hasLength(2));
    expect(relayMessage, startsWith('["EVENT",{"kind":1059,'));
    return relayMessage.substring('["EVENT",'.length, relayMessage.length - 1);
  }

  test('the relay is the coordinator\'s, as getRelayUrl writes it', () {
    expect(
      OutgoingNostrChatMessage.relayUrl(temple, network).toString(),
      relay,
    );
    expect(relay, startsWith('ws://'));
    expect(relay, endsWith('.onion/relay/'));
  });

  test(
    'two wraps of one rumor: the peer\'s first, then our own; each opens only with its recipient\'s key',
    () {
      final message = composeOk();
      expect(message.relayMessages, hasLength(2));
      final forPeer = unwrap(wrapOf(message.relayMessages[0]), peerKey);
      final forUs = unwrap(wrapOf(message.relayMessages[1]), ourKey);
      expect(forPeer.rumor, forUs.rumor);
      expect(forPeer.wrap['tags'], [
        ['p', peerKey.publicKeyHex],
      ]);
      expect(forUs.wrap['tags'], [
        ['p', ourKey.publicKeyHex],
      ]);
      expect(
        () => unwrap(wrapOf(message.relayMessages[0]), ourKey),
        throwsA(anything),
      );
      expect(message.eventIds, [forPeer.wrap['id'], forUs.wrap['id']]);
    },
  );

  test(
    'the rumor is the reference\'s: kind 14, the text, the three tags in order, the second rounded up',
    () {
      final rumor = unwrap(wrapOf(composeOk().relayMessages[0]), peerKey).rumor;
      expect(rumor['kind'], 14);
      expect(rumor['content'], 'Hello, the fiat is sent');
      expect(rumor['created_at'], nowSeconds + 1);
      expect(rumor['pubkey'], ourKey.publicKeyHex);
      expect(rumor['tags'], [
        ['order_id', 'temple/$testOrderId'],
        ['p', peerKey.publicKeyHex, relay],
        ['p', ourKey.publicKeyHex, relay],
      ]);
      expect(rumor.containsKey('sig'), isFalse);
      expect(rumor.keys, [
        'created_at',
        'content',
        'tags',
        'kind',
        'pubkey',
        'id',
      ]);
    },
  );

  test('a rumor on a whole second is dated at that second', () {
    final exact = DateTime.utc(2026, 11, 15, 18);
    final message = OutgoingNostrChatMessage.compose(
      identity: us,
      order: readOrderAt(9),
      coordinator: temple,
      network: network,
      text: 'x',
      now: exact,
      random: DeterministicRandom('whole second'),
    );
    final value =
        (message as Ok<OutgoingNostrChatMessage, NostrChatFailure>).value;
    final rumor = unwrap(wrapOf(value.relayMessages[1]), ourKey).rumor;
    expect(rumor['created_at'], exact.millisecondsSinceEpoch ~/ 1000);
  });

  test(
    'the seal is signed by the robot\'s key, each wrap by a throwaway key of its own',
    () {
      final message = composeOk();
      final forPeer = unwrap(wrapOf(message.relayMessages[0]), peerKey);
      final forUs = unwrap(wrapOf(message.relayMessages[1]), ourKey);
      expect(forPeer.seal['pubkey'], ourKey.publicKeyHex);
      expect(forUs.seal['pubkey'], ourKey.publicKeyHex);
      expect(forPeer.seal['tags'], isEmpty);
      final throwaways = {forPeer.wrap['pubkey'], forUs.wrap['pubkey']};
      expect(throwaways, hasLength(2));
      expect(throwaways, isNot(contains(ourKey.publicKeyHex)));
      expect(throwaways, isNot(contains(peerKey.publicKeyHex)));
      expect(forPeer.wrap.keys, [
        'kind',
        'content',
        'created_at',
        'tags',
        'pubkey',
        'id',
        'sig',
      ]);
      expect(forPeer.seal.keys, [
        'kind',
        'content',
        'created_at',
        'tags',
        'pubkey',
        'id',
        'sig',
      ]);
    },
  );

  test(
    'seals and wraps are dated in the last two days, never in the future, and spread over them',
    () {
      final dates = <int>[];
      for (var i = 0; i < 10; i++) {
        final message = composeOk(random: Random.secure());
        for (final (index, relayMessage) in message.relayMessages.indexed) {
          final opened = unwrap(
            wrapOf(relayMessage),
            index == 0 ? peerKey : ourKey,
          );
          dates
            ..add(opened.wrap['created_at'] as int)
            ..add(opened.seal['created_at'] as int);
        }
      }
      for (final date in dates) {
        expect(date, lessThanOrEqualTo(nowSeconds));
        expect(date, greaterThanOrEqualTo(nowSeconds - 2 * 24 * 60 * 60));
      }
      // 40 dates drawn over two days: all of them within one hour of each other has a probability below 10^-50.
      expect(dates.reduce(max) - dates.reduce(min), greaterThan(3600));
    },
  );

  test(
    'every random byte comes from the source passed: the same source gives the same events, another source others',
    () {
      expect(composeOk().relayMessages, composeOk().relayMessages);
      expect(
        composeOk(random: DeterministicRandom('other')).eventIds,
        isNot(composeOk().eventIds),
      );
    },
  );

  test('nothing of the text, the keys or the order is printed', () {
    final message = composeOk(text: 'my secret text');
    expect(message.toString(), isNot(contains('secret')));
    expect(message.toString(), isNot(contains('$testOrderId')));
    expect(message.toString(), isNot(contains(ourKey.publicKeyHex)));
  });

  group('nothing is built', () {
    Result<OutgoingNostrChatMessage, NostrChatFailure> compose(
      CoordinatorOrder order, {
      RobotIdentity? identity,
      Coordinator? coordinator,
    }) => OutgoingNostrChatMessage.compose(
      identity: identity ?? us,
      order: order,
      coordinator: coordinator ?? temple,
      network: network,
      text: 'Hello',
      now: now,
      random: DeterministicRandom('refused'),
    );

    test('when the order lacks the peer\'s key, or ours', () {
      for (final field in ['maker_nostr_pubkey', 'taker_nostr_pubkey']) {
        final order = readOrder(orderAnswer(9, changes: {field: 'None'}));
        expect(
          compose(order),
          isA<Err<OutgoingNostrChatMessage, NostrChatFailure>>().having(
            (e) => e.failure,
            'failure',
            isA<NostrChatKeyMissing>(),
          ),
        );
      }
    });

    test(
      'when a key of the order is the all-zero placeholder, which is no curve point',
      () {
        for (final field in ['maker_nostr_pubkey', 'taker_nostr_pubkey']) {
          final order = readOrder(orderAnswer(9, changes: {field: '0' * 64}));
          expect(
            compose(order),
            isA<Err<OutgoingNostrChatMessage, NostrChatFailure>>().having(
              (e) => e.failure,
              'failure',
              isA<NostrChatKeyMissing>(),
            ),
          );
        }
      },
    );

    test(
      'when the key the coordinator holds for this robot is not the robot\'s',
      () {
        final order = readOrder(
          orderAnswer(9, changes: {'taker_nostr_pubkey': peerKey.publicKeyHex}),
        );
        expect(
          compose(order),
          isA<Err<OutgoingNostrChatMessage, NostrChatFailure>>().having(
            (e) => e.failure,
            'failure',
            isA<NostrChatKeyNotOurs>(),
          ),
        );
      },
    );

    test(
      'when the coordinator has no address, hence no relay, on the network',
      () {
        final noTestnet = Federation.robosats.coordinators.firstWhere(
          (coordinator) => coordinator.testnet.onion == null,
        );
        expect(
          compose(readOrderAt(9), coordinator: noTestnet),
          isA<Err<OutgoingNostrChatMessage, NostrChatFailure>>().having(
            (e) => e.failure,
            'failure',
            isA<NostrChatNoRelay>(),
          ),
        );
      },
    );
  });

  test('a message as long as the chat allows fits a relay\'s event size', () {
    final message = composeOk(
      text: '\u0001' * OutgoingChatMessage.maxTextBytes,
    );
    for (final relayMessage in message.relayMessages) {
      expect(
        utf8.encode(wrapOf(relayMessage)).length,
        lessThanOrEqualTo(OutgoingNostrChatMessage.maxEventBytes),
      );
    }
  });

  group('nostrRelaysFor builds the pool of RoboPool.updateRelays', () {
    List<Uri> relaysOn(RobosatsNetwork network) => [
      for (final coordinator in Federation.robosats.coordinators)
        ?OutgoingNostrChatMessage.relayUrl(coordinator, network),
    ];

    test(
      'min(3, n) relays, the order\'s coordinator\'s first, distinct, all of the federation; the others drawn at random',
      () {
        final mainnet = relaysOn(RobosatsNetwork.mainnet);
        expect(mainnet.length, greaterThanOrEqualTo(4));
        final first = OutgoingNostrChatMessage.relayUrl(
          temple,
          RobosatsNetwork.mainnet,
        );
        final drawn = <Uri>{};
        for (var seed = 0; seed < 200; seed++) {
          final relays = nostrRelaysFor(
            temple,
            Federation.robosats,
            RobosatsNetwork.mainnet,
            Random(seed),
          );
          expect(relays, hasLength(3));
          expect(relays.first, first);
          expect(relays.toSet(), hasLength(3));
          expect(mainnet, containsAll(relays));
          drawn.addAll(relays.skip(1));
        }
        expect(drawn, mainnet.where((relay) => relay != first).toSet());
      },
    );

    test('every relay when the network has fewer than three', () {
      final testnet = relaysOn(RobosatsNetwork.testnet);
      expect(testnet.length, lessThan(3));
      final relays = nostrRelaysFor(
        temple,
        Federation.robosats,
        RobosatsNetwork.testnet,
        Random(1),
      );
      expect(relays.toSet(), testnet.toSet());
      expect(relays.first.toString(), relay);
    });

    test('none when the order\'s coordinator has no relay on the network', () {
      final noTestnet = Federation.robosats.coordinators.firstWhere(
        (coordinator) => coordinator.testnet.onion == null,
      );
      expect(
        nostrRelaysFor(
          noTestnet,
          Federation.robosats,
          RobosatsNetwork.testnet,
          Random(1),
        ),
        isEmpty,
      );
    });
  });
}
