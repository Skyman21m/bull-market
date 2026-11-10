import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/p2p_tor_state.dart';
import 'package:p2p/src/domain/taker_estimate.dart';
import 'package:p2p/src/domain/tor_wait.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart';

/// Reads [elements] as the book of temple, through the real parser of the package.
Future<List<PublicOrder>> parse(List<Map<String, Object?>> elements) async {
  final transport = FakeTransport(books: {'temple': elements});
  final result = await CoordinatorClient(
    transport,
    clock: () => testNow,
  ).fetchBook(coordinator('temple'), RobosatsNetwork.mainnet);
  return switch (result) {
    Ok(:final value) => value.orders,
    Err(:final failure) => throw StateError('$failure'),
  };
}

void main() {
  group('TorWait', () {
    TorWait walk(List<P2pTorState> states) =>
        states.fold(TorWait.initializing, (wait, state) => wait.after(state));

    test('follows the three steps', () {
      expect(walk([P2pTorState.notStarted]), TorWait.initializing);
      expect(walk([P2pTorState.connecting]), TorWait.connecting);
      expect(walk([P2pTorState.connecting, P2pTorState.ready]), TorWait.ready);
    });

    test('ignores « not started » once connecting', () {
      expect(
        walk([
          P2pTorState.notStarted,
          P2pTorState.connecting,
          P2pTorState.notStarted,
        ]),
        TorWait.connecting,
      );
    });

    test('stays ready whatever Tor reports next', () {
      for (final state in P2pTorState.values) {
        expect(TorWait.ready.after(state), TorWait.ready);
      }
    });

    test('a failure, then a restart from « not started »', () {
      expect(
        walk([P2pTorState.connecting, P2pTorState.failed]),
        TorWait.failed,
      );
      expect(
        TorWait.failed.after(P2pTorState.notStarted),
        TorWait.initializing,
      );
      expect(TorWait.failed.after(P2pTorState.connecting), TorWait.connecting);
    });
  });

  group('TakerEstimate', () {
    test(
      'a buyer receives the sats less routing budget, plus the fee as the official client counts it',
      () async {
        final [order] = await parse([
          bookOrder(id: 1, type: 1, amount: 100, satoshisNow: 107000),
        ]);

        expect(TakerEstimate.of(order, takerFee: 0)?.maxSats, 106893);
        expect(TakerEstimate.of(order, takerFee: 0.00175)?.maxSats, 107080);
      },
    );

    test('a seller sends the sats less the fee', () async {
      final [order] = await parse([
        bookOrder(id: 1, type: 0, amount: 100, satoshisNow: 107000),
      ]);

      expect(TakerEstimate.of(order, takerFee: 0.00175)?.maxSats, 106813);
    });

    test('a range gives a range, at the rate of its largest amount', () async {
      final [order] = await parse([
        bookOrder(
          id: 1,
          type: 0,
          minAmount: 50,
          maxAmount: 300,
          satoshisNow: 300000,
        ),
      ]);

      final estimate = TakerEstimate.of(order, takerFee: 0);
      expect(estimate?.minSats, 50000);
      expect(estimate?.maxSats, 300000);
      expect(estimate?.isRange, isTrue);
    });

    test('no sats at the current price gives no estimate', () async {
      final [order] = await parse([bookOrder(id: 1, satoshisNow: null)]);

      expect(TakerEstimate.of(order, takerFee: 0), isNull);
    });
  });
}
