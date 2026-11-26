import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../../public/p2p_wallet_port.dart';
import '../domain/robot_binding.dart';
import '../domain/trade/trade_payout.dart';
import '../domain/trade/trade_status.dart';
import '../domain/trade/trade_watch.dart';
import '../domain/trade/wallet_rate_check.dart';
import '../domain/trade_record.dart';
import '../domain/usecases/trade/check_payout_rate_usecase.dart';

/// [CheckPayoutRateUsecase.termsOf], which the locator gives the cubit.
typedef PayoutRateTermsOf =
    Future<PayoutRateTermsRead?> Function(TradeRecord record);

/// [CheckPayoutRateUsecase.priceOf], which the locator gives the cubit.
typedef PayoutRatePriceOf =
    Future<P2pWalletBitcoinRate> Function(
      TradeRecord record,
      PayoutRateTerms terms,
    );

/// Which buyer's step a check is for: the payout (6 and 8, and since #237 15 once a new invoice is asked) or « fiat sent » (9), of a contract ([take]).
@immutable
final class PayoutRateStep {
  final int take;
  final bool fiatSent;

  const PayoutRateStep(this.take, {required this.fiatSent});

  /// The step of [status], `null` where the rule says nothing: at 15 only once the failed invoice expired and a new one is asked, of the same sats as at 6 and 8 (design note `docs/design/phase-3-making-an-order.md` § 3.3 bis); before that the coordinator retries and asks nothing.
  static PayoutRateStep? of(TradeStatus status) => switch (status) {
    WaitingForBoth(role: TradeRole.buyer) ||
    WaitingForPayout(role: TradeRole.buyer) ||
    RoutingFailed(
      role: TradeRole.buyer,
      invoiceExpired: true,
    ) => PayoutRateStep(status.trail.take, fiatSent: false),
    Chatting(role: TradeRole.buyer, fiatSent: false) => PayoutRateStep(
      status.trail.take,
      fiatSent: true,
    ),
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is PayoutRateStep &&
      other.take == take &&
      other.fiatSent == fiatSent;

  @override
  int get hashCode => Object.hash(take, fiatSent);
}

/// What the rule keeps beyond one page of a trade, until the app stops (in memory only, never on disk: schema 9 keeps where a payout came from, #204, not its sats): per contract the smallest invoice's sats asked at 6 or 8 (for 9) and the largest the payout panel asked at 6 or 8 (for 15, #281), and per network and currency the last price read and when.
final class PayoutRateMemory {
  final Map<(RobotSlot, String, int, int), Sats> _asked = {};
  final Map<(RobotSlot, String, int, int), Sats> _first = {};
  final Map<
    (RobosatsNetwork, String),
    ({P2pWalletBitcoinRate price, DateTime at})
  >
  _prices = {};

  /// The smallest invoice's sats asked at 6 or 8 for contract [take] of [record], when this run of the app saw one.
  Sats? askedOf(TradeRecord record, int take) =>
      _asked[(record.robot, record.coordinatorAlias, record.orderId, take)];

  /// [sats] asked at 6 or 8 for contract [take] of [record]: kept when smaller than what is kept (an honest coordinator never changes a contract's sats, `api/logics.py:1331-1335`).
  void keepAsked(TradeRecord record, int take, Sats sats) {
    final key = (record.robot, record.coordinatorAlias, record.orderId, take);
    final kept = _asked[key];
    if (kept == null || sats.value < kept.value) _asked[key] = sats;
  }

  /// The largest invoice's sats the payout panel asked at 6 or 8 for contract [take] of [record], when this run of the app saw one: what 15 is compared with (#281).
  Sats? firstOf(TradeRecord record, int take) =>
      _first[(record.robot, record.coordinatorAlias, record.orderId, take)];

  /// [sats] asked by the payout panel at 6 or 8 for contract [take] of [record]: kept when larger than what is kept, so that no earlier read of a smaller sum can make a smaller sum at 15 look unchanged (design note § 3.3 bis, point 4).
  void keepFirst(TradeRecord record, int take, Sats sats) {
    final key = (record.robot, record.coordinatorAlias, record.orderId, take);
    final kept = _first[key];
    if (kept == null || sats.value > kept.value) _first[key] = sats;
  }

