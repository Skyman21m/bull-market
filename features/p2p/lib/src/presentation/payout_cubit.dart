import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart'
    show MiningFeeRate, PayoutInvoiceRefused, RoutingBudgetPpm;

import '../domain/p2p_failure.dart';
import '../domain/trade/trade_payout.dart';
import '../domain/trade/trade_payout_outcome.dart';
import '../domain/trade/trade_watch.dart';
import '../domain/trade_record.dart';
import '../domain/usecases/trade/hold_trade_key_usecase.dart';
import '../domain/usecases/trade/submit_payout_usecase.dart';
import '../domain/usecases/trade/trade_keyring.dart';

/// [SubmitPayoutUsecase.ask], which the locator gives the cubit.
typedef PayoutAsker =
    Result<PayoutAsk, PayoutCheckRefusal> Function(
      TradeRecord record,
      TradeSeen seen,
    );

/// [SubmitPayoutUsecase.check], which the locator gives the cubit.
typedef PayoutChecker =
    Result<CheckedPayout, PayoutCheckRefusal> Function(
      TradeRecord record,
      TradeSeen seen,
      PayoutDestination destination,
    );

/// [SubmitPayoutUsecase.execute], which the locator gives the cubit.
typedef PayoutSender =
    Future<Result<PayoutSubmission, PayoutNotSent>> Function(
      TradeRecord record,
      CheckedPayout shown, {
      void Function(PayoutProgress step)? onProgress,
    });

/// [HoldTradeKeyUsecase.execute], which the locator gives the cubit as a function that takes a hold and returns its release ([TradeKeyHold.release]).
typedef TradeKeyHolder = void Function() Function(TradeRecord record);

/// The two ways the buyer is paid, the reference's two tabs (`Prompts/Payout.tsx:77-111`).
enum PayoutKind { lightning, onchain }

/// What the user typed and chose in the payout panel: its only copy, which the panel shows and the checks read, so that a panel built again shows exactly what is checked (review of #132). As the reference keeps its forms above its prompts (`TradeBox/index.tsx:139-140`), it lasts as long as the trade's page.
@immutable
final class PayoutForm {
  final PayoutKind kind;

  /// The invoice's field, the reference's `lightning:` prefix taken off (`Forms/LightningPayout.tsx:143-155`).
  final String invoice;

  /// « Advanced options », and the « Routing Budget » it shows: [budget] is the one applied, [budgetText] what its field shows, in ppm or, with [budgetInSats], in sats.
  final bool advanced;
  final RoutingBudgetPpm budget;
  final bool budgetInSats;
  final String budgetText;

  final String address;

  /// The mining fee rate's field: the coordinator's suggestion as it sent it, taken once, when the on-chain payout is first offered, as the reference takes it when its form is first shown and never again (`Forms/OnchainPayout.tsx:47-49`), then what the user types; `null` before.
  final String? fee;

  const PayoutForm._({
    required this.kind,
    required this.invoice,
    required this.advanced,
    required this.budget,
    required this.budgetInSats,
    required this.budgetText,
    required this.address,
    required this.fee,
  });

  /// The reference's defaults (`Forms/LightningPayout.tsx`, `defaultLightning`): Lightning, no advanced options, a budget of 1,000 ppm.
  static final PayoutForm initial = PayoutForm._(
    kind: PayoutKind.lightning,
    invoice: '',
    advanced: false,
    budget: RoutingBudgetPpm.referenceDefault,
    budgetInSats: false,
    budgetText: '${RoutingBudgetPpm.referenceDefault.ppm}',
    address: '',
    fee: null,
  );

  PayoutForm _with({
    PayoutKind? kind,
    String? invoice,
    bool? advanced,
    RoutingBudgetPpm? budget,
    bool? budgetInSats,
    String? budgetText,
    String? address,
    String? Function()? fee,
  }) => PayoutForm._(
    kind: kind ?? this.kind,
    invoice: invoice ?? this.invoice,
    advanced: advanced ?? this.advanced,
    budget: budget ?? this.budget,
    budgetInSats: budgetInSats ?? this.budgetInSats,
    budgetText: budgetText ?? this.budgetText,
    address: address ?? this.address,
    fee: fee == null ? this.fee : fee(),
  );

