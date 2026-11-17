import 'dart:async';
import 'dart:convert';

import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/maker_terms.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/testing.dart' show ScriptedMakerRequest;
import 'package:primitives/primitives.dart';
import 'package:test/test.dart';

import 'support/make_harness.dart';

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
          expect(read.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
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
}
