import 'package:primitives/primitives.dart';

import '../../../../public/p2p_wallet_port.dart';
import '../../trade/trade_payout.dart';
import '../../trade_record.dart';

/// The buyer's payout from this wallet (#90): an invoice of the wallet's Instant Payments wallet for exactly what the coordinator asks, or a new address of its Bitcoin wallet, which the payout panel puts in its field as a pasted one, so that the panel's own check, display and « Submit » apply unchanged.
///
/// The only file of the feature that names `P2pWalletPort.newLightningInvoice` and `newReceiveAddress` (`wallet_port_architecture_test.dart`). It submits nothing: the user still taps « Submit ».
/// The invoice is asked for one payout, the trade's and its contract's ([payoutKey]): the wallet gives again the invoice it made for that key while it still waits for its payment, so that taps do not pile up orders at the swap service, and never one made for another trade or another contract.
/// After a failed payout (15) the key stays the trade's: the wallet makes a new invoice once its earlier order for the trade has ended, and while it still waits it gives that invoice again, which the coordinator refuses (« You must submit a NEW invoice », `api/logics.py:878-880`; the payment hash is the primary key of its payments, `api/models/ln_payment.py:67-69`): such an invoice, given for this trade at an earlier step, is not put in the field ([PayoutWalletEarlierInvoiceOpen]).
/// One instance for the app's run (a lazy singleton), so that it remembers, in memory only, the step at which it gave each invoice; after a restart the coordinator's own refusal says it.
class PayoutFromWalletUsecase {
  final P2pWalletPort _wallet;

  /// The step ([_stepOf]) at which each invoice was first given, by its text.
  final Map<String, String> _firstGivenAt = {};

  PayoutFromWalletUsecase(this._wallet);

  /// An invoice of exactly [amount] for [ask], the trade's payout as the coordinator asks it; [P2pWalletServiceRefused] if the wallet gave another amount (which its port does not); [PayoutWalletEarlierInvoiceOpen] at 15 for the invoice it gave for this trade before the payout failed.
  Future<Result<P2pWalletInvoice, PayoutWalletNoInvoice>> invoice(
    PayoutAsk ask,
    Sats amount,
  ) async {
    final made = await _wallet.newLightningInvoice(
      ask.record.network,
      amount,
      payout: payoutKey(ask),
    );
    switch (made) {
      case Err(:final failure):
        return Err(PayoutWalletRefusedInvoice(failure));
      case Ok(:final value) when value.amount != amount:
        return const Err(PayoutWalletRefusedInvoice(P2pWalletServiceRefused()));
      case Ok(:final value):
        final step = _stepOf(ask);
        final first = _firstGivenAt.putIfAbsent(value.bolt11, () => step);
        if (ask.isNewInvoice && first != step) {
          return const Err(PayoutWalletEarlierInvoiceOpen());
        }
        return Ok(value);
    }
  }

  /// A new address of the wallet's Bitcoin wallet on the trade's network.
  Future<Result<P2pWalletAddress, P2pWalletRefusal>> address(
    TradeRecord record,
  ) => _wallet.newReceiveAddress(record.network);

  /// The key of [ask]'s payout, one per trade and contract: its network, coordinator and order (`network:coordinatorAlias:orderId`), the same at 6, 8 and 15, for contract 0 (every taker's trade, and a maker's first contract), so that an invoice asked before this key had a contract is given again as before; and the contract appended (`network:coordinatorAlias:orderId:take`) from contract 1 on, a maker buyer's order taken again after a return to the book (#179, design note `docs/design/phase-3-making-an-order.md` § 3.4): its amount is the new contract's, and the coordinator keys its payments by payment hash (`api/models/ln_payment.py:67-69`), so the invoice of an earlier contract is never given again.
  /// Two trades never share it: a coordinator's order has one open trade at a time on a network; the contract is the trail's of the status the payout is asked at.
  static String payoutKey(PayoutAsk ask) {
    final record = ask.record;
    final trade =
        '${record.network.name}:${record.coordinatorAlias}:${record.orderId}';
    final take = ask.seen.status.trail.take;
    return take == 0 ? trade : '$trade:$take';
  }

  /// The step of [ask]: its status and its end, which the coordinator sets again at each failed payout (`api/lightning/lnd.py:680-684`).
  static String _stepOf(PayoutAsk ask) =>
      '${ask.seen.status.position.name}:${ask.deadline.toUtc().microsecondsSinceEpoch}';
}

/// Why [PayoutFromWalletUsecase.invoice] gives no invoice.
sealed class PayoutWalletNoInvoice extends Failure {
  const PayoutWalletNoInvoice();
}

/// The wallet refused: [refusal] says why.
final class PayoutWalletRefusedInvoice extends PayoutWalletNoInvoice {
  final P2pWalletRefusal refusal;

  const PayoutWalletRefusedInvoice(this.refusal);

  @override
  String toString() => 'PayoutWalletRefusedInvoice(${refusal.runtimeType})';
}

/// At 15, the wallet gave again the invoice it gave for this trade before the payout failed: it still waits for its payment, and the coordinator takes only a new invoice (`api/logics.py:878-880`).
final class PayoutWalletEarlierInvoiceOpen extends PayoutWalletNoInvoice {
  const PayoutWalletEarlierInvoiceOpen();
}