  /// The coordinator's [suggested] rate as the field's text, as it sent it: no rounding, so that a rate of more than 3 decimals reads « Invalid » rather than another rate.
  static String suggestionText(double? suggested) => switch (suggested) {
    null => '',
    final rate when rate == rate.truncateToDouble() => '${rate.toInt()}',
    final rate => '$rate',
  };

  /// [fee] as a rate that may be sent: a number, with a comma or a point, from 2 to 500 with at most 3 decimals ([MiningFeeRate.of]).
  static MiningFeeRate? rateOf(String text) {
    final value = double.tryParse(text.trim().replaceAll(',', '.'));
    return value == null ? null : MiningFeeRate.of(value);
  }
}

/// What the payout panel of one trade shows (#91): what the coordinator asks, what the user typed, its check, and where a payout being given stands.
@immutable
final class PayoutPanelState {
  /// The status the panel works from, the latest it was shown, or `null` before; kept as it was while a payout is given ([PayoutCubit.show]).
  final TradeSeen? seen;

  /// What the coordinator asks at [seen] ([SubmitPayoutUsecase.ask]), or why nothing can be given now; `null` before [PayoutCubit.show].
  final Result<PayoutAsk, PayoutCheckRefusal>? ask;

  final PayoutForm form;

  /// [form]'s invoice and address checked against [seen] ([SubmitPayoutUsecase.check]): the [CheckedPayout] the panel shows and « Submit » gives, or why it cannot be given; `null` while the field is empty (or, for the address, while the rate is not one that may be sent).
  final Result<CheckedPayout, PayoutCheckRefusal>? invoice;
  final Result<CheckedPayout, PayoutCheckRefusal>? address;

  final PayoutPhase phase;

  /// What the coordinator asked when the last payout was given, while that payout was received or may have been: the panel shows its form under that outcome when a later read says nothing is asked any more (the read just after a payout received shows the next status before the trade screen does: review of #132).
  final PayoutAsk? given;

  const PayoutPanelState._({
    required this.seen,
    required this.ask,
    required this.form,
    required this.invoice,
    required this.address,
    required this.phase,
    required this.given,
  });

  PayoutPanelState.initial()
    : this._(
        seen: null,
        ask: null,
        form: PayoutForm.initial,
        invoice: null,
        address: null,
        phase: const PayoutEditing(),
        given: null,
      );

  /// The check of [kind]'s tab.
  Result<CheckedPayout, PayoutCheckRefusal>? checkOf(PayoutKind kind) =>
      switch (kind) {
        PayoutKind.lightning => invoice,
        PayoutKind.onchain => address,
      };

  /// The on-chain payout the coordinator offers at [seen], or `null`.
  OnchainAsk? get onchain => switch (ask) {
    Ok(:final value) => value.onchain,
    _ => null,
  };

  /// The mining fee rate of the form's field, when it is one that may be sent; `null` otherwise.
  MiningFeeRate? get rate => switch (form.fee) {
    final text? => PayoutForm.rateOf(text),
    null => null,
  };

  /// Whether the last payout given was received or may have been: what the panel says of it outranks a read that says nothing is asked any more, and the form stays as it was given.
  bool get outcomeTold => switch (phase) {
    PayoutEditing(notice: PayoutNoticeGiven() || PayoutNoticeUnknown()) => true,
    _ => false,
  };

  /// What the panel shows the form for: what the coordinator asks, or, under a payout received or that may have been, what it asked when it was given.
  PayoutAsk? get shownAsk => switch (ask) {
    Ok(:final value) => value,
    _ when outcomeTold => given,
    _ => null,
  };

