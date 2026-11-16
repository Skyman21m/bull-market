import 'dart:async';
import 'dart:math';

import 'package:p2p/src/data/trade_chat_pin_repository_impl.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/trade_chat.dart';
import 'package:p2p/src/domain/trade/trade_chat_pin.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/trade_harness.dart';

/// The peer's key a trade's chat pinned, kept with the trade's record by its two fingerprints (#139): after a restart of the app, played by fresh chats over the same database, the key served is compared with it instead of being trusted again. Over the coordinator the tests play, never a real one, key or message.
void main() {
  // The peer, the order's maker: a robot of another Garage Key of the tests, and the key the official client would make for it.
  final makerRobot = switch (NetworkGarageKey(
    RobosatsNetwork.testnet,
    otherTradeKey,
  ).firstUsableRobot(0)) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
  final maker = makerRobot.identity;
  late UnlockedRobotPgpKey makerKey;
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

  /// A random generator whose first [split] draws are [a]'s and the rest [b]'s: with [a] the seed of a key, the same primary key and another encryption subkey, bound by that primary key, as only the holder of its private key can make (review of #139).
  Random spliced(Random a, Random b, int split) => _Spliced(a, b, split);

  UnlockedRobotPgpKey keyWith(RobotIdentity identity, Random random) {
    final key = switch (RobotPgpKey.generateWith(
      identity,
      now: realNow,
      random: random,
    )) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
    return switch (key.unlock(identity)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
  }

  int posts(TradeHarness app) => app.coordinator.requests
      .where((r) => r.url.path == '/api/chat/' && r.body != null)
      .length;

  /// [record] for another robot: the same order, another slot.
  TradeRecord withRobot(TradeRecord record, RobotSlot robot) => TradeRecord(
    robot: robot,
    coordinatorAlias: record.coordinatorAlias,
    coordinatorOnion: record.coordinatorOnion,
    orderId: record.orderId,
    role: record.role,
    origin: record.origin,
    takenAt: record.takenAt,
    confirmedAt: record.confirmedAt,
    closedAt: record.closedAt,
  );

  /// The Nostr keys the order gives, the peer's and this robot's, as the first copy pins them.
  ChatNostrPin nostrKeysOf(TradeSeen seen) => switch (seen.order) {
    CoordinatorOrder(
      makerNostrPublicKeyHex: final peer?,
      takerNostrPublicKeyHex: final own?,
    ) =>
      ChatNostrPin(peer: peer, own: own),
    final other => throw StateError('no Nostr keys: $other'),
  };

  /// The trade's status as a new read of the order stores it.
  Future<TradeSeen> readAgain(TradeHarness app, TradeRecord record) async {
    final run = app.watchOf(record);
    await app.elapse(const Duration(seconds: 11));
    final seen = run.lastStatus.seen;
    await run.subscription.cancel();
    return seen;
  }

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

  ChatView viewOf(Result<ChatView, ChatReadFailure> read) => switch (read) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('read failed: $failure'),
  };

  String forgedKey(int seed) => keyOf(maker, seed).key.publicKey.armored;

  group('the pin kept with the trade', () {
    test(
      'the first read pins the peer\'s key and keeps its two fingerprints, nothing else',
      () async {
        final (app, record, seen) = await atNine();
        expect(
          await app.pins.pinOf(record),
          isA<Ok<ChatPinFingerprints?, P2pFailure>>().having(
            (ok) => ok.value,
            'pin',
            isNull,
          ),
        );
        final view = await read(app, record, seen);
        expect(view.peerKey, isA<ChatPeerKeyPinned>());
        final pin = switch (await app.pins.pinOf(record)) {
          Ok(value: final pin?) => pin,
          final other => throw StateError('$other'),
        };
        expect(pin.primary, makerKey.key.publicKey.fingerprint);
        expect(pin.subkey, makerKey.key.publicKey.subkeyFingerprint);
        expect(pin.subkey, isNot(pin.primary));
        // Kept once: later reads write nothing.
        await read(app, record, seen);
        expect(app.pins.keeps, 1);
        final rows = await app.database
            .customSelect('SELECT * FROM trade_chat_pins')
            .get();
        expect(
          rows.single.data.keys,
          unorderedEquals([
            'key_fingerprint',
            'robot_index',
            'primary_fingerprint',
            'subkey_fingerprint',
          ]),
        );
      },
    );

    test(
      'after a restart the same key is pinned again silently, with no new write',
      () async {
        final (app, record, seen) = await atNine();
        app.coordinator.peerSays(written(app, 'Hello'));
        await read(app, record, seen);
        final (restarted, _) = app.chatAfterRestart();
        final view = viewOf(await restarted.read(record, seen));
        expect(view.peerKey, isA<ChatPeerKeyPinned>());
        expect(view.canSend, isTrue);
        expect(view.entries.single.validSignature, isTrue);
        expect(app.pins.keeps, 1);
      },
    );

    test(
      'after a restart a key forged in the peer\'s name, served on a page with no message of the peer, is the same sticky breach as within one run: nothing leaves',
      () async {
        final (app, record, seen) = await atNine();
        await read(app, record, seen);
        final (restartedRead, restartedSend) = app.chatAfterRestart();
        app.coordinator.peerPublicKey = forgedKey(931);
        final view = viewOf(await restartedRead.read(record, seen));
        expect(view.peerKey, isA<ChatPeerKeyBreach>());
        expect(view.canSend, isFalse);
        final posts = app.coordinator.requests
            .where((r) => r.url.path == '/api/chat/' && r.body != null)
            .length;
        expect(
          await restartedSend.send(record, seen, 'My IBAN'),
          isA<Err<ChatSent, ChatSendRefusal>>().having(
            (e) => e.failure,
            'refusal',
            isA<ChatPeerKeyChanged>(),
          ),
        );
        expect(
          app.coordinator.requests
              .where((r) => r.url.path == '/api/chat/' && r.body != null)
              .length,
          posts,
        );
        // The real key served again: the breach stays, and the pin kept is unchanged.
        app.coordinator.peerPublicKey = makerKey.key.publicKey.armored;
        expect(
          viewOf(await restartedRead.read(record, seen)).peerKey,
          isA<ChatPeerKeyBreach>(),
        );
        expect(
          await app.pins.pinOf(record),
          isA<Ok<ChatPinFingerprints?, P2pFailure>>().having(
            (ok) => ok.value,
            'pin',
            ChatPinFingerprints.of(makerKey.key.publicKey),
          ),
        );
      },
    );

    test('after a restart a key gone is a breach too', () async {
      final (app, record, seen) = await atNine();
      await read(app, record, seen);
      final (restarted, _) = app.chatAfterRestart();
      app.coordinator.peerPublicKey = null;
      expect(
        viewOf(await restarted.read(record, seen)).peerKey,
        isA<ChatPeerKeyBreach>(),
      );
    });

    test(
      'a trade with no pin kept, as one recorded before this change, pins at its first read as before',
      () async {
        final (app, record, seen) = await atNine(peerKey: false);
        final (restarted, _) = app.chatAfterRestart();
        expect(
          viewOf(await restarted.read(record, seen)).peerKey,
          isA<ChatPeerKeyAwaited>(),
        );
        app.coordinator.peerPublicKey = forgedKey(932);
        // The limit of trust on first use, unchanged: no pin kept, the first key is pinned and kept.
        expect(
          viewOf(await restarted.read(record, seen)).peerKey,
          isA<ChatPeerKeyPinned>(),
        );
        expect(app.pins.keeps, 1);
      },
    );

    test(
      'a pin that cannot be read: the read gives nothing and pins nothing; the next one reads it',
      () async {
        final (app, record, seen) = await atNine();
        await read(app, record, seen);
        final (restarted, _) = app.chatAfterRestart();
        app.pins.refuseReads = true;
        app.coordinator.peerPublicKey = forgedKey(933);
        expect(
          await restarted.read(record, seen),
          isA<Err<ChatView, ChatReadFailure>>().having(
            (e) => e.failure,
            'failure',
            isA<ChatReadFailed>(),
          ),
        );
        app.pins.refuseReads = false;
        expect(
          viewOf(await restarted.read(record, seen)).peerKey,
          isA<ChatPeerKeyBreach>(),
        );
      },
    );

    test(
      'a pin that cannot be written stays pinned in this run and is written at a later read',
      () async {
        final (app, record, seen) = await atNine();
        app.pins.refuseWrites = true;
        expect(
          (await read(app, record, seen)).peerKey,
          isA<ChatPeerKeyPinned>(),
        );
        expect(
          await app.pins.pinOf(record),
          isA<Ok<ChatPinFingerprints?, P2pFailure>>().having(
            (ok) => ok.value,
            'pin',
            isNull,
          ),
        );
        app.pins.refuseWrites = false;
        await read(app, record, seen);
        expect(app.pins.keeps, 2);
        expect(
          await app.pins.pinOf(record),
          isA<Ok<ChatPinFingerprints?, P2pFailure>>().having(
            (ok) => ok.value,
            'pin',
            ChatPinFingerprints.of(makerKey.key.publicKey),
          ),
        );
      },
    );

    test(
      'another pin found kept when this run keeps its own is a breach',
      () async {
        final (app, record, seen) = await atNine();
        final other = ChatPinFingerprints.of(keyOf(maker, 934).key.publicKey);
        app.pins.beforeKeep = () async {
          await TradeChatPinRepositoryImpl(app.database).keep(record, other);
        };
        expect(
          (await read(app, record, seen)).peerKey,
          isA<ChatPeerKeyBreach>(),
        );
      },
    );

    test(
      'the repository: written once, never changed, only for an open trade, never read for another trade',
      () async {
        final (app, record, _) = await atNine();
        final repository = TradeChatPinRepositoryImpl(app.database);
        final pin = ChatPinFingerprints.of(makerKey.key.publicKey);
        final other = ChatPinFingerprints.of(keyOf(maker, 935).key.publicKey);
        expect(
          await repository.keep(record, pin),
          isA<Ok<bool, P2pFailure>>().having((ok) => ok.value, 'kept', isTrue),
        );
        expect(
          await repository.keep(record, pin),
          isA<Ok<bool, P2pFailure>>().having((ok) => ok.value, 'kept', isTrue),
        );
        expect(
          await repository.keep(record, other),
          isA<Ok<bool, P2pFailure>>().having((ok) => ok.value, 'kept', isFalse),
        );
        expect(
          await repository.pinOf(record),
          isA<Ok<ChatPinFingerprints?, P2pFailure>>().having(
            (ok) => ok.value,
            'pin',
            pin,
          ),
        );
        await expectLater(
          app.database.customStatement('DELETE FROM trade_chat_pins'),
          throwsA(anything),
        );
        await expectLater(
          app.database.customStatement(
            "UPDATE trade_chat_pins SET primary_fingerprint = ?",
            [other.primary],
          ),
          throwsA(anything),
        );
        // Another robot of the same Garage Key, or the same index of another Garage Key: no pin, and none can be written, for they have no open trade.
        for (final stranger in [
          withRobot(
            record,
            RobotSlot(
              record.network,
              record.robot.keyFingerprint,
              record.robot.accountIndex + 1,
            ),
          ),
          withRobot(
            record,
            RobotSlot(
              record.network,
              makerRobot.keyFingerprint,
              record.robot.accountIndex,
            ),
          ),
        ]) {
          expect(
            await repository.pinOf(stranger),
            isA<Ok<ChatPinFingerprints?, P2pFailure>>().having(
              (ok) => ok.value,
              'pin',
              isNull,
            ),
          );
          expect(
            await repository.nostrPinOf(stranger),
            isA<Ok<ChatNostrPin?, P2pFailure>>().having(
              (ok) => ok.value,
              'pin',
              isNull,
            ),
          );
          expect(
            await repository.keep(stranger, pin),
            isA<Err<bool, P2pFailure>>(),
          );
        }
      },
    );

    test(
      'the repository: a closed trade\'s pin is a storage failure, and nothing is written',
      () async {
        final (app, record, _) = await atNine();
        await app.database.customStatement(
          'UPDATE trades SET closed_at = 1 WHERE key_fingerprint = ? AND robot_index = ?',
          [record.robot.keyFingerprint.hex, record.robot.accountIndex],
        );
        final repository = TradeChatPinRepositoryImpl(app.database);
        expect(
          await repository.keep(
            record,
            ChatPinFingerprints.of(makerKey.key.publicKey),
          ),
          isA<Err<bool, P2pFailure>>().having(
            (e) => e.failure,
            'failure',
            isA<P2pStorageFailure>(),
          ),
        );
        expect(
          await repository.keepNostr(record, ChatNostrPin(peer: 'a' * 64, own: 'b' * 64)),
          isA<Err<bool, P2pFailure>>(),
        );
        expect(
          await app.database.customSelect('SELECT * FROM trade_chat_pins').get(),
          isEmpty,
        );
        expect(
          await app.database
              .customSelect('SELECT * FROM trade_chat_nostr_pins')
              .get(),
          isEmpty,
        );
      },
    );

    test(
      'after a restart a key with the pinned primary key and another encryption subkey, bound by that primary key, is a breach: nothing leaves',
      () async {
        final sibling = keyWith(maker, spliced(Random(93), Random(4242), 32));
        expect(
          sibling.key.publicKey.fingerprint,
          makerKey.key.publicKey.fingerprint,
        );
        expect(
          sibling.key.publicKey.subkeyFingerprint,
          isNot(makerKey.key.publicKey.subkeyFingerprint),
        );
        final (app, record, seen) = await atNine();
        await read(app, record, seen);
        final (restartedRead, restartedSend) = app.chatAfterRestart();
        app.coordinator.peerPublicKey = sibling.key.publicKey.armored;
        expect(
          viewOf(await restartedRead.read(record, seen)).peerKey,
          isA<ChatPeerKeyBreach>(),
        );
        final before = posts(app);
        expect(
          await restartedSend.send(record, seen, 'My IBAN'),
          isA<Err<ChatSent, ChatSendRefusal>>(),
        );
        expect(posts(app), before);
      },
    );

    test('after a restart a key that cannot be read is a breach too', () async {
      final (app, record, seen) = await atNine();
      await read(app, record, seen);
      final (restarted, _) = app.chatAfterRestart();
      app.coordinator.peerPublicKey = 'not a key';
      expect(
        viewOf(await restarted.read(record, seen)).peerKey,
        isA<ChatPeerKeyBreach>(),
      );
    });

    test(
      'no pin kept, a key forged in the page of a message the peer signed with its real key: a breach, and no pin is written',
      () async {
        final (app, record, seen) = await atNine(peerKey: false);
        app.coordinator.peerSays(written(app, 'Hello'));
        app.coordinator.peerPublicKey = forgedKey(936);
        expect(
          (await read(app, record, seen)).peerKey,
          isA<ChatPeerKeyBreach>(),
        );
        expect(app.pins.keeps, 0);
        expect(
          await app.pins.pinOf(record),
          isA<Ok<ChatPinFingerprints?, P2pFailure>>().having(
            (ok) => ok.value,
            'pin',
            isNull,
          ),
        );
      },
    );

    test(
      'no message is posted while the pin is not kept: the send is refused as « not sent », and goes once a read kept the pin (review of #139)',
      () async {
        final (app, record, seen) = await atNine();
        app.pins.refuseWrites = true;
        expect(
          (await read(app, record, seen)).peerKey,
          isA<ChatPeerKeyPinned>(),
        );
        final before = posts(app);
        expect(
          await app.chatSend.send(record, seen, 'Hello'),
          isA<Err<ChatSent, ChatSendRefusal>>().having(
            (e) => e.failure,
            'refusal',
            isA<ChatSendUnavailable>().having(
              (u) => u.cause,
              'cause',
              isA<P2pStorageFailure>(),
            ),
          ),
        );
        expect(posts(app), before);
        await pumpEventQueue();
        expect(app.relays.published, isEmpty);
        // Not kept, a restart would trust whatever key is served: so nothing went.
        app.pins.refuseWrites = false;
        await read(app, record, seen);
        expect(
          await app.chatSend.send(record, seen, 'Hello'),
          isA<Ok<ChatSent, ChatSendRefusal>>(),
        );
        expect(posts(app), before + 1);
      },
    );
  });

  group('the Nostr keys kept with the trade (part of #159)', () {
    test(
      'kept before the first copy is published, once, with the keys the order gives',
      () async {
        final (app, record, seen) = await atNine();
        await read(app, record, seen);
        expect(
          await app.chatSend.send(record, seen, 'First'),
          isA<Ok<ChatSent, ChatSendRefusal>>(),
        );
        await pumpEventQueue();
        expect(app.relays.messages, hasLength(1));
        expect(
          await app.pins.nostrPinOf(record),
          isA<Ok<ChatNostrPin?, P2pFailure>>().having(
            (ok) => ok.value,
            'pin',
            nostrKeysOf(seen),
          ),
        );
        await app.chatSend.send(record, seen, 'Second');
        await pumpEventQueue();
        expect(app.relays.messages, hasLength(2));
        expect(app.pins.nostrKeeps, 1);
        final rows = await app.database
            .customSelect('SELECT * FROM trade_chat_nostr_pins')
            .get();
        expect(
          rows.single.data.keys,
          unorderedEquals([
            'key_fingerprint',
            'robot_index',
            'peer_key',
            'own_key',
          ]),
        );
      },
    );

    test(
      'after a restart the same keys go on with no new write; a key the order then changes stops every copy, the coordinator still gets the messages',
      () async {
        final (app, record, seen) = await atNine();
        await read(app, record, seen);
        await app.chatSend.send(record, seen, 'First');
        await pumpEventQueue();
        final (restartedRead, restartedSend) = app.chatAfterRestart();
        viewOf(await restartedRead.read(record, seen));
        await restartedSend.send(record, seen, 'Second');
        await pumpEventQueue();
        expect(app.relays.messages, hasLength(2));
        expect(app.pins.nostrKeeps, 1);

        final (againRead, againSend) = app.chatAfterRestart();
        // Another valid key: the x-only key of the secret key 2, public.
        app.coordinator.makerNostrPublicKey =
            'c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5';
        final changed = await readAgain(app, record);
        expect(
          changed.order?.makerNostrPublicKeyHex,
          app.coordinator.makerNostrPublicKey,
        );
        viewOf(await againRead.read(record, changed));
        expect(
          await againSend.send(record, changed, 'Third'),
          isA<Ok<ChatSent, ChatSendRefusal>>(),
        );
        await pumpEventQueue();
        expect(app.relays.messages, hasLength(2));
        expect(app.coordinator.chat, hasLength(3));
        expect(app.pins.nostrKeeps, 1);
      },
    );

    test(
      'Nostr keys that cannot be read: the read gives nothing; the next one reads them',
      () async {
        final (app, record, seen) = await atNine();
        await read(app, record, seen);
        await app.chatSend.send(record, seen, 'First');
        await pumpEventQueue();
        final (restartedRead, restartedSend) = app.chatAfterRestart();
        app.pins.refuseNostrReads = true;
        expect(
          await restartedRead.read(record, seen),
          isA<Err<ChatView, ChatReadFailure>>().having(
            (e) => e.failure,
            'failure',
            isA<ChatReadFailed>(),
          ),
        );
        app.pins.refuseNostrReads = false;
        app.coordinator.makerNostrPublicKey =
            'c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5';
        final changed = await readAgain(app, record);
        viewOf(await restartedRead.read(record, changed));
        await restartedSend.send(record, changed, 'Second');
        await pumpEventQueue();
        expect(app.relays.messages, hasLength(1));
      },
    );

    test(
      'Nostr keys that cannot be written: no copy leaves; the next copy writes them and leaves',
      () async {
        final (app, record, seen) = await atNine();
        await read(app, record, seen);
        app.pins.refuseNostrWrites = true;
        expect(
          await app.chatSend.send(record, seen, 'First'),
          isA<Ok<ChatSent, ChatSendRefusal>>(),
        );
        await pumpEventQueue();
        expect(app.relays.published, isEmpty);
        expect(app.coordinator.chat, hasLength(1));
        app.pins.refuseNostrWrites = false;
        await app.chatSend.send(record, seen, 'Second');
        await pumpEventQueue();
        expect(app.relays.messages, hasLength(1));
        expect(app.pins.nostrKeeps, 2);
        expect(
          await app.pins.nostrPinOf(record),
          isA<Ok<ChatNostrPin?, P2pFailure>>().having(
            (ok) => ok.value,
            'pin',
            nostrKeysOf(seen),
          ),
        );
      },
    );

    test(
      'other Nostr keys found kept when this run keeps its own: no copy leaves, now or later, and the kept keys stay',
      () async {
        final (app, record, seen) = await atNine();
        await read(app, record, seen);
        final other = ChatNostrPin(
          peer:
              'c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5',
          own: nostrKeysOf(seen).own,
        );
        expect(
          await TradeChatPinRepositoryImpl(
            app.database,
          ).keepNostr(record, other),
          isA<Ok<bool, P2pFailure>>().having((ok) => ok.value, 'kept', isTrue),
        );
        await app.chatSend.send(record, seen, 'First');
        await app.chatSend.send(record, seen, 'Second');
        await pumpEventQueue();
        expect(app.relays.published, isEmpty);
        expect(app.coordinator.chat, hasLength(2));
        expect(
          await app.pins.nostrPinOf(record),
          isA<Ok<ChatNostrPin?, P2pFailure>>().having(
            (ok) => ok.value,
            'pin',
            other,
          ),
        );
      },
    );

    test(
      'the repository: written once, never changed, true for the same keys, false for others',
      () async {
        final (app, record, seen) = await atNine();
        final repository = TradeChatPinRepositoryImpl(app.database);
        final pin = nostrKeysOf(seen);
        final other = ChatNostrPin(peer: 'c' * 64, own: pin.own);
        for (final (keys, kept) in [(pin, true), (pin, true), (other, false)]) {
          expect(
            await repository.keepNostr(record, keys),
            isA<Ok<bool, P2pFailure>>().having(
              (ok) => ok.value,
              'kept',
              kept,
            ),
          );
        }
        expect(
          await repository.nostrPinOf(record),
          isA<Ok<ChatNostrPin?, P2pFailure>>().having(
            (ok) => ok.value,
            'pin',
            pin,
          ),
        );
      },
    );
  });
}

/// The first [split] draws from [a], the rest from [b].
final class _Spliced implements Random {
  final Random a;
  final Random b;
  final int split;
  int _drawn = 0;

  _Spliced(this.a, this.b, this.split);

  @override
  int nextInt(int max) => (_drawn++ < split ? a : b).nextInt(max);

  @override
  bool nextBool() => throw UnsupportedError('not drawn by the key');

  @override
  double nextDouble() => throw UnsupportedError('not drawn by the key');
}
