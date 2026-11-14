import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';

import '../trade_record.dart' show TradeRole;
import 'trade_edges.dart';

/// Why a stored record of a trade's terms or trail cannot be restored: a type, never the stored text.
///
/// A trade whose record is refused is never resumed from a fresh trail (#87): it is shown as it is, read-only, with the reason.
sealed class TradeRecordRefusal extends Failure {
  const TradeRecordRefusal();

  @override
  String toString() => runtimeType.toString();
}

/// Not a record this version wrote: an unknown version, a missing or out-of-bounds value, a time after the resume or out of order.
final class TradeRecordMalformed extends TradeRecordRefusal {
  const TradeRecordMalformed();
}

/// A trail record of another trade than the terms it is restored with: another order, coordinator, network or role.
final class TradeRecordOfAnotherTrade extends TradeRecordRefusal {
  const TradeRecordOfAnotherTrade();
}

/// The trade's coordinator is no longer in the federation list, or no longer on the trade's network: the trade can be shown, never resumed (no read is sent to a coordinator the list does not vouch for).
final class TradeCoordinatorGone extends TradeRecordRefusal {
  const TradeCoordinatorGone();
}

/// Why a new trail record may not replace the stored one ([TradeTrailRecord.whyNotReplace]).
enum TrailReplacementRefusal {
  /// The new record's version is lower.
  olderVersion,

  /// It is of another trade (order, coordinator, network or role).
  otherTrade,

  /// It comes from a read earlier than the stored one's.
  earlierRead,

  /// It clears a breach of trust.
  breachCleared,

  /// It changes whether the history is known.
  historyChanged,

  /// It clears or changes a pinned payment hash.
  hashChanged,

  /// It clears or moves back the last read of the pre-take, or clears the pre-take's deadline.
  preTakeForgotten,

  /// It moves the position along no edge of the trade (and records no breach), or leaves an end.
  positionMoved,

  /// A value that is not one a trail writes (an unknown position).
  malformed,
}

/// The exact, storable form of `TradeTerms`: plain values only, written at the take and read back as they were (#86, design note § 3.5).
///
/// Doubles are stored as the IEEE doubles they are (SQLite `REAL`), so a round trip gives the same terms; the coordinator is its short alias, resolved again in the federation list.
/// **Set once**: written with the pending take and never changed afterwards (#87 adds a database trigger that refuses any update of it).
@immutable
final class TradeTermsRecord {
  /// The version of this form: a record of another version is refused, never guessed.
  static const currentVersion = 1;

  final int version;

  /// `RobosatsNetwork.name`.
  final String network;
  final String coordinatorAlias;
  final int orderId;

  /// `TradeRole.name`.
  final String role;

  /// `OrderType.wire`.
  final int type;
  final int currencyId;
  final double amount;
  final bool isRange;
  final double premiumPercent;
  final int? explicitSatoshis;
  final double bondSizePercent;
  final int escrowSeconds;
  final double bookPrice;
  final double takerFee;

  const TradeTermsRecord({
    required this.version,
    required this.network,
    required this.coordinatorAlias,
    required this.orderId,
    required this.role,
    required this.type,
    required this.currencyId,
    required this.amount,
    required this.isRange,
    required this.premiumPercent,
    required this.explicitSatoshis,
    required this.bondSizePercent,
    required this.escrowSeconds,
    required this.bookPrice,
    required this.takerFee,
  });

  List<Object?> get _fields => [
    version,
    network,
    coordinatorAlias,
    orderId,
    role,
    type,
    currencyId,
    amount,
    isRange,
    premiumPercent,
    explicitSatoshis,
    bondSizePercent,
    escrowSeconds,
    bookPrice,
    takerFee,
  ];

  @override
  bool operator ==(Object other) =>
      other is TradeTermsRecord && _sameList(other._fields, _fields);

  @override
  int get hashCode => Object.hashAll(_fields);

  /// The order and its coordinator, never an amount.
  @override
  String toString() => 'TradeTermsRecord($coordinatorAlias#$orderId)';
}

/// The exact, storable form of `TradeTrail`: what the state machine remembers of a trade between two reads, written after each read and read back when the app resumes the trade (#86, design note § 3.5, § 4.5).
///
/// Times are microseconds since the epoch, in UTC; payment hashes are 64 lowercase hexadecimal characters. A payment hash is public (it is in the invoice), and nothing here is a secret or a text of the coordinator.
@immutable
final class TradeTrailRecord {
  /// The version of this form: a record of another version is refused, never guessed.
  static const currentVersion = 1;

  final int version;

  /// The trade the trail belongs to, compared with the terms it is restored with: `RobosatsNetwork.name`, the coordinator's short alias, the order, `TradeRole.name`.
  final String network;
  final String coordinatorAlias;
  final int orderId;
  final String role;