  /// The payout « Submit » of [kind]'s tab gives: its check, when it is exactly what the fields show (the text, the budget, the rate), nothing is being sent, no payout given was received or may have been, and the coordinator did not refuse this very invoice (as the reference disables « Submit » on its `badInvoice` until the invoice or the amount changes, `Forms/LightningPayout.tsx:143-155`, `:643`).
  CheckedPayout? submittable(PayoutKind kind) {
    final payout = switch (checkOf(kind)) {
      Ok(:final value) => value,
      _ => null,
    };
    if (payout == null || !_shows(payout)) return null;
    return switch (phase) {
      PayoutEditing(notice: PayoutNoticeGiven() || PayoutNoticeUnknown()) =>
        null,
      PayoutEditing(
        notice: PayoutNoticeNotTaken(
          kind: PayoutKind.lightning,
          cause: PayoutInvoiceRefused(),
        ),
      )
          when kind == PayoutKind.lightning =>
        null,
      PayoutEditing() => payout,
      PayoutSending() => null,
    };
  }

  /// Whether [payout] is what the form shows: its text, and its budget or rate.
  bool _shows(CheckedPayout payout) => switch (payout) {
    CheckedPayoutInvoice(:final text, :final budget) =>
      text == form.invoice && budget == form.budget,
    CheckedPayoutAddress(:final text, rate: final checked) =>
      text == form.address && checked == rate,
  };

  /// Whether a payout given told something between [before] and [after], other than nothing sent (a payout no longer valid aside): the trade's watch is then asked to read at once.
  static bool toldBetween(PayoutPanelState before, PayoutPanelState after) =>
      before.phase is PayoutSending &&
      switch (after.phase) {
        PayoutEditing(notice: PayoutNoticeNotSent(:final refusal)) =>
          refusal is PayoutNoLongerValid,
        PayoutEditing(notice: _?) => true,
        _ => false,
      };

  PayoutPanelState _with({
    TradeSeen? seen,
    Result<PayoutAsk, PayoutCheckRefusal>? ask,
    PayoutForm? form,
    Result<CheckedPayout, PayoutCheckRefusal>? Function()? invoice,
    Result<CheckedPayout, PayoutCheckRefusal>? Function()? address,
    PayoutPhase? phase,
    PayoutAsk? Function()? given,
  }) => PayoutPanelState._(
    seen: seen ?? this.seen,
    ask: ask ?? this.ask,
    form: form ?? this.form,
    invoice: invoice == null ? this.invoice : invoice(),
    address: address == null ? this.address : address(),
    phase: phase ?? this.phase,
    given: given == null ? this.given : given(),
  );
}

/// Where a payout being given stands.
@immutable
sealed class PayoutPhase {
  const PayoutPhase();
}

/// Nothing is being sent: « Submit » gives the payout shown; [notice] says what the last one gave, when one was given.
final class PayoutEditing extends PayoutPhase {
  final PayoutNotice? notice;

  const PayoutEditing({this.notice});
}

/// A payout is being given: [step] says what it waits for, since [kind]'s « Submit » was pressed, and [waitedLong] that it has waited [PayoutCubit.stillWaitingAfter].
final class PayoutSending extends PayoutPhase {
  final PayoutKind kind;
  final PayoutProgress step;
  final bool waitedLong;

  const PayoutSending(this.kind, this.step, {this.waitedLong = false});
}

/// What a payout given told, which the panel says in words of its own: never a coordinator's text.
@immutable
sealed class PayoutNotice {
  /// The tab the payout was given from.
  final PayoutKind kind;

  const PayoutNotice(this.kind);
}

/// The coordinator recorded the payout ([PayoutGiven]).
final class PayoutNoticeGiven extends PayoutNotice {
  const PayoutNoticeGiven(super.kind);
}

/// The coordinator recorded no payout, or the request never reached it ([PayoutNotTaken]): [cause] says why.
final class PayoutNoticeNotTaken extends PayoutNotice {
  final Failure cause;

