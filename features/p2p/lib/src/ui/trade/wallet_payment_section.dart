import 'package:bull_ui/bull_ui.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../domain/trade/trade_status.dart';
import '../../domain/trade/trade_watch.dart';
import '../../domain/trade_record.dart';

/// What the bond panel, or the escrow panel (#97), gives the wallet's payment at each build: the trade, the status shown now, the invoice's step and the amount the panel's title states.
///
/// [status] is the status the screen shows, which may be one the trade's cubit kept from an earlier read when the watch gave a status not understood at the same position (`TradeCubit`), never one kept by the slot itself: the payment pull request asks `walletPaymentFor` with it only to offer, and its payment use case reads the order again and pays only from the status it then computes (`AGENTS.md`, « Rules for the screens (#88) »).
/// [seen] is that status as the screen shows it, marked stored (the slot is offered only for a stored status), which the payment's checks take.
/// [amount] is the bond of the title « Lock {{amountSats}} Sats to TAKE order » (`bond_satoshis`), or the escrow of « Lock {{amountSats}} Sats as collateral » (`escrow_satoshis`), a figure of the coordinator: the ceiling the wallet pays is the decoded amount of the checked invoice, bounded by the take's terms, never this figure.
@immutable
final class WalletPaymentRequest {
  final TradeRecord record;
  final TradeStatus status;
  final TradeSeen seen;
  final Sats amount;

  /// The invoice paid: the taker's bond at 3, or the seller's escrow at 6 and 7.
  final InvoiceStep step;

  /// The trade's currency, which the reference's line on the escrow's hold invoice names; `null` for the bond.
  final RobosatsCurrency? currency;

  /// Whether the screen's clock passed the invoice's `payableUntil`: the wallet offers nothing more, but says where a payment it made stands.
  final bool invoiceExpired;

  const WalletPaymentRequest({
    required this.record,
    required this.status,
    required this.seen,
    required this.amount,
    this.step = InvoiceStep.bond,
    this.currency,
    this.invoiceExpired = false,
  });
}

/// What the wallet offers in the slot: [child], and whether « Pay with another wallet » is to open now ([othersOpen]: the wallet refused, and the other way is the one left).
@immutable
final class WalletPaymentSlot {
  final Widget child;
  final bool othersOpen;

  /// Whether this wallet is paying the invoice or paid it: « Pay with another wallet » then closes and offers neither the QR code nor the copy.
  final bool othersHidden;

  /// Whether it is not known yet, or cannot be read, whether this wallet paid the invoice: the other way is offered only after a tap (the bond's section stays closed; the escrow's QR code waits behind « Pay with another wallet », #97).
  final bool othersBehindTap;

  const WalletPaymentSlot(
    this.child, {
    this.othersOpen = false,
    this.othersHidden = false,
    this.othersBehindTap = false,
  });
}

/// Where a payment of the bond, or of the escrow, from this wallet stands, as « Cancel » needs it (#100, #97): [sending] while either is being sent, [sent] while the bond's is on its way (sent, held, or not yet known; not refunded nor settled), [escrowSent] while the escrow's is; and whether each was paid with this wallet ([bondPaid], [escrowPaid]), for the line that says how a bond or collateral paid so comes back (#207).
@immutable
final class WalletBondState {
  final bool sending;
  final bool sent;
  final bool escrowSent;

  /// Whether the bond, and the escrow, were paid with this wallet, as the trade's payment records tell.
  final WalletPaidHere bondPaid;
  final WalletPaidHere escrowPaid;

  const WalletBondState({
    required this.sending,
    required this.sent,
    this.escrowSent = false,
    this.bondPaid = WalletPaidHere.no,
    this.escrowPaid = WalletPaidHere.no,
  });

  /// This state with the bond said not paid with this wallet: what comes back at 8 of a maker seller's order whose buyer gives no payout is the collateral only, the bond staying locked with the order back in the book (#188).
  WalletBondState get escrowOnly => WalletBondState(
    sending: sending,
    sent: sent,
    escrowSent: escrowSent,
    escrowPaid: escrowPaid,
  );

  static const none = WalletBondState(sending: false, sent: false);
}

/// Whether a bond or an escrow was paid with this wallet, as the trade's payment records tell (#207): [yes] only when the payment of this wallet is established as paying the invoice (the port's « pending », a hold invoice the coordinator holds, or « paid », one settled); [cannotTell] when the records cannot be read, a payment is being sent, or its funds may have left without the invoice established as paid by them (sent but not yet received by the swap service, the bond perhaps locked by another wallet meanwhile; a broadcast not known; a review; an expiry or failure after sending; a refund, which does not tell a hold invoice cancelled after its lock from the service failing to pay it: reviews of #208); [no] otherwise (nothing paid with this wallet, nothing left it, or the records still being read, which takes a moment).
enum WalletPaidHere { no, yes, cannotTell }

/// Builds what the wallet offers for [request], or `null` when it has nothing to offer: then the section is empty and « Pay with another wallet » opens at once.
typedef WalletPaymentBuilder =
    WalletPaymentSlot? Function(
      BuildContext context,
      WalletPaymentRequest request,
    );

/// The slot of « Pay with this wallet » at the top of the bond panel, the owner's request of 2026-11-13 (design note § 2.1): paying from this wallet is to be the main way, « Pay with another wallet » under it the other.
///
/// Empty today: the payment needs the payment engine (#116) and a payment use case, which the next pull request brings by giving the trade screen a [WalletPaymentBuilder]. Without one, or when it builds `null`, the section draws nothing, offers no button, and the panel opens « Pay with another wallet ».
/// The builder decides everything shown in the slot (the balance, « Pay with this wallet », its confirmation, the payment's progress, why the wallet cannot pay); the bond panel only places it.
class WalletPaymentSection extends StatelessWidget {
  final WalletPaymentRequest request;
  final WalletPaymentBuilder? builder;

  const WalletPaymentSection({
    super.key,
    required this.request,
    required this.builder,
  });

  /// What [builder] offers for [request] in [context], `null` when nothing: the bond panel opens « Pay with another wallet » then.
  static WalletPaymentSlot? offer(
    BuildContext context,
    WalletPaymentBuilder? builder,
    WalletPaymentRequest request,
  ) => builder?.call(context, request);

  @override
  Widget build(BuildContext context) =>
      offer(context, builder, request)?.child ?? const SizedBox.shrink();
}