  /// The last price read for [currency] on [network], and when.
  ({P2pWalletBitcoinRate price, DateTime at})? priceOf(
    RobosatsNetwork network,
    String currency,
  ) => _prices[(network, currency)];

  void keepPrice(
    RobosatsNetwork network,
    String currency,
    P2pWalletBitcoinRate price,
    DateTime at,
  ) => _prices[(network, currency)] = (price: price, at: at);
}

/// Where the check of the step shown stands.
@immutable
sealed class PayoutRateState {
  const PayoutRateState();
}

/// Nothing to show: no step of the rule, or nothing to compare.
final class PayoutRateNone extends PayoutRateState {
  const PayoutRateNone();
}

/// The Bull wallet's price is being read for [step].
final class PayoutRateReading extends PayoutRateState {
  final PayoutRateStep step;

  const PayoutRateReading(this.step);
}

/// The check of [step], of sats coming from [basis]; for a currency the Bull wallet does not price, of an order made here, [against] the gap in hundredths of a percent of the contract's sats against the buyer since the order was made, only beyond the owner's threshold (#237, `CheckPayoutRateUsecase.againstOf`), `null` otherwise.
final class PayoutRateChecked extends PayoutRateState {
  final PayoutRateStep step;
  final WalletRateCheck check;
  final PayoutRateBasis basis;
  final BigInt? against;

  const PayoutRateChecked(
    this.step,
    this.check, {
    this.basis = const PayoutRateAskedNow(),
    this.against,
  });
}

/// This device's records of the trade could not be opened now, so nothing of [step] was compared (#237): « Amount not checked », with « Retry », which reads them again; [given] the sats the payout panel asks at 6, 8 and 15 (`PayoutAsk.buyerSats`), for the breakdown to draw it, `null` where none is asked.
final class PayoutRateTermsUnread extends PayoutRateState {
  final PayoutRateStep step;
  final Sats? given;

  const PayoutRateTermsUnread(this.step, {this.given});
}

/// The read of [step] gives no sats the buyer receives: nothing compared, « rate not checked » said rather than nothing; [notSeen] for a contract seen late at 9 whose invoice this app never saw, whose alert is said too (#207).
final class PayoutRateSatsMissing extends PayoutRateState {
  final PayoutRateStep step;
  final bool notSeen;

  const PayoutRateSatsMissing(this.step, {this.notSeen = false});
}

/// The state machine says the amounts of [step]'s contract do not agree: nothing compared, its warning said alone (security review of #182, C1 bis), but for a contract seen late at 9 whose invoice this app never saw ([notSeen]), whose alert is said beside it (third security pass of #182, R13, #207).
final class PayoutRateAmountsDisagree extends PayoutRateState {
  final PayoutRateStep step;
  final bool notSeen;

  const PayoutRateAmountsDisagree(this.step, {this.notSeen = false});
}

/// The comparison of [step] is within the owner's threshold while the screen shows an alert (`ShownAlerts.any`: a warning of the state machine, the trace of terms shown otherwise, the trace of a payout not given from this wallet; `CheckPayoutRateUsecase.reassuresBesideAlert`): nothing drawn, the alert said alone, never a reassuring line beside it (C1 of the functional review, C1 and C2 of the security review of #249, for any buyer).
final class PayoutRateAlertAlone extends PayoutRateState {
  final PayoutRateStep step;

  const PayoutRateAlertAlone(this.step);
}

/// What a line of the rule says, to tell whether a read changed it.
enum PayoutRateVerdict {
  none,
  reading,
  within,
  warns,
  notPriced,
  unverified,
  satsMissing,
  disagree,

  /// A currency the Bull wallet does not price, with the alert of a gap against the buyer since the order was made (#237).
  notPricedAgainst,

  /// The trade's records could not be opened: nothing compared (#237).
  termsUnread,