  /// `TradePosition.name` of the last status.
  final String position;

  /// When the answer of the last status was read.
  final int readAtMicros;

  /// The payment hash of the first bond invoice and of the first escrow invoice of the trade.
  final String? bondHash;
  final String? escrowHash;

  /// The deadline of the last order read, for its position.
  final int? deadlineMicros;

  /// When an answer last showed the pre-take, and the pre-take's deadline it gave.
  final int? bondStepSeenAtMicros;
  final int? bondStepDeadlineMicros;

  /// Whether an answer of the trade was a breach of trust.
  final bool breached;

  /// Whether the trail started without the trade's history (a trade found by recovery).
  final bool historyUnknown;

  const TradeTrailRecord({
    required this.version,
    required this.network,
    required this.coordinatorAlias,
    required this.orderId,
    required this.role,
    required this.position,
    required this.readAtMicros,
    required this.bondHash,
    required this.escrowHash,
    required this.deadlineMicros,
    required this.bondStepSeenAtMicros,
    required this.bondStepDeadlineMicros,
    required this.breached,
    required this.historyUnknown,
  });

  List<Object?> get _fields => [
    version,
    network,
    coordinatorAlias,
    orderId,
    role,
    position,
    readAtMicros,
    bondHash,
    escrowHash,
    deadlineMicros,
    bondStepSeenAtMicros,
    bondStepDeadlineMicros,
    breached,
    historyUnknown,
  ];

  /// Whether this record may replace [stored] as the trade's trail: see [whyNotReplace].
  bool mayReplace(TradeTrailRecord stored) => whyNotReplace(stored) == null;

  /// Why this record may not replace [stored] as the trade's trail, or `null` when it may (#87 asks before every write of a trail).
  ///
  /// The rule, which every trail `TradeStatus.from` writes after [stored] meets, and which a trail of an earlier read never meets:
  /// - the version does not go down, and the trade (order, coordinator, network, role) is the same;
  /// - the read is not earlier than the stored one's;
  /// - a breach of trust stays recorded, and whether the history is known never changes;
  /// - a pinned payment hash (bond, escrow) stays set and the same;
  /// - the pre-take's last read stays set and does not move back, and its deadline stays set (the coordinator may move it either way);
  /// - the position stays, or moves along the edges of the trade ([TradeEdges.allows]), or anywhere from the start of a trade whose history is unknown, or anywhere but out of an end when the new record records a breach (an unexpected edge is a breach the trail remembers); an end is never left.
  TrailReplacementRefusal? whyNotReplace(TradeTrailRecord stored) {
    if (version < stored.version) return TrailReplacementRefusal.olderVersion;
    if (network != stored.network ||
        coordinatorAlias != stored.coordinatorAlias ||
        orderId != stored.orderId ||
        role != stored.role) {
      return TrailReplacementRefusal.otherTrade;
    }
    if (readAtMicros < stored.readAtMicros) {
      return TrailReplacementRefusal.earlierRead;
    }
    if (stored.breached && !breached) {
      return TrailReplacementRefusal.breachCleared;
    }
    if (historyUnknown != stored.historyUnknown) {
      return TrailReplacementRefusal.historyChanged;
    }
    if ((stored.bondHash != null && bondHash != stored.bondHash) ||
        (stored.escrowHash != null && escrowHash != stored.escrowHash)) {
      return TrailReplacementRefusal.hashChanged;
    }
    final seen = stored.bondStepSeenAtMicros;
    final nowSeen = bondStepSeenAtMicros;
    if ((seen != null && (nowSeen == null || nowSeen < seen)) ||
        (stored.bondStepDeadlineMicros != null &&
            bondStepDeadlineMicros == null)) {
      return TrailReplacementRefusal.preTakeForgotten;
    }
    final from = TradePosition.values
        .where((value) => value.name == stored.position)
        .firstOrNull;
    final to = TradePosition.values
        .where((value) => value.name == position)
        .firstOrNull;
    final tradeRole = TradeRole.values
        .where((value) => value.name == role)
        .firstOrNull;
    if (from == null || to == null || tradeRole == null) {
      return TrailReplacementRefusal.malformed;
    }
    if (from == to) return null;
    if (from.isTerminal) return TrailReplacementRefusal.positionMoved;
    final allowed =
        TradeEdges.allows(tradeRole, from, to) ||
        (historyUnknown && from == TradePosition.start) ||
        breached;
    return allowed ? null : TrailReplacementRefusal.positionMoved;
  }

  @override
  bool operator ==(Object other) =>
      other is TradeTrailRecord && _sameList(other._fields, _fields);

  @override
  int get hashCode => Object.hashAll(_fields);

  /// The trade, the position and the breach, never a hash.
  @override
  String toString() =>
      'TradeTrailRecord($coordinatorAlias#$orderId, $position, breached: $breached)';
}

bool _sameList(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
