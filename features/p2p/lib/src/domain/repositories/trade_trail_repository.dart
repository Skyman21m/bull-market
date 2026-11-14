import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../p2p_failure.dart';
import '../robot_binding.dart';
import '../trade/trade_storable.dart';
import '../trade_record.dart';

/// The terms and the trail of each trade of this device's robots, kept so that a trade resumes after the app was killed from what it was taken with and what it last saw, never from a fresh trail (#87, design note `docs/design/phase-2-taking-an-order.md` § 3.5, § 4.5).
///
/// The terms are written once, with the pending take, and never again; the trail is written with the pending take too, then after each read, and only moves forward.
/// The database keeps both itself, whatever the code that writes (the triggers of `trade_trails.drift`); the position of a trail moves only along the edges of the trade, which [TradeTrailRecord.whyNotReplace] alone says, and [storeTrail] asks it before every write.
/// Every write is one statement, synced to disk before its future completes, and never runs inside a database transaction (nothing in the feature opens one).
/// It holds no secret: the public order's figures, positions, times, payment hashes (public: they are in the invoices) and flags.
abstract interface class TradeTrailRepository {
  /// Records [terms] for [trade], once: the terms are never written again.
  ///
  /// They must be of the trade's order, coordinator, network and role, and the trade open, or the database refuses them ([P2pStorageFailure]); terms already recorded for the trade are a [TradeAlreadyRecordedFailure], and nothing is written.
  @useResult
  Future<Result<void, P2pFailure>> recordTerms(
    TradeRecord trade,
    TradeTermsRecord terms,
  );

  /// Stores [trail] as the trail of [trade]: the first one, or one that replaces the stored one.
  ///
  /// It reads the stored trail first and asks [TradeTrailRecord.whyNotReplace] of it: a refusal is a [TrailKept] with the reason, and nothing is written.
  /// The write is then conditional on the stored trail being still the one compared, column for column: a write that another write beat in between, as a read that ended late, writes nothing and is a [TrailKept] with no reason, the trail stored then winning.
  /// A trail of a closed trade is never written again ([TrailKept]); a first trail needs the trade's terms recorded and the trade open, or the database refuses it ([P2pStorageFailure]).
  @useResult
  Future<Result<TrailStoreOutcome, P2pFailure>> storeTrail(
    TradeRecord trade,
    TradeTrailRecord trail,
  );

  /// The terms and the trail stored for [trade], each absent when none was written, in one read.
  @useResult
  Future<Result<StoredTradeHistory, P2pFailure>> historyOf(TradeRecord trade);

  /// The terms and the trail stored for the trades of [network], by robot: a new map after each write of either, the trades without either left out.
  ///
  /// A database that cannot be read gives a [P2pStorageFailure] in place of the map.
  Stream<Result<Map<RobotSlot, StoredTradeHistory>, P2pFailure>> watchHistories(
    RobosatsNetwork network,
  );
}

/// What is stored of one trade's terms and trail.
@immutable
final class StoredTradeHistory {
  /// The terms, or `null` when none were written: a pending take whose request never left.
  final TradeTermsRecord? terms;

  /// The trail, or `null` when none was written.
  final TradeTrailRecord? trail;

  /// Whether a row is stored that this code does not read back as a record: a value of another type than the code writes.
  ///
  /// The database's constraints refuse what this code never writes; a row read back so is shown as a record that cannot be restored.
  final bool unreadable;

  const StoredTradeHistory({
    required this.terms,
    required this.trail,
    this.unreadable = false,
  });

  @override
  bool operator ==(Object other) =>
      other is StoredTradeHistory &&
      other.terms == terms &&
      other.trail == trail &&
      other.unreadable == unreadable;

  @override
  int get hashCode => Object.hash(terms, trail, unreadable);

  @override
  String toString() =>
      'StoredTradeHistory(terms: ${terms != null}, trail: $trail, unreadable: $unreadable)';
}

/// What a write of a trail did.
@immutable
sealed class TrailStoreOutcome {
  /// The trail stored once the write is over: the one written, or the one that was kept.
  TradeTrailRecord get stored;

  const TrailStoreOutcome();
}

/// The trail was written: it is now [stored].
final class TrailStored extends TrailStoreOutcome {
  @override
  final TradeTrailRecord stored;

  const TrailStored(this.stored);

  @override
  String toString() => 'TrailStored($stored)';
}

/// The trail was not written: [stored] stays, and the trade goes on from it.
///
/// [reason] is why [TradeTrailRecord.whyNotReplace] refused the trail over the stored one; `null` when the stored trail changed between the read and the write (another write won), or the trade was closed meanwhile.
final class TrailKept extends TrailStoreOutcome {
  @override
  final TradeTrailRecord stored;
  final TrailReplacementRefusal? reason;

  const TrailKept(this.stored, {required this.reason});

  @override
  String toString() => 'TrailKept($stored, ${reason?.name ?? 'raced'})';
}
