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

  /// It clears or changes a pinned payment hash, but a maker's escrow at its next contract, which it clears or replaces with another, never keeps.
  hashChanged,

  /// It clears or moves back the last read of the pre-take, or clears the pre-take's deadline.
  preTakeForgotten,

  /// It moves the position along no edge of the trade (and records no breach), or leaves an end.
  positionMoved,

  /// It moves a maker's contract other than forward (schema 8): `take` back or by more than one, or by one without a later contract deadline from and to the positions a new contract allows; or a contract's deadline, taker or amount taken cleared, changed within the contract, or first written in the write that moves `take`; or gives a trade not made here a contract at all.
  contractMoved,

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

/// The exact, storable form of what a maker asked (schema 8, #176; design note `docs/design/phase-3-making-an-order.md` § 3.2, § 3.5): plain values only, written with the pending make before its request leaves and read back as they were.
///
/// It names no order, which does not exist yet when it is written; the coordinator is its short alias. The amount is fixed ([amount]) or a range ([minAmount] and [maxAmount]), one or the other. Whether the order has a password, never the password nor its hash.
/// **Set once**: the database refuses any update and any delete of it (`maker_terms.drift`).
@immutable
final class MakerTermsRecord {
  /// The version of this form: a record of another version is refused, never guessed.
  static const currentVersion = 1;

  final int version;

  /// `RobosatsNetwork.name`.
  final String network;
  final String coordinatorAlias;

  /// `TradeRole.name`: the maker of a buy order buys.
  final String role;

  /// `OrderType.wire`.
  final int type;
  final int currencyId;
  final double? amount;
  final double? minAmount;
  final double? maxAmount;
  final double premiumPercent;
  final String paymentMethod;
  final double bondSizePercent;
  final int publicSeconds;
  final int escrowSeconds;
  final String? description;
  final bool hasPassword;
  final double? latitude;
  final double? longitude;

  /// The coordinator's price of a bitcoin in the currency, read just before the make.
  final double createdPrice;
  final double makerFee;

  const MakerTermsRecord({
    required this.version,
    required this.network,
    required this.coordinatorAlias,
    required this.role,
    required this.type,
    required this.currencyId,
    required this.amount,
    required this.minAmount,
    required this.maxAmount,
    required this.premiumPercent,
    required this.paymentMethod,
    required this.bondSizePercent,
    required this.publicSeconds,
    required this.escrowSeconds,
    required this.description,
    required this.hasPassword,
    required this.latitude,
    required this.longitude,
    required this.createdPrice,
    required this.makerFee,
  });

  List<Object?> get _fields => [
    version,
    network,
    coordinatorAlias,
    role,
    type,
    currencyId,
    amount,
    minAmount,
    maxAmount,
    premiumPercent,
    paymentMethod,
    bondSizePercent,
    publicSeconds,
    escrowSeconds,
    description,
    hasPassword,
    latitude,
    longitude,
    createdPrice,
    makerFee,
  ];

  @override
  bool operator ==(Object other) =>
      other is MakerTermsRecord && _sameList(other._fields, _fields);

  @override
  int get hashCode => Object.hashAll(_fields);

  /// The coordinator only: never an amount, a payment method, a description or a place.
  @override
  String toString() => 'MakerTermsRecord($coordinatorAlias)';
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

