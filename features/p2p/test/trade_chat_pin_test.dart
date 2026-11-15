import 'dart:async';
import 'dart:math';

import 'package:p2p/src/data/trade_chat_pin_repository_impl.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
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
  final maker = switch (NetworkGarageKey(
    RobosatsNetwork.testnet,
    otherTradeKey,
  ).firstUsableRobot(0)) {
    Ok(:final value) => value.identity,
    Err(:final failure) => throw StateError('$failure'),
  };
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
      'the repository: written once, never changed, only for an open trade',
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
      },
    );
  });
}