  /// Nothing drawn beside an alert of the state machine ([PayoutRateAlertAlone]).
  alertAlone,
}

/// The owner's payment rule on a buyer's side (#182, design note § 3.3), on the trade screen: the only caller of [CheckPayoutRateUsecase], for an order made here whose user buys and, since #249, for an order taken here whose user buys ([CheckPayoutRateUsecase.termsOf]; a seller's trade never sees it, not even « reading »).
///
/// What is compared follows each read of the order shown, at once, with the price already read: another figure at the same step is compared again (security review of #182, C1). The Bull wallet's price is read (one request outside Tor, [CheckPayoutRateUsecase.priceOf]) only while the screen is shown (the screen does not call [show] when hidden), and only when a step has something to compare and: no price of the currency was read in this run of the app; or the step is shown for the first time, appears anew (the screen built or shown again, the app back) or moves to another status (8 after 6) while the last read is [freshFor] old (or could not be read, for a step shown for the first time); or « Submit » or « Confirm … sent » is pressed while it is [freshFor] old ([beforeAct]); or « Retry » after a price that could not be read. A new read of the same status, which the trade's watch brings at its own cadence, never reads it: never in a loop.
class PayoutRateCubit extends Cubit<PayoutRateState> {
  final TradeRecord record;
  final PayoutRateTermsOf _termsOf;
  final PayoutRatePriceOf _priceOf;
  final PayoutRateMemory memory;

  /// The clock of the reads' age.
  final DateTime Function() now;

  /// How old a price may be when its step is shown again or acted on: older, it is read again (the create form's own bound, `MakeOrderCubit.staleAfter`).
  static const Duration freshFor = Duration(minutes: 3);

  /// How long a read is awaited, past which the price is taken as not read (the shell's own bound, `ReadWalletRateUsecase.readBound`).
  static const Duration readBound = Duration(seconds: 15);

  PayoutRateTerms? _terms;
  bool _termsRead = false;
  Future<PayoutRateTermsRead?>? _termsReading;

  /// Whether the last reading of the terms found this device's records unreadable (#237): tried again at « Retry » and when the step is shown anew, never at the watch's cadence, and never kept as the answer for the page's life.
  bool _unreadable = false;

  /// The status shown last, its step and its kind (8 after 6 is the same step at another status).
  TradeSeen? _seen;
  PayoutRateStep? _step;
  Type? _status;

  /// The price read under way, which every caller awaits rather than reading again.
  Future<void>? _reading;

  PayoutRateCubit(
    this.record, {
    required PayoutRateTermsOf terms,
    required PayoutRatePriceOf price,
    required this.memory,
    required this.now,
  }) : _termsOf = terms,
       _priceOf = price,
       super(const PayoutRateNone());

  /// A buyer's trade, made or taken here: which of them the rule compares, [CheckPayoutRateUsecase.termsOf] says.
  bool get _applies => record.role == TradeRole.buyer;

  /// The screen shows [seen]: what it compares is compared at once with the price read, and the price read as the class says, [appeared] when the step appears anew (the screen built, shown again, the app back).
  Future<void> show(TradeSeen seen, {bool appeared = false}) async {
    if (!_applies || isClosed) return;
    final step = PayoutRateStep.of(seen.status);
    if (step == null || !seen.stored) {
      // Compared with the step shown before this one, before it is forgotten: a step gone (a read refused while waiting, the order at 10) leaves nothing of its check, so that no line of it stays where the screen shows none (security review of #219, C1; before, `_step` was cleared first and the check stayed).
      final changed = step != _step;
      if (step == null) {
        _seen = null;
        _step = null;
        _status = null;
      }
      if (state is! PayoutRateNone && changed) {
        emit(const PayoutRateNone());
      }
      return;
    }
    final newStep = step != _step;
    final moved =
        !newStep && _status != null && _status != seen.status.runtimeType;
    _seen = seen;
    _step = step;
    _status = seen.status.runtimeType;
    final PayoutRateTermsRead? found;
    if (_termsRead) {
      found = _terms;
    } else if (_unreadable && !(newStep || appeared || moved)) {
      // Records that could not be read are read again only when the step is shown anew or at « Retry », never at the watch's cadence (#237).
      found = const PayoutRateTermsUnreadable();
    } else {
      // « Reading » before the terms are known only for an order made here, as since #182: a taker buyer whose terms give nothing to compare never sees it (R6 of the functional review of #249); one whose terms are compared sees it once the price is asked.
      if (record.origin == TradeOrigin.madeHere) {
        emit(PayoutRateReading(step));
      }
      found = await _readTerms();
    }
    // A later show took over meanwhile: it does the rest.
    if (isClosed || !identical(_seen, seen)) return;
    final PayoutRateTerms terms;
    switch (found) {
      case null:
        // The rule does not compare this trade: nothing said, none emitted again over none.
        if (state is! PayoutRateNone) emit(const PayoutRateNone());
        return;
      case PayoutRateTermsUnreadable():
        // Never silent: the silence of the rule says « checked, nothing wrong » (#237).
        emit(PayoutRateTermsUnread(step, given: _givenOf(seen)));
        return;
      case final PayoutRateTerms readable:
        terms = readable;
    }
    final subject = _subjectOf(terms, seen);
    final kept = memory.priceOf(record.network, terms.currency.code);
    final stale = kept == null || !now().isBefore(kept.at.add(freshFor));
    final unread = kept?.price is P2pWalletRateUnavailable;
    final read =
        subject is PayoutRateCompared &&
        _reading == null &&
        (kept == null ||
            ((newStep || appeared || moved) && (stale || (newStep && unread))));
    if (read) {
      await _read(terms);
    } else {
      _emitFor(
        step,
        terms,
        seen,
        subject,
        _reading == null ? kept?.price : null,
      );
    }
  }