  /// The payout given.
  final CheckedPayout shown;

  const PayoutNoticeNotTaken(super.kind, this.cause, this.shown);

  /// Whether the coordinator answered it, as the reference's `bad_invoice` or `bad_address` (or `bad_request`) message: said under the field, as the reference's helper text (`Forms/LightningPayout.tsx:602-619`, `Forms/OnchainPayout.tsx:114-118`); otherwise the request never reached it, said under « Submit ».
  bool get byCoordinator => cause is! P2pFailure;
}

/// The payout may have been recorded ([PayoutOutcomeUnknown], or `execute` failed): never given again by the panel.
final class PayoutNoticeUnknown extends PayoutNotice {
  const PayoutNoticeUnknown(super.kind);
}

/// A read made after a payout was received or may have been still shows the coordinator asking for one: « Submit » is offered again, and the panel says why.
final class PayoutNoticeAskedAgain extends PayoutNotice {
  const PayoutNoticeAskedAgain(super.kind);
}

/// Nothing was sent ([PayoutNotSent]): [refusal] says why; for [PayoutChangedSinceShown] the fresh value replaced the one shown, to confirm again, and [change] says what changed.
final class PayoutNoticeNotSent extends PayoutNotice {
  final PayoutNotSent refusal;
  final PayoutChange? change;

  const PayoutNoticeNotSent(super.kind, this.refusal, {this.change});
}

/// What changed between the payout shown and the same one checked again before it was signed ([PayoutChangedSinceShown]), the first that applies.
enum PayoutChange {
  /// The amount asked or received.
  amount,

  /// The invoice now expires before the end of the step and a day.
  expiry,

  /// The trade's status carries a warning it did not.
  status,

  /// Anything else the user would see differently.
  other;

  static PayoutChange between(CheckedPayout shown, CheckedPayout fresh) {
    final newWarnings = fresh.warnings.where(
      (w) => !shown.warnings.contains(w),
    );
    final amountChanged = switch ((shown, fresh)) {
      (final CheckedPayoutInvoice s, final CheckedPayoutInvoice f) =>
        s.buyerSats != f.buyerSats || s.amount != f.amount,
      (final CheckedPayoutAddress s, final CheckedPayoutAddress f) =>
        s.invoiceAmount != f.invoiceAmount ||
            s.swapFeePercent != f.swapFeePercent ||
            s.sentSats != f.sentSats,
      _ => true,
    };
    if (amountChanged || newWarnings.contains(PayoutWarning.sentBelowMinimum)) {
      return PayoutChange.amount;
    }
    if (newWarnings.contains(PayoutWarning.invoiceMayExpireFirst)) {
      return PayoutChange.expiry;
    }
    final kinds = {for (final w in shown.statusWarnings) w.runtimeType};
    if (fresh.statusWarnings.any((w) => !kinds.contains(w.runtimeType))) {
      return PayoutChange.status;
    }
    return PayoutChange.other;
  }
}

/// The payout panel of one shown trade (#91, `AGENTS.md` « Rules for the payout panel (#91) »): the only caller of [SubmitPayoutUsecase] and [HoldTradeKeyUsecase], which the locator gives it as their members.
///
/// It holds the form ([PayoutForm]): the panel shows it and changes it through [selectKind], [editInvoice], [setAdvanced], [editBudget], [switchBudgetUnit], [editAddress] and [editFee], and each change is checked at once against the status shown, as the reference checks its field as it changes (`Forms/LightningPayout.tsx:143-155`); [show] takes each status the trade screen shows and checks the form again; [submit] gives the very [CheckedPayout] shown to [SubmitPayoutUsecase.execute], once at a time, and never again by itself, whatever it gave.
/// [hold] and [release] keep the robot's key while the panel is shown with the app in the foreground (`TradeKeyring`); closing the cubit releases it.
class PayoutCubit extends Cubit<PayoutPanelState> {
  final TradeRecord record;
  final PayoutAsker _ask;
  final PayoutChecker _check;
  final PayoutSender _send;
  final TradeKeyHolder _holdKey;
  final DateTime Function() _now;
  final Duration _stillWaitingAfter;

