import 'dart:async';
import 'dart:convert';

import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/trade/active_trade.dart';
import 'package:p2p/src/domain/trade/maker_terms.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/testing.dart' show ScriptedFault, ScriptedMakerRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/make_harness.dart';
import 'support/trade_harness.dart' show AppKilled;

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
        final sent = jsonDecode(utf8.decode(make.body ?? const []));
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
    }) async {
      final made = await harness.makeOrder(request);
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
        final other = harness.coordinator.inventOrder(harness.robot(5));
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
      'shows an order of this robot created before the make was written: not recognized',
      () async {
        final harness = await MakeHarness.start();
        harness.coordinator.orderChanges[42] = {
          'created_at': harness.now
              .subtract(const Duration(minutes: 11))
              .toIso8601String(),
        };
        final outcome = valueOf(await harness.makeOrder());
        expect(outcome, isA<MakePending>());
        expect(
          (outcome as MakePending).reason,
          MakePendingReason.notRecognized,
        );
        expect(harness.records.confirms, 0);
      },
    );

    test(
      'names a second order of this robot once the first is confirmed: the make keeps its first order',
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
