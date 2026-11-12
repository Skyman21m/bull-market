import 'package:bull_tor/tor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/p2p_tor_state.dart';
import 'package:p2p/src/domain/taker_estimate.dart';
import 'package:p2p/src/domain/tor_wait.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart';

Future<List<PublicOrder>> parse(List<Map<String, Object?>> elements) =>
    parseOrders(elements);

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

  group('P2pTorReport', () {
    test('carries the share Tor reports while it connects, and only then', () {
      expect(
        P2pTorReport.of(
          const TorConnecting(source: TorSource.embedded, progress: 0.3),
        ),
        P2pTorReport(P2pTorState.connecting, progress: 0.3),
      );
      expect(
        P2pTorReport.of(const TorConnecting(source: TorSource.embedded)),
        P2pTorReport(P2pTorState.connecting),
      );
      expect(
        P2pTorReport.of(
          const TorConnecting(source: TorSource.embedded),
        ).progress,
        isNull,
      );
      expect(
        P2pTorReport.of(const TorStopped(TorSource.embedded)),
        P2pTorReport(P2pTorState.notStarted),
      );
      expect(
        P2pTorReport.of(const TorUninitialized()),
        P2pTorReport(P2pTorState.notStarted),
      );
      expect(
        P2pTorReport.of(
          const TorUnavailable(
            source: TorSource.embedded,
            failure: TorBootstrapTimeoutFailure(),
          ),
        ),
        P2pTorReport(P2pTorState.failed),
      );
      for (final state in [
        P2pTorState.notStarted,
        P2pTorState.ready,
        P2pTorState.failed,
      ]) {
        expect(P2pTorReport(state, progress: 0.5).progress, isNull);
      }
    });

    test(
      'keeps a share within 0 and 1, and drops one that is not a number',
      () {
        double? share(double progress) =>
            P2pTorReport(P2pTorState.connecting, progress: progress).progress;

        expect(share(1.5), 1);
        expect(share(-0.2), 0);
        expect(share(double.infinity), 1);
        expect(share(double.nan), isNull);
        expect(share(0.42), 0.42);
      },
    );

    test('two reports alike are equal, so a repeat is dropped', () {
      expect(
        P2pTorReport(P2pTorState.connecting, progress: 0.3),
        P2pTorReport(P2pTorState.connecting, progress: 0.3),
      );
      expect(
        P2pTorReport(P2pTorState.connecting, progress: 0.3).hashCode,
        P2pTorReport(P2pTorState.connecting, progress: 0.3).hashCode,
      );
      expect(
        P2pTorReport(P2pTorState.connecting, progress: 0.3),
        isNot(P2pTorReport(P2pTorState.connecting, progress: 0.4)),
      );
      expect(
        P2pTorReport(P2pTorState.connecting),
        isNot(P2pTorReport(P2pTorState.connecting, progress: 0)),
      );
    });
  });

  group('the percentage of the Tor wait', () {
    P2pTorReport connecting([double? share]) =>
        P2pTorReport(P2pTorState.connecting, progress: share);
    final stopped = P2pTorReport(P2pTorState.notStarted);
    final ready = P2pTorReport(P2pTorState.ready);
    final failed = P2pTorReport(P2pTorState.failed);

    /// The step and the percentage the wait shows after each report, from [from] with no percentage.
    List<(TorWait, int?)> walk(
      List<P2pTorReport> reports, {
      TorWait from = TorWait.initializing,
    }) {
      var wait = from;
      int? percent;
      final shown = <(TorWait, int?)>[];
      for (final report in reports) {
        wait = wait.after(report.state);
        percent = wait.percentAfter(report, shown: percent);
        shown.add((wait, percent));
      }
      return shown;
    }

    List<int?> percents(List<P2pTorReport> reports, {TorWait? from}) => [
      for (final (_, percent) in walk(
        reports,
        from: from ?? TorWait.initializing,
      ))
        percent,
    ];

    test('none before Tor reports a share, then 0 % when it reports 0', () {
      // A cold start as `bull_tor` reports it: not started, connecting with no share (the repository starts an attempt), stopped (the backend cleans up), then Arti's shares from 0.
      expect(
        walk([
          stopped,
          connecting(),
          stopped,
          connecting(0),
          connecting(0),
          connecting(0.12),
        ]),
        [
          (TorWait.initializing, null),
          (TorWait.connecting, null),
          (TorWait.connecting, null),
          (TorWait.connecting, 0),
          (TorWait.connecting, 0),
          (TorWait.connecting, 12),
        ],
      );
    });

    test('a middle share, rounded down to the whole percent', () {
      expect(percents([connecting(0.5)]), [50]);
      expect(percents([connecting(0.429)]), [42]);
      expect(percents([connecting(0.004)]), [0]);
      expect(percents([connecting(0.29)]), [29]);
      // 0.29 as Arti's single-precision fraction reaches Dart.
      expect(percents([connecting(0.28999999165534973)]), [29]);
    });

    test('never 100 % while Tor is not ready, even at a full share', () {
      expect(percents([connecting(0.995)]), [99]);
      expect(percents([connecting(0.99999)]), [99]);
      expect(percents([connecting(1)]), [99]);
      expect(TorWait.maxPercent, 99);
    });

    test('a share that goes back during one attempt keeps the highest', () {
      expect(
        percents([
          connecting(0.6),
          connecting(0.4),
          connecting(0.59),
          connecting(0.65),
        ]),
        [60, 60, 60, 65],
      );
    });

    test('a jump is shown as it comes', () {
      expect(percents([connecting(0.05), connecting(0.9)]), [5, 90]);
    });

    test('a full share held before ready reads 99 %, then none once ready', () {
      // `bull_tor` reports a full share while it holds readiness, then ready.
      expect(walk([connecting(0.8), connecting(1), connecting(1), ready]), [
        (TorWait.connecting, 80),
        (TorWait.connecting, 99),
        (TorWait.connecting, 99),
        (TorWait.ready, null),
      ]);
    });

    test('once ready, a directory refresh brings no percentage back', () {
      expect(
        walk([
          connecting(0.5),
          ready,
          connecting(0.3),
          connecting(1),
          stopped,
        ]).skip(1),
        everyElement((TorWait.ready, null)),
      );
    });

    test('none once Tor has failed', () {
      expect(walk([connecting(0.4), failed]).last, (TorWait.failed, null));
    });

    test('a new attempt starts over: none, then its own shares', () {
      // The Snowflake fallback after a timeout of the direct attempt: the repository starts a new attempt (connecting with no share), the backend stops the old Arti, then reports from 0.
      expect(
        walk([
          connecting(0.45),
          connecting(),
          stopped,
          connecting(0),
          connecting(0.2),
        ]),
        [
          (TorWait.connecting, 45),
          (TorWait.connecting, null),
          (TorWait.connecting, null),
          (TorWait.connecting, 0),
          (TorWait.connecting, 20),
        ],
      );
    });

    test('Retry: from the error, a new attempt with its own shares', () {
      // The cubit shows « initializing » with no percentage when the user retries; `bull_tor` stops Arti and starts it again.
      expect(
        percents([
          connecting(),
          stopped,
          connecting(0),
          connecting(0.1),
        ], from: TorWait.initializing),
        [null, null, 0, 10],
      );
      expect(percents([connecting(0.3)], from: TorWait.failed), [30]);
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
