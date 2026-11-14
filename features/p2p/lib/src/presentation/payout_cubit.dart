import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show MiningFeeRate, RoutingBudgetPpm;

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

/// What the payout panel of one trade shows (#91): what the coordinator asks, what was pasted and checked in each tab, and where a payout being given stands.
@immutable
final class PayoutPanelState {
  /// The status the panel was last shown with, or `null` before.
  final TradeSeen? seen;

  /// What the coordinator asks at [seen] ([SubmitPayoutUsecase.ask]), or why nothing can be given now; `null` before [PayoutCubit.show].
  final Result<PayoutAsk, PayoutCheckRefusal>? ask;

  /// What the text of each tab gives, checked against [seen] ([SubmitPayoutUsecase.check]): the [CheckedPayout] the panel shows and « Submit » gives, or why it cannot be given; `null` while the tab's field is empty.
  final Result<CheckedPayout, PayoutCheckRefusal>? invoice;
  final Result<CheckedPayout, PayoutCheckRefusal>? address;

  final PayoutPhase phase;

  const PayoutPanelState({
    this.seen,
    this.ask,
    this.invoice,
    this.address,
    this.phase = const PayoutEditing(),
  });

  /// The check of [kind]'s tab.
  Result<CheckedPayout, PayoutCheckRefusal>? checkOf(PayoutKind kind) =>
      switch (kind) {
        PayoutKind.lightning => invoice,
        PayoutKind.onchain => address,
      };

  /// The payout « Submit » of [kind]'s tab gives, when its text was checked and nothing is being sent.
  CheckedPayout? submittable(PayoutKind kind) =>
      switch ((phase, checkOf(kind))) {
        (PayoutEditing(), Ok(:final value)) => value,
        _ => null,
      };