  /// « Retry »: the price read again, only after a price that could not be read; after records that could not be read (#237), the records opened again (nothing sent), then, when they give the terms, the step checked as when it is shown anew, which may read the price.
  Future<void> retry() async {
    if (isClosed) return;
    if (state is PayoutRateTermsUnread) {
      final seen = _seen;
      if (seen != null) await show(seen, appeared: true);
      return;
    }
    final terms = _terms;
    if (terms == null) return;
    if (state case PayoutRateChecked(check: WalletRateUnverified())) {
      await _read(terms);
    }
  }

  /// Before « Submit » gives the payout, or before the dialog of « Confirm … sent » opens (decided by the coordinator of the work after the reviews of #182): a price read under way is awaited, and a price [freshFor] old read again (within [readBound]); `true` when the line shown did not change, or now says the sats are within the margin with no warning (the press goes on: a line that became « within the margin », from a read under way as from « rate not checked » or a warning, never stops it, third functional pass of #182, #207), `false` when it changed to any other line, which the screen then shows, and a second press goes on. Nothing is ever blocked.
  Future<bool> beforeAct() async {
    final terms = _terms;
    final seen = _seen;
    if (!_applies || isClosed || terms == null || seen == null) return true;
    final before = verdictOf(state);
    final reading = _reading;
    if (reading != null) {
      await reading;
    } else if (_subjectOf(terms, seen) is PayoutRateCompared) {
      final kept = memory.priceOf(record.network, terms.currency.code);
      if (kept == null || !now().isBefore(kept.at.add(freshFor))) {
        await _read(terms);
      }
    }
    if (isClosed) return false;
    final after = verdictOf(state);
    return after == before || after == PayoutRateVerdict.within;
  }

  /// What the line of [state] says.
  static PayoutRateVerdict verdictOf(PayoutRateState state) => switch (state) {
    PayoutRateNone() => PayoutRateVerdict.none,
    PayoutRateReading() => PayoutRateVerdict.reading,
    // A contract seen late whose invoice this app never saw is an alert of its own (#207).
    PayoutRateSatsMissing(notSeen: true) ||
    PayoutRateAmountsDisagree(notSeen: true) => PayoutRateVerdict.warns,
    PayoutRateSatsMissing() => PayoutRateVerdict.satsMissing,
    PayoutRateAmountsDisagree() => PayoutRateVerdict.disagree,
    PayoutRateAlertAlone() => PayoutRateVerdict.alertAlone,
    PayoutRateTermsUnread() => PayoutRateVerdict.termsUnread,
    PayoutRateChecked(:final check, :final basis, :final against) =>
      switch (check) {
        // A coordinator's figure that moved since the invoice is an alert of its own, whatever the price says; at 15, fewer sats than at 6 or 8 too (#281).
        _
            when basis is PayoutRateTold ||
                basis is PayoutRateNotSeen ||
                basis is PayoutRateBelowFirst =>
          PayoutRateVerdict.warns,
        WalletRateCompared(:final warns) =>
          warns ? PayoutRateVerdict.warns : PayoutRateVerdict.within,
        WalletRateNotPriced() when against != null =>
          PayoutRateVerdict.notPricedAgainst,
        WalletRateNotPriced() => PayoutRateVerdict.notPriced,
        WalletRateUnverified() => PayoutRateVerdict.unverified,
      },
  };

