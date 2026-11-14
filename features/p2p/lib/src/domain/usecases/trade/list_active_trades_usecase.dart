import 'dart:async';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../../p2p_failure.dart';
import '../../repositories/trade_trail_repository.dart';
import '../../robot_binding.dart';
import '../../trade/active_trade.dart';
import '../../trade/trade_edges.dart';
import '../../trade/trade_status.dart';
import '../../trade/trade_storable.dart';
import '../../trade/trade_terms.dart';
import '../../trade_record.dart';
import '../../trade_robots.dart';

/// The active trades of a network, each with where its stored trail says it stands, for the « Active trades » list (#87, #88): read from the device only, nothing sent.
///
/// A new list after each write of the records, the terms or the trails; a trade whose records cannot be restored is listed as [ActiveTradeUnrestorable], never left out; a database that cannot be read gives a [P2pStorageFailure] in place of the list, never an empty one.
final class ListActiveTradesUsecase {
  final TradeRobots _robots;
  final TradeTrailRepository _trails;
  final DateTime Function() _clock;

  const ListActiveTradesUsecase(
    this._robots,
    this._trails, {
    required this._clock,
  });

  Stream<Result<List<ActiveTrade>, P2pFailure>> execute(
    RobosatsNetwork network,
  ) {
    Result<List<TradeRecord>, P2pFailure>? records;
    Result<Map<RobotSlot, StoredTradeHistory>, P2pFailure>? histories;
    StreamSubscription<Result<List<TradeRecord>, P2pFailure>>? recordsSub;
    StreamSubscription<Result<Map<RobotSlot, StoredTradeHistory>, P2pFailure>>?
    historiesSub;
    late final StreamController<Result<List<ActiveTrade>, P2pFailure>> out;

    void emit() {
      final (r, h) = (records, histories);
      if (r == null || h == null) return;
      switch ((r, h)) {
        case (Err(:final failure), _) || (_, Err(:final failure)):
          out.add(Err(failure));
        case (Ok(value: final list), Ok(value: final map)):
          out.add(
            Ok(
              List.unmodifiable([
                for (final record in list)
                  ActiveTrade(record, _standingOf(record, map[record.robot])),
              ]),
            ),
          );
      }
    }

    void failed(Object error, StackTrace stackTrace) {
      if (error is Exception) {
        out.add(const Err(P2pStorageFailure()));
      } else {
        out.addError(error, stackTrace);
      }
    }

    out = StreamController(
      onListen: () {
        recordsSub = _robots.activeTrades(network).listen((value) {
          records = value;
          emit();
        }, onError: failed);
        historiesSub = _trails.watchHistories(network).listen((value) {
          histories = value;
          emit();
        }, onError: failed);
      },
      onCancel: () async {
        await recordsSub?.cancel();
        await historiesSub?.cancel();
      },
    );
    return out.stream;
  }

  /// Where [record] stands by [history], restored as the watch restores it.
  ActiveTradeStanding _standingOf(
    TradeRecord record,
    StoredTradeHistory? history,
  ) {
    final terms = history?.terms;
    if (history == null || terms == null) {
      return record.isPendingTake
          ? const ActiveTradeTakeNeverSent()
          : const ActiveTradeUnrestorable(TradeRecordMalformed());
    }
    if (history.unreadable) {
      return const ActiveTradeUnrestorable(TradeRecordMalformed());
    }
    final TradeTerms restored;
    switch (TradeTerms.restore(terms)) {
      case Ok(:final value):
        restored = value;
      case Err(:final failure):
        return ActiveTradeUnrestorable(failure);
    }
    if (restored.network != record.network ||
        restored.coordinator.shortAlias != record.coordinatorAlias ||
        restored.orderId != record.orderId ||
        restored.role != record.role) {
      return const ActiveTradeUnrestorable(TradeRecordOfAnotherTrade());
    }
    final trail = history.trail;
    if (trail == null) {
      return record.isPendingTake || record.origin == TradeOrigin.recovered
          ? ActiveTradeAt(
              TradePosition.start,
              deadline: null,
              breached: false,
              historyUnknown: record.origin == TradeOrigin.recovered,
            )
          : const ActiveTradeUnrestorable(TradeRecordMalformed());
    }
    return switch (TradeTrail.restore(trail, terms: restored, now: _clock())) {
      Ok(:final value) => ActiveTradeAt(
        value.position,
        deadline: value.deadline,
        breached: value.breached,
        historyUnknown: value.historyUnknown,
      ),
      Err(:final failure) => ActiveTradeUnrestorable(failure),
    };
  }
}
