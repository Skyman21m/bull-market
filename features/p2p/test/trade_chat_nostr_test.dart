import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
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
  // A third robot: a key the coordinator could give in the peer's place.
  final stranger = switch (NetworkGarageKey(
    RobosatsNetwork.testnet,
    otherTradeKey,
  ).firstUsableRobot(1)) {
    Ok(:final value) => value.identity,
    Err(:final failure) => throw StateError('$failure'),
  };
  late UnlockedRobotPgpKey makerKey;
  late UnlockedRobotPgpKey strangerKey;
  final realNow = DateTime.now().toUtc();

  UnlockedRobotPgpKey keyOf(RobotIdentity identity, int seed) {
    final key = switch (RobotPgpKey.generateWith(
      identity,
      now: realNow,
      random: Random(seed),
    )) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
    return switch (key.unlock(identity)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
  }

  setUpAll(() {
    makerKey = keyOf(maker, 93);
    strangerKey = keyOf(stranger, 94);
  });

  /// The trade's status as a new read of the order stores it.
  Future<TradeSeen> readAgain(TradeHarness app, TradeRecord record) async {
    final run = app.watchOf(record);
    await app.elapse(const Duration(seconds: 11));
    final seen = run.lastStatus.seen;
    await run.subscription.cancel();
    return seen;
  }

  /// A send whose post gets no known answer, then a read that does not show it: the message is pending.
  Future<ChatPendingMessage> pendingAfter(
    TradeHarness app,
    TradeRecord record,
    TradeSeen seen,
    String text,
  ) async {
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
    final sent = await app.chatSend.send(record, seen, text);
    app.coordinator.onRequest = null;
    await pumpEventQueue();
    return switch (sent) {
      Ok(value: ChatSentNotConfirmed(:final pending)) => pending,
      final other => throw StateError('$other'),
    };
  }

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

  group(
    'the copy leaves only when the post to the coordinator leaves (review of #158, decision A)',
    () {
      test(
        'nothing leaves when the last read shows the chat closed: refused before sending',
        () async {
          final (app, record, _) = await chatting();
          app.coordinator.moveTo(11);
          final closed = await readAgain(app, record);
          final posts = app.coordinator.requests
              .where((r) => r.url.path == '/api/chat/' && r.body != null)
              .length;
          final sent = await app.chatSend.send(record, closed, 'Hello');
          await pumpEventQueue();
          expect(sent, isA<Err<ChatSent, ChatSendRefusal>>());
          expect(
            app.coordinator.requests
                .where((r) => r.url.path == '/api/chat/' && r.body != null)
                .length,
            posts,
          );
          expect(app.relays.published, isEmpty);
        },
      );

      test(
        'nothing leaves when the transport has no place for the post every time',
        () async {
          final (app, record, seen) = await chatting();
          for (var i = 0; i < 20; i++) {
            app.coordinator.failNext(
              ScriptedRequest.chatPost,
              ScriptedFault.busy,
            );
          }
          final sent = await app.chatSend.send(record, seen, 'Hello');
          await pumpEventQueue();
          expect(sent, isA<Err<ChatSent, ChatSendRefusal>>());
          expect(app.coordinator.chat, isEmpty);
          expect(app.relays.published, isEmpty);
        },
      );

      test(
        'nothing leaves when a key breach is read while the post waits for a place',
        () async {
          final (app, record, seen) = await chatting();
          final gate = Completer<void>();
          app.holdBusyWait = gate.future;
          app.coordinator.failNext(
            ScriptedRequest.chatPost,
            ScriptedFault.busy,
          );
          final sending = app.chatSend.send(record, seen, 'Hello');
          while (app.busyWaits.isEmpty) {
            await pumpEventQueue(times: 1);
          }
          app.coordinator.peerPublicKey = strangerKey.key.publicKey.armored;
          final read = await app.chatRead.read(record, seen);
          expect(
            read,
            isA<Ok<ChatView, ChatReadFailure>>().having(
              (ok) => ok.value.peerKey,
              'peer key',
              isA<ChatPeerKeyBreach>(),
            ),
          );
          gate.complete();
          final sent = await sending;
          await pumpEventQueue();
          expect(
            sent,
            isA<Err<ChatSent, ChatSendRefusal>>().having(
              (e) => e.failure,
              'refusal',
              isA<ChatPeerKeyChanged>(),
            ),
          );
          expect(app.coordinator.chat, isEmpty);
          expect(app.relays.published, isEmpty);
        },
      );

      test(
        'declared, as the reference: when the coordinator refuses the post after its copy left, the copy is out',
        () async {
          final (app, record, seen) = await chatting();
          app.coordinator.moveTo(11);
          // The post is written, the copy composed and published, and only then is the post served, and refused.
          app.coordinator.failNext(
            ScriptedRequest.chatPost,
            ScriptedFault.servedLate,
          );
          final sending = app.chatSend.send(record, seen, 'Hello');
          await pumpEventQueue();
          expect(app.relays.messages, hasLength(1));
          app.coordinator.serveLate();
          expect(await sending, isA<Err<ChatSent, ChatSendRefusal>>());
        },
      );

      test(
        'a refusal known while the copy is composed: the copy is not published (second review of #158)',
        () async {
          final (app, record, seen) = await chatting();
          app.coordinator.moveTo(11);
          final gate = Completer<void>();
          app.keys.holdCompose = gate.future;
          final sent = await app.chatSend.send(record, seen, 'Hello');
          expect(sent, isA<Err<ChatSent, ChatSendRefusal>>());
          gate.complete();
          await pumpEventQueue();
          expect(app.relays.published, isEmpty);
        },
      );

      test(
        'nothing leaves when the coordinator cannot be reached: the post was never written (second review of #158)',
        () async {
          final (app, record, seen) = await chatting();
          app.coordinator.failNext(
            ScriptedRequest.chatPost,
            ScriptedFault.unreachable,
          );
          await app.chatSend.send(record, seen, 'Hello');
          await pumpEventQueue();
          expect(app.relays.published, isEmpty);
        },
      );

      test(
        'a message stored while its copy is composed: the copy is published all the same',
        () async {
          final (app, record, seen) = await chatting();
          final gate = Completer<void>();
          app.keys.holdCompose = gate.future;
          final sent = await app.chatSend.send(record, seen, 'Hello');
          expect(
            sent,
            isA<Ok<ChatSent, ChatSendRefusal>>().having(
              (ok) => ok.value,
              'sent',
              isA<ChatSentStored>(),
            ),
          );
          gate.complete();
          await pumpEventQueue();
          expect(app.relays.messages, hasLength(1));
        },
      );
    },
  );

  group('a relay accepted it: one is enough (review of #158)', () {
    test(
      'one relay accepting and the others failing: « Send again » publishes nothing again',
      () async {
        final (app, record, seen) = await chatting();
        final first = OutgoingNostrChatMessage.relayUrl(
          Federation.robosats.byAlias('temple') ?? (throw StateError('temple')),
          RobosatsNetwork.testnet,
        );
        app.relays.answerFor = (relay) => relay == first
            ? const NostrRelayAccepted()
            : const NostrRelayUnreachable();
        final pending = await pendingAfter(app, record, seen, 'Hello?');
        final count = app.relays.published.length;
        expect(count, greaterThan(1));
        await app.chatSend.sendAgain(record, seen, pending.id);
        await pumpEventQueue();
        expect(app.relays.published, hasLength(count));
      },
    );

    test(
      'no relay accepting: « Send again » publishes the same events again',
      () async {
        final (app, record, seen) = await chatting();
        app.relays.answerFor = (_) => const NostrRelayRefused();
        final pending = await pendingAfter(app, record, seen, 'Hello?');
        final count = app.relays.published.length;
        app.relays.answerFor = null;
        await app.chatSend.sendAgain(record, seen, pending.id);
        await pumpEventQueue();
        expect(app.relays.published, hasLength(count * 2));
        expect(app.relays.messages, hasLength(1));
      },
    );
  });

  test(
    '« Send again » composes the copy when the first send could not (review of #158)',
    () async {
      final (app, record, seen) = await chatting(
        configure: (app) => app.coordinator.makerNostrPublicKey = null,
      );
      final pending = await pendingAfter(app, record, seen, 'Hello?');
      expect(app.relays.published, isEmpty);
      app.coordinator.makerNostrPublicKey =
          'f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9';
      final withKeys = await readAgain(app, record);
      expect(withKeys.order?.makerNostrPublicKeyHex, isNotNull);
      await app.chatSend.sendAgain(record, withKeys, pending.id);
      await pumpEventQueue();
      expect(app.relays.messages, hasLength(1));
    },
  );

  group(
    'the trade\'s Nostr keys pinned at its first copy (security review of #158)',
    () {
      test(
        'a peer key the order changes during the trade stops every later copy; a fixed word is logged; the coordinator still gets the messages',
        () async {
          final (app, record, seen) = await chatting();
          await app.chatSend.send(record, seen, 'First');
          await pumpEventQueue();
          expect(app.relays.messages, hasLength(1));
          // Another valid key: the x-only key of the secret key 2, public.
          app.coordinator.makerNostrPublicKey =
              'c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5';
          final changed = await readAgain(app, record);
          expect(
            changed.order?.makerNostrPublicKeyHex,
            app.coordinator.makerNostrPublicKey,
          );
          final printed = <String>[];
          final print = debugPrint;
          debugPrint = (String? line, {int? wrapWidth}) {
            if (line != null) printed.add(line);
          };
          final Result<ChatSent, ChatSendRefusal> sent;
          try {
            sent = await app.chatSend.send(record, changed, 'Second');
            await pumpEventQueue();
          } finally {
            debugPrint = print;
          }
          expect(sent, isA<Ok<ChatSent, ChatSendRefusal>>());
          expect(app.coordinator.chat, hasLength(2));
          expect(app.relays.messages, hasLength(1));
          // Even when the order gives the first key back.
          app.coordinator.makerNostrPublicKey =
              'f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9';
          final back = await readAgain(app, record);
          await app.chatSend.send(record, back, 'Third');
          await pumpEventQueue();
          expect(app.relays.messages, hasLength(1));
          expect(
            printed.where(
              (line) => line.contains(
                'P2P Nostr copy not sent: a Nostr key of the trade changed',
              ),
            ),
            isNotEmpty,
          );
          for (final line in printed) {
            expect(line, isNot(contains('c6047f94')));
            expect(line, isNot(contains('Second')));
          }
        },
      );

      test(
        'our own key changed by the order during the trade stops the copies too',
        () async {
          final (app, record, seen) = await chatting();
          await app.chatSend.send(record, seen, 'First');
          await pumpEventQueue();
          expect(app.relays.messages, hasLength(1));
          app.coordinator.takerNostrPublicKey =
              'c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5';
          final changed = await readAgain(app, record);
          app.coordinator.takerNostrPublicKey = null;
          final back = await readAgain(app, record);
          await app.chatSend.send(record, changed, 'Second');
          await app.chatSend.send(record, back, 'Third');
          await pumpEventQueue();
          expect(app.relays.messages, hasLength(1));
          expect(app.coordinator.chat, hasLength(3));
        },
      );
    },
  );

  group(
    'no failure of the Nostr copy reaches the post, the screen or the zone (security review of #158)',
    () {
      test('a composition that throws', () async {
        final (app, record, seen) = await chatting();
        app.keys.composeThrows = StateError('a bug in the composition');
        final errors = <Object>[];
        final printed = <String>[];
        final print = debugPrint;
        debugPrint = (String? line, {int? wrapWidth}) {
          if (line != null) printed.add(line);
        };
        Result<ChatSent, ChatSendRefusal>? sent;
        try {
          await runZonedGuarded(() async {
            sent = await app.chatSend.send(record, seen, 'Hello');
            await pumpEventQueue();
          }, (error, _) => errors.add(error));
        } finally {
          debugPrint = print;
        }
        expect(errors, isEmpty);
        // The error's type, never its message.
        expect(
          printed.where(
            (line) => line.contains('P2P Nostr copy failed (StateError)'),
          ),
          isNotEmpty,
        );
        expect(
          printed.where((line) => line.contains('a bug in the composition')),
          isEmpty,
        );
        expect(
          sent,
          isA<Ok<ChatSent, ChatSendRefusal>>().having(
            (ok) => ok.value,
            'sent',
            isA<ChatSentStored>(),
          ),
        );
        expect(app.relays.published, isEmpty);
      });

      test('a publication that fails asynchronously', () async {
        final (app, record, seen) = await chatting();
        app.relays.thrown = StateError('an adapter that breaks its contract');
        final errors = <Object>[];
        Result<ChatSent, ChatSendRefusal>? sent;
        await runZonedGuarded(() async {
          sent = await app.chatSend.send(record, seen, 'Hello');
          await pumpEventQueue();
        }, (error, _) => errors.add(error));
        expect(errors, isEmpty);
        expect(sent, isA<Ok<ChatSent, ChatSendRefusal>>());
        expect(app.relays.published, isNotEmpty);
      });
    },
  );

  test(
    'two messages composed at once with two different peer keys never go to both: the keys are pinned before composing (second review of #158)',
    () async {
      final (app, record, seen) = await chatting();
      final first = app.coordinator.makerNostrPublicKey;
      const second =
          'c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5';
      app.coordinator.makerNostrPublicKey = second;
      final changed = await readAgain(app, record);
      final gate = Completer<void>();
      app.keys.holdCompose = gate.future;
      await app.chatSend.send(record, seen, 'One');
      await app.chatSend.send(record, changed, 'Two');
      gate.complete();
      await pumpEventQueue();
      final peers = {
        for (final p in app.relays.published)
          ((jsonDecode(p.message.relayMessages.first) as List<dynamic>)[1]
                  as Map<String, dynamic>)['tags']
              .toString(),
      };
      expect(peers.where((tags) => tags.contains(second)), isEmpty);
      expect(app.relays.messages.length, lessThanOrEqualTo(1));
      expect(first, isNotNull);
    },
  );

  test(
    'an invalid key, the all-zero placeholder among them, is never pinned: the copies go once the order gives a valid one (verification of 230b49ad2, UC)',
    () async {
      final (app, record, seen) = await chatting(
        configure: (app) => app.coordinator.makerNostrPublicKey = '0' * 64,
      );
      await app.chatSend.send(record, seen, 'First');
      await pumpEventQueue();
      expect(app.relays.published, isEmpty);
      app.coordinator.makerNostrPublicKey =
          'f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9';
      final valid = await readAgain(app, record);
      await app.chatSend.send(record, valid, 'Second');
      await pumpEventQueue();
      expect(app.relays.messages, hasLength(1));
    },
  );

  group(
    'the pin checked again before publishing (verification of 230b49ad2, UB)',
    () {
      test(
        'a copy composed while a later post saw a key change is not published',
        () async {
          final (app, record, seen) = await chatting();
          app.coordinator.makerNostrPublicKey =
              'c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5';
          final changed = await readAgain(app, record);
          final gate = Completer<void>();
          app.keys.holdCompose = gate.future;
          await app.chatSend.send(record, seen, 'One');
          await app.chatSend.send(record, changed, 'Two');
          gate.complete();
          await pumpEventQueue();
          expect(app.relays.published, isEmpty);
        },
      );

      test(
        '« Send again » publishes nothing once a key changed, even a copy no relay accepted',
        () async {
          final (app, record, seen) = await chatting();
          app.relays.answerFor = (_) => const NostrRelayRefused();
          final pending = await pendingAfter(app, record, seen, 'Hello?');
          final count = app.relays.published.length;
          expect(count, greaterThan(0));
          app.relays.answerFor = null;
          app.coordinator.makerNostrPublicKey =
              'c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5';
          final changed = await readAgain(app, record);
          await app.chatSend.send(record, changed, 'Seen with the new key');
          await app.chatSend.sendAgain(record, seen, pending.id);
          await pumpEventQueue();
          expect(app.relays.published, hasLength(count));
        },
      );
    },
  );
}
