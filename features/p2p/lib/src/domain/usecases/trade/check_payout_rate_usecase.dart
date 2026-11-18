import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show FiatAmount;

import '../../../../public/p2p_wallet_port.dart';
import '../../trade/trade_payout.dart';
import '../../trade/trade_status.dart';
import '../../trade/trade_terms.dart';
import '../../trade/trade_warning.dart';
import '../../trade/trade_watch.dart';
import '../../trade/wallet_rate_check.dart';
import '../../trade_record.dart';
import 'trade_reader.dart';

/// The owner's payment rule on the buyer's side (#182, decided on 2026-11-17, design note `docs/design/phase-3-making-an-order.md` § 3.3): for an order made here whose user buys, the sats the buyer receives against the sats the contract's amount is worth at the Bull wallet's own price, with the order's premium ([WalletRateCheck.ofMakerPayout]). Information and a warning: it never stops « Submit » nor « Confirm … sent », and moves nothing.
///
/// What is compared ([subjectAt], pure), for the contract's amount kept in the trail (the fixed amount, or a range's amount its take chose, #183): at 6 and 8 the sats of the invoice the payout panel asks and « Submit » gives (`PayoutAsk.buyerSats`, the order's `trade_satoshis`), so that the comparison and « Submit invoice for … » speak of the same invoice (security review of #182, C1 bis); at 9, where the coordinator gives no `trade_satoshis` (`api/views.py:346-356` leaves out `CHA`), the order's `satoshis_now` (its `last_satoshis`, `api/views.py:324`) less the maker fee of the terms ([MakerTerms.payoutAt]), which nothing checks: it is compared with the invoice's sats this app kept for the contract ([PayoutRateAsked]), the smaller of the two compared, and without them said as the coordinator's figure of now (security review of #182, C2). Nothing is compared while the state machine says the amounts do not agree ([PayoutRateMismatch]).
///
/// The price is read through the wallet's port ([priceOf], [P2pWalletPort.bitcoinRate]), outside Tor, as the wallet's own screens read it, unless the wallet's pricer holds it from less than a minute before or is already reading it: the request carries the currency's code and the user's IP address, nothing of the trade (accepted by the owner on 2026-11-17 for the maker bond, the same read). When the screen asks it is `PayoutRateCubit`'s. The shell bounds a read to 15 s (`ReadWalletRateUsecase.readBound`), past which the price is unavailable.
final class CheckPayoutRateUsecase {
  final TradeReader _reader;
  final P2pWalletPort _wallet;

  const CheckPayoutRateUsecase(this._reader, this._wallet);

  /// The terms of [record] when the rule applies to it: an order made here whose user buys, its terms readable; `null` otherwise (a taker's trade, a maker seller's, records that cannot be read), and nothing is ever compared nor read for it.
  Future<MakerTerms?> termsOf(TradeRecord record) async {
    if (record.origin != TradeOrigin.madeHere ||
        record.role != TradeRole.buyer) {
      return null;
    }
    final TradeTerms terms;
    switch (await _reader.open(record)) {
      case TradeOpened(:final trade):
        terms = trade.terms;
      case _:
        return null;
    }
    return switch (terms.side) {
      MadeSide(:final maker) when terms.role == TradeRole.buyer => maker,
      _ => null,
    };
  }

  /// The Bull wallet's price of a bitcoin in the currency of [maker], for [record]'s network: one request outside Tor, or none when the wallet's pricer holds it from less than a minute before.
  Future<P2pWalletBitcoinRate> priceOf(TradeRecord record, MakerTerms maker) =>
      _wallet.bitcoinRate(record.network, maker.currency);

  /// The warnings of the state machine that say the amounts of a contract do not agree with each other or with the terms: while one is raised, nothing is compared, the warning alone said (security review of #182, C1 bis).
  static bool amountsDisagree(TradeStatus status) => status.warnings.any(
    (warning) =>
        warning is PayoutAmountMismatch ||
        warning is MakerFeeAboveAnnounced ||
        warning is TakerFeeAboveAnnounced ||
        warning is TradePriceOutsideOrder ||
        warning is InvoiceAmountMismatch,
  );

