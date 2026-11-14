import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';

/// A stored record of a trade's terms or trail that cannot be restored: an unknown version, a missing or out-of-bounds value. A type, never the stored text.
///
/// A trade whose record is refused is not resumed from a fresh trail: the use case says the records cannot be read (#87).
final class TradeRecordMalformed extends Failure {
  const TradeRecordMalformed();

  @override
  String toString() => 'TradeRecordMalformed';
}

/// The exact, storable form of `TradeTerms`: plain values only, written at the take and read back as they were (#86, design note § 3.5).
///
/// Doubles are stored as the IEEE doubles they are (SQLite `REAL`), so a round trip gives the same terms; the coordinator is its short alias, resolved again in the federation list.
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

  @override
  bool operator ==(Object other) =>
      other is TradeTrailRecord && _sameList(other._fields, _fields);

  @override
  int get hashCode => Object.hashAll(_fields);

  /// The position and the breach, never a hash.
  @override
  String toString() => 'TradeTrailRecord($position, breached: $breached)';
}

bool _sameList(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