  /// After how long a payout being given is said to be still waiting, as the take does (`TakeOrderCubit.stillWaitingAfter`).
  static const stillWaitingAfter = Duration(seconds: 30);

  /// The latest status the screen showed, applied once no payout is being given.
  TradeSeen? _latest;

  /// When the last payout given told it was received or may have been: only a read sent after it decides whether one is asked again.
  DateTime? _toldAt;

  Timer? _stillWaiting;

  /// The release of the hold taken, while one is.
  void Function()? _hold;

  /// `now` is the app's clock (`P2pClock`), the one the trade's reads are dated with.
  PayoutCubit(
    this.record,
    this._ask,
    this._check,
    this._send,
    this._holdKey, {
    required this._now,
    this._stillWaitingAfter = PayoutCubit.stillWaitingAfter,
  }) : super(PayoutPanelState.initial());

  /// Whether the robot's key is held: for the tests.
  @visibleForTesting
  bool get holdsKey => _hold != null;

  /// The panel is shown with [seen], the status the trade screen shows: what the coordinator asks, and the form checked again against it.
  ///
  /// While a payout is being given nothing changes: the status is applied once it told something, so that the screen never shows other figures than the ones being given. A status read before the one the panel works from changes nothing. A payout received or that may have been is offered again only once a read sent after what it told shows the status still asking for one.
  void show(TradeSeen seen) {
    if (isClosed || identical(seen, _latest)) return;
    final current = state.seen;
    if (current != null && seen.status.seenAt.isBefore(current.status.seenAt)) {
      return;
    }
    _latest = seen;
    if (state.phase is PayoutSending) return;
    _apply(seen);
  }

  void _apply(TradeSeen seen) {
    final ask = _ask(record, seen);
    final told = _toldAt;
    final sentAt = seen.requestedAt ?? seen.status.seenAt;
    var phase = state.phase;
    if (phase case PayoutEditing(
      notice: final PayoutNotice notice,
    ) when notice is PayoutNoticeGiven || notice is PayoutNoticeUnknown) {
      if (told != null && sentAt.isAfter(told)) {
        _toldAt = null;
        phase = PayoutEditing(
          notice: ask is Ok ? PayoutNoticeAskedAgain(notice.kind) : null,
        );
      }
    }
    // The coordinator's suggested rate, taken once, when the on-chain payout is first offered (`Forms/OnchainPayout.tsx:47-49`).
    var form = state.form;
    if (form.fee == null) {
      if (ask case Ok(value: PayoutAsk(onchain: final onchain?))) {
        form = form._with(
          fee: () => PayoutForm.suggestionText(onchain.suggestedSatPerVbyte),
        );
      }
    }
    final next = state._with(seen: seen, ask: ask, phase: phase, form: form);
    if (next.outcomeTold) {
      // Under a payout received or that may have been, a read that asks nothing any more leaves the form as it was given.
      emit(ask is Ok ? _checked(next) : next);
    } else {
      emit(_checked(next._with(given: () => null)));
    }
  }

  /// [next] with its form checked against its status.
  PayoutPanelState _checked(PayoutPanelState next) {
    final seen = next.seen;
    if (seen == null) return next;
    final form = next.form;
    final rate = next.rate;
    return next._with(
      invoice: () => form.invoice.isEmpty
          ? null
          : _check(
              record,
              seen,
              PayoutInvoiceText(form.invoice, budget: form.budget),
            ),
      address: () => form.address.isEmpty || rate == null
          ? null
          : _check(record, seen, PayoutAddressText(form.address, rate: rate)),
    );
  }

  /// Whether the form may change: not while a payout is being given, nor once one was received or may have been (until a later read asks for one again).
  bool get _editable =>
      !isClosed && state.phase is PayoutEditing && !state.outcomeTold;

