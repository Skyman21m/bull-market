import 'package:primitives/primitives.dart';

import '../../../../public/p2p_wallet_port.dart';
import '../../trade/trade_payout.dart';
import '../../trade_record.dart';

/// The buyer's payout from this wallet (#90): an invoice of the wallet's Instant Payments wallet for exactly what the coordinator asks, or a new address of its Bitcoin wallet, which the payout panel puts in its field as a pasted one, so that the panel's own check, display and « Submit » apply unchanged.
///
/// The only file of the feature that names `P2pWalletPort.newLightningInvoice` and `newReceiveAddress` (`wallet_port_architecture_test.dart`). It submits nothing: the user still taps « Submit ».
/// The invoice is asked for one payout ([payoutKey]): the wallet gives again the invoice it made for that key while it still waits for its payment, so that taps do not pile up orders at the swap service, and never one made for another trade; a failed payout that asks for a new invoice (status 15) is a new key, so that the coordinator gets another invoice than the one it could not pay.
class PayoutFromWalletUsecase {
  final P2pWalletPort _wallet;

  const PayoutFromWalletUsecase(this._wallet);

  /// An invoice of exactly [amount] for [ask], the trade's payout as the coordinator asks it; [P2pWalletServiceRefused] if the wallet gave another amount (which its port does not).
  Future<Result<P2pWalletInvoice, P2pWalletRefusal>> invoice(
    PayoutAsk ask,
    Sats amount,
  ) async {
    final made = await _wallet.newLightningInvoice(
      ask.record.network,
      amount,
      payout: payoutKey(ask),
    );
    return switch (made) {
      Ok(:final value) when value.amount != amount => const Err(
        P2pWalletServiceRefused(),
      ),
      _ => made,
    };
  }

  /// A new address of the wallet's Bitcoin wallet on the trade's network.
  Future<Result<P2pWalletAddress, P2pWalletRefusal>> address(
    TradeRecord record,
  ) => _wallet.newReceiveAddress(record.network);

  /// The key of [ask]'s payout: the trade (its network, coordinator and order), and for a new invoice after a failed payout (15) the end of that step, which the coordinator sets again at each failure (`api/lightning/lnd.py:680-684`), so that each failed payout gets a new invoice.
  static String payoutKey(PayoutAsk ask) {
    final record = ask.record;
    final trade =
        '${record.network.name}:${record.coordinatorAlias}:${record.orderId}';
    return ask.isNewInvoice
        ? '$trade:again:${ask.deadline.toUtc().microsecondsSinceEpoch}'
        : trade;
  }
}
