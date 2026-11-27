import 'dart:convert';

import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/trade/trade_host_rating.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/testing.dart' show ScriptedFault, ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/signed_bodies.dart';
import 'support/trade_harness.dart';

/// « Rate your host » (#95): the token of `POST /api/review/` and the event of kind 31986 on the relays, as the official client asks and publishes them (`TradeBox/Prompts/Successful.tsx:54-105`, commit ff1998c), over the coordinator the tests play and relays the tests record, never a real one.
void main() {
  int sent(TradeHarness app, ScriptedRequest kind) =>
      app.coordinator.received.where((k) => k == kind).length;

  /// A trade taken on a fresh run, its bond locked, moved to [status], and that status as a read stored it.
  Future<(TradeHarness, TradeRecord, TradeSeen)> at({
    int status = 14,
    int orderId = 42,
    String alias = 'temple',
    RobosatsNetwork network = RobosatsNetwork.testnet,
  }) async {
    final app = await TradeHarness.start(
      orderId: orderId,
      alias: alias,
      network: network,
    );
    final taken = await app.takeShown();
    expect(taken, isA<Ok<TakeOutcome, TakeRefusal>>());
    final record = TradeHarness.recordOf(taken);
    final run = app.watchOf(record);
    await app.settle();
    app.coordinator
      ..lockBond(app.robot(0))
      ..moveTo(status);
    await app.elapse(const Duration(seconds: 5));
    final last = run.lastStatus;
    await run.subscription.cancel();
    return (app, last.record, last.seen);
  }

  HostReviewToken tokenOf(Result<HostReviewToken, HostTokenNotGiven> result) =>
      switch (result) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };

  HostRating stars(int n) => HostRating.of(n) ?? fail('no rating');

  final notGiven = isA<Err<HostReviewToken, HostTokenNotGiven>>();

  group('the token', () {
    test(
      'asked once from 14 with the robot\'s Nostr key and short header',
      () async {
        final (app, record, finished) = await at();
        app.coordinator.requests.clear();
        final token = tokenOf(await app.rateHost.fetchToken(record, finished));
        final robot = app.robot(0);
        final key = robot.nostrKeyPair().publicKeyHex;
        expect(token.hex, app.coordinator.reviewToken(key));
        // The robot read back first, for the key the request is signed with (GHSA-22q8-9ghc-jg3h), then the request once.
        expect(app.coordinator.requests.map((r) => r.url.path), [
          '/api/robot/',
          '/api/review/',
        ]);
        final request = app.coordinator.requests.last;
        expect(request.method, CoordinatorHttpMethod.post);
        expect(request.url.path, '/api/review/');
        expect(request.robot, robot.sessionKey);
        expect(request.headers['Authorization'], robot.authorizationHeader());
        expect(jsonDecode(unsignedBodyOf(request.body)), {'pubkey': key});
        expect(app.relays.published, isEmpty);
      },
    );

    test(
      'a busy transport is tried again, as every request of a robot',
      () async {
        final (app, record, finished) = await at();
        app.coordinator.failNext(ScriptedRequest.review, ScriptedFault.busy);
        expect(
          await app.rateHost.fetchToken(record, finished),
          isA<Ok<HostReviewToken, HostTokenNotGiven>>(),
        );
        expect(sent(app, ScriptedRequest.review), 2);
      },
    );

    test(
      'not given: refused (1052), unreachable, or of another form',
      () async {
        final (app, record, finished) = await at();
        app.coordinator.moveTo(13);
        expect(await app.rateHost.fetchToken(record, finished), notGiven);
        app.coordinator.moveTo(14);
        app.coordinator.failNext(
          ScriptedRequest.review,
          ScriptedFault.unreachable,
        );
        expect(await app.rateHost.fetchToken(record, finished), notGiven);
        for (final wrong in <Object>[
          '',
          'ab' * 63,
          ('ab' * 64).toUpperCase(),
          '${'ab' * 63}"]',
        ]) {
          app.coordinator.reviewTokenOverride = wrong;
          expect(
            await app.rateHost.fetchToken(record, finished),
            notGiven,
            reason: '$wrong',
          );
        }
        expect(sent(app, ScriptedRequest.review), 6);
      },
    );

    test('not asked for a status that does not offer the rating', () async {
      final (app, record, nine) = await at(status: 9);
      app.coordinator.requests.clear();
      expect(await app.rateHost.fetchToken(record, nine), notGiven);
      final (finishedApp, finishedRecord, finished) = await at();
      finishedApp.coordinator.requests.clear();
      expect(
        await finishedApp.rateHost.fetchToken(
          finishedRecord,
          TradeSeen(finished.status, order: null),
        ),
        notGiven,
      );
      expect(app.coordinator.requests, isEmpty);
      expect(finishedApp.coordinator.requests, isEmpty);
    });

    test(
      'neither asked nor published for the same order number on another coordinator or network',
      () async {
        final (app, record, finished) = await at();
        final token = tokenOf(await app.rateHost.fetchToken(record, finished));
        final (_, _, lake) = await at(alias: 'lake');
        final (_, _, mainnet) = await at(network: RobosatsNetwork.mainnet);
        for (final (name, other) in [('lake', lake), ('mainnet', mainnet)]) {
          expect(other.order?.id, record.orderId, reason: name);
          app.coordinator.requests.clear();
          expect(
            await app.rateHost.fetchToken(record, other),
            notGiven,
            reason: name,
          );
          await app.rateHost.publish(record, other, token, stars(5));
          expect(app.coordinator.requests, isEmpty, reason: name);
        }
        expect(lake.order?.coordinator.shortAlias, 'lake');
        expect(mainnet.order?.network, RobosatsNetwork.mainnet);
        expect(app.relays.published, isEmpty);
        expect(app.keys.rated, isEmpty);
      },
    );

    test(
      'neither asked nor published for the order of another trade',
      () async {
        final (app, record, finished) = await at();
        final token = tokenOf(await app.rateHost.fetchToken(record, finished));
        final (_, _, otherSeen) = await at(orderId: 43);
        expect(otherSeen.order?.id, 43);
        app.coordinator.requests.clear();
        expect(await app.rateHost.fetchToken(record, otherSeen), notGiven);
        await app.rateHost.publish(record, otherSeen, token, stars(5));
        expect(app.coordinator.requests, isEmpty);
        expect(app.relays.published, isEmpty);
        expect(app.keys.rated, isEmpty);
      },
    );
  });

  group('the rating', () {
    test(
      'one event of kind 31986 per tap, the reference\'s, on the relays of the pool',
      () async {
        final (app, record, finished) = await at();
        final token = tokenOf(await app.rateHost.fetchToken(record, finished));
        final robot = app.robot(0);
        final temple = Federation.robosats.coordinators.firstWhere(
          (c) => c.shortAlias == 'temple',
        );
        await app.rateHost.publish(record, finished, token, stars(4));
        final relays = [for (final p in app.relays.published) p.relay];
        expect(
          relays.first,
          OutgoingNostrChatMessage.relayUrl(temple, record.network),
        );
        expect(relays.toSet(), hasLength(relays.length));
        final withRelay = Federation.robosats.coordinators
            .where(
              (c) =>
                  OutgoingNostrChatMessage.relayUrl(c, record.network) != null,
            )
            .length;
        expect(relays, hasLength(withRelay < 3 ? withRelay : 3));
        expect(
          app.relays.published.map((p) => p.robot),
          everyElement(robot.sessionKey),
        );
        final rating = app.relays.hostRatings.single;
        final event =
            (jsonDecode(rating.relayMessages.single) as List<dynamic>)[1]
                as Map<String, dynamic>;
        expect(event['kind'], 31986);
        expect(event['content'], '');
        expect(event['pubkey'], robot.nostrKeyPair().publicKeyHex);
        expect(event['created_at'], app.now.millisecondsSinceEpoch ~/ 1000);
        expect(event['tags'], [
          ['sig', token.hex],
          ['d', 'temple:${record.orderId}'],
          ['p', temple.nostrHexPubkey],
          ['rating', '0.8'],
        ]);
        expect(rating.eventIds, [event['id']]);
        // Each tap publishes once more, the same stars included; nothing is asked of the coordinator for it.
        final asked = sent(app, ScriptedRequest.review);
        await app.rateHost.publish(record, finished, token, stars(4));
        await app.rateHost.publish(record, finished, token, stars(1));
        expect(app.relays.hostRatings, hasLength(3));
        expect(app.keys.rated, hasLength(3));
        expect(sent(app, ScriptedRequest.review), asked);
      },
    );

    test('nothing published when the event could not be composed', () async {
      final (app, record, finished) = await at();
      final token = tokenOf(await app.rateHost.fetchToken(record, finished));
      app.keys.rateFailure = const RobotKeyComputeFailure();
      await app.rateHost.publish(record, finished, token, stars(5));
      expect(app.relays.published, isEmpty);
    });

    test(
      'nothing published for a status that does not offer the rating',
      () async {
        final (app, record, finished) = await at();
        final token = tokenOf(await app.rateHost.fetchToken(record, finished));
        await app.rateHost.publish(
          record,
          TradeSeen(finished.status, order: null),
          token,
          stars(5),
        );
        expect(app.relays.published, isEmpty);
        expect(app.keys.rated, isEmpty);
      },
    );
  });
}