  PayoutPanelState _with({
    TradeSeen? seen,
    Result<PayoutAsk, PayoutCheckRefusal>? ask,
    Result<CheckedPayout, PayoutCheckRefusal>? Function()? invoice,
    Result<CheckedPayout, PayoutCheckRefusal>? Function()? address,
    PayoutPhase? phase,
  }) => PayoutPanelState(
    seen: seen ?? this.seen,
    ask: ask ?? this.ask,
    invoice: invoice == null ? this.invoice : invoice(),
    address: address == null ? this.address : address(),
    phase: phase ?? this.phase,
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

/// A payout is being given: [step] says what it waits for, since [kind]'s « Submit » was pressed.
final class PayoutSending extends PayoutPhase {
  final PayoutKind kind;
  final PayoutProgress step;

  const PayoutSending(this.kind, this.step);
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

  /// The payout given, for the texts that name its amount.
  final CheckedPayout shown;

  const PayoutNoticeNotTaken(super.kind, this.cause, this.shown);
}

/// The payout may have been recorded ([PayoutOutcomeUnknown]): never given again by the panel.
final class PayoutNoticeUnknown extends PayoutNotice {
  const PayoutNoticeUnknown(super.kind);
}

/// Nothing was sent ([PayoutNotSent]): [refusal] says why; for [PayoutChangedSinceShown] the fresh value replaced the one shown, to confirm again.
final class PayoutNoticeNotSent extends PayoutNotice {
  final PayoutNotSent refusal;

  const PayoutNoticeNotSent(super.kind, this.refusal);
}

/// The payout panel of one shown trade (#91, `AGENTS.md` « Rules for the payout panel (#91) »): the only caller of [SubmitPayoutUsecase] and [HoldTradeKeyUsecase], which the locator gives it as their members.
///
/// [show] takes each status the trade screen shows; [checkInvoice] and [checkAddress] check what the user pasted or typed, as the reference checks its field as it changes (`Forms/LightningPayout.tsx:143-155`), and the panel shows what they give; [submit] gives that very [CheckedPayout] to [SubmitPayoutUsecase.execute], once at a time, and never again by itself, whatever it gave.
/// [hold] and [release] keep the robot's key while the panel is shown with the app in the foreground (`TradeKeyring`); closing the cubit releases it.
class PayoutCubit extends Cubit<PayoutPanelState> {
  final TradeRecord record;
  final PayoutAsker _ask;
  final PayoutChecker _check;
  final PayoutSender _send;
  final TradeKeyHolder _holdKey;

  /// What was last given to each tab's check, checked again whenever the status changes, so that what is shown is checked against the status shown.
  PayoutDestination? _invoiceInput;
  PayoutDestination? _addressInput;

  /// The release of the hold taken, while one is.
  void Function()? _hold;

  PayoutCubit(this.record, this._ask, this._check, this._send, this._holdKey)
    : super(const PayoutPanelState());

  /// Whether the robot's key is held: for the tests.
  @visibleForTesting
  bool get holdsKey => _hold != null;

  /// The panel is shown with [seen], the status the trade screen shows: what the coordinator asks, and each tab's text checked again against it.
  void show(TradeSeen seen) {
    if (isClosed || identical(seen, state.seen)) return;
    emit(
      state._with(
        seen: seen,
        ask: _ask(record, seen),
        invoice: () => _checked(seen, _invoiceInput),
        address: () => _checked(seen, _addressInput),
      ),
    );
  }

  /// Checks [text], an invoice pasted or typed, with [budget] (`null` for an empty field, which shows nothing).
  void checkInvoice(String text, RoutingBudgetPpm budget) {
    _invoiceInput = text.isEmpty
        ? null
        : PayoutInvoiceText(text, budget: budget);
    final seen = state.seen;
    if (isClosed || seen == null) return;
    emit(state._with(invoice: () => _checked(seen, _invoiceInput)));
  }

  /// Checks [text], an address pasted or typed, at [rate] (`null` when the rate typed is not one that may be sent, which leaves nothing to give).
  void checkAddress(String text, MiningFeeRate? rate) {
    _addressInput = text.isEmpty || rate == null
        ? null
        : PayoutAddressText(text, rate: rate);
    final seen = state.seen;
    if (isClosed || seen == null) return;
    emit(state._with(address: () => _checked(seen, _addressInput)));
  }

  Result<CheckedPayout, PayoutCheckRefusal>? _checked(
    TradeSeen seen,
    PayoutDestination? input,
  ) => input == null ? null : _check(record, seen, input);

  /// Gives the payout of [kind]'s tab, the one shown: nothing while one is being given, or when the tab holds no checked payout.
  Future<void> submit(PayoutKind kind) async {
    final shown = state.submittable(kind);
    if (isClosed || shown == null) return;
    emit(state._with(phase: PayoutSending(kind, PayoutProgress.unlockingKey)));
    final result = await _send(
      record,
      shown,
      onProgress: (step) {
        if (!isClosed && state.phase is PayoutSending) {
          emit(state._with(phase: PayoutSending(kind, step)));
        }
      },
    );
    if (isClosed) return;
    switch (result) {
      case Ok(value: PayoutGiven()):
        emit(
          state._with(phase: PayoutEditing(notice: PayoutNoticeGiven(kind))),
        );
      case Ok(value: PayoutNotTaken(:final cause)):
        emit(
          state._with(
            phase: PayoutEditing(
              notice: PayoutNoticeNotTaken(kind, cause, shown),
            ),
          ),
        );
      case Ok(value: PayoutOutcomeUnknown()):
        emit(
          state._with(phase: PayoutEditing(notice: PayoutNoticeUnknown(kind))),
        );
      // What the user would see changed: the fresh value is shown in place of the old, to confirm again.
      case Err(failure: final PayoutChangedSinceShown changed):
        emit(
          state._with(
            invoice: kind == PayoutKind.lightning
                ? () => Ok(changed.fresh)
                : null,
            address: kind == PayoutKind.onchain
                ? () => Ok(changed.fresh)
                : null,
            phase: PayoutEditing(notice: PayoutNoticeNotSent(kind, changed)),
          ),
        );
      case Err(:final failure):
        emit(
          state._with(
            phase: PayoutEditing(notice: PayoutNoticeNotSent(kind, failure)),
          ),
        );
    }
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
    release();
    return super.close();
  }
}
