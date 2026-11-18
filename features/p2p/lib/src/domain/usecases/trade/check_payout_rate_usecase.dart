import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show FiatAmount;

import '../../../../public/p2p_wallet_port.dart';
import '../../trade/trade_status.dart';
import '../../trade/trade_terms.dart';
import '../../trade/trade_watch.dart';
import '../../trade/wallet_rate_check.dart';
import '../../trade_record.dart';
import 'trade_reader.dart';

/// The owner's payment rule on the buyer's side (#182, decided on 2026-11-17, design note `docs/design/phase-3-making-an-order.md` § 3.3): for an order made here whose user buys, the sats the coordinator fixed for the contract against the sats the contract's amount is worth at the Bull wallet's own price read now, with the order's premium ([WalletRateCheck.ofMakerPayout]). Information and a warning: it never stops « Submit » nor « Confirm … sent », and moves nothing.
///
/// The sats compared are what the buyer receives: the order's `trade_satoshis`, `Logics.payout_amount`'s `invoice_amount` (`api/views.py:345-371`, given once both bonds are locked, at 6, 8 and 9 alike), which is the payout invoice's amount at 6 and 8 (`WaitingForBoth.payoutAmount`, checked equal to it by the state machine, `PayoutAmountMismatch`), and the order's `last_satoshis` less the maker fee (`MakerTerms.feeAgrees`).
///
/// The price is read through the wallet's port ([P2pWalletPort.bitcoinRate]), outside Tor, as the wallet's own screens read it, unless the wallet's pricer holds it from less than a minute before or is already reading it: the request carries the currency's code and the user's IP address, nothing of the trade (accepted by the owner on 2026-11-17 for the maker bond, the same read). The screen asks it once per contract and step (the payout at 6 or 8, « fiat sent » at 9) when the panel is shown, and again only on « Retry »; never in a loop. The shell bounds a read to 15 s (`ReadWalletRateUsecase.readBound`), past which the price is unavailable.
final class CheckPayoutRateUsecase {
  final TradeReader _reader;
  final P2pWalletPort _wallet;

  const CheckPayoutRateUsecase(this._reader, this._wallet);

  /// The check for [seen], a status of [record]: `null` when there is nothing to compare (a taker's trade, a maker seller's, a status that is not the buyer's payout at 6 or 8 or its « fiat sent » at 9, a status not marked stored, a read that gives no sats, or records that cannot be read), and the price is then not read.
  Future<WalletRateCheck?> execute(TradeRecord record, TradeSeen seen) async {
    if (!seen.stored ||
        record.origin != TradeOrigin.madeHere ||
        record.role != TradeRole.buyer) {
      return null;
    }
    final contract = contractOf(seen);
    if (contract == null) return null;
    final TradeTerms terms;
    switch (await _reader.open(record)) {
      case TradeOpened(:final trade):
        terms = trade.terms;
      case _:
        return null;
    }
    final maker = switch (terms.side) {
      MadeSide(:final maker) when terms.role == TradeRole.buyer => maker,
      _ => null,
    };
    if (maker == null) return null;
    final amount = maker.contractAmount(contract.rangeAmount);
    if (amount == null) return null;
    return WalletRateCheck.ofMakerPayout(
      maker,
      amount: amount,
      received: contract.received,
      wallet: await _wallet.bitcoinRate(record.network, maker.currency),
    );
  }

  /// What a buyer's step of [seen] compares: the sats given (`trade_satoshis`), and a range's amount taken; `null` at any other status.
  static ({Sats received, FiatAmount? rangeAmount})? contractOf(
    TradeSeen seen,
  ) {
    final order = seen.order;
    final rangeAmount = order?.takenAmount;
    final received = switch (seen.status) {
      WaitingForBoth(
        role: TradeRole.buyer,
        :final payoutAmount,
        :final tradeSatoshis,
      ) ||
      WaitingForPayout(
        role: TradeRole.buyer,
        :final payoutAmount,
        :final tradeSatoshis,
      ) => payoutAmount ?? tradeSatoshis,
      Chatting(role: TradeRole.buyer, fiatSent: false) => order?.tradeSatoshis,
      _ => null,
    };
    if (received == null) return null;
    return (received: received, rangeAmount: rangeAmount);
  }
}
