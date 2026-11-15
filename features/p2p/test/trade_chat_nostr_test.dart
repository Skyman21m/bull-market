import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/trade/trade_chat.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/testing.dart' show ScriptedFault, ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/trade_harness.dart';

/// The chat's messages also published over Nostr (#94), as the official client publishes them (`onSendMessage`, `EncryptedChat/index.tsx:201-239`): over the coordinator the tests play and relays the tests record, never a real relay, coordinator, key or message.
void main() {
  final maker = switch (NetworkGarageKey(
    RobosatsNetwork.testnet,
    otherTradeKey,
  ).firstUsableRobot(0)) {
    Ok(:final value) => value.identity,
    Err(:final failure) => throw StateError('$failure'),
  };
  late UnlockedRobotPgpKey makerKey;
  final realNow = DateTime.now().toUtc();

  setUpAll(() {
    final key = switch (RobotPgpKey.generateWith(
      maker,
      now: realNow,
      random: Random(93),
    )) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
    makerKey = switch (key.unlock(maker)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
  });

  /// A trade at the chat step, its chat read once with the peer's key pinned.
  ///
  /// [configure] sets what the coordinator says of the order's Nostr keys before the order is read.
  Future<(TradeHarness, TradeRecord, TradeSeen)> chatting({
    void Function(TradeHarness app)? configure,
  }) async {
    final app = await TradeHarness.start(maker: maker);
    configure?.call(app);
    final taken = await app.takeShown();
    expect(taken, isA<Ok<TakeOutcome, TakeRefusal>>());
    final record = TradeHarness.recordOf(taken);
    final run = app.watchOf(record);
    await app.settle();
    app.coordinator.lockBond(app.robot(0));
    if (realNow.isAfter(app.now)) await app.elapse(realNow.difference(app.now));
    app.coordinator.moveTo(9);
    app.coordinator.peerPublicKey = makerKey.key.publicKey.armored;
    await app.elapse(const Duration(seconds: 11));
    final status = run.lastStatus;
    await run.subscription.cancel();
    expect(status.seen.status.position, TradePosition.chatting);
    final read = await app.chatRead.read(status.record, status.seen);
    expect(read, isA<Ok<ChatView, ChatReadFailure>>());
    return (app, status.record, status.seen);
  }

  final testnetRelays = [
    for (final coordinator in Federation.robosats.coordinators)
      ?OutgoingNostrChatMessage.relayUrl(coordinator, RobosatsNetwork.testnet),
  ];

  Map<String, dynamic> wrapOf(String relayMessage) =>
      (jsonDecode(relayMessage) as List<dynamic>)[1] as Map<String, dynamic>;

  test(
    'a message is posted to the coordinator and published once to min(3, n) relays, the order\'s coordinator\'s first, through the robot\'s sessions',
    () async {
      final (app, record, seen) = await chatting();
      final sent = await app.chatSend.send(record, seen, 'Hello');
      expect(
        sent,
        isA<Ok<ChatSent, ChatSendRefusal>>().having(
          (ok) => ok.value,
          'sent',
          isA<ChatSentStored>(),
        ),
      );
      await pumpEventQueue();
      final published = app.relays.published;
      expect(app.relays.messages, hasLength(1));
      expect(published, hasLength(min(3, testnetRelays.length)));
      expect(
        published.first.relay,
        OutgoingNostrChatMessage.relayUrl(
          Federation.robosats.byAlias('temple') ?? (throw StateError('temple')),
          RobosatsNetwork.testnet,
        ),
      );
      expect({for (final p in published) p.relay}, hasLength(published.length));
      for (final p in published) {
        expect(testnetRelays, contains(p.relay));
        expect(p.robot, app.robot(0).sessionKey);
      }
      // The peer's wrap first, then our own: each names its recipient alone.
      final message = app.relays.messages.single;
      expect(message.relayMessages, hasLength(2));
      expect(wrapOf(message.relayMessages[0])['tags'], [
        ['p', app.coordinator.makerNostrPublicKey],
      ]);
      expect(wrapOf(message.relayMessages[1])['tags'], [
        ['p', app.robot(0).nostrKeyPair().publicKeyHex],
      ]);
      expect(wrapOf(message.relayMessages[0])['kind'], 1059);
    },
  );

  test(
    'a relay that never answers neither delays nor blocks the post, nor changes the message\'s state',
    () async {
      final (app, record, seen) = await chatting();
      app.relays.hold = Completer<void>().future;
      final sent = await app.chatSend
          .send(record, seen, 'Hello')
          .timeout(const Duration(seconds: 5));
      expect(
        sent,
        isA<Ok<ChatSent, ChatSendRefusal>>().having(
          (ok) => ok.value,
          'sent',
          isA<ChatSentStored>(),
        ),
      );
      expect(app.coordinator.chat, hasLength(1));
      await pumpEventQueue();
      expect(app.relays.published, isNotEmpty);
    },
  );

  test('every relay failing changes nothing of what the chat shows', () async {
    final (app, record, seen) = await chatting();
    app.relays.answer = const NostrRelayUnreachable();
    final sent = await app.chatSend.send(record, seen, 'Hello');
    expect(sent, isA<Ok<ChatSent, ChatSendRefusal>>());
    await pumpEventQueue();
    final view = app.chatRead.current(record);
    expect(view.entries.single.text, 'Hello');
    expect(view.pending, isEmpty);
  });

  test(
    'nothing is published when the coordinator holds for this robot a Nostr key that is not the robot\'s',
    () async {
      final (app, record, seen) = await chatting(
        configure: (app) => app.coordinator.takerNostrPublicKey =
            app.coordinator.makerNostrPublicKey,
      );
      expect(
        seen.order?.takerNostrPublicKeyHex,
        app.coordinator.makerNostrPublicKey,
      );
      final sent = await app.chatSend.send(record, seen, 'Hello');
      expect(sent, isA<Ok<ChatSent, ChatSendRefusal>>());
      await pumpEventQueue();
      expect(app.relays.published, isEmpty);
    },
  );

  test(
    'nothing is published when the order lacks the maker\'s Nostr key',
    () async {
      final (app, record, seen) = await chatting(
        configure: (app) => app.coordinator.makerNostrPublicKey = null,
      );
      expect(seen.order?.makerNostrPublicKeyHex, isNull);
      final sent = await app.chatSend.send(record, seen, 'Hello');
      expect(sent, isA<Ok<ChatSent, ChatSendRefusal>>());
      await pumpEventQueue();
      expect(app.relays.published, isEmpty);
    },
  );

  group('« Send again »', () {
    Future<(TradeHarness, TradeRecord, TradeSeen, ChatPendingMessage)>
    pendingMessage() async {
      final (app, record, seen) = await chatting();
      Map<String, Object?>? hidden;
      app.coordinator.onRequest = (request) {
        if (request.url.path == '/api/chat/' &&
            request.body == null &&
            app.coordinator.chat.isNotEmpty &&
            hidden == null) {
          hidden = app.coordinator.chat.removeLast();
        }
      };
      app.coordinator.failNext(
        ScriptedRequest.chatPost,
        ScriptedFault.answerLost,
      );
      final sent = await app.chatSend.send(record, seen, 'Hello?');
      app.coordinator.onRequest = null;
      final pending = switch (sent) {
        Ok(value: ChatSentNotConfirmed(:final pending)) => pending,
        final other => throw StateError('$other'),
      };
      await pumpEventQueue();
      return (app, record, seen, pending);
    }

    test('publishes nothing again when a relay accepted the message', () async {
      final (app, record, seen, pending) = await pendingMessage();
      final first = app.relays.published.length;
      expect(first, greaterThan(0));
      await app.chatSend.sendAgain(record, seen, pending.id);
      await pumpEventQueue();
      expect(app.relays.published, hasLength(first));
    });

    test(
      'publishes the same events again, and only them, when no relay accepted them',
      () async {
        final (app, record, seen) = await chatting();
        app.relays.answer = const NostrRelayTimedOut();
        Map<String, Object?>? hidden;
        app.coordinator.onRequest = (request) {
          if (request.url.path == '/api/chat/' &&
              request.body == null &&
              app.coordinator.chat.isNotEmpty &&
              hidden == null) {
            hidden = app.coordinator.chat.removeLast();
          }
        };
        app.coordinator.failNext(
          ScriptedRequest.chatPost,
          ScriptedFault.answerLost,
        );
        final sent = await app.chatSend.send(record, seen, 'Hello?');
        app.coordinator.onRequest = null;
        final pending = switch (sent) {
          Ok(value: ChatSentNotConfirmed(:final pending)) => pending,
          final other => throw StateError('$other'),
        };
        await pumpEventQueue();
        final first = app.relays.messages.single;
        final firstCount = app.relays.published.length;
        app.relays.answer = const NostrRelayAccepted();
        await app.chatSend.sendAgain(record, seen, pending.id);
        await pumpEventQueue();
        expect(app.relays.published.length, firstCount * 2);
        expect(app.relays.messages, hasLength(1));
        expect(identical(app.relays.messages.single, first), isTrue);
      },
    );
  });
}
