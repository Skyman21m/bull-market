import 'package:meta/meta.dart';
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
/// The sats compared are what the buyer receives, `Logics.payout_amount`'s `invoice_amount` (`api/logics.py:650-669`): at 6 and 8 the payout invoice's amount the coordinator asks (`WaitingForBoth.payoutAmount`, checked by the state machine, `PayoutAmountMismatch`); at 9, where the coordinator gives no `trade_satoshis` (`api/views.py:346-356` lists 6, 7, 8, 10 to 15, not 9), the same figure computed from the order's `satoshis_now`, its `last_satoshis` (`api/views.py:324`), and the maker fee of the terms ([MakerTerms.payoutAt]).
///
/// The price is read through the wallet's port ([P2pWalletPort.bitcoinRate]), outside Tor, as the wallet's own screens read it, unless the wallet's pricer holds it from less than a minute before or is already reading it: the request carries the currency's code and the user's IP address, nothing of the trade (accepted by the owner on 2026-11-17 for the maker bond, the same read). The screen asks it once per contract and step (the payout at 6 or 8, « fiat sent » at 9) when the panel is shown, and again only on « Retry »; never in a loop. The shell bounds a read to 15 s (`ReadWalletRateUsecase.readBound`), past which the price is unavailable.
final class CheckPayoutRateUsecase {
  final TradeReader _reader;
  final P2pWalletPort _wallet;

  const CheckPayoutRateUsecase(this._reader, this._wallet);

  /// The finding for [seen], a status of [record]: `null` when the rule says nothing (a taker's trade, a maker seller's, a status that is not the buyer's payout at 6 or 8 or its « fiat sent » at 9, a status not marked stored, or records that cannot be read), and the price is then not read; [PayoutRateNoSats] when the read gives no sats the buyer receives (nothing compared, said as « rate not checked », the price not read); otherwise the comparison ([PayoutRateFound]).
  ///
  /// The sats compared: at 6 and 8 the payout's `invoice_amount` (`WaitingForBoth.payoutAmount`, else the order's `trade_satoshis`, `api/views.py:345-371`); at 9, where the coordinator gives no `trade_satoshis` (its list leaves out `CHA`, `api/views.py:346-356`), the order's `satoshis_now` (its `last_satoshis`, given to a participant at every status, `api/views.py:324`) less the maker fee of the terms, as `Logics.payout_amount` computes `invoice_amount` ([MakerTerms.payoutAt]).
  Future<PayoutRateFinding?> execute(TradeRecord record, TradeSeen seen) async {
    if (!seen.stored ||
        record.origin != TradeOrigin.madeHere ||
        record.role != TradeRole.buyer) {
      return null;
    }
    final step = stepOf(seen);
    if (step == null) return null;
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
    final sats = satsOf(maker, seen);
    if (sats == null) return const PayoutRateNoSats();
    return PayoutRateFound(
      WalletRateCheck.ofMakerPayout(
        maker,
        amount: sats.amount,
        received: sats.received,
        wallet: await _wallet.bitcoinRate(record.network, maker.currency),
      ),
    );
  }

  /// The finding for [seen] of an order of [maker], at the wallet's price [wallet], as [execute] makes it once it has the terms and the price: `null` outside the rule's steps.
  static PayoutRateFinding? findingAt(
    MakerTerms maker,
    TradeSeen seen, {
    required P2pWalletBitcoinRate wallet,
  }) {
    if (stepOf(seen) == null) return null;
    final sats = satsOf(maker, seen);
    if (sats == null) return const PayoutRateNoSats();
    return PayoutRateFound(
      WalletRateCheck.ofMakerPayout(
        maker,
        amount: sats.amount,
        received: sats.received,
        wallet: wallet,
      ),
    );
  }

  /// The sats the buyer receives at [seen] and the contract's amount, for an order of [maker]: the payout's at 6 and 8, the order's `last_satoshis` less the maker fee where the coordinator gives no `trade_satoshis` (9); `null` when the read gives neither, or outside the rule's steps.
  static ({Sats received, FiatAmount amount})? satsOf(
    MakerTerms maker,
    TradeSeen seen,
  ) {
    final step = stepOf(seen);
    if (step == null) return null;
    final last = step.last;
    final received = step.given ?? (last == null ? null : maker.payoutAt(last));
    final amount = maker.contractAmount(step.rangeAmount);
    if (received == null || amount == null) return null;
    return (received: received, amount: amount);
  }

  /// What a buyer's step of [seen] gives: the payout's sats at 6 and 8 ([given]), the order's `last_satoshis` ([last]), and a range's amount taken; `null` at any other status.
  static ({Sats? given, Sats? last, FiatAmount? rangeAmount})? stepOf(
    TradeSeen seen,
  ) {
    final order = seen.order;
    final last = order?.satoshisNow;
    final rangeAmount = order?.takenAmount;
    return switch (seen.status) {
      WaitingForBoth(
        role: TradeRole.buyer,
        :final payoutAmount,
        :final tradeSatoshis,
      ) ||
      WaitingForPayout(
        role: TradeRole.buyer,
        :final payoutAmount,
        :final tradeSatoshis,
      ) => (
        given: payoutAmount ?? tradeSatoshis,
        last: last,
        rangeAmount: rangeAmount,
      ),
      // No `trade_satoshis` at 9 (`api/views.py:346-356`): the order's `last_satoshis` only.
      Chatting(role: TradeRole.buyer, fiatSent: false) => (
        given: null,
        last: last,
        rangeAmount: rangeAmount,
      ),
      _ => null,
    };
  }
}

/// What the owner's rule on a maker buyer's side found for a step.
@immutable
sealed class PayoutRateFinding {
  const PayoutRateFinding();
}

/// The sats the buyer receives compared with the contract's amount at the Bull wallet's price.
final class PayoutRateFound extends PayoutRateFinding {
  final WalletRateCheck check;

  const PayoutRateFound(this.check);
}

/// The read gives no sats the buyer receives: nothing compared, and the screen says « rate not checked » rather than nothing.
final class PayoutRateNoSats extends PayoutRateFinding {
  const PayoutRateNoSats();
}
