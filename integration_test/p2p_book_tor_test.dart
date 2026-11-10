import 'dart:convert';
import 'dart:io';

import 'package:bb_mobile/init.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';

// A coordinator that is down is an outage on its side, not a defect of this stack: the test only requires this many mainnet coordinators to answer.
const _mainnetQuorum = 3;

// Every request starts at once and the transport bounds each one by 132 seconds (twice `torConnectDeadline`), Tor start included, so a load must end within this.
const _loadBound = Duration(minutes: 3);

/// Prints one measurement as a single greppable line: `P2P_BOOK_MEASURE {json}`.
///
/// Only labels of this app and numbers: never text sent by a coordinator.
void _measure(Map<String, Object?> values) {
  debugPrint('P2P_BOOK_MEASURE ${jsonEncode(values)}');
}

/// A fixed label for a failure, with the number or field name the package gives, never coordinator text.
Map<String, Object?> _failure(CoordinatorFailure failure) => {
  'failure': failure.runtimeType.toString(),
  if (failure case CoordinatorUnexpectedStatus(:final statusCode))
    'status': statusCode,
  if (failure case CoordinatorResponseMalformed(:final field)) 'field': field,
};

/// What one coordinator gave, and when, in milliseconds since the load started.
typedef _CoordinatorLoad = ({
  Coordinator coordinator,
  RobosatsNetwork network,
  Result<CoordinatorInfo, CoordinatorFailure> info,
  int infoMs,
  CoordinatorBookOutcome book,
  int bookMs,
});

Map<String, Object?> _bookFields(CoordinatorBookOutcome outcome) =>
    switch (outcome.result) {
      Ok(value: final book) => {
        'outcome': 'ok',
        'ordersKept': book.orders.length,
        'ordersDropped': book.droppedOrders,
        'droppedReasons': {
          for (final reason in book.dropped.map((r) => r.name).toSet())
            reason: book.dropped.where((r) => r.name == reason).length,
        },
        'truncated': book.truncated,
      },
      Err(:final failure) => {'outcome': 'failed', ..._failure(failure)},
    };

Future<void> main({bool isInitialized = false}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  // Opt-in only, as in robosats_tor_test.dart: these tests call live RoboSats coordinators over Tor, so an outage there must never fail CI or a normal local run.
  // The environment variable is the form verified on Linux desktop; the dart-define form is meant for a phone and has not been exercised.
  final runLiveRobosatsTest =
      Platform.environment['RUN_LIVE_ROBOSATS_TEST'] == 'true' ||
      const bool.fromEnvironment('RUN_LIVE_ROBOSATS_TEST');

  group(
    'P2P federation book over embedded Tor',
    skip: runLiveRobosatsTest
        ? false
        : 'calls live RoboSats coordinators: set RUN_LIVE_ROBOSATS_TEST=true',
    () {
      test(
        'loads the info and the book of every coordinator in parallel',
        timeout: const Timeout(Duration(minutes: 8)),
        () async {
          final facade = locator<P2pFacade>();
          final watch = Stopwatch()..start();
          int? torReadyMs;
          final torStates = facade.watchTorState().listen((state) {
            _measure({
              'step': 'tor_state',
              'state': state.name,
              'ms': watch.elapsedMilliseconds,
            });
            if (state == P2pTorState.ready) torReadyMs ??= watch.elapsedMilliseconds;
          });

          try {
            // Cold: every request of both networks starts now, and the first ones start Tor.
            final loads = <Future<_CoordinatorLoad>>[];
            for (final network in RobosatsNetwork.values) {
              final books = facade.requestBooks(network);
              for (final MapEntry(key: coordinator, value: book)
                  in books.entries) {
                // Each completion is timed as it happens, whichever of the two ends first.
                final timedInfo = facade
                    .fetchInfo(coordinator, network)
                    .then((r) => (r, watch.elapsedMilliseconds));
                final timedBook = book.then(
                  (o) => (o, watch.elapsedMilliseconds),
                );
                loads.add(() async {
                  final (infoResult, infoMs) = await timedInfo;
                  final (bookOutcome, bookMs) = await timedBook;
                  return (
                    coordinator: coordinator,
                    network: network,
                    info: infoResult,
                    infoMs: infoMs,
                    book: bookOutcome,
                    bookMs: bookMs,
                  );
                }());
              }
            }
            final results = await Future.wait(loads);
            final coldMs = watch.elapsedMilliseconds;

            for (final load in results) {
              _measure({
                'step': 'coordinator',
                'alias': load.coordinator.shortAlias,
                'network': load.network.name,
                'ms': load.bookMs,
                ..._bookFields(load.book),
                'infoOutcome': load.info is Ok ? 'ok' : 'failed',
                'infoMs': load.infoMs,
                if (load.info case Err(:final failure))
                  'infoFailure': _failure(failure),
                'torReadyMs': torReadyMs,
              });
            }

            // Warm: the mainnet books again, on the sessions the cold load opened.
            final warmStart = watch.elapsedMilliseconds;
            final warm = facade.requestBooks(RobosatsNetwork.mainnet);
            final warmResults = await Future.wait([
              for (final book in warm.values)
                book.then((o) => (o, watch.elapsedMilliseconds - warmStart)),
            ]);
            for (final (outcome, ms) in warmResults) {
              _measure({
                'step': 'coordinator_warm',
                'alias': outcome.coordinator.shortAlias,
                'network': RobosatsNetwork.mainnet.name,
                'ms': ms,
                ..._bookFields(outcome),
              });
            }

            bool answered(_CoordinatorLoad load) =>
                load.info is Ok && load.book.result is Ok;
            final answeredMainnet = results
                .where((l) => l.network == RobosatsNetwork.mainnet)
                .where(answered)
                .map((l) => l.coordinator.shortAlias)
                .toList();
            final answeredTestnet = results
                .where((l) => l.network == RobosatsNetwork.testnet)
                .where(answered)
                .map((l) => l.coordinator.shortAlias)
                .toList();
            _measure({
              'step': 'summary',
              'torReadyMs': torReadyMs,
              'coldLoadMs': coldMs,
              'warmLoadMs': watch.elapsedMilliseconds - warmStart,
              'mainnetAnswered': answeredMainnet,
              'testnetAnswered': answeredTestnet,
            });

            expect(answeredMainnet.length, greaterThanOrEqualTo(_mainnetQuorum));
            expect(Duration(milliseconds: coldMs), lessThan(_loadBound));
          } finally {
            await torStates.cancel();
            await facade.closeSessions();
          }
        },
      );
    },
  );
}