  /// A maker's current contract (schema 8; design note `docs/design/phase-3-making-an-order.md` § 3.2): its index, 0 for the order's first take; the deadline the coordinator gave it; its taker's hash id; the amount it took of a range. A trade not made here keeps 0 and none of them.
  final int take;
  final int? takeDeadlineMicros;
  final String? takerHashId;
  final double? takenAmount;

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
    this.take = 0,
    this.takeDeadlineMicros,
    this.takerHashId,
    this.takenAmount,
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
    take,
    takeDeadlineMicros,
    takerHashId,
    takenAmount,
  ];

  /// Whether this record may replace [stored] as the trade's trail: see [whyNotReplace].
  bool mayReplace(TradeTrailRecord stored, {bool madeHere = false}) =>
      whyNotReplace(stored, madeHere: madeHere) == null;

  /// Why this record may not replace [stored] as the trade's trail, or `null` when it may (#87 asks before every write of a trail); [madeHere] says whether the trade is a maker's, which the record does not hold (the trade's origin, `madeHere`): `false` gives a taker's rule, which refuses every move of a maker's that differs.
  ///
  /// The rule, which every trail `TradeStatus.from` writes after [stored] meets, and which a trail of an earlier read never meets:
  /// - the version does not go down, and the trade (order, coordinator, network, role) is the same;
  /// - the read is not earlier than the stored one's;
  /// - a breach of trust stays recorded, and whether the history is known never changes;
  /// - a pinned payment hash (bond, escrow) stays set and the same, but the escrow's in the write that moves a maker's contract to the next, where it is cleared or replaced by another hash, never kept, as the trigger `trade_trails_forward` says (design note `docs/design/phase-3-making-an-order.md` § 3.5);
  /// - a maker's contract moves only forward, as the same trigger says (schema 8): `take` stays, or moves by one from `public`, `paused`, `waitingForBoth`, `waitingForEscrow` or `waitingForPayout` with a contract deadline to `waitingForBoth`, `waitingForEscrow` or `waitingForPayout` with a later one; the contract's deadline, taker and amount taken are written from nothing with `take` unchanged, changed only when it moves, never cleared; a trade not made here never has a contract;
  /// - the pre-take's last read stays set and does not move back, and its deadline stays set (the coordinator may move it either way);
  /// - the position stays, or moves along the edges of the trade ([TradeEdges.allows] for a taker, [TradeEdges.allowsMade] for a maker), or anywhere from the start of a trade whose history is unknown, or anywhere but out of an end when the new record records a breach (an unexpected edge is a breach the trail remembers); an end is never left.
  TrailReplacementRefusal? whyNotReplace(
    TradeTrailRecord stored, {
    bool madeHere = false,
  }) {
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
    final nextContract = take != stored.take;
    if ((stored.bondHash != null && bondHash != stored.bondHash) ||
        (stored.escrowHash != null &&
            (nextContract
                ? escrowHash == stored.escrowHash
                : escrowHash != stored.escrowHash))) {
      return TrailReplacementRefusal.hashChanged;
    }
    if ((!madeHere && _hasContract) || _contractMoved(stored)) {
      return TrailReplacementRefusal.contractMoved;
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
        (madeHere
            ? TradeEdges.allowsMade(tradeRole, from, to)
            : TradeEdges.allows(tradeRole, from, to)) ||
        (historyUnknown && from == TradePosition.start) ||
        breached;
    return allowed ? null : TrailReplacementRefusal.positionMoved;
  }

  /// Whether this record holds a contract, which only a maker's trail does.
  bool get _hasContract =>
      take != 0 ||
      takeDeadlineMicros != null ||
      takerHashId != null ||
      takenAmount != null;

  /// The positions a maker's next contract is read from, and those it is read at (design note `docs/design/phase-3-making-an-order.md` § 3.2, § 3.5): as `trade_trails_forward` writes them.
  static const _beforeNextContract = {
    'public',
    'paused',
    'waitingForBoth',
    'waitingForEscrow',
    'waitingForPayout',
  };
  static const _atNextContract = {
    'waitingForBoth',
    'waitingForEscrow',
    'waitingForPayout',
  };

  /// Whether this record moves the contract of [stored] other than forward: see [whyNotReplace].
  bool _contractMoved(TradeTrailRecord stored) {
    if (take == stored.take) {
      return (stored.takeDeadlineMicros != null &&
              takeDeadlineMicros != stored.takeDeadlineMicros) ||
          (stored.takerHashId != null && takerHashId != stored.takerHashId) ||
          (stored.takenAmount != null && takenAmount != stored.takenAmount);
    }
    final from = stored.takeDeadlineMicros;
    final to = takeDeadlineMicros;
    return take != stored.take + 1 ||
        from == null ||
        to == null ||
        to <= from ||
        !_beforeNextContract.contains(stored.position) ||
        !_atNextContract.contains(position) ||
        (takerHashId == null) != (stored.takerHashId == null) ||
        (takenAmount == null) != (stored.takenAmount == null);
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
