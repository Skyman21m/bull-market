import 'dart:async';
import 'dart:math';

import 'package:p2p/src/domain/trade/trade_chat.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/key_output.dart';
import 'support/trade_harness.dart';

/// The chat's export (#93), as the official client's « Export » and « Don't trust, verify » give it, the owner's choice: over the coordinator the tests play and robots of the tests' Garage Keys, never a real one.
void main() {
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

  test(
    'the credentials as the reference names them, the robot\'s token as the passphrase, and every message; the lease closed, nothing printed',
    () async {
      final (app, record, seen) = await atNine();
      app.coordinator.peerSays(written(app, 'Hello'));
      await read(app, record, seen);
      final output = await captureKeyOutput(() async {
        final exported = switch (await app.chatExport.execute(record)) {
          Ok(:final value) => value,
          Err(:final failure) => throw StateError('$failure'),
        };
        final credentials = exported['credentials']! as Map<String, Object?>;
        expect(credentials.keys, [
          'own_public_key',
          'peer_public_key',
          'encrypted_private_key',
          'passphrase',
        ]);
        expect(credentials['own_public_key'], ourKey(app).armored);
        expect(credentials['peer_public_key'], makerKey.key.publicKey.armored);
        expect(credentials['passphrase'], app.robot(0).token.reveal());
        expect(
          '${credentials['encrypted_private_key']}',
          startsWith('-----BEGIN PGP PRIVATE KEY BLOCK-----'),
        );
        final messages = exported['messages']! as List<Object?>;
        final hello = messages.single! as Map<String, Object?>;
        expect(hello.keys, [
          'index',
          'encryptedMessage',
          'plainTextMessage',
          'validSignature',
          'userNick',
          'time',
        ]);
        expect(hello['plainTextMessage'], 'Hello');
        expect(hello['validSignature'], isTrue);
        expect(hello['userNick'], maker.nickname);
      });
      expect(output.contains(app.robot(0).token.reveal()), isFalse);
      expect(output.contains('Hello'), isFalse);
      expect(app.keyring.keepsKeyOf(record.robot), isFalse);
    },
  );

  test(
    'with the key held as the shown chat panel holds it: the export asks the coordinator nothing and gives the messages the watch already decrypted (#157)',
    () async {
      final (app, record, seen) = await atNine();
      // The chat panel's cubit holds the key while it is shown, and its reads lease it.
      final hold = app.holdKey.execute(record);
      app.coordinator.peerSays(written(app, 'Hello'));
      await read(app, record, seen);
      final asked = app.coordinator.received.length;
      final exported = switch (await app.chatExport.execute(record)) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };
      // Neither the chat read again nor the robot read again for its key.
      expect(app.coordinator.received.skip(asked), isEmpty);
      final messages = exported['messages']! as List<Object?>;
      expect(
        (messages.single! as Map<String, Object?>)['plainTextMessage'],
        'Hello',
      );
      hold.release();
      expect(app.keyring.keepsKeyOf(record.robot), isFalse);
    },
  );

  test('a robot\'s key that cannot be had: no export', () async {
    final (app, record, seen) = await atNine();
    await read(app, record, seen);
    app.keys.unlockFailure = const RobotKeyComputeFailure();
    expect(
      await app.chatExport.execute(record),
      isA<Err<Map<String, Object?>, ChatReadFailure>>().having(
        (e) => e.failure,
        'failure',
        isA<ChatTradeUnavailable>(),
      ),
    );
  });
}
