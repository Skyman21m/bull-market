import '../trade_record.dart' show TradeRole;
import 'payout_trace.dart';
import 'trade_status.dart';
import 'trade_warning.dart';
import 'trade_watch.dart';
import 'wallet_rate_check.dart';

/// What counts as an alert the trade screen shows the user beside a payment's comparison with the Bull wallet's price (the owner's rule that an alert speaks alone, never with a reassuring line beside it; corrections C1 of the functional review and C1, C2 of the security review of #249). The one place this rule is written: the confirmation of « Pay with this wallet » (the bond, the escrow) and a buyer's payout read it, for an order taken here and an order made here alike.
///
/// An alert is:
/// - a warning of the state machine on the status shown, or on its invoice, but `ContractSeenLate` (a next contract seen late is information, drawn in the text colour) ([stateMachine]);
/// - the trace of terms shown otherwise (#231: the coordinator showed this trade with other terms, then put them back), drawn in the warning colour while the trade lasts ([termsTrace]);
/// - at 9, the trace of a buyer's payout not given from this wallet (#204: pasted, given elsewhere, or not known), drawn in the warning colour before « Confirm … sent » ([payoutTrace]).
///
/// Beside an alert, only the line that reassures is left out ([reassuresBeside]); an alert never silences another: a red comparison, « rate not checked » and « not priced » stay, in the confirmation of « Pay with this wallet » as at the payout, for a taker and a maker (security review of #249, C5: a confirmation stays open, and « Pay » with it, when a read brings an alert).
///
/// The alerts a confirmation draws of its own (a maker seller's earlier escrows not back or kept, the order's bond held too, a confirmation stale or asked again) are its caller's to add ([reassuresBeside]'s `besides`).
abstract final class ShownAlerts {
  /// Whether [seen] shows any alert of the trade ([stateMachine], [termsTrace], [payoutTrace]).
  static bool any(TradeSeen seen) =>
      stateMachine(seen.status) || termsTrace(seen.status) || payoutTrace(seen);

  /// Whether [status] or its invoice carries a warning of the state machine other than `ContractSeenLate`.
  static bool stateMachine(TradeStatus status) {
    final invoice = status.invoice;
    return [
      ...status.warnings,
      if (invoice case CheckedInvoice(:final warnings)) ...warnings,
    ].any((warning) => warning is! ContractSeenLate);
  }

  /// Whether the trace of terms shown otherwise is drawn for [status] (#231): a read showed other terms since schema 9, the trade has not ended, and the status shown does not carry `TradeTermsChanged` itself (whose own alert speaks then).
  static bool termsTrace(TradeStatus status) =>
      status.trail.termsChangedAt != null &&
      !status.isTerminal &&
      !status.has<TradeTermsChanged>();

  /// Whether the trace of where a buyer's payout came from is drawn for [seen] (#204): at 9, before « Fiat sent », for a buyer whose payout was not given from this wallet, or whose trace is not known. The screen leaves it out where the rule's own red line says the invoice was never seen here (`p2pPayoutRateNotSeen`), itself an alert.
  static bool payoutTrace(TradeSeen seen) {
    final status = seen.status;
    return status is Chatting &&
        status.role == TradeRole.buyer &&
        !status.fiatSent &&
        seen.payout is! PayoutFromThisWallet;
  }

  /// Whether the line of [check] would reassure beside an alert of [seen] ([any]) or beside one its caller draws ([besides]): a comparison within the owner's threshold. Such a line is not drawn. A comparison that is itself an alert (red, « rate not checked », a currency the Bull wallet does not price) is drawn beside it.
  static bool reassuresBeside(
    TradeSeen seen,
    WalletRateCheck check, {
    bool besides = false,
  }) => (besides || any(seen)) && check is WalletRateCompared && !check.warns;
}
