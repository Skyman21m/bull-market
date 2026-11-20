import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';

import '../p2p_failure.dart';
import '../trade/payout_trace.dart';
import '../trade_record.dart';

/// Where the payout of each contract of a buyer's trade came from, as this device gave it (schema 9, #204; design note `docs/design/phase-3-making-an-order.md` § 3.5 bis): kept so that « Confirm … sent » says, after any restart, whether the payout of the contract the trade stands at was given from this wallet, pasted, or not given from this device.
///
/// One record per trade and contract (`take`), written once the coordinator's answer took the payout or may have ([recordPayout]), and never deleted; the database's triggers refuse a record of a closed trade, of a seller's, of a contract its trail is not at, and the mark of a contract under way before schema 9 (`unrecorded`), which the step to schema 9 alone writes.
/// Each method is one statement that commits on its own; never call it inside a database transaction.
/// It holds no secret: a time, whether it was this wallet's or pasted, an invoice or an address; never the invoice, its payment hash, nor the address.
abstract interface class TradePayoutRepository {
  /// Where the payout of [trade]'s contract [take] came from: [PayoutFromThisWallet], [PayoutPasted], [PayoutUnrecorded] for a contract under way before schema 9, or [PayoutNotGivenHere] when this device recorded none.
  ///
  /// A database that cannot be read, or a row this code never writes, is a [P2pStorageFailure].
  @useResult
  Future<Result<PayoutTrace, P2pFailure>> traceOf(
    TradeRecord trade, {
    required int take,
  });

  /// Records that the payout of [trade]'s contract [take], a [kind] from [source], was given at [at]: the first record of the contract, or a later payout of it (a new invoice at 15, or a payout given after the mark of a contract under way before schema 9), which replaces the one before.
  ///
  /// `false`: nothing was written. A record of a closed trade, of a seller's, or of a contract its trail is not at is refused by the database ([P2pStorageFailure]).
  @useResult
  Future<Result<bool, P2pFailure>> recordPayout(
    TradeRecord trade, {
    required int take,
    required PayoutTraceSource source,
    required PayoutTraceKind kind,
    required DateTime at,
  });
}
