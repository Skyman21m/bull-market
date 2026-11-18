import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../../public/p2p_wallet_port.dart';
import '../domain/robot_binding.dart';
import '../domain/trade/maker_terms.dart';
import '../domain/trade/trade_status.dart';
import '../domain/trade/trade_watch.dart';
import '../domain/trade/wallet_rate_check.dart';
import '../domain/trade_record.dart';
import '../domain/usecases/trade/check_payout_rate_usecase.dart';

/// [CheckPayoutRateUsecase.termsOf], which the locator gives the cubit.
typedef PayoutRateTermsOf = Future<MakerTerms?> Function(TradeRecord record);

/// [CheckPayoutRateUsecase.priceOf], which the locator gives the cubit.
typedef PayoutRatePriceOf =
    Future<P2pWalletBitcoinRate> Function(TradeRecord record, MakerTerms maker);

/// Which buyer's step a check is for: the payout (6 and 8) or « fiat sent » (9), of a contract ([take]).
@immutable
final class PayoutRateStep {
  final int take;
  final bool fiatSent;

  const PayoutRateStep(this.take, {required this.fiatSent});

  /// The step of [status], `null` where the rule says nothing.
  static PayoutRateStep? of(TradeStatus status) => switch (status) {
    WaitingForBoth(role: TradeRole.buyer) ||
    WaitingForPayout(
      role: TradeRole.buyer,
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

/// What the rule keeps beyond one page of a trade, until the app stops (in memory only, never on disk: #204 will keep the invoice given, schema 9): per contract the smallest invoice's sats asked at 6 or 8, and per network and currency the last price read and when.
final class PayoutRateMemory {
  final Map<(RobotSlot, String, int, int), Sats> _asked = {};
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

/// The check of [step], of sats coming from [basis].
final class PayoutRateChecked extends PayoutRateState {
  final PayoutRateStep step;
  final WalletRateCheck check;
  final PayoutRateBasis basis;

  const PayoutRateChecked(
    this.step,
    this.check, {
    this.basis = const PayoutRateAskedNow(),
  });
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
}

/// The owner's payment rule on a maker buyer's side (#182, design note § 3.3), on the trade screen: the only caller of [CheckPayoutRateUsecase], for an order made here whose user buys only (a taker's trade never sees it, not even « reading »).
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

  MakerTerms? _maker;
  bool _termsRead = false;
  Future<MakerTerms?>? _termsReading;

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

  bool get _applies =>
      record.origin == TradeOrigin.madeHere && record.role == TradeRole.buyer;

  /// The screen shows [seen]: what it compares is compared at once with the price read, and the price read as the class says, [appeared] when the step appears anew (the screen built, shown again, the app back).
  Future<void> show(TradeSeen seen, {bool appeared = false}) async {
    if (!_applies || isClosed) return;
    final step = PayoutRateStep.of(seen.status);
    if (step == null || !seen.stored) {
      if (step == null) {
        _step = null;
        _status = null;
      }
      if (state is! PayoutRateNone && step != _step) {
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
    if (!_termsRead) emit(PayoutRateReading(step));
    final maker = await _terms();
    // A later show took over meanwhile: it does the rest.
    if (isClosed || !identical(_seen, seen)) return;
    if (maker == null) {
      emit(const PayoutRateNone());
      return;
    }
    final subject = _subjectOf(maker, seen);
    final kept = memory.priceOf(record.network, maker.currency.code);
    final stale = kept == null || !now().isBefore(kept.at.add(freshFor));
    final unread = kept?.price is P2pWalletRateUnavailable;
    final read =
        subject is PayoutRateCompared &&
        _reading == null &&
        (kept == null ||
            ((newStep || appeared || moved) && (stale || (newStep && unread))));
    if (read) {
      await _read(maker);
    } else {
      _emitFor(step, maker, subject, _reading == null ? kept?.price : null);
    }
  }

  /// « Retry »: the price read again, only after a price that could not be read.
  Future<void> retry() async {
    final maker = _maker;
    if (maker == null || isClosed) return;
    if (state case PayoutRateChecked(check: WalletRateUnverified())) {
      await _read(maker);
    }
  }

  /// Before « Submit » gives the payout, or before the dialog of « Confirm … sent » opens (decided by the coordinator of the work after the reviews of #182): a price read under way is awaited, and a price [freshFor] old read again (within [readBound]); `true` when the line shown did not change, or now says the sats are within the margin with no warning (the press goes on: a line that became « within the margin », from a read under way as from « rate not checked » or a warning, never stops it, third functional pass of #182, #207), `false` when it changed to any other line, which the screen then shows, and a second press goes on. Nothing is ever blocked.
  Future<bool> beforeAct() async {
    final maker = _maker;
    final seen = _seen;
    if (!_applies || isClosed || maker == null || seen == null) return true;
    final before = verdictOf(state);
    final reading = _reading;
    if (reading != null) {
      await reading;
    } else if (_subjectOf(maker, seen) is PayoutRateCompared) {
      final kept = memory.priceOf(record.network, maker.currency.code);
      if (kept == null || !now().isBefore(kept.at.add(freshFor))) {
        await _read(maker);
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
    PayoutRateChecked(:final check, :final basis) => switch (check) {
      // A coordinator's figure that moved since the invoice is an alert of its own, whatever the price says.
      _ when basis is PayoutRateTold || basis is PayoutRateNotSeen =>
        PayoutRateVerdict.warns,
      WalletRateCompared(:final warns) =>
        warns ? PayoutRateVerdict.warns : PayoutRateVerdict.within,
      WalletRateNotPriced() => PayoutRateVerdict.notPriced,
      WalletRateUnverified() => PayoutRateVerdict.unverified,
    },
  };

  Future<MakerTerms?> _terms() async {
    if (_termsRead) return _maker;
    final maker = await (_termsReading ??= _termsOf(record));
    _maker = maker;
    _termsRead = true;
    return maker;
  }

  /// What [seen] compares, the invoice's sats it shows kept for 9.
  PayoutRateSubject? _subjectOf(MakerTerms maker, TradeSeen seen) {
    final take = seen.status.trail.take;
    final subject = CheckPayoutRateUsecase.subjectAt(
      record,
      maker,
      seen,
      asked: memory.askedOf(record, take),
    );
    final keep = switch (subject) {
      PayoutRateCompared(:final keep?) ||
      PayoutRateMismatch(:final keep?) => keep,
      _ => null,
    };
    if (keep != null) memory.keepAsked(record, take, keep);
    return subject;
  }

  void _emitFor(
    PayoutRateStep step,
    MakerTerms maker,
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
      final PayoutRateCompared compared =>
        price == null
            ? PayoutRateReading(step)
            : PayoutRateChecked(
                step,
                CheckPayoutRateUsecase.compare(maker, compared, price),
                basis: compared.basis,
              ),
    });
  }

  /// One read of the price at a time; its answer compared with what the step shown compares when it lands, never with what it compared when asked.
  Future<void> _read(MakerTerms maker) {
    final step = _step;
    if (step != null && !isClosed) emit(PayoutRateReading(step));
    return _reading ??= () async {
      P2pWalletBitcoinRate price;
      try {
        price = await _priceOf(record, maker).timeout(readBound);
      } on TimeoutException {
        price = const P2pWalletRateUnavailable();
      }
      memory.keepPrice(record.network, maker.currency.code, price, now());
      _reading = null;
      final seen = _seen;
      final step = _step;
      if (isClosed || seen == null || step == null) return;
      _emitFor(step, maker, _subjectOf(maker, seen), price);
    }();
  }
}