  /// [form], a change of [kind]'s tab, checked; what the last payout of that tab told, when it was refused or nothing was sent, goes with the text it was about.
  void _edit(PayoutForm form, PayoutKind kind) {
    var phase = state.phase;
    if (phase case PayoutEditing(notice: final notice?)
        when notice.kind == kind &&
            (notice is PayoutNoticeNotTaken || notice is PayoutNoticeNotSent)) {
      phase = const PayoutEditing();
    }
    emit(_checked(state._with(form: form, phase: phase)));
  }

  /// Shows [kind]'s tab.
  void selectKind(PayoutKind kind) {
    if (isClosed || kind == state.form.kind) return;
    emit(state._with(form: state.form._with(kind: kind)));
  }

  /// The invoice's field is [text] (pasted, typed or made by the wallet), the reference's `lightning:` prefix taken off.
  void editInvoice(String text) {
    if (!_editable) return;
    final invoice = text.startsWith(_lightningPrefix)
        ? text.substring(_lightningPrefix.length)
        : text;
    _edit(state.form._with(invoice: invoice), PayoutKind.lightning);
  }

  static const _lightningPrefix = 'lightning:';

  /// « Advanced options » on or off; off brings the reference's default budget back (`Forms/LightningPayout.tsx:229-243`).
  void setAdvanced(bool on) {
    if (!_editable) return;
    final form = state.form;
    _edit(
      on
          ? form._with(advanced: true)
          : form._with(
              advanced: false,
              budget: RoutingBudgetPpm.referenceDefault,
              budgetInSats: false,
              budgetText: '${RoutingBudgetPpm.referenceDefault.ppm}',
            ),
      PayoutKind.lightning,
    );
  }

  /// The budget's field typed as [text], in ppm or in sats of the buyer's amount, taken as the reference takes it (`Forms/LightningPayout.tsx:266-288`): an empty field is 0, and a value that is no whole number, or at 99,999 ppm or more, is refused, the field keeping the budget applied. Returns whether it was taken.
  bool editBudget(String text) {
    if (!_editable || !state.form.advanced) return false;
    final value = text.isEmpty ? 0 : int.tryParse(text);
    final ask = state.ask;
    if (value == null ||
        value < 0 ||
        ask is! Ok<PayoutAsk, PayoutCheckRefusal>) {
      return false;
    }
    final buyer = ask.value.buyerSats.value.toInt();
    final ppm = state.form.budgetInSats
        ? (buyer == 0 ? null : (value * 1000000 / buyer).round())
        : value;
    final budget = ppm == null ? null : RoutingBudgetPpm.of(ppm);
    if (budget == null) return false;
    _edit(
      state.form._with(budget: budget, budgetText: '$value'),
      PayoutKind.lightning,
    );
    return true;
  }

  /// The budget's unit switched, the field showing the budget applied in the other unit (`Forms/LightningPayout.tsx:403-410`, `:300`).
  void switchBudgetUnit() {
    if (!_editable) return;
    final form = state.form;
    final asked = switch (state.ask) {
      Ok(:final value) => value.invoiceSatsFor(form.budget),
      _ => null,
    };
    if (asked == null) return;
    final inSats = !form.budgetInSats;
    emit(
      state._with(
        form: form._with(
          budgetInSats: inSats,
          budgetText: inSats
              ? '${(asked.value.toInt() / 1000000 * form.budget.ppm).ceil()}'
              : '${form.budget.ppm}',
        ),
      ),
    );
  }

  /// The address's field is [text] (pasted, typed or made by the wallet).
  void editAddress(String text) {
    if (!_editable) return;
    _edit(state.form._with(address: text), PayoutKind.onchain);
  }

  /// The mining fee typed as [text]: from now on the rate is the user's, whatever the coordinator suggests.
  void editFee(String text) {
    if (!_editable) return;
    _edit(state.form._with(fee: () => text), PayoutKind.onchain);
  }

