import 'dart:async';

import 'package:robosats/robosats.dart' show Coordinator, RobosatsNetwork;

/// The takes in flight in this process, one at a time per order: a second take of an order waits for the first to end, then finds its record (#87, review of #117).
///
/// One for the feature, for the run of the app (a lazy singleton of the composition: `P2pLocator.registerTrades`), so that every `TakeOrderUsecase`, which the composition makes anew for each use, shares it.
/// Per order rather than for every take: a take that waits on a slow coordinator (up to the transport's 132 s) must not hold back a take of another order; two orders never share a robot (the robot layer reserves each in one statement), so nothing else needs the takes in turn.
/// The database refuses a second open trade of an order too (the trigger `trades_one_open_per_order`), across connections; this lock keeps the second take from reserving and contacting a robot first.
final class TradeTakeLocks {
  final Map<(RobosatsNetwork, String, int), Future<void>> _tails = {};

  /// Runs [take] once every take of order [orderId] of [coordinator] on [network] begun before it has ended, whatever it gave.
  Future<T> run<T>(
    RobosatsNetwork network,
    Coordinator coordinator,
    int orderId,
    Future<T> Function() take,
  ) async {
    final key = (network, coordinator.shortAlias, orderId);
    final before = _tails[key] ?? Future<void>.value();
    final done = Completer<void>();
    final tail = done.future;
    _tails[key] = tail;
    try {
      await before;
      return await take();
    } finally {
      done.complete();
      if (identical(_tails[key], tail)) _tails.remove(key);
    }
  }
}