  /// What the rule compares at [seen], a status of [record] whose terms are [maker]: `null` outside its steps (the payout at 6 or 8, « fiat sent » at 9) or for a status not marked stored.
  ///
  /// [asked] is the smallest invoice's sats this app saw asked at 6 or 8 for the contract, when it kept one (in memory only: not after a restart, #204).
  static PayoutRateSubject? subjectAt(
    TradeRecord record,
    MakerTerms maker,
    TradeSeen seen, {
    Sats? asked,
  }) {
    if (!seen.stored) return null;
    final order = seen.order;
    final status = seen.status;
    // The contract's amount is the one the trail keeps with the contract (a range's amount taken, kept from the contract's first read, #178), or the terms' fixed amount, never the read's alone: a coordinator that shows another amount within the contract has the state machine say it (`TradeTermsChanged`), and the comparison stays on the amount of the contract the user saw taken (#183). A range without one kept, or with one outside its bounds, gives no amount: « rate not checked », never a comparison.
    final kept = status.trail.takenAmount;
    final amount = maker.contractAmount(
      kept == null ? null : FiatAmount.tryCreate(kept),
    );
    // Another amount than the contract's kept one: the state machine's alert alone (`TradeSeen.contractAmountMoved`, C5 of #183).
    final moved = seen.contractAmountMovedFrom(maker.amount);
    switch (status) {
      case WaitingForBoth(role: TradeRole.buyer) ||
          WaitingForPayout(role: TradeRole.buyer):
        final invoice = switch (PayoutAsk.of(record, seen)) {
          Ok(:final value) => value.buyerSats,
          Err() => null,
        };
        // Every figure the coordinator gave for what the buyer receives: the smallest is the one kept for 9.
        final payout = order?.payoutInvoiceAmount;
        final keep = switch ((invoice, payout)) {
          (final a?, final b?) => a.value <= b.value ? a : b,
          (final a?, null) => a,
          (null, final b?) => b,
          _ => null,
        };
        if (amountsDisagree(status) || moved) return PayoutRateMismatch(keep);
        if (invoice == null || amount == null) return const PayoutRateNoSats();
        return PayoutRateCompared(
          received: invoice,
          amount: amount,
          basis: const PayoutRateAskedNow(),
          keep: keep,
        );
      case Chatting(role: TradeRole.buyer, fiatSent: false):
        final last = order?.satoshisNow;
        // A contract this app saw only from 9 on (another taker, « seen late »), with no invoice kept: its alert is said whatever the coordinator's figures then say, beside « rate not checked » or the amounts' warning, never hidden by them (third security pass of #182, R13, #207).
        final notSeen = asked == null && status.has<ContractSeenLate>();
        if (amount == null) return PayoutRateNoSats(notSeen: notSeen);
        // Another amount than the contract's: the alert alone, the kept invoice not compared either, so that no line reassures beside it (C5 of #183).
        if (moved) return PayoutRateMismatch(null, notSeen: notSeen);
        final disagree = amountsDisagree(status);
        // The invoice's sats this app kept are its own figure: compared even when the coordinator's figures are missing or do not agree, beside the state machine's warning (second security review of #182, R8).
        if (asked != null && (last == null || disagree)) {
          return PayoutRateCompared(
            received: asked,
            amount: amount,
            basis: const PayoutRateAskedOnly(),
          );
        }
        // No sats at all is said as such (the state machine's fee warning then only says the same).
        if (last == null) return PayoutRateNoSats(notSeen: notSeen);
        if (disagree) return PayoutRateMismatch(null, notSeen: notSeen);
        final told = maker.payoutAt(last);
        if (asked == null) {
          return PayoutRateCompared(
            received: told,
            amount: amount,
            // A contract this app saw only from 9 on (another taker, « seen late »): its invoice was never seen here, which is no restart (second security review of #182, R9).
            basis: notSeen
                ? const PayoutRateNotSeen()
                : const PayoutRateToldNow(),
          );
        }
        final gap = told.value - asked.value;
        // One sat either way is the rounding of a half (`MakerTerms.payoutAt`, exact, against the coordinator's floats).
        if (gap.abs() <= BigInt.one) {
          return PayoutRateCompared(
            received: told.value <= asked.value ? told : asked,
            amount: amount,
            basis: const PayoutRateAsked(),
          );
        }
        return PayoutRateCompared(
          received: told.value <= asked.value ? told : asked,
          amount: amount,
          basis: PayoutRateTold(told: told, asked: asked),
        );
      case _:
        return null;
    }
  }

  /// The comparison of [subject] for an order of [maker] at the wallet's price [wallet].
  static WalletRateCheck compare(
    MakerTerms maker,
    PayoutRateCompared subject,
    P2pWalletBitcoinRate wallet,
  ) => WalletRateCheck.ofMakerPayout(
    maker,
    amount: subject.amount,
    received: subject.received,
    wallet: wallet,
  );
}

