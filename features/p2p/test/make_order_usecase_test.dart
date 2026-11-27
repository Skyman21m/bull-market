import 'dart:async';
import 'dart:convert';

import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/trade_trail_repository.dart';
import 'package:p2p/src/domain/trade/active_trade.dart';
import 'package:p2p/src/domain/trade/make_price_check.dart';
import 'package:p2p/src/domain/trade/maker_terms.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_storable.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/testing.dart' show ScriptedFault, ScriptedMakerRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/make_harness.dart';
import 'support/robot_coordinators.dart' show pairOf;
import 'support/trade_harness.dart' show AppKilled;
import 'support/signed_bodies.dart';

/// The make use case (#179, design note `docs/design/phase-3-making-an-order.md` § 3.4): the order made once, written before it leaves, confirmed only by a read that shows the robot as its maker, and never lost when its answer is.
void main() {
  T valueOf<T>(Result<T, Failure> result) => switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => fail('$failure'),
  };

  MakeStarted started(Result<MakeOutcome, MakeRefusal> made) =>
      switch (valueOf(made)) {
        final MakeStarted value => value,
        final other => fail('not started: $other'),
      };

  int makes(MakeHarness harness) => harness.coordinator.received
      .where((kind) => kind == ScriptedMakerRequest.make)
      .length;

  group('a make answered', () {
    test(
      'reads the coordinator anonymously once, writes the make and its terms before it leaves, sends the terms once, and starts the trade from the robot\'s read',
      () async {
        final harness = await MakeHarness.start();
        // The make held on its way, the records read while it is: the pending make and its terms are on disk before it leaves.
        final release = Completer<void>();
        harness.coordinator.holdMake = release.future;
        final making = harness.makeOrder();
        await harness.settle();
        expect(makes(harness), 1);
        final pendingAtSend = await harness.pendingMakes();
        expect(pendingAtSend, hasLength(1));
        final termsAtSend = valueOf(
          await harness.trails.makerTermsOf(pendingAtSend.single.robot),
        );
        expect(termsAtSend, isNotNull);
        expect(await harness.activeRecords(), isEmpty);
        release.complete();
        final outcome = started(await making);
        expect(outcome.stored, isTrue);
        expect(outcome.status, isA<WaitingForMakerBond>());
        expect(outcome.status.warnings, isEmpty);
        expect(outcome.record.origin, TradeOrigin.madeHere);
        expect(outcome.record.orderId, 42);
        expect(outcome.record.confirmedAt, isNotNull);
        expect(outcome.record.closedAt, isNull);

        // Info and limits once each, before any robot, and anonymous.
        final requests = harness.coordinator.requests;
        final info = requests.where((r) => r.url.path == '/api/info/');
        final limits = requests.where((r) => r.url.path == '/api/limits/');
        expect(info, hasLength(1));
        expect(limits, hasLength(1));
        for (final read in [...info, ...limits]) {
          expect(read.robot, isNull);
          expect(
            read.headers.keys.map((k) => k.toLowerCase()),
            isNot(contains('authorization')),
          );
        }
        final firstRobot = requests.indexWhere((r) => r.robot != null);
        expect(requests.indexOf(info.single), lessThan(firstRobot));
        expect(requests.indexOf(limits.single), lessThan(firstRobot));
        expect(makes(harness), 1);

        // What was sent is exactly the terms' request, as stored.
        final make = requests.singleWhere((r) => r.url.path == '/api/make/');
        final terms = valueOf(
          await harness.trails.makerTermsOf(outcome.record.robot),
        );
        final restored = valueOf(MakerTerms.restore(terms!));
        // The reference client's body (`Order.make`, `frontend/src/models/Order.model.ts:196-215`), its 17 keys in its order, built from the terms stored.
        final sent = jsonDecode(unsignedBodyOf(make.body));
        expect(sent, {
          'type': restored.request.type.wire,
          'currency': restored.request.currency.id,
          'amount': 100,
          'has_range': false,
          'min_amount': null,
          'max_amount': null,
          'payment_method': restored.request.paymentMethod,
          'is_explicit': false,
          'premium': 2,
          'satoshis': null,
          'public_duration': restored.request.publicDuration.inSeconds,
          'escrow_duration': restored.request.escrowDuration.inSeconds,
          'bond_size': 3,
          'latitude': null,
          'longitude': null,
          'password': null,
          'description': null,
        });
        expect((sent as Map).keys.toList(), [
          'type',
          'currency',
          'amount',
          'has_range',
          'min_amount',
          'max_amount',
          'payment_method',
          'is_explicit',
          'premium',
          'satoshis',
          'public_duration',
          'escrow_duration',
          'bond_size',
          'latitude',
          'longitude',
          'password',
          'description',
        ]);
        expect(restored.request, MakeHarness.request());
        expect(restored.createdPrice, 91711.15);
        expect(restored.makerFee, 0.00025);

        // Its trail, from the first read.
        final trail = await harness.trailOf(outcome.record);
        expect(trail?.position, TradePosition.makerBondStep.name);
        expect(harness.coordinator.order(42).bond, isNotNull);
        expect(await harness.pendingMakes(), isEmpty);
        expect(await harness.activeRecords(), [outcome.record]);
        expect(terms, termsAtSend);
      },
    );
  });

  group('a make refused before any robot', () {
    Future<void> refusedWithoutRobot(
      MakeHarness harness,
      Matcher refusal, {
      MakeOrderRequest? request,
      MakePriceSeen? seen,
    }) async {
      final made = await harness.makeOrder(request, seen);
      expect(made, isA<Err<MakeOutcome, MakeRefusal>>());
      expect((made as Err<MakeOutcome, MakeRefusal>).failure, refusal);
      // No robot was reserved or contacted, no record written, no make sent.
      expect(
        harness.coordinator.requests.where((r) => r.robot != null),
        isEmpty,
      );
      expect(await harness.allTrades(), isEmpty);
      expect(makes(harness), 0);
    }

    test('when /api/info/ cannot be read', () async {
      final harness = await MakeHarness.start();
      harness.coordinator.failNext(
        ScriptedMakerRequest.info,
        ScriptedFault.unreachable,
      );
      await refusedWithoutRobot(harness, isA<MakeCoordinatorUnreadable>());
    });

    test('when /api/limits/ cannot be read', () async {
      final harness = await MakeHarness.start();
      harness.coordinator.failNext(
        ScriptedMakerRequest.limits,
        ScriptedFault.timedOut,
      );
      await refusedWithoutRobot(harness, isA<MakeCoordinatorUnreadable>());
    });

    test('when /api/limits/ has no price for the currency', () async {
      final harness = await MakeHarness.start();
      await refusedWithoutRobot(
        harness,
        isA<MakePriceUnknown>(),
        request: MakeHarness.request(currency: RobosatsCurrency.fromId(1)),
      );
    });

    test('when the maker fee is above its ceiling of 1 %', () async {
      final harness = await MakeHarness.start();
      harness.coordinator.makerFee = 0.0101;
      await refusedWithoutRobot(
        harness,
        isA<MakeTermsRefused>().having(
          (r) => r.reason,
          'reason',
          isA<MakerFeeTooHigh>(),
        ),
      );
    });

    test('when the price is extravagant, too high or too low', () async {
      for (final price in [1e15, 0.00009]) {
        final harness = await MakeHarness.start();
        harness.coordinator.prices[2] = price;
        await refusedWithoutRobot(
          harness,
          isA<MakeTermsRefused>().having(
            (r) => r.reason,
            'reason',
            isA<MakerTermsUnusable>(),
          ),
        );
      }
    });

    test(
      'when the price check seen was of another currency, even at the same price (second security review of #181, R11)',
      () async {
        final harness = await MakeHarness.start();
        await refusedWithoutRobot(
          harness,
          isA<MakePriceCheckChanged>(),
          seen: MakePriceSeen.of(
            currency: RobosatsCurrency.fromId(1) ?? (throw StateError('USD')),
            coordinatorPrice: harness.coordinator.prices[2] ?? 0,
          ),
        );
        // The same seen of the request's currency: made.
        expect(
          await harness.makeOrder(
            null,
            MakePriceSeen.of(
              currency: MakeHarness.request().currency,
              coordinatorPrice: harness.coordinator.prices[2] ?? 0,
            ),
          ),
          isA<Ok<MakeOutcome, MakeRefusal>>(),
        );
      },
    );

    test('when the amount is outside the limits of the form', () async {
      for (final amount in [19, 5000]) {
        final harness = await MakeHarness.start();
        await refusedWithoutRobot(
          harness,
          isA<MakeAmountOutsideLimits>(),
          request: MakeHarness.request(amount: amount.toDouble()),
        );
      }
    });
  });

  group('a make refused by the coordinator', () {
    for (final (code, why) in [
      (null, 'the empty 400 of its form check'),
      (1000, 'the robot already in an order'),
      (1004, 'an order too big'),
      (1037, 'its book full'),
    ]) {
      test('closes the pending make, never sends again: $why', () async {
        final harness = await MakeHarness.start();
        harness.coordinator.refuseNextMake(code);
        final outcome = valueOf(await harness.makeOrder());
        expect(outcome, isA<MakeNotMade>());
        final notMade = outcome as MakeNotMade;
        expect(notMade.make.closedAt, isNotNull);
        expect(notMade.closeProblem, isNull);
        expect(await harness.pendingMakes(), isEmpty);
        expect(await harness.activeRecords(), isEmpty);
        expect(makes(harness), 1);
        expect(harness.coordinator.orders, isEmpty);
      });
    }

    test(
      'a busy transport sends it again once a place is free: one make reaches the coordinator',
      () async {
        final harness = await MakeHarness.start();
        harness.coordinator.failNext(
          ScriptedMakerRequest.make,
          ScriptedFault.busy,
        );
        started(await harness.makeOrder());
        expect(harness.coordinator.orders, hasLength(1));
      },
    );
  });

  group('a make whose answer was lost', () {
    test(
      'stays pending, and its resolution finds the order the robot made: never a second make',
      () async {
        final harness = await MakeHarness.start();
        harness.coordinator.failNext(
          ScriptedMakerRequest.make,
          ScriptedFault.answerLost,
        );
        final outcome = valueOf(await harness.makeOrder());
        expect(outcome, isA<MakePending>());
        expect(
          (outcome as MakePending).reason,
          MakePendingReason.outcomeUnknown,
        );
        expect(await harness.activeRecords(), isEmpty);
        final pending = (await harness.pendingMakes()).single;
        final resolved = await harness.make.resolve(pending);
        expect(resolved, isA<MakeStarted>());
        final start = resolved as MakeStarted;
        expect(start.record.orderId, 42);
        expect(start.status, isA<WaitingForMakerBond>());
        expect(start.stored, isTrue);
        expect(makes(harness), 1);
        expect(await harness.pendingMakes(), isEmpty);
      },
    );

    test(
      'a make that did nothing is closed once the robot, read after it, names no order',
      () async {
        final harness = await MakeHarness.start();
        harness.coordinator.failNext(
          ScriptedMakerRequest.make,
          ScriptedFault.timedOut,
        );
        expect(valueOf(await harness.makeOrder()), isA<MakePending>());
        final resolved = await harness.make.resolve(
          (await harness.pendingMakes()).single,
        );
        expect(resolved, isA<MakeNotMade>());
        expect((resolved as MakeNotMade).make.closedAt, isNotNull);
        expect(await harness.pendingMakes(), isEmpty);
        expect(makes(harness), 1);
      },
    );

    test(
      'a make that lands after the app concluded there was none makes an order at 0 never shown, expired in 300 s, nothing paid',
      () async {
        final harness = await MakeHarness.start();
        harness.coordinator.failNext(
          ScriptedMakerRequest.make,
          ScriptedFault.landsLate,
        );
        expect(valueOf(await harness.makeOrder()), isA<MakePending>());
        final pending = (await harness.pendingMakes()).single;
        expect(await harness.make.resolve(pending), isA<MakeNotMade>());
        final robotOfMake = harness.coordinator.requests
            .singleWhere((r) => r.url.path == '/api/make/')
            .robot;

        // The request lands now: the coordinator makes the order, waiting at 0 for a bond nobody asked for.
        harness.coordinator.landLate();
        final orphan = harness.coordinator.order(42);
        expect(orphan.status, 0);
        expect(orphan.bond, isNull);
        final requestsBefore = harness.coordinator.requests.length;
        await harness.elapse(const Duration(seconds: 306));
        harness.coordinator.clean();
        expect(orphan.status, 5);
        expect(orphan.expiryReason, 1);
        // No bond invoice was ever made (it is made at the maker's first read), so none was shown or paid; the app sent nothing more.
        expect(orphan.bond, isNull);
        expect(harness.coordinator.requests.length, requestsBefore);
        // The make stays closed, and its robot is never used again: a resolution of the make as it was listed sends nothing.
        expect(await harness.make.resolve(pending), isA<MakeNoLongerPending>());
        expect(harness.coordinator.requests.length, requestsBefore);
        expect(await harness.pendingMakes(), isEmpty);
        started(await harness.makeOrder());
        final second = harness.coordinator.requests
            .where((r) => r.url.path == '/api/make/')
            .last
            .robot;
        expect(second, isNot(robotOfMake));
        expect(makes(harness), 2);
      },
    );

    test(
      'a 201 that differs from what was sent is an outcome unknown, resolved by the robot',
      () async {
        final harness = await MakeHarness.start();
        harness.coordinator.makeAnswerChanges.add({'premium': '3.00'});
        final outcome = valueOf(await harness.makeOrder());
        expect(outcome, isA<MakePending>());
        final resolved = await harness.make.resolve(
          (await harness.pendingMakes()).single,
        );
        expect(resolved, isA<MakeStarted>());
        expect(makes(harness), 1);
      },
    );

    test(
      'a read of the order that fails leaves the make pending, and its resolution confirms it',
      () async {
        final harness = await MakeHarness.start();
        // Once the make is sent: the order's read after it, and the robot's read that follows, both unanswered.
        harness.coordinator.onRequest = (request) {
          if (request.url.path == '/api/make/') {
            harness.coordinator
              ..failNext(ScriptedMakerRequest.order, ScriptedFault.unreachable)
              ..failNext(ScriptedMakerRequest.robot, ScriptedFault.unreachable);
          }
        };
        final outcome = valueOf(await harness.makeOrder());
        expect(outcome, isA<MakePending>());
        expect((outcome as MakePending).reason, MakePendingReason.unread);
        final resolved = await harness.make.resolve(
          (await harness.pendingMakes()).single,
        );
        expect(resolved, isA<MakeStarted>());
        expect(makes(harness), 1);
      },
    );

    test(
      'a read past the 300 s answers 1022 once, then the order expired: the trade starts and ends at 5',
      () async {
        final harness = await MakeHarness.start();
        harness.coordinator.failNext(
          ScriptedMakerRequest.make,
          ScriptedFault.answerLost,
        );
        expect(valueOf(await harness.makeOrder()), isA<MakePending>());
        await harness.elapse(const Duration(seconds: 301));
        final resolved = await harness.make.resolve(
          (await harness.pendingMakes()).single,
        );
        expect(resolved, isA<MakeStarted>());
        final start = resolved as MakeStarted;
        expect(start.status, isA<Expired>());
        expect(start.record.closedAt, isNotNull);
        expect(harness.coordinator.order(42).bond, isNull);
      },
    );
  });

  group('the resolution', () {
    test(
      'closes a make whose order the robot names is cancelled (1043): it proves nothing, but nothing was shown',
      () async {
        final harness = await MakeHarness.start();
        harness.coordinator.failNext(
          ScriptedMakerRequest.make,
          ScriptedFault.answerLost,
        );
        expect(valueOf(await harness.makeOrder()), isA<MakePending>());
        harness.coordinator.order(42).status = 4;
        final resolved = await harness.make.resolve(
          (await harness.pendingMakes()).single,
        );
        expect(resolved, isA<MakeNotMade>());
        expect((resolved as MakeNotMade).refusal, isA<OrderCancelled>());
        expect(resolved.make.closedAt, isNotNull);
        expect(harness.records.confirms, 0);
      },
    );

    test(
      'waits for the make in flight: its robot is read only once the make\'s request ended',
      () async {
        final harness = await MakeHarness.start();
        final release = Completer<void>();
        harness.coordinator.holdMake = release.future;
        final making = harness.makeOrder();
        await harness.settle();
        final pending = (await harness.pendingMakes()).single;
        int robotReads() => harness.coordinator.requests
            .where((r) => r.url.path == '/api/robot/')
            .length;
        final before = robotReads();
        final resolving = harness.make.resolve(pending);
        await harness.settle();
        // Nothing of the resolution left while the make is held.
        expect(robotReads(), before);
        release.complete();
        expect(valueOf(await making), isA<MakeStarted>());
        expect(await resolving, isA<MakeNoLongerPending>());
        expect(makes(harness), 1);
      },
    );

    test(
      'a make whose terms read back otherwise than written is not sent, and closed',
      () async {
        final harness = await MakeHarness.start();
        harness.trails.readBack = (stored) => stored == null
            ? null
            : MakerTermsRecord(
                version: stored.version,
                network: stored.network,
                coordinatorAlias: stored.coordinatorAlias,
                role: stored.role,
                type: stored.type,
                currencyId: stored.currencyId,
                amount: stored.amount,
                minAmount: stored.minAmount,
                maxAmount: stored.maxAmount,
                premiumPercent: stored.premiumPercent + 1,
                paymentMethod: stored.paymentMethod,
                bondSizePercent: stored.bondSizePercent,
                publicSeconds: stored.publicSeconds,
                escrowSeconds: stored.escrowSeconds,
                description: stored.description,
                hasPassword: stored.hasPassword,
                latitude: stored.latitude,
                longitude: stored.longitude,
                createdPrice: stored.createdPrice,
                makerFee: stored.makerFee,
              );
        final made = await harness.makeOrder();
        expect(
          made,
          isA<Err<MakeOutcome, MakeRefusal>>().having(
            (e) => e.failure,
            'failure',
            isA<MakeNotRecorded>(),
          ),
        );
        expect(makes(harness), 0);
        expect(await harness.pendingMakes(), isEmpty);
      },
    );
  });

  group('a robot that is not fresh', () {
    Future<void> refused(MakeHarness harness) async {
      final made = await harness.makeOrder();
      expect(
        made,
        isA<Err<MakeOutcome, MakeRefusal>>().having(
          (e) => e.failure,
          'failure',
          isA<MakeRobotRefused>().having(
            (r) => r.failure,
            'failure',
            isA<RobotNotForNewTradeFailure>(),
          ),
        ),
      );
      expect(await harness.pendingMakes(), isEmpty);
      expect(await harness.allTrades(), isEmpty);
      expect(makes(harness), 0);
    }

    test(
      'one the coordinator already had with another pair is never used for a make',
      () async {
        final harness = await MakeHarness.start();
        final robot = harness.robot(0);
        final pair = pairOf(robot);
        harness.coordinator.existsWithPair(
          robot,
          publicKey: pair.publicKey.armored,
          encryptedPrivateKey: pair.encryptedPrivateKeyArmored,
          nostrPublicKey: robot.nostrKeyPair().publicKeyHex,
        );
        await refused(harness);
      },
    );

    for (final fields in [
      {'active_order_id': 7},
      {'last_order_id': 7},
    ]) {
      test(
        'one that holds an order ($fields) is never used for a make',
        () async {
          final harness = await MakeHarness.start();
          harness.coordinator.robotAnswerHas(harness.robot(0), fields);
          await refused(harness);
        },
      );
    }
  });

  group('a write that fails', () {
    test('the pending make not written: nothing sent', () async {
      final harness = await MakeHarness.start();
      harness.records.pendingFailure = const P2pStorageFailure();
      expect(
        await harness.makeOrder(),
        isA<Err<MakeOutcome, MakeRefusal>>().having(
          (e) => e.failure,
          'failure',
          isA<MakeNotRecorded>(),
        ),
      );
      expect(await harness.allTrades(), isEmpty);
      expect(makes(harness), 0);
    });

    test(
      'the terms not written: the pending make closed, nothing sent',
      () async {
        final harness = await MakeHarness.start();
        harness.trails.makerTermsFailure = const P2pStorageFailure();
        expect(
          await harness.makeOrder(),
          isA<Err<MakeOutcome, MakeRefusal>>().having(
            (e) => e.failure,
            'failure',
            isA<MakeNotRecorded>(),
          ),
        );
        expect(await harness.pendingMakes(), isEmpty);
        final rows = await harness.allTrades();
        expect(rows, hasLength(1));
        expect(rows.single['closed_at'], isNotNull);
        expect(makes(harness), 0);
      },
    );

    test(
      'the confirmation refused: the make stays pending, never closed, and its resolution confirms it',
      () async {
        final harness = await MakeHarness.start();
        harness.records.confirmFailure = const P2pStorageFailure();
        final outcome = valueOf(await harness.makeOrder());
        expect(outcome, isA<MakePending>());
        expect((outcome as MakePending).reason, MakePendingReason.notConfirmed);
        expect(await harness.pendingMakes(), hasLength(1));
        harness.records.confirmFailure = null;
        final resolved = await harness.make.resolve(
          (await harness.pendingMakes()).single,
        );
        expect(resolved, isA<MakeStarted>());
        expect((resolved as MakeStarted).record.orderId, 42);
        expect(makes(harness), 1);
      },
    );

    test(
      'the close refused after a refusal: the make said not made with its problem, kept pending, closed by its resolution',
      () async {
        final harness = await MakeHarness.start();
        harness.coordinator.refuseNextMake(1037);
        harness.records.closeFailure = const P2pStorageFailure();
        final outcome = valueOf(await harness.makeOrder());
        expect(outcome, isA<MakeNotMade>());
        expect((outcome as MakeNotMade).closeProblem, isA<P2pStorageFailure>());
        expect(await harness.pendingMakes(), hasLength(1));
        harness.records.closeFailure = null;
        expect(
          await harness.make.resolve((await harness.pendingMakes()).single),
          isA<MakeNotMade>(),
        );
        expect(await harness.pendingMakes(), isEmpty);
        expect(makes(harness), 1);
      },
    );

    test(
      'the close refused for a make that never left: never sent, not closed, nothing sent',
      () async {
        final harness = await MakeHarness.start();
        harness.kill = MakeKillAt.afterPendingMake;
        await expectLater(harness.makeOrder(), throwsA(isA<AppKilled>()));
        final again = harness.restart();
        again.records.closeFailure = const P2pStorageFailure();
        final sent = again.coordinator.requests.length;
        final resolved = await again.make.resolve(
          (await again.pendingMakes()).single,
        );
        expect(resolved, isA<MakeNeverSent>());
        expect((resolved as MakeNeverSent).closed, isFalse);
        expect(await again.pendingMakes(), hasLength(1));
        expect(again.coordinator.requests.length, sent);
      },
    );

    test(
      'the first trail not written: the trade confirmed, its status not stored, no invoice',
      () async {
        final harness = await MakeHarness.start();
        harness.trails.storeFailure = const P2pStorageFailure();
        final start = started(await harness.makeOrder());
        expect(start.stored, isFalse);
        expect(start.status.invoice, isNull);
        expect(start.recordProblem, isA<P2pStorageFailure>());
        expect(start.record.confirmedAt, isNotNull);
        expect(await harness.trailOf(start.record), isNull);
      },
    );

    for (final deleted in [true, false]) {
      test(
        'the Garage Key ${deleted ? 'deleted' : 'replaced'} once the robot is put: no make written or sent',
        () async {
          final harness = await MakeHarness.start();
          harness.coordinator.onRequest = (request) {
            // The robot's first contact: its key pair in the header.
            if (request.url.path == '/api/robot/' &&
                (request.headers['Authorization'] ?? '').split(' | ').length ==
                    4) {
              if (deleted) {
                harness.deleteKey();
              } else {
                harness.replaceKey();
              }
            }
          };
          expect(
            await harness.makeOrder(),
            isA<Err<MakeOutcome, MakeRefusal>>().having(
              (e) => e.failure,
              'failure',
              isA<MakeRobotRefused>(),
            ),
          );
          expect(await harness.allTrades(), isEmpty);
          expect(makes(harness), 0);
        },
      );
    }

    test(
      'a busy transport at every attempt: the make never left, closed',
      () async {
        final harness = await MakeHarness.start();
        for (var i = 0; i < 8; i++) {
          harness.coordinator.failNext(
            ScriptedMakerRequest.make,
            ScriptedFault.busy,
          );
        }
        final outcome = valueOf(await harness.makeOrder());
        expect(outcome, isA<MakeNotMade>());
        expect((outcome as MakeNotMade).make.closedAt, isNotNull);
        expect(harness.coordinator.orders, isEmpty);
        expect(await harness.pendingMakes(), isEmpty);
      },
    );
  });

  group('the line of a pending make', () {
    test(
      'terms it cannot read are never said « never sent »: the make may have left',
      () async {
        final harness = await MakeHarness.start();
        harness.coordinator.failNext(
          ScriptedMakerRequest.make,
          ScriptedFault.answerLost,
        );
        expect(valueOf(await harness.makeOrder()), isA<MakePending>());
        // The terms row read as one this code never writes (a value of another storage class), which the CHECKs of `maker_terms` refuse: played over the stream, not written.
        harness.trails.madeHistories = (stored) => {
          for (final key in stored.keys)
            key: const StoredMadeHistory(
              terms: null,
              trail: null,
              unreadable: true,
            ),
        };
        final listed = valueOf(
          await harness.make.pendingMakes(harness.network).first,
        );
        expect(listed.single.neverSent, isFalse);
        // And with no terms row at all, never sent.
        harness.trails.madeHistories = (stored) => const {};
        final bare = valueOf(
          await harness.make.pendingMakes(harness.network).first,
        );
        expect(bare.single.neverSent, isTrue);
      },
    );
  });

  group('the app killed', () {
    test(
      'after the robot was reserved: no make, no record, the robot never used again',
      () async {
        final harness = await MakeHarness.start();
        harness.kill = MakeKillAt.afterReservation;
        await expectLater(harness.makeOrder(), throwsA(isA<AppKilled>()));
        final again = harness.restart();
        expect(await again.pendingMakes(), isEmpty);
        expect(await again.allTrades(), isEmpty);
        expect(makes(again), 0);
        started(await again.makeOrder());
        expect(
          again.coordinator.requests
              .singleWhere((r) => r.url.path == '/api/make/')
              .robot,
          again.robot(1).sessionKey,
        );
      },
    );

    test(
      'between the pending make and its terms: closed at once with no request',
      () async {
        final harness = await MakeHarness.start();
        harness.kill = MakeKillAt.afterPendingMake;
        await expectLater(harness.makeOrder(), throwsA(isA<AppKilled>()));
        final again = harness.restart();
        final listed = valueOf(
          await again.make.pendingMakes(again.network).first,
        );
        expect(listed.single.neverSent, isTrue);
        final sent = again.coordinator.requests.length;
        final resolved = await again.make.resolve(listed.single.make);
        expect(resolved, isA<MakeNeverSent>());
        expect((resolved as MakeNeverSent).closed, isTrue);
        expect(again.coordinator.requests.length, sent);
        expect(await again.pendingMakes(), isEmpty);
        expect(makes(again), 0);
      },
    );

    test(
      'between the terms and the make: the robot names no order, the make is closed, nothing was sent',
      () async {
        final harness = await MakeHarness.start();
        harness.kill = MakeKillAt.afterMakerTerms;
        await expectLater(harness.makeOrder(), throwsA(isA<AppKilled>()));
        final again = harness.restart();
        final listed = valueOf(
          await again.make.pendingMakes(again.network).first,
        );
        expect(listed.single.neverSent, isFalse);
        expect(
          await again.make.resolve(listed.single.make),
          isA<MakeNotMade>(),
        );
        expect(await again.pendingMakes(), isEmpty);
        expect(makes(again), 0);
      },
    );

    for (final (fault, made) in [
      (ScriptedFault.answerLost, true),
      (ScriptedFault.timedOut, false),
      (ScriptedFault.landsLate, false),
    ]) {
      test(
        'while the make was on its way (${fault.name}): its order found if it exists, the make closed otherwise, never sent again',
        () async {
          final harness = await MakeHarness.start();
          harness.coordinator.failNext(ScriptedMakerRequest.make, fault);
          // The app dies with the request: nothing of this run is used again.
          expect(valueOf(await harness.makeOrder()), isA<MakePending>());
          final again = harness.restart();
          final resolved = await again.make.resolve(
            (await again.pendingMakes()).single,
          );
          expect(resolved, made ? isA<MakeStarted>() : isA<MakeNotMade>());
          expect(makes(again), 1);
          expect(await again.pendingMakes(), isEmpty);
        },
      );
    }

    test(
      'after the answer, before the confirmation: the resolution confirms the order with the bond made at the first read',
      () async {
        final harness = await MakeHarness.start();
        harness.kill = MakeKillAt.beforeConfirm;
        await expectLater(harness.makeOrder(), throwsA(isA<AppKilled>()));
        final bond = harness.coordinator.order(42).bond;
        expect(bond, isNotNull);
        final again = harness.restart();
        expect(await again.activeRecords(), isEmpty);
        final resolved = await again.make.resolve(
          (await again.pendingMakes()).single,
        );
        final start = resolved as MakeStarted;
        expect(start.status, isA<WaitingForMakerBond>());
        expect(
          ((start.status as WaitingForMakerBond).bond as CheckedInvoice).bolt11,
          bond?.text,
        );
        expect(makes(again), 1);
      },
    );

    test(
      'between the confirmation and the first trail: resumed from the first read, never closed as never sent',
      () async {
        final harness = await MakeHarness.start();
        harness.kill = MakeKillAt.beforeFirstTrail;
        await expectLater(harness.makeOrder(), throwsA(isA<AppKilled>()));
        final again = harness.restart();
        final record = (await again.activeRecords()).single;
        expect(record.origin, TradeOrigin.madeHere);
        expect(await again.trailOf(record), isNull);
        final listed = valueOf(await again.list.execute(again.network).first);
        expect(
          listed.single.standing,
          isA<ActiveTradeAt>().having(
            (at) => at.position,
            'position',
            TradePosition.start,
          ),
        );
        final run = again.watchOf(record);
        await again.settle();
        final status = run.lastStatus;
        expect(status.stored, isTrue);
        expect(status.seen.status, isA<WaitingForMakerBond>());
        expect(status.seen.status.warnings, isEmpty);
        expect(
          (await again.trailOf(record))?.position,
          TradePosition.makerBondStep.name,
        );
        expect(makes(again), 1);
        await run.subscription.cancel();
      },
    );

    test(
      'between the confirmation and the first trail, the bond paid from another client meanwhile: followed, with the warning of an edge the reference never takes',
      () async {
        final harness = await MakeHarness.start();
        harness.kill = MakeKillAt.beforeFirstTrail;
        await expectLater(harness.makeOrder(), throwsA(isA<AppKilled>()));
        harness.coordinator.lockMakerBond(42);
        final again = harness.restart();
        final record = (await again.activeRecords()).single;
        final run = again.watchOf(record);
        await again.settle();
        expect(run.lastStatus.seen.status, isA<MakerOrderPublic>());
        expect(run.lastStatus.seen.status.has<TradeStatusUnexpected>(), isTrue);
        await run.subscription.cancel();
      },
    );
  });

  group('a coordinator that lies', () {
    test(
      'answers the make with another robot\'s order: not taken, the robot\'s own order is',
      () async {
        final harness = await MakeHarness.start();
        // Public, so that this robot can read it: the read shows another maker.
        final other = harness.coordinator.inventOrder(
          harness.robot(5),
          status: 1,
        );
        harness.coordinator.makeAnswerChanges.add({'id': other.id});
        final start = started(await harness.makeOrder());
        expect(start.record.orderId, isNot(other.id));
        expect(
          start.record.orderId,
          harness.coordinator.ordersOf(harness.robot(0)).single.id,
        );
      },
    );

    test(
      'names, as the robot\'s active order, another robot\'s order: never confirmed, no bond shown, the make pending',
      () async {
        final harness = await MakeHarness.start();
        final other = harness.coordinator.inventOrder(
          harness.robot(5),
          status: 1,
        );
        harness.coordinator
          ..failNext(ScriptedMakerRequest.make, ScriptedFault.answerLost)
          // Once the make is sent: the robot put on the coordinator before it was fresh.
          ..onRequest = (request) {
            if (request.url.path == '/api/make/') {
              harness.coordinator.robotAnswerHas(harness.robot(0), {
                'active_order_id': other.id,
              });
            }
          };
        expect(valueOf(await harness.makeOrder()), isA<MakePending>());
        final resolved = await harness.make.resolve(
          (await harness.pendingMakes()).single,
        );
        expect(resolved, isA<MakePending>());
        expect(
          (resolved as MakePending).reason,
          MakePendingReason.notRecognized,
        );
        expect(harness.records.confirms, 0);
        expect(await harness.activeRecords(), isEmpty);
        // The robot's own order is never read: no bond was made for it.
        expect(
          harness.coordinator.ordersOf(harness.robot(0)).single.bond,
          isNull,
        );
      },
    );

    test(
      'names, as the robot\'s last order, another robot\'s order: never confirmed',
      () async {
        final harness = await MakeHarness.start();
        final other = harness.coordinator.inventOrder(
          harness.robot(5),
          status: 1,
        );
        harness.coordinator
          ..failNext(ScriptedMakerRequest.make, ScriptedFault.timedOut)
          // Once the make is sent: the robot put on the coordinator before it was fresh.
          ..onRequest = (request) {
            if (request.url.path == '/api/make/') {
              harness.coordinator.robotAnswerHas(harness.robot(0), {
                'last_order_id': other.id,
              });
            }
          };
        expect(valueOf(await harness.makeOrder()), isA<MakePending>());
        final resolved = await harness.make.resolve(
          (await harness.pendingMakes()).single,
        );
        expect(resolved, isA<MakePending>());
        expect(harness.records.confirms, 0);
      },
    );

    test(
      'shows an order of this robot created long before the make: confirmed, then judged by the state machine, as the robot was fresh',
      () async {
        // Since the functional review of #179 the creation time is not compared with this device's clock: a coordinator that lies sets it as it likes. With the terms asked, the order is the one asked; with other terms, the state machine says so before any bond.
        final harness = await MakeHarness.start();
        final older = harness.now
            .subtract(const Duration(minutes: 11))
            .toIso8601String();
        harness.coordinator.orderChanges[42] = {'created_at': older};
        final asked = started(await harness.makeOrder());
        expect(asked.record.orderId, 42);
        expect(asked.status, isA<WaitingForMakerBond>());
        expect(asked.status.warnings, isEmpty);

        final other = await MakeHarness.start();
        other.coordinator.orderChanges[42] = {
          'created_at': older,
          'premium': '3.00',
        };
        final changed = started(await other.makeOrder());
        expect(changed.status.has<TradeTermsChanged>(), isTrue);
        final bond =
            (changed.status as WaitingForMakerBond).bond as CheckedInvoice;
        expect(bond.mayShow, isFalse);
        expect(bond.warnings, isNotEmpty);
      },
    );

    for (final skew in [
      const Duration(minutes: -15),
      const Duration(minutes: 15),
    ]) {
      test(
        'a coordinator whose clock is ${skew.inMinutes} min from this device\'s: an honest make is recognized',
        () async {
          final harness = await MakeHarness.start();
          harness.skewCoordinator(skew);
          // A coordinator running the fix of GHSA-22q8-9ghc-jg3h refuses a make signed 15 minutes off its clock (1060, below): this one plays a coordinator not updated yet, whose dates alone are off.
          harness.coordinator.checksSignatures = false;
          final start = started(await harness.makeOrder());
          expect(start.record.orderId, 42);
          expect(start.status, isA<WaitingForMakerBond>());
          expect(harness.records.confirms, 1);
          // And so is one whose answer was lost, by the resolution.
          final again = await MakeHarness.start();
          again
            ..skewCoordinator(skew)
            ..coordinator.checksSignatures = false
            ..coordinator.failNext(
              ScriptedMakerRequest.make,
              ScriptedFault.answerLost,
            );
          expect(valueOf(await again.makeOrder()), isA<MakePending>());
          expect(
            await again.make.resolve((await again.pendingMakes()).single),
            isA<MakeStarted>(),
          );
        },
      );
    }

    for (final skew in [
      const Duration(seconds: -301),
      const Duration(minutes: 15),
    ]) {
      test(
        'a coordinator running the fix whose clock is ${skew.inSeconds} s from this device\'s refuses the make with 1060: nothing is made, the pending make closed',
        () async {
          final harness = await MakeHarness.start();
          harness.skewCoordinator(skew);
          final made = valueOf(await harness.makeOrder());
          expect(
            made,
            isA<MakeNotMade>().having(
              (m) => m.refusal,
              'refusal',
              isA<ActionSignatureRefused>().having(
                (f) => f.reason,
                'reason',
                ActionSignatureRefusal.clockSkew,
              ),
            ),
          );
          expect(harness.coordinator.orders, isEmpty);
          expect(await harness.pendingMakes(), isEmpty);
          expect(harness.records.confirms, 0);
        },
      );
    }

    test(
      'within 300 s of this device\'s clock, a make signed by a coordinator running the fix is made',
      () async {
        for (final skew in [
          const Duration(seconds: -299),
          const Duration(seconds: 299),
        ]) {
          final harness = await MakeHarness.start();
          harness.skewCoordinator(skew);
          expect(started(await harness.makeOrder()).record.orderId, 42);
        }
      },
    );

    test(
      'once its order is confirmed, a make is never confirmed with a second order: resolved again it sends nothing, and the database refuses a second order id',
      () async {
        final harness = await MakeHarness.start();
        harness.coordinator.failNext(
          ScriptedMakerRequest.make,
          ScriptedFault.answerLost,
        );
        expect(valueOf(await harness.makeOrder()), isA<MakePending>());
        final pending = (await harness.pendingMakes()).single;
        final first = await harness.make.resolve(pending) as MakeStarted;
        final second = harness.coordinator.inventOrder(harness.robot(0));
        harness.coordinator.robotAnswerHas(harness.robot(0), {
          'active_order_id': second.id,
        });
        // The pending make as the screen held it, resolved again: nothing sent, and the database takes no second order for it.
        final sent = harness.coordinator.requests.length;
        expect(await harness.make.resolve(pending), isA<MakeNoLongerPending>());
        expect(harness.coordinator.requests.length, sent);
        expect(
          await harness.records.confirmMake(pending, orderId: second.id),
          isA<Err<TradeRecord, P2pFailure>>(),
        );
        expect(
          (await harness.activeRecords()).single.orderId,
          first.record.orderId,
        );
      },
    );

    test(
      'changes the description: no bond shown without the warning, never paid from this wallet',
      () async {
        final harness = await MakeHarness.start();
        harness.coordinator.orderChanges[42] = {
          'description': 'Pay me on chain',
        };
        final start = started(await harness.makeOrder());
        final status = start.status as WaitingForMakerBond;
        expect(status.has<TradeTermsChanged>(), isTrue);
        final bond = status.bond as CheckedInvoice;
        expect(bond.mayShow, isFalse);
        expect(bond.mayShowAnyway, isTrue);
      },
    );

    test(
      'says the order has a password: no bond shown without the warning',
      () async {
        final harness = await MakeHarness.start();
        harness.coordinator.orderChanges[42] = {'has_password': true};
        final start = started(await harness.makeOrder());
        expect(start.status.has<TradeTermsChanged>(), isTrue);
        expect(
          ((start.status as WaitingForMakerBond).bond as CheckedInvoice)
              .mayShow,
          isFalse,
        );
      },
    );

    test(
      'a protected order with a meeting point (#189): its SHA-256 and the point sent once, the terms stored without the hash, no warning at the reads that agree',
      () async {
        final harness = await MakeHarness.start();
        final point =
            OrderLocation.tryCreate(48.8816, 2.3272) ?? fail('location');
        final asked = MakeHarness.request(
          location: point,
          password: 'a test password',
          paymentMethod: 'Cash F2F',
        );
        final start = started(await harness.makeOrder(asked));
        expect(start.status.warnings, isEmpty);
        final make = harness.coordinator.requests.singleWhere(
          (r) => r.url.path == '/api/make/',
        );
        final body = unsignedBodyOf(make.body);
        final sent = jsonDecode(body) as Map<String, Object?>;
        expect(sent['password'], OrderPasswordHash.of('a test password')?.hex);
        expect(sent['latitude'], 48.8816);
        expect(sent['longitude'], 2.3272);
        expect(body, isNot(contains('a test password')));
        // The terms keep that there is a password and the point, never the hash nor the password.
        final terms = valueOf(
          await harness.trails.makerTermsOf(start.record.robot),
        );
        expect(terms?.hasPassword, isTrue);
        expect(terms?.latitude, 48.8816);
        expect(terms?.longitude, 2.3272);
        final restored = valueOf(MakerTerms.restore(terms ?? fail('no terms')));
        expect(restored.request, asked);
        expect(restored.request.passwordHash, isNull);
        expect(restored.request.isSendable, isFalse);
      },
    );

    test(
      'a request kept without its password\'s hash is never sent (#189)',
      () async {
        final harness = await MakeHarness.start();
        final kept = MakeHarness.request(password: 'a test password').kept;
        final made = await harness.makeOrder(kept);
        expect(
          made,
          isA<Err<MakeOutcome, MakeRefusal>>().having(
            (e) => e.failure,
            'failure',
            isA<MakeTermsRefused>(),
          ),
        );
        expect(harness.coordinator.requests, isEmpty);
        expect(await harness.allTrades(), isEmpty);
      },
    );

    test('a description as asked is no warning', () async {
      final harness = await MakeHarness.start();
      final start = started(
        await harness.makeOrder(MakeHarness.request(description: 'Fast payer')),
      );
      expect(start.status.warnings, isEmpty);
    });

    test(
      'changes the public duration: said once the order is public, the bond then locked',
      () async {
        final harness = await MakeHarness.start();
        final start = started(await harness.makeOrder());
        harness.coordinator.lockMakerBond(42);
        final made = harness.coordinator.order(42);
        final run = harness.watchOf(start.record);
        await harness.settle();
        expect(run.lastStatus.seen.status, isA<MakerOrderPublic>());
        expect(run.lastStatus.seen.status.warnings, isEmpty);
        await run.subscription.cancel();
        harness.coordinator.orderChanges[42] = {
          'expires_at': made.createdAt
              .add(const Duration(hours: 1))
              .toIso8601String(),
        };
        final again = harness.watchOf(start.record);
        await harness.settle();
        expect(again.lastStatus.seen.status, isA<MakerOrderPublic>());
        expect(again.lastStatus.seen.status.has<TradeTermsChanged>(), isTrue);
        await again.subscription.cancel();
      },
    );

    test(
      'changes the public duration while the order is paused: said too',
      () async {
        final harness = await MakeHarness.start();
        final start = started(await harness.makeOrder());
        harness.coordinator
          ..lockMakerBond(42)
          ..pause(42);
        final made = harness.coordinator.order(42);
        harness.coordinator.orderChanges[42] = {
          'expires_at': made.createdAt
              .add(const Duration(hours: 1))
              .toIso8601String(),
        };
        final run = harness.watchOf(start.record);
        await harness.settle();
        expect(
          run.lastStatus.seen.status,
          isA<MakerOrderPublic>().having((s) => s.paused, 'paused', isTrue),
        );
        expect(run.lastStatus.seen.status.has<TradeTermsChanged>(), isTrue);
        await run.subscription.cancel();
      },
    );

    test(
      'says the robot made no order when it made one: the make closed, the order at 0 never shown and expired, nothing paid',
      () async {
        final harness = await MakeHarness.start();
        harness.coordinator
          ..failNext(ScriptedMakerRequest.make, ScriptedFault.answerLost)
          ..hideOrders = true;
        expect(valueOf(await harness.makeOrder()), isA<MakePending>());
        expect(
          await harness.make.resolve((await harness.pendingMakes()).single),
          isA<MakeNotMade>(),
        );
        final hidden = harness.coordinator.order(42);
        expect(hidden.bond, isNull);
        await harness.elapse(const Duration(seconds: 306));
        harness.coordinator.clean();
        expect(hidden.status, 5);
        expect(hidden.bond, isNull);
      },
    );

    test(
      'refuses a make it made: the make closed, the order at 0 never shown, nothing paid',
      () async {
        final harness = await MakeHarness.start();
        harness.coordinator.refuseAfterMaking = 1004;
        expect(valueOf(await harness.makeOrder()), isA<MakeNotMade>());
        expect(harness.coordinator.order(42).bond, isNull);
        expect(await harness.pendingMakes(), isEmpty);
      },
    );

    test(
      'makes the bond at another price than the one it announced just before: a warning, never paid from this wallet',
      () async {
        final harness = await MakeHarness.start();
        harness.coordinator.onRequest = (request) {
          if (request.url.path == '/api/order/') {
            harness.coordinator.prices[2] = 91711.15 / 2;
          }
        };
        final start = started(await harness.makeOrder());
        expect(start.status.has<BondAmountOutsideOrder>(), isTrue);
      },
    );

    test(
      'known limit: a price announced ten times too low just before the make makes a bond ten times too large agree',
      () async {
        final harness = await MakeHarness.start();
        harness.coordinator.prices[2] = 9171.115;
        final start = started(await harness.makeOrder());
        final bond =
            (start.status as WaitingForMakerBond).bond as CheckedInvoice;
        expect(bond.amount.value.toInt(), greaterThan(30000));
        expect(start.status.has<BondAmountOutsideOrder>(), isFalse);
      },
    );
  });

  group('the active trades', () {
    test(
      'list a pending make apart, and a confirmed make from its maker\'s terms, never as a take',
      () async {
        final harness = await MakeHarness.start();
        harness.coordinator.failNext(
          ScriptedMakerRequest.make,
          ScriptedFault.answerLost,
        );
        expect(valueOf(await harness.makeOrder()), isA<MakePending>());
        final pending = valueOf(
          await harness.make.pendingMakes(harness.network).first,
        );
        expect(pending.single.neverSent, isFalse);
        expect(
          valueOf(await harness.list.execute(harness.network).first),
          isEmpty,
        );
        await harness.make.resolve(pending.single.make);
        expect(
          valueOf(await harness.make.pendingMakes(harness.network).first),
          isEmpty,
        );
        final listed = valueOf(
          await harness.list.execute(harness.network).first,
        );
        expect(
          listed.single.standing,
          isA<ActiveTradeAt>().having(
            (at) => at.position,
            'position',
            TradePosition.makerBondStep,
          ),
        );
      },
    );

    test(
      'follow a made trade through its watch: the bond locked, the order public',
      () async {
        final harness = await MakeHarness.start();
        final start = started(await harness.makeOrder());
        harness.coordinator.lockMakerBond(42);
        final run = harness.watchOf(start.record);
        await harness.settle();
        expect(run.lastStatus.stored, isTrue);
        expect(run.lastStatus.seen.status, isA<MakerOrderPublic>());
        expect(run.lastStatus.takePending, isFalse);
        await run.subscription.cancel();
        final listed = valueOf(
          await harness.list.execute(harness.network).first,
        );
        expect(
          listed.single.standing,
          isA<ActiveTradeAt>().having(
            (at) => at.position,
            'position',
            TradePosition.public,
          ),
        );
      },
    );
  });
}
