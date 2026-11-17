import 'dart:async';

import 'package:robosats/robosats.dart' show RobosatsNetwork;

/// The makes in flight in this process, and the resolutions of pending makes, one at a time per network (#179, design note `docs/design/phase-3-making-an-order.md` § 3.4): keyed by network, since a make has no order id before its answer.
///
/// One for the feature, for the run of the app (a lazy singleton of the composition), so that every `MakeOrderUsecase` shares it.
/// So the resolution of a pending make never reads its robot while that make's own request is in flight in this process: a robot read under the lock is sent after the request ended, answered or timed out, which is what lets a robot that names no order close the pending make (§ 3.4, step 6).
final class TradeMakeLocks {
  final Map<RobosatsNetwork, Future<void>> _tails = {};

  /// Runs [body] once every make or resolution on [network] begun before it has ended, whatever it gave.
  Future<T> run<T>(RobosatsNetwork network, Future<T> Function() body) async {
    final before = _tails[network] ?? Future<void>.value();
    final done = Completer<void>();
    final tail = done.future;
    _tails[network] = tail;
    try {
      await before;
      return await body();
    } finally {
      done.complete();
      if (identical(_tails[network], tail)) _tails.remove(network);
    }
  }
}
