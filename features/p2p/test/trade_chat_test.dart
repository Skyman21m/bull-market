import 'dart:async';
import 'dart:math';

import 'package:p2p/src/domain/trade/trade_chat.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/send_chat_message_usecase.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/testing.dart'
    show Bolt11TestInvoice, ScriptedFault, ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/key_output.dart';
import 'support/trade_harness.dart';

/// The chat of a trade (#93): its read and its send, over the coordinator the tests play (never a real coordinator, never a real key, token or message), with a peer whose key the test makes.
void main() {
  // The peer, the order's maker: a robot of another Garage Key of the tests, and the key the official client would make for it.
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
  // The real clock: the robots' keys are dated by it, a day back.
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

  /// A trade taken, its bond locked, moved to 9 (the chat), on the real clock, and the status at 9 as a read stored it.
  Future<(TradeHarness, TradeRecord, TradeSeen)> atNine({
    bool peerKey = true,
  }) async {
    final app = await TradeHarness.start(maker: maker);
    final taken = await app.takeShown();
    expect(
      taken,
      isA<Ok<TakeOutcome, TakeRefusal>>().having(
        (ok) => ok.value,
        'outcome',
        isA<TakeStarted>(),
      ),
    );
    final record = TradeHarness.recordOf(taken);
    final run = app.watchOf(record);
    await app.settle();
    app.coordinator.lockBond(app.robot(0));
    if (realNow.isAfter(app.now)) await app.elapse(realNow.difference(app.now));
    app.coordinator.moveTo(9);
    if (peerKey) app.coordinator.peerPublicKey = makerKey.key.publicKey.armored;
    await app.elapse(const Duration(seconds: 11));
    final status = run.lastStatus;
    await run.subscription.cancel();
    expect(status.seen.status.position, TradePosition.chatting);
    expect(status.seen.stored, isTrue);
    return (app, status.record, status.seen);
  }

  PgpPublicKey ourKey(TradeHarness app) => switch (PgpPublicKey.parse(
    app.coordinator.publicKeyOf(app.robot(0)) ?? '',
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  /// [text] written by [from] to this robot, as the official client posts it.
  OutgoingChatMessage written(
    TradeHarness app,
    String text, {
    UnlockedRobotPgpKey? from,
  }) => switch ((from ?? makerKey).encryptChatMessageToPost(
    text,
    peer: ourKey(app),
    now: app.now,
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  Future<ChatView> read(
    TradeHarness app,
    TradeRecord record,
    TradeSeen seen,
  ) async => switch (await app.chatRead.read(record, seen)) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('read failed: $failure'),
  };

  group('the read', () {
    test(
      'pins the peer\'s key, decrypts each message once with the right key, and reads on from the last index',
      () async {
        final (app, record, seen) = await atNine();
        // A mark that would reorder the text, cleaned before it is shown.
        app.coordinator.peerSays(written(app, 'Hello,\u202E buyer'));
        final first = await read(app, record, seen);
        expect(first.connected, isTrue);
        expect(first.peerConnected, isTrue);
        expect(first.peerKey, isA<ChatPeerKeyPinned>());
        expect(first.canSend, isTrue);
        expect(first.entries, hasLength(1));
        final hello = first.entries.single;
        expect(hello.index, 1);
        expect(hello.author, ChatAuthor.peer);
        expect(hello.text, 'Hello, buyer');
        expect(hello.validSignature, isTrue);
        expect(hello.nick, maker.nickname);
        expect(first.ownKey, ourKey(app));
        // The lease closed at once: no hold, so no key kept.
        expect(app.keyring.keepsKeyOf(record.robot), isFalse);
        final unlocks = app.keys.unlocked.length;

        // Nothing new: no request beyond the page, no key unlocked.
        final again = await read(app, record, seen);
        expect(again.entries, hasLength(1));
        expect(app.keys.unlocked.length, unlocks);
        expect(app.chats.of(record).offset, 1);
        // The next read asks from the last index.
        final asked = app.coordinator.requests
            .where((r) => r.url.path == '/api/chat/')
            .last;
        expect(asked.url.queryParameters['offset'], '1');
      },
    );

    test(
      'without the peer\'s key: the peer\'s messages wait, nothing can be sent, and they are read once the key comes',
      () async {
        final (app, record, seen) = await atNine(peerKey: false);
        app.coordinator.peerSays(written(app, 'Are you there?'));
        final waiting = await read(app, record, seen);
        expect(waiting.peerKey, isA<ChatPeerKeyAwaited>());
        expect(waiting.canSend, isFalse);
        expect(waiting.entries.single.awaitingPeerKey, isTrue);
        expect(waiting.entries.single.text, isNull);
        expect(
          await app.chatSend.send(record, seen, 'Yes'),
          isA<Err<ChatSent, ChatSendRefusal>>().having(
            (e) => e.failure,
            'refusal',
            isA<ChatPeerKeyNotKnown>(),
          ),
        );
        app.coordinator.peerPublicKey = makerKey.key.publicKey.armored;
        final known = await read(app, record, seen);
        expect(known.peerKey, isA<ChatPeerKeyPinned>());
        expect(known.entries.single.text, 'Are you there?');
        expect(known.entries.single.validSignature, isTrue);
      },
    );

    test(
      'a key that changes after it was pinned, or one that is not the peer\'s by its name, is a breach: nothing is sent any more',
      () async {
        final (app, record, seen) = await atNine();
        await read(app, record, seen);
        app.coordinator.peerPublicKey = strangerKey.key.publicKey.armored;
        final changed = await read(app, record, seen);
        expect(
          changed.peerKey,
          isA<ChatPeerKeyBreach>().having(
            (b) => b.pinned,
            'pinned',
            makerKey.key.publicKey,
          ),
        );
        expect(changed.canSend, isFalse);
        // The breach stays, even when the coordinator gives the first key back.
        app.coordinator.peerPublicKey = makerKey.key.publicKey.armored;
        expect(
          (await read(app, record, seen)).peerKey,
          isA<ChatPeerKeyBreach>(),
        );
        expect(
          await app.chatSend.send(record, seen, 'Hello'),
          isA<Err<ChatSent, ChatSendRefusal>>().having(
            (e) => e.failure,
            'refusal',
            isA<ChatPeerKeyChanged>(),
          ),
        );

        // Misnamed from the first page: never taken.
        final (other, otherRecord, otherSeen) = await atNine(peerKey: false);
        other.coordinator.peerPublicKey = strangerKey.key.publicKey.armored;
        expect(
          (await read(other, otherRecord, otherSeen)).peerKey,
          isA<ChatPeerKeyBreach>().having((b) => b.pinned, 'pinned', isNull),
        );
        // A key gone after it was pinned is a breach too.
        final (third, thirdRecord, thirdSeen) = await atNine();
        await read(third, thirdRecord, thirdSeen);
        third.coordinator.peerPublicKey = null;
        expect(
          (await read(third, thirdRecord, thirdSeen)).peerKey,
          isA<ChatPeerKeyBreach>(),
        );
      },
    );

    test(
      'a key forged in the peer\'s name after the pin is a breach that stays, and nothing is posted',
      () async {
        final (app, record, seen) = await atNine();
        await read(app, record, seen);
        // The coordinator makes a key of its own for the maker's identity: named after the peer, so not misnamed.
        app.coordinator.peerPublicKey = keyOf(maker, 931).key.publicKey.armored;
        final forged = await read(app, record, seen);
        expect(
          forged.peerKey,
          isA<ChatPeerKeyBreach>().having(
            (b) => b.pinned,
            'pinned',
            makerKey.key.publicKey,
          ),
        );
        app.coordinator.peerPublicKey = makerKey.key.publicKey.armored;
        expect(
          (await read(app, record, seen)).peerKey,
          isA<ChatPeerKeyBreach>(),
        );
        final posts = _posts(app);
        expect(
          await app.chatSend.send(record, seen, 'Hello'),
          isA<Err<ChatSent, ChatSendRefusal>>().having(
            (e) => e.failure,
            'refusal',
            isA<ChatPeerKeyChanged>(),
          ),
        );
        expect(_posts(app), posts);
      },
    );

    test(
      'the limit of trust on first use: a key forged in the peer\'s name at the first read, before any message of the peer, is pinned silently',
      () async {
        final (app, record, seen) = await atNine(peerKey: false);
        final forgedKey = keyOf(maker, 932);
        app.coordinator.peerPublicKey = forgedKey.key.publicKey.armored;
        final view = await read(app, record, seen);
        expect(
          view.peerKey,
          isA<ChatPeerKeyPinned>().having(
            (p) => p.key,
            'key',
            forgedKey.key.publicKey,
          ),
        );
        expect(view.canSend, isTrue);
      },
    );

    test(
      'after a restart, a key forged in the peer\'s name is a breach: nothing leaves, and the peer\'s earlier message stays verified with the key kept (#139)',
      () async {
        final (app, record, seen) = await atNine();
        app.coordinator.peerSays(written(app, 'My IBAN follows'));
        expect(
          (await read(app, record, seen)).peerKey,
          isA<ChatPeerKeyPinned>(),
        );
        // The process killed in the background: a new run has only the key kept with the trade's record (#139), and the coordinator serves a key of its own in the peer's name. Without a key kept, #138's rule makes it a breach too (`trade_chat_pin_test.dart`).
        final (restartedRead, restartedSend) = app.chatAfterRestart();
        app.coordinator.peerPublicKey = keyOf(maker, 933).key.publicKey.armored;
        final again = switch (await restartedRead.read(record, seen)) {
          Ok(:final value) => value,
          Err(:final failure) => throw StateError('$failure'),
        };
        expect(again.peerKey, isA<ChatPeerKeyBreach>());
        expect(again.canSend, isFalse);
        expect(again.entries.single.validSignature, isTrue);
        expect(again.entries.single.text, 'My IBAN follows');
        final posts = _posts(app);
        expect(
          await restartedSend.send(record, seen, 'Here it is'),
          isA<Err<ChatSent, ChatSendRefusal>>().having(
            (e) => e.failure,
            'refusal',
            isA<ChatPeerKeyChanged>(),
          ),
        );
        expect(_posts(app), posts);
        // The real key served again: the breach stays.
        app.coordinator.peerPublicKey = makerKey.key.publicKey.armored;
        expect(switch (await restartedRead.read(record, seen)) {
          Ok(:final value) => value.peerKey,
          Err(:final failure) => throw StateError('$failure'),
        }, isA<ChatPeerKeyBreach>());
      },
    );

    test(
      'after a restart with no pin kept, a key forged in the peer\'s name that does not verify the peer\'s earlier messages is a breach: nothing leaves (#138, security review of #139)',
      () async {
        final (app, record, seen) = await atNine();
        app.coordinator.peerSays(written(app, 'My IBAN follows'));
        // The pin is never written in this run, as for a trade of an older version of the app.
        app.pins.refuseWrites = true;
        expect(
          (await read(app, record, seen)).peerKey,
          isA<ChatPeerKeyPinned>(),
        );
        final (restartedRead, restartedSend) = app.chatAfterRestart();
        app.coordinator.peerPublicKey = keyOf(maker, 934).key.publicKey.armored;
        final again = switch (await restartedRead.read(record, seen)) {
          Ok(:final value) => value,
          Err(:final failure) => throw StateError('$failure'),
        };
        expect(again.peerKey, isA<ChatPeerKeyBreach>());
        expect(again.canSend, isFalse);
        expect(again.entries.single.validSignature, isFalse);
        final posts = _posts(app);
        expect(
          await restartedSend.send(record, seen, 'Here it is'),
          isA<Err<ChatSent, ChatSendRefusal>>().having(
            (e) => e.failure,
            'refusal',
            isA<ChatPeerKeyChanged>(),
          ),
        );
        expect(_posts(app), posts);
        expect(app.pins.keeps, greaterThan(0));
        expect(
          await app.pins.pinOf(record),
          isA<Ok<PgpPublicKey?, P2pFailure>>().having(
            (ok) => ok.value,
            'pin',
            isNull,
          ),
        );
      },
    );

    test(
      'the decryption that could not run takes nothing: the next read decrypts the page (second pass of the review of #93)',
      () async {
        final (app, record, seen) = await atNine();
        app.coordinator.peerSays(written(app, 'Hello'));
        app.keys.chatDecryptFailure = const RobotKeyComputeFailure();
        expect(
          await app.chatRead.read(record, seen),
          isA<Err<ChatView, ChatReadFailure>>().having(
            (e) => e.failure,
            'failure',
            isA<ChatTradeUnavailable>(),
          ),
        );
        expect(app.chatRead.current(record).entries, isEmpty);
        expect(app.chats.of(record).offset, 0);
        expect(app.keyring.keepsKeyOf(record.robot), isFalse);
        app.keys.chatDecryptFailure = null;
        final view = await read(app, record, seen);
        expect(view.entries.single.text, 'Hello');
        expect(view.entries.single.validSignature, isTrue);
      },
    );

    test(
      'a message the peer\'s key did not sign is marked; one from neither party is never checked as the peer\'s; one that is not an encrypted message is unreadable',
      () async {
        final (app, record, seen) = await atNine();
        // The key pinned first: in the page that pins it, a message it does not verify is a breach (below).
        await read(app, record, seen);
        // Signed by a third robot, under the peer's nickname.
        app.coordinator.peerSays(
          written(app, 'Pay me here', from: strangerKey),
        );
        // Under a nickname of neither party.
        app.coordinator.chat.add({
          'index': 2,
          'time': app.now.toIso8601String(),
          'message': written(app, 'Hi').wire,
          'nick': 'NoOneHere',
        });
        app.coordinator.chat.add({
          'index': 3,
          'time': app.now.toIso8601String(),
          'message': 'plain text',
          'nick': maker.nickname,
        });
        final view = await read(app, record, seen);
        expect(view.entries[0].validSignature, isFalse);
        expect(view.entries[0].text, 'Pay me here');
        expect(view.entries[1].author, ChatAuthor.unknown);
        expect(view.entries[1].validSignature, isFalse);
        expect(view.entries[2].unreadable, isTrue);
        expect(view.entries[2].text, isNull);
      },
    );

    test(
      'a message shown again at a new index is marked as a repeat; a gap is marked; the first message seen at an index is kept',
      () async {
        final (app, record, seen) = await atNine();
        final first = written(app, 'IBAN one');
        app.coordinator.peerSays(first);
        await read(app, record, seen);
        // The coordinator shows the same message again later, and a message at index 4 after a missing 3.
        app.coordinator.chat
          ..add({
            'index': 2,
            'time': app.now.toIso8601String(),
            'message': first.wire,
            'nick': maker.nickname,
          })
          ..add({
            'index': 4,
            'time': app.now.toIso8601String(),
            'message': written(app, 'after a gap').wire,
            'nick': maker.nickname,
          });
        final view = await read(app, record, seen);
        expect(view.entries[1].repeatOf, 1);
        expect(view.entries[1].sentTwice, isFalse);
        expect(view.entries[2].afterGap, isTrue);
        expect(view.incomplete, isTrue);
        // The reads go on from before the gap.
        expect(app.chats.of(record).offset, 2);
        // Another text at an index already shown, read again beyond the gap, is not taken.
        app.coordinator.chat[2] = {
          ...app.coordinator.chat[2],
          'message': written(app, 'IBAN two').wire,
        };
        final kept = await read(app, record, seen);
        expect(kept.entries[2].text, 'after a gap');
      },
    );

    test(
      'a gap of the reference\'s numbering that holds three reads is read past',
      () async {
        final (app, record, seen) = await atNine();
        final hello = written(app, 'one');
        // Two posts at once share index 1; the next skips 2.
        app.coordinator.chat
          ..add({
            'index': 1,
            'time': app.now.toIso8601String(),
            'message': hello.wire,
            'nick': maker.nickname,
          })
          ..add({
            'index': 1,
            'time': app.now.toIso8601String(),
            'message': written(app, 'two').wire,
            'nick': maker.nickname,
          })
          ..add({
            'index': 3,
            'time': app.now.toIso8601String(),
            'message': written(app, 'three').wire,
            'nick': maker.nickname,
          });
        for (var i = 0; i < 2; i++) {
          await read(app, record, seen);
          expect(app.chats.of(record).offset, 1, reason: '$i');
        }
        await read(app, record, seen);
        expect(app.chats.of(record).offset, 3);
      },
    );

    test(
      'a read with no order, or a status where the chat is closed, asks nothing',
      () async {
        final (app, record, seen) = await atNine();
        final before = app.coordinator.requests.length;
        expect(
          await app.chatRead.read(record, TradeSeen(seen.status, order: null)),
          isA<Err<ChatView, ChatReadFailure>>(),
        );
        expect(app.coordinator.requests.length, before);
      },
    );
  });

  group('the send', () {
    test(
      'refuses before anything leaves: empty, too long, a Garage Key, an invoice or an address alone, the robot\'s token',
      () async {
        final (app, record, seen) = await atNine();
        await read(app, record, seen);
        final posts = app.coordinator.requests
            .where((r) => r.url.path == '/api/chat/' && r.body != null)
            .length;
        for (final (text, refusal) in <(String, Matcher)>[
          ('   \n', isA<ChatTextEmpty>()),
          (
            'x' * (OutgoingChatMessage.maxTextBytes + 1),
            isA<ChatTextTooLong>(),
          ),
          ('my key ${tradeKey.revealBech32()}', isA<ChatTextHoldsGarageKey>()),
          ('token: ${app.robot(0).token.reveal()}', isA<ChatTextHoldsToken>()),
        ]) {
          expect(
            await app.chatSend.send(record, seen, text),
            isA<Err<ChatSent, ChatSendRefusal>>().having(
              (e) => e.failure,
              'refusal',
              refusal,
            ),
            reason: text.length > 40 ? text.substring(0, 40) : text,
          );
        }
        expect(
          app.coordinator.requests
              .where((r) => r.url.path == '/api/chat/' && r.body != null)
              .length,
          posts,
        );
      },
    );

    test(
      'the very text typed, encrypted to the pinned key and to this robot, posted once, stored at its index',
      () async {
        final (app, record, seen) = await atNine();
        await read(app, record, seen);
        const text = 'Hi! Send to IBAN FR76 …';
        final sent = await app.chatSend.send(record, seen, text);
        expect(
          sent,
          isA<Ok<ChatSent, ChatSendRefusal>>().having(
            (ok) => ok.value,
            'sent',
            isA<ChatSentStored>().having((s) => s.index, 'index', 1),
          ),
        );
        expect(app.coordinator.chat, hasLength(1));
        // The peer reads exactly that text, signed by this robot.
        final stored = app.coordinator.chat.single['message'] as String;
        final decrypted = switch (makerKey.decryptChatMessage(
          stored,
          sender: ourKey(app),
          now: app.now,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => throw StateError('$failure'),
        };
        expect(decrypted.text, text);
        expect(decrypted.validSignature, isTrue);
        // The lease of the send closed at once.
        expect(app.keyring.keepsKeyOf(record.robot), isFalse);
        final view = app.chatRead.current(record);
        expect(view.entries.single.author, ChatAuthor.self);
        expect(view.entries.single.text, text);
        expect(view.pending, isEmpty);
      },
    );

    test(
      'an answer lost: the message is looked for in a read from the offset it was posted with, and found stored',
      () async {
        final (app, record, seen) = await atNine();
        await read(app, record, seen);
        app.coordinator.failNext(
          ScriptedRequest.chatPost,
          ScriptedFault.answerLost,
        );
        final sent = await app.chatSend.send(record, seen, 'Are you there?');
        expect(
          sent,
          isA<Ok<ChatSent, ChatSendRefusal>>().having(
            (ok) => ok.value,
            'sent',
            isA<ChatSentStored>(),
          ),
        );
        expect(app.coordinator.chat, hasLength(1));
      },
    );

    test(
      'not confirmed: pending, never sent again by itself; sent again, it is the same encrypted message, and its copy is labelled as sent twice',
      () async {
        final (app, record, seen) = await atNine();
        await read(app, record, seen);
        // The coordinator stores the message, the answer is lost, and the read after it does not show it.
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
        final pending = switch (sent) {
          Ok(value: ChatSentNotConfirmed(:final pending)) => pending,
          final other => throw StateError('$other'),
        };
        expect(pending.text, 'Hello?');
        expect(app.chatRead.current(record).pending, hasLength(1));
        app.coordinator.onRequest = null;
        final wire = hidden?['message'];
        // Reads do not send it again.
        await read(app, record, seen);
        expect(app.coordinator.chat, isEmpty);
        // The user sends it again: the same encrypted message.
        final again = await app.chatSend.sendAgain(record, seen, pending.id);
        expect(again, isA<Ok<ChatSent, ChatSendRefusal>>());
        expect(app.coordinator.chat.single['message'], wire);
        expect(app.chatRead.current(record).pending, isEmpty);
        // The first copy shows up after all: one message sent twice, not a replay.
        app.coordinator.chat.add({...?hidden, 'index': 2});
        final view = await read(app, record, seen);
        expect(view.entries[1].repeatOf, 1);
        expect(view.entries[1].sentTwice, isTrue);
      },
    );

    test(
      'the text is sent as typed: spaces, line feeds, tabs and control characters around it kept, nothing trimmed or cleaned (review of #93)',
      () async {
        final (app, record, seen) = await atNine();
        await read(app, record, seen);
        const text = '  \n Hi\tthere \u0007\n  ';
        expect(
          await app.chatSend.send(record, seen, text),
          isA<Ok<ChatSent, ChatSendRefusal>>(),
        );
        final stored = app.coordinator.chat.single['message'] as String;
        expect(switch (makerKey.decryptChatMessage(
          stored.trim(),
          sender: ourKey(app),
          now: app.now,
        )) {
          Ok(:final value) => value.text,
          Err(:final failure) => throw StateError('$failure'),
        }, text);
      },
    );

    test(
      'a breach read while a send waits stops it before the post (review of #93)',
      () async {
        final (app, record, seen) = await atNine();
        await read(app, record, seen);
        final unlock = Completer<void>();
        app.keys.holdUnlock = unlock.future;
        final posts = _posts(app);
        final sending = app.chatSend.send(record, seen, 'Hello');
        await app.settle();
        app.coordinator.peerPublicKey = keyOf(maker, 934).key.publicKey.armored;
        expect(
          (await read(app, record, seen)).peerKey,
          isA<ChatPeerKeyBreach>(),
        );
        unlock.complete();
        app.keys.holdUnlock = null;
        expect(
          await sending,
          isA<Err<ChatSent, ChatSendRefusal>>().having(
            (e) => e.failure,
            'refusal',
            isA<ChatPeerKeyChanged>(),
          ),
        );
        expect(_posts(app), posts);
      },
    );

    test(
      'a breach read while the limiter waits after a busy answer stops the post before it leaves (second pass of the review of #93)',
      () async {
        final (app, record, seen) = await atNine();
        await read(app, record, seen);
        final wait = Completer<void>();
        app.holdBusyWait = wait.future;
        app.coordinator.failNext(ScriptedRequest.chatPost, ScriptedFault.busy);
        final sending = app.chatSend.send(record, seen, 'Hello');
        await app.settle();
        expect(app.busyWaits, isNotEmpty);
        app.holdBusyWait = null;
        app.coordinator.peerPublicKey = keyOf(maker, 936).key.publicKey.armored;
        expect(
          (await read(app, record, seen)).peerKey,
          isA<ChatPeerKeyBreach>(),
        );
        wait.complete();
        expect(
          await sending,
          isA<Err<ChatSent, ChatSendRefusal>>().having(
            (e) => e.failure,
            'refusal',
            isA<ChatPeerKeyChanged>(),
          ),
        );
        expect(app.coordinator.chat, isEmpty);
      },
    );

    test(
      'a message not confirmed is not sent again after a breach (review of #93)',
      () async {
        final (app, record, seen) = await atNine();
        await read(app, record, seen);
        app.coordinator.onRequest = (request) {
          if (request.url.path == '/api/chat/' &&
              request.body == null &&
              app.coordinator.chat.isNotEmpty) {
            app.coordinator.chat.removeLast();
          }
        };
        app.coordinator.failNext(
          ScriptedRequest.chatPost,
          ScriptedFault.answerLost,
        );
        final pending = switch (await app.chatSend.send(
          record,
          seen,
          'Hello?',
        )) {
          Ok(value: ChatSentNotConfirmed(:final pending)) => pending,
          final other => throw StateError('$other'),
        };
        app.coordinator.onRequest = null;
        app.coordinator.peerPublicKey = keyOf(maker, 935).key.publicKey.armored;
        expect(
          (await read(app, record, seen)).peerKey,
          isA<ChatPeerKeyBreach>(),
        );
        final posts = _posts(app);
        expect(
          await app.chatSend.sendAgain(record, seen, pending.id),
          isA<Err<ChatSent, ChatSendRefusal>>().having(
            (e) => e.failure,
            'refusal',
            isA<ChatPeerKeyChanged>(),
          ),
        );
        expect(_posts(app), posts);
      },
    );

    test(
      'a message of this robot shown again that it did not send again is a replay, not « sent twice » (review of #93)',
      () async {
        final (app, record, seen) = await atNine();
        await read(app, record, seen);
        expect(
          await app.chatSend.send(record, seen, 'Paid'),
          isA<Ok<ChatSent, ChatSendRefusal>>(),
        );
        app.coordinator.chat.add({...app.coordinator.chat.single, 'index': 2});
        final view = await read(app, record, seen);
        expect(view.entries[1].repeatOf, 1);
        expect(view.entries[1].sentTwice, isFalse);
      },
    );

    test(
      'refused by the coordinator: nothing stored, the kind said, never its text',
      () async {
        final (app, record, seen) = await atNine();
        await read(app, record, seen);
        app.coordinator.moveTo(11);
        final sent = await app.chatSend.send(record, seen, 'Hello');
        expect(
          sent,
          isA<Err<ChatSent, ChatSendRefusal>>().having(
            (e) => e.failure,
            'refusal',
            isA<ChatSendRefused>().having(
              (r) => r.cause,
              'cause',
              isA<ChatRefused>(),
            ),
          ),
        );
        expect(app.coordinator.chat, isEmpty);
      },
    );
  });

  test(
    'what the screen may show of a text: no control character but line feeds and tabs, no mark that reorders text',
    () {
      expect(
        ChatEntry.displayable('a\u202Eb\u2066c\u0007d\ne\tf\u200F'),
        'abcd\ne\tf',
      );
      expect(
        ChatEntry.displayable('Bonjour, ça va ? 👋'),
        'Bonjour, ça va ? 👋',
      );
    },
  );

  test(
    'no format character survives in a peer\'s text: zero-width, soft hyphen, Arabic letter mark, byte order mark, tag characters, variation selectors (review of #93)',
    () {
      expect(
        ChatEntry.displayable(
          'FR76\u200B 3000\u200C6\u200D0\u2060001\u2064 \uFEFF1\u00AD2\u061C3\u{E0041}4\uFE0F5\u{E0100}6\r',
        ),
        'FR76 300060001 123456',
      );
      // The separators render as line breaks; private use, noncharacters and letters that show nothing are dropped; a run of combining marks keeps four (second pass of the review of #93).
      expect(ChatEntry.displayable('a\u2028b\u2029c'), 'a\nb\nc');
      expect(
        ChatEntry.displayable(
          'I\uE000B\u{F0000}A\uFDD0N\uFFFE \u{10FFFF}F\u3164R\u2800\u115F\u1160\uFFA07\u034F6',
        ),
        'IBAN FR76',
      );
      expect(
        ChatEntry.displayable('e\u0301\u0302\u0303\u0304\u0305\u0306\u0307x'),
        'e\u0301\u0302\u0303\u0304x',
      );
      expect(ChatEntry.displayable('Vi\u1EC7t Nam'), 'Vi\u1EC7t Nam');
      // The zero-width joiner is dropped too: an emoji sequence shows as its parts.
      expect(
        ChatEntry.displayable('\u{1F468}\u200D\u{1F469}'),
        '\u{1F468}\u{1F469}',
      );
    },
  );

  test(
    'as the user types: too long said before any key, at the byte (review of #93)',
    () {
      expect(
        SendChatMessageUsecase.refusalOf(
          'x' * OutgoingChatMessage.maxTextBytes,
        ),
        isNull,
      );
      expect(
        SendChatMessageUsecase.refusalOf(
          'x' * (OutgoingChatMessage.maxTextBytes + 1),
        ),
        isA<ChatTextTooLong>(),
      );
    },
  );

  test(
    'an invoice or an address alone is sent, as the reference sends it: the owner chose to stay with the reference (`AGENTS.md`)',
    () {
      final invoice = Bolt11TestInvoice(
        network: Bolt11Network.testnet,
        sats: 106606,
        seed: 3,
        createdAt: realNow,
        expiry: const Duration(days: 1),
      );
      for (final text in [
        invoice.text,
        'lightning:${invoice.text.toUpperCase()}',
        'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4',
        'bitcoin:tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx?amount=1',
      ]) {
        expect(SendChatMessageUsecase.refusalOf(text), isNull, reason: text);
      }
    },
  );

  test(
    'a history too large to read from the start is said, and the newer messages are read only on the user\'s choice',
    () async {
      final (app, record, seen) = await atNine();
      // A peer that posted enough: over the 4 MiB a page may take.
      app.coordinator.chat.add({
        'index': 1,
        'time': app.now.toIso8601String(),
        'message': 'x' * (CoordinatorReadBounds.chatBytes + 1),
        'nick': maker.nickname,
      });
      final big = await read(app, record, seen);
      expect(big.historyTooLarge, isTrue);
      expect(app.chats.of(record).offset, 0);
      // Not skipped by itself: the next read asks from the start again.
      await read(app, record, seen);
      expect(app.chats.of(record).offset, 0);
      // The order shown was read while the chat was empty: its last chat index is 0, as the reference answers, so nothing can be skipped yet.
      expect(seen.order?.chatLastIndex, 0);
      expect(
        app.chatRead.readNewerOnly(record, seen),
        isA<Err<ChatView, ChatSkipRefusal>>().having(
          (e) => e.failure,
          'refusal',
          isA<ChatSkipNeedsOrderRead>(),
        ),
      );
      expect(app.chats.of(record).offset, 0);
      expect(app.chats.of(record).view.skippedEarlier, isFalse);
      // The order read again gives the highest index: the skip is done.
      final run = app.watchOf(record);
      await app.elapse(const Duration(seconds: 11));
      final fresh = run.lastStatus.seen;
      await run.subscription.cancel();
      expect(fresh.order?.chatLastIndex, 1);
      final newer = switch (app.chatRead.readNewerOnly(record, fresh)) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };
      expect(newer.skippedEarlier, isTrue);
      expect(newer.historyTooLarge, isFalse);
      expect(app.chats.of(record).offset, 1);
      expect((await read(app, record, fresh)).historyTooLarge, isFalse);
    },
  );

  test('nothing is printed or logged: no text, no message, no key', () async {
    final (app, record, seen) = await atNine();
    const secret = 'my-secret-payment-detail';
    final output = await captureKeyOutput(() async {
      app.coordinator.peerSays(written(app, secret));
      final view = await read(app, record, seen);
      await app.chatSend.send(record, seen, '$secret again');
      Zone.current.print('$view ${view.entries} ${app.chats.of(record)}');
    });
    expect(output.contains(secret), isFalse);
    expect(output.contains('BEGIN PGP'), isFalse);
  });
}

/// How many messages were posted to the coordinator of [app].
int _posts(TradeHarness app) => app.coordinator.requests
    .where((r) => r.url.path == '/api/chat/' && r.body != null)
    .length;