/// What the rule compares at a status.
@immutable
sealed class PayoutRateSubject {
  const PayoutRateSubject();
}

/// The sats the buyer receives, [received], for [amount] of the contract, and where they come from ([basis]); at 6 and 8 the invoice's sats to keep for 9 ([keep]).
final class PayoutRateCompared extends PayoutRateSubject {
  final Sats received;
  final FiatAmount amount;
  final PayoutRateBasis basis;
  final Sats? keep;

  const PayoutRateCompared({
    required this.received,
    required this.amount,
    required this.basis,
    this.keep,
  });

  @override
  bool operator ==(Object other) =>
      other is PayoutRateCompared &&
      other.received == received &&
      other.amount == amount &&
      other.basis == basis;

  @override
  int get hashCode => Object.hash(received, amount, basis);
}

/// The read gives no sats the buyer receives: nothing compared, and the screen says « rate not checked » rather than nothing; at 9, for a contract seen late whose invoice this app never saw, with that alert ([notSeen], #207).
final class PayoutRateNoSats extends PayoutRateSubject {
  final bool notSeen;

  const PayoutRateNoSats({this.notSeen = false});

  @override
  bool operator ==(Object other) =>
      other is PayoutRateNoSats && other.notSeen == notSeen;

  @override
  int get hashCode => Object.hash(0, notSeen);
}

/// The state machine says the contract's amounts do not agree: nothing compared, its warning said alone, but at 9 for a contract seen late whose invoice this app never saw, said with that alert ([notSeen], #207); at 6 and 8 the smallest figure to keep for 9 ([keep]).
final class PayoutRateMismatch extends PayoutRateSubject {
  final Sats? keep;
  final bool notSeen;

  const PayoutRateMismatch(this.keep, {this.notSeen = false});

  @override
  bool operator ==(Object other) =>
      other is PayoutRateMismatch && other.notSeen == notSeen;

  @override
  int get hashCode => Object.hash(1, notSeen);
}

/// Where the sats compared come from.
@immutable
sealed class PayoutRateBasis {
  const PayoutRateBasis();
}

/// At 6 and 8: the invoice the payout panel asks now.
final class PayoutRateAskedNow extends PayoutRateBasis {
  const PayoutRateAskedNow();

  @override
  bool operator ==(Object other) => other is PayoutRateAskedNow;

  @override
  int get hashCode => 2;
}

/// At 9: the coordinator's figure of now agrees with the invoice's sats this app kept for the contract.
final class PayoutRateAsked extends PayoutRateBasis {
  const PayoutRateAsked();

  @override
  bool operator ==(Object other) => other is PayoutRateAsked;

  @override
  int get hashCode => 3;
}

/// At 9: the coordinator now tells [told] sats where the invoice it asked for the contract was of [asked]: the smaller compared, and said.
final class PayoutRateTold extends PayoutRateBasis {
  final Sats told;
  final Sats asked;

  const PayoutRateTold({required this.told, required this.asked});

  @override
  bool operator ==(Object other) =>
      other is PayoutRateTold && other.told == told && other.asked == asked;

  @override
  int get hashCode => Object.hash(told, asked);
}

/// At 9, the coordinator's figures missing or not agreeing: the invoice's sats this app kept for the contract compared alone, the state machine's warning said beside them.
final class PayoutRateAskedOnly extends PayoutRateBasis {
  const PayoutRateAskedOnly();

  @override
  bool operator ==(Object other) => other is PayoutRateAskedOnly;

  @override
  int get hashCode => 5;
}

/// At 9, a contract seen late (`ContractSeenLate`, another taker) whose invoice this app never saw: the coordinator's figure of now, and an alert that the invoice was not seen.
final class PayoutRateNotSeen extends PayoutRateBasis {
  const PayoutRateNotSeen();

  @override
  bool operator ==(Object other) => other is PayoutRateNotSeen;

  @override
  int get hashCode => 6;
}

/// At 9 with no invoice's sats kept for the contract (the app started again between 8 and 9, #204): the coordinator's figure of now, said as such.
final class PayoutRateToldNow extends PayoutRateBasis {
  const PayoutRateToldNow();

  @override
  bool operator ==(Object other) => other is PayoutRateToldNow;

  @override
  int get hashCode => 4;
}