  /// The terms read from this device's records, kept for the page's life once read; records that could not be read are not kept, and read again at the next call (#237).
  Future<PayoutRateTermsRead?> _readTerms() async {
    if (_termsRead) return _terms;
    final read = await (_termsReading ??= _termsOf(record));
    _termsReading = null;
    switch (read) {
      case PayoutRateTermsUnreadable():
        _unreadable = true;
      case final PayoutRateTerms? terms:
        _unreadable = false;
        _terms = terms;
        _termsRead = true;
    }
    return read;
  }

  /// The sats the payout panel asks at [seen] (6, 8 and 15), for the breakdown to draw « Amount not checked » beside them; `null` where none is asked.
  Sats? _givenOf(TradeSeen seen) => switch (PayoutAsk.of(record, seen)) {
    Ok(:final value) => value.buyerSats,
    Err() => null,
  };

  /// What [seen] compares, the figures of 6 and 8 it shows kept for 9 and for 15 (never those of 15, which is compared with them, #281).
  PayoutRateSubject? _subjectOf(PayoutRateTerms terms, TradeSeen seen) {
    final take = seen.status.trail.take;
    final subject = CheckPayoutRateUsecase.subjectFor(
      record,
      terms,
      seen,
      asked: memory.askedOf(record, take),
      first: memory.firstOf(record, take),
    );
    final (keep, keepFirst) = switch (subject) {
      PayoutRateCompared(:final keep, :final keepFirst) ||
      PayoutRateMismatch(:final keep, :final keepFirst) => (keep, keepFirst),
      _ => (null, null),
    };
    if (keep != null) memory.keepAsked(record, take, keep);
    if (keepFirst != null) memory.keepFirst(record, take, keepFirst);
    return subject;
  }

  /// The state of [step] for [subject], of [seen], at [price]: a comparison within the threshold beside an alert the screen shows is [PayoutRateAlertAlone] ([CheckPayoutRateUsecase.reassuresBesideAlert]).
  void _emitFor(
    PayoutRateStep step,
    PayoutRateTerms terms,
    TradeSeen seen,
    PayoutRateSubject? subject,
    P2pWalletBitcoinRate? price,
  ) {
    if (isClosed) return;
    emit(switch (subject) {
      null => const PayoutRateNone(),
      PayoutRateNoSats(:final notSeen) => PayoutRateSatsMissing(
        step,
        notSeen: notSeen,
      ),
      PayoutRateMismatch(:final notSeen) => PayoutRateAmountsDisagree(
        step,
        notSeen: notSeen,
      ),
      final PayoutRateCompared compared => switch (price) {
        null => PayoutRateReading(step),
        final price => switch (CheckPayoutRateUsecase.compareFor(
          terms,
          compared,
          price,
        )) {
          final check
              when CheckPayoutRateUsecase.reassuresBesideAlert(
                seen,
                check,
                compared.basis,
              ) =>
            PayoutRateAlertAlone(step),
          final check => PayoutRateChecked(
            step,
            check,
            basis: compared.basis,
            // A currency the Bull wallet does not price, an order made here: the gap against the buyer since the order was made, beyond the owner's threshold only (#237).
            against: CheckPayoutRateUsecase.againstOf(terms, check, seen),
          ),
        },
      },
    });
  }

  /// One read of the price at a time; its answer compared with what the step shown compares when it lands, never with what it compared when asked.
  Future<void> _read(PayoutRateTerms terms) {
    final step = _step;
    if (step != null && !isClosed) emit(PayoutRateReading(step));
    return _reading ??= () async {
      P2pWalletBitcoinRate price;
      try {
        price = await _priceOf(record, terms).timeout(readBound);
      } on TimeoutException {
        price = const P2pWalletRateUnavailable();
      }
      memory.keepPrice(record.network, terms.currency.code, price, now());
      _reading = null;
      final seen = _seen;
      final step = _step;
      if (isClosed || seen == null || step == null) return;
      _emitFor(step, terms, seen, _subjectOf(terms, seen), price);
    }();
  }
}