  /// Gives the payout of [kind]'s tab, the one shown: nothing while one is being given, or when the tab holds no checked payout that is exactly what the fields show.
  ///
  /// When [SubmitPayoutUsecase.execute] throws (a fault), the payout may have left: the panel says it does not know, never gives it again, and the fault goes on up.
  Future<void> submit(PayoutKind kind) async {
    final shown = state.submittable(kind);
    if (isClosed || shown == null) return;
    // What the coordinator asks now, the form shown under the outcome should a read ask nothing any more.
    final asked = state.shownAsk;
    emit(
      state._with(
        phase: PayoutSending(kind, PayoutProgress.opening),
        given: () => asked,
      ),
    );
    _stillWaiting = Timer(_stillWaitingAfter, () {
      if (isClosed) return;
      if (state.phase case PayoutSending(:final kind, :final step)) {
        emit(state._with(phase: PayoutSending(kind, step, waitedLong: true)));
      }
    });
    final Result<PayoutSubmission, PayoutNotSent> result;
    try {
      result = await _send(
        record,
        shown,
        onProgress: (step) {
          if (isClosed) return;
          if (state.phase case PayoutSending(
            step: final current,
            :final waitedLong,
          ) when current != step) {
            emit(
              state._with(
                phase: PayoutSending(kind, step, waitedLong: waitedLong),
              ),
            );
          }
        },
      );
    } on Object {
      _stopWaiting();
      if (!isClosed) {
        _toldAt = _now();
        _told(PayoutNoticeUnknown(kind));
      }
      rethrow;
    }
    _stopWaiting();
    if (isClosed) return;
    switch (result) {
      case Ok(value: PayoutGiven(:final seen)):
        _toldAt = _now();
        _told(PayoutNoticeGiven(kind), seen);
      case Ok(value: PayoutNotTaken(:final cause, :final seen)):
        _told(PayoutNoticeNotTaken(kind, cause, shown), seen);
      case Ok(value: PayoutOutcomeUnknown(:final seen)):
        _toldAt = _now();
        _told(PayoutNoticeUnknown(kind), seen);
      // What the user would see changed: the form is checked again against the fresh read, and that check is shown in place of the old, to confirm again.
      case Err(failure: final PayoutChangedSinceShown changed):
        _told(
          PayoutNoticeNotSent(
            kind,
            changed,
            change: PayoutChange.between(shown, changed.fresh),
          ),
          changed.seen,
        );
      case Err(failure: PayoutNoLongerValid(:final seen) && final failure):
        _told(PayoutNoticeNotSent(kind, failure), seen);
      case Err(:final failure):
        _told(PayoutNoticeNotSent(kind, failure));
    }
  }

  /// The payout given told [notice]: said, then the newest status known applied, [seen] (the read after it) when it is newer than the screen's.
  void _told(PayoutNotice notice, [TradeSeen? seen]) {
    emit(state._with(phase: PayoutEditing(notice: notice)));
    final latest = _latest;
    final newest = switch ((seen, latest)) {
      (final s?, final l?) when !l.status.seenAt.isAfter(s.status.seenAt) => s,
      (final s?, null) => s,
      (_, final l) => l,
    };
    if (newest == null) return;
    _latest = newest;
    _apply(newest);
  }

  void _stopWaiting() {
    _stillWaiting?.cancel();
    _stillWaiting = null;
  }

  /// Keeps the robot's key once a signature unlocks it: while the panel is shown with the app in the foreground. A second call does nothing.
  void hold() {
    if (isClosed || _hold != null) return;
    _hold = _holdKey(record);
  }

  /// Lets the key go: the panel left, the app hidden or paused, or another tab shown. A second call does nothing.
  void release() {
    final release = _hold;
    _hold = null;
    release?.call();
  }

  @override
  Future<void> close() {
    _stopWaiting();
    release();
    return super.close();
  }
}
