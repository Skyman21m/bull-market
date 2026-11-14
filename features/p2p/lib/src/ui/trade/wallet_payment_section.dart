import 'package:bull_ui/bull_ui.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';

import '../../domain/trade/trade_status.dart';
import '../../domain/trade_record.dart';

/// What the bond panel gives the wallet's payment at each build: the trade, the status shown now and the bond the panel's title states.
///
/// [status] is the status of the trade's last read, never one kept by the slot: the payment pull request asks `walletPaymentFor` with it, and its payment use case reads the order again and pays only from the status it then computes (`AGENTS.md`, « Rules for the screens (#88) »).
/// [amount] is the bond of the title « Lock {{amountSats}} Sats to TAKE order » (`bond_satoshis`): the confirmation states it, and the wallet pays at most it.
@immutable
final class WalletPaymentRequest {
  final TradeRecord record;
  final WaitingForTakerBond status;
  final Sats amount;

  const WalletPaymentRequest({
    required this.record,
    required this.status,
    required this.amount,
  });
}

/// Builds what the wallet offers for [request], or `null` when it has nothing to offer: then the section is empty and « Pay with another wallet » opens at once.
typedef WalletPaymentBuilder =
    Widget? Function(BuildContext context, WalletPaymentRequest request);

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
  static Widget? offer(
    BuildContext context,
    WalletPaymentBuilder? builder,
    WalletPaymentRequest request,
  ) => builder?.call(context, request);

  @override
  Widget build(BuildContext context) =>
      offer(context, builder, request) ?? const SizedBox.shrink();
}
