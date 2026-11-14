import 'package:bull_ui/bull_ui.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';

import '../../domain/trade/trade_status.dart';
import '../../domain/trade/trade_watch.dart';
import '../../domain/trade_record.dart';

/// What the bond panel gives the wallet's payment at each build: the trade, the status shown now and the bond the panel's title states.
///
/// [status] is the status the screen shows, which may be one the trade's cubit kept from an earlier read when the watch gave a status not understood at the same position (`TradeCubit`), never one kept by the slot itself: the payment pull request asks `walletPaymentFor` with it only to offer, and its payment use case reads the order again and pays only from the status it then computes (`AGENTS.md`, « Rules for the screens (#88) »).
/// [seen] is that status as the screen shows it, marked stored (the slot is offered only for a stored status), which the payment's checks take.
/// [amount] is the bond of the title « Lock {{amountSats}} Sats to TAKE order » (`bond_satoshis`, a figure of the coordinator): the confirmation states it, but the ceiling the wallet pays is the decoded amount of the checked invoice, bounded by the take's terms, never this figure.
@immutable
final class WalletPaymentRequest {
  final TradeRecord record;
  final WaitingForTakerBond status;
  final TradeSeen seen;
  final Sats amount;

  /// Whether the screen's clock passed the invoice's `payableUntil`: the wallet offers nothing more, but says where a payment it made stands.
  final bool invoiceExpired;

  const WalletPaymentRequest({
    required this.record,
    required this.status,
    required this.seen,
    required this.amount,
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

  const WalletPaymentSlot(
    this.child, {
    this.othersOpen = false,
    this.othersHidden = false,
  });
}

/// Where a payment of the bond from this wallet stands, as « Cancel » needs it (#100): [sending] while it is being sent, [sent] while it is on its way (sent, held, or not yet known; not refunded nor settled).
@immutable
final class WalletBondState {
  final bool sending;
  final bool sent;

  const WalletBondState({required this.sending, required this.sent});

  static const none = WalletBondState(sending: false, sent: false);
}

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
