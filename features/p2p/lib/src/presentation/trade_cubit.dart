import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';

import '../domain/trade/trade_cancel.dart';
import '../domain/trade/trade_chat_step.dart';
import '../domain/trade/trade_status.dart';
import '../domain/trade/trade_watch.dart';
import '../domain/trade_record.dart';
import '../domain/usecases/trade/cancel_trade_usecase.dart';
import '../domain/usecases/trade/chat_step_action_usecase.dart';
import '../domain/usecases/trade/watch_trade_usecase.dart';

/// [WatchTradeUsecase.execute], which the locator gives the cubit.
typedef TradeWatcher =
    Stream<TradeWatchState> Function(
      TradeRecord record, {
      Stream<TradeWatchSignal> signals,
      bool onScreen,
    });

/// [CancelTradeUsecase.execute], which the locator gives the cubit.
typedef TradeCanceller =
    Future<Result<CancelOutcome, CancelRefusal>> Function(
      TradeRecord record,
      TradeSeen seen, {
      BondLossAcknowledged? bondLoss,
    });

/// [ChatStepActionUsecase.confirmFiatSent] or [ChatStepActionUsecase.undoFiatSent], which the locator gives the cubit.
typedef TradeFiatSender =
    Future<Result<ChatStepOutcome, ChatStepRefusal>> Function(
      TradeRecord record,
      TradeSeen seen, {
      void Function(ChatStepProgress step)? onProgress,
    });

/// What the trade screen shows of one trade (#88).
@immutable
final class TradeScreenState {
  final TradeRecord record;

  /// The last state the watch of the trade gave, or the read after a cancel; `null` before the first.
  final TradeWatchState? watch;
  final TradeCancelState cancel;

  /// Where an action of the chat step stands (#95).
  final ChatStepState chatStep;

  const TradeScreenState(
    this.record, {
    this.watch,
    this.cancel = const CancelIdle(),
    this.chatStep = const ChatStepIdle(),
  });

  /// Whether an action of the trade runs, a cancel or an action of the chat step: every button that could cross it is off meanwhile.
  bool get actionRunning =>
      cancel is CancelRunning || chatStep is ChatStepRunning;

  /// The status the user sees, with the order it was read from, when the trade has one.
  TradeSeen? get seen => switch (watch) {
    TradeWatchStatus(:final seen) => seen,
    _ => null,
  };

  TradeScreenState _with({
    TradeWatchState? watch,
    TradeCancelState? cancel,
    ChatStepState? chatStep,
  }) => TradeScreenState(
    watch?.record ?? record,
    watch: watch ?? this.watch,
    cancel: cancel ?? this.cancel,
    chatStep: chatStep ?? this.chatStep,
  );
}

/// Where a cancel of the trade stands.
@immutable
sealed class TradeCancelState {
  const TradeCancelState();
}

/// No cancel runs; [notice] says what the last one gave, when one was tried and it says something.
final class CancelIdle extends TradeCancelState {
  final TradeCancelNotice? notice;

  const CancelIdle({this.notice});
}

/// A cancel runs: its button cannot be pressed again.
final class CancelRunning extends TradeCancelState {
  const CancelRunning();
}

/// What a cancel gave that the screen says, as a type: never a coordinator's text.
@immutable
sealed class TradeCancelNotice {
  const TradeCancelNotice();
}

/// The cancel was not sent ([CancelRefusal]).
final class CancelWasRefused extends TradeCancelNotice {
  final CancelRefusal refusal;

  const CancelWasRefused(this.refusal);
}

/// The cancel was refused before the coordinator acted, or never left: nothing was cancelled ([CancelNotDone.cause]).
final class CancelWasNotDone extends TradeCancelNotice {
  final Failure cause;

  const CancelWasNotDone(this.cause);
}

/// The cancel may have happened: the next reads tell.
final class CancelWasUnknown extends TradeCancelNotice {
  const CancelWasUnknown();
}

/// Where an action of the chat step stands (#95).
@immutable
sealed class ChatStepState {
  const ChatStepState();
}

/// No action of the chat step runs; [notice] says what the last one, [action], gave, when one was tried and it says something.
final class ChatStepIdle extends ChatStepState {
  final ChatStepNotice? notice;
  final ChatStepAction action;

  const ChatStepIdle({
    this.notice,
    this.action = ChatStepAction.confirmFiatSent,
  });
}

/// [action] runs, at [progress] once the use case told its first step: its button cannot be pressed again, and the screen says what it waits for; [waitedLong] once it has waited [TradeCubit.stillWaitingAfter].
final class ChatStepRunning extends ChatStepState {
  final ChatStepAction action;
  final ChatStepProgress? progress;
  final bool waitedLong;

  const ChatStepRunning(this.action, {this.progress, this.waitedLong = false});
}

/// What an action of the chat step gave that the screen says, as a type: never a coordinator's text.
@immutable
sealed class ChatStepNotice {
  const ChatStepNotice();
}

/// The action was not sent ([ChatStepRefusal]).
final class ChatStepWasRefused extends ChatStepNotice {
  final ChatStepRefusal refusal;

  const ChatStepWasRefused(this.refusal);
}

/// The action was refused before the coordinator acted, or never left: nothing was done ([ChatStepNotDone.cause]).
final class ChatStepWasNotDone extends ChatStepNotice {
  final Failure cause;

  const ChatStepWasNotDone(this.cause);
}

/// The action may have happened: the status shown is the read after it, and the next reads tell.
final class ChatStepWasUnknown extends ChatStepNotice {
  const ChatStepWasUnknown();
}

/// Follows one shown trade, cancels it (#88) and sends the actions of its chat step (#95): the only caller of [WatchTradeUsecase], [CancelTradeUsecase] and [ChatStepActionUsecase], which the locator gives it as their methods.
///
/// One watch at a time for the trade: [start] listens, [suspend] (the app hidden or paused) cancels the subscription, [resume] (the app back) listens again, which reads at once; [signal] passes what the screen says (shown or not, read now) to the subscription in place.
/// Closing the cubit cancels the subscription: no timer is left, and a read in flight writes nothing.
/// One action of the trade runs at a time, a cancel or an action of the chat step: a second one meanwhile does nothing, and none is ever sent again by the screen.
class TradeCubit extends Cubit<TradeScreenState> {
  final TradeWatcher _watch;
  final TradeCanceller _cancel;
  final TradeFiatSender? _confirmFiatSent;
  final TradeFiatSender? _undoFiatSent;
  StreamSubscription<TradeWatchState>? _subscription;

  /// How long an action of the chat step runs before the screen adds « Still waiting for {coordinator}. Tor can take a minute. », as the payout's (`PayoutCubit.stillWaitingAfter`).
  static const stillWaitingAfter = Duration(seconds: 30);
  Timer? _stillWaiting;
  StreamController<TradeWatchSignal>? _signals;
  bool _onScreen = true;

  /// [confirmFiatSent] and [undoFiatSent] are `null` where the screen offers no action of the chat step.
  TradeCubit(
    TradeRecord record,
    this._watch,
    this._cancel, {
    this._confirmFiatSent,
    this._undoFiatSent,
  }) : super(TradeScreenState(record));

  /// Whether the screen may offer « Confirm {{amount}} {{currencyCode}} sent ».
  bool get offersFiatSent => _confirmFiatSent != null;

  /// Whether the screen may offer « Payment failed? ».
  bool get offersUndoFiatSent => _undoFiatSent != null;

  /// Whether a watch subscription is open: for the tests.
  @visibleForTesting
  bool get watching => _subscription != null;

  /// Starts following the trade: does nothing when it is already followed.
  void start() {
    if (isClosed || _subscription != null) return;
    final signals = StreamController<TradeWatchSignal>();
    _signals = signals;
    late final StreamSubscription<TradeWatchState> subscription;
    subscription = _subscription =
        _watch(
          state.record,
          signals: signals.stream,
          onScreen: _onScreen,
        ).listen(
          (watch) {
            // Superseded by a newer watch of the trade: not an error; the stream ends and this cubit stops, showing what it showed.
            if (isClosed || watch is TradeWatchSuperseded) return;
            final kept = _keepingWhatWasRead(watch);
            emit(state._with(watch: kept, chatStep: _chatStepAfter(kept)));
          },
          onDone: () {
            // Only this subscription's end clears it: a later start's subscription stays.
            if (identical(_subscription, subscription)) _subscription = null;
            unawaited(signals.close());
            if (identical(_signals, signals)) _signals = null;
          },
        );
  }

  /// What an action of the chat step's notice becomes once the watch gives [watch]: gone when the status shows the action recorded (an outcome unknown whose request landed) or another position than the one the notice was given at, so that a notice never stays under a status it does not speak of (review of #95's second pull request); kept otherwise, a running action included.
  ChatStepState? _chatStepAfter(TradeWatchState watch) {
    final chatStep = state.chatStep;
    if (chatStep is! ChatStepIdle || chatStep.notice == null) return null;
    if (watch is! TradeWatchStatus) return null;
    final seen = watch.seen;
    final shown = state.seen;
    final moved =
        shown != null && shown.status.position != seen.status.position;
    if (ChatStepAction.confirmFiatSent.doneAt(seen) || moved) {
      return const ChatStepIdle();
    }
    return null;
  }

  /// [watch], or, when it is a status not understood yet ([StatusUnknown], as the watch gives when it opens a trade again from its stored trail, or when the stored trail won over its read) at the very position of the status shown, that status with what [watch] says of its reads and records: the screen does not fall back to its wait for a status it has already shown at that position.
  TradeWatchState _keepingWhatWasRead(TradeWatchState watch) {
    final shown = state.seen;
    // A status not marked stored is shown as it is: nothing payable is kept from before.
    if (watch is! TradeWatchStatus ||
        !watch.stored ||
        shown == null ||
        watch.seen.status is! StatusUnknown ||
        shown.status is StatusUnknown ||
        shown.status.position != watch.seen.status.position) {
      return watch;
    }
    return TradeWatchStatus(
      watch.record,
      shown,
      failedReads: watch.failedReads,
      lastReadFailure: watch.lastReadFailure,
      recordProblem: watch.recordProblem,
      takePending: watch.takePending,
    );
  }

  /// Stops following the trade while the app is hidden or paused: nothing runs in the background.
  Future<void> suspend() async {
    final subscription = _subscription;
    final signals = _signals;
    _subscription = null;
    _signals = null;
    await subscription?.cancel();
    await signals?.close();
  }

  /// Follows the trade again when the app comes back: listening reads at once; not once the status shown is an end, as the official client stops reading at an end (`Slot.model.ts:216-223`): the screen keeps what it shows (an order public again with « Take Order » included).
  void resume() {
    if (state.seen?.status.isTerminal ?? false) return;
    start();
  }

  /// Tells the watch whether the trade's screen is the one shown, or to read now.
  void signal(TradeWatchSignal signal) {
    switch (signal) {
      case TradeWatchSignal.onScreen:
        _onScreen = true;
      case TradeWatchSignal.offScreen:
        _onScreen = false;
      case TradeWatchSignal.readNow:
        break;
    }
    _signals?.add(signal);
  }

  /// Cancels the trade at [seen], the status the screen showed when the user asked; [bondLoss] only from the confirmation of a cancel that loses the bond.
  Future<void> cancel(TradeSeen seen, {BondLossAcknowledged? bondLoss}) async {
    if (isClosed || state.actionRunning) return;
    emit(state._with(cancel: const CancelRunning()));
    final Result<CancelOutcome, CancelRefusal> result;
    try {
      result = await _cancel(state.record, seen, bondLoss: bondLoss);
    } on Object {
      // A bug of the use case: « Cancel » free again, the outcome said unknown, and the error passed on.
      if (!isClosed) {
        emit(state._with(cancel: const CancelIdle(notice: CancelWasUnknown())));
      }
      rethrow;
    }
    if (isClosed) return;
    switch (result) {
      case Err(:final failure):
        emit(
          state._with(cancel: CancelIdle(notice: CancelWasRefused(failure))),
        );
      case Ok(value: final outcome):
        emit(
          state._with(
            watch: TradeWatchStatus(
              outcome.record,
              outcome.seen,
              recordProblem: outcome.recordProblem,
              takePending: false,
            ),
            cancel: CancelIdle(
              notice: switch (outcome) {
                CancelDone() => null,
                CancelNotDone(:final cause) => CancelWasNotDone(cause),
                CancelOutcomeUnknown() => const CancelWasUnknown(),
              },
            ),
          ),
        );
        // The watch reads again at once, so that what follows the cancel is shown as soon as the coordinator tells it.
        _signals?.add(TradeWatchSignal.readNow);
    }
  }

  /// Sends the buyer's « fiat sent » at [seen], the status the screen showed when the user confirmed the reference's dialog: once, never again by itself; nothing while another action of the trade runs.
  Future<void> confirmFiatSent(TradeSeen seen) =>
      _chatStep(ChatStepAction.confirmFiatSent, _confirmFiatSent, seen);

  /// Sends the buyer's « Payment failed? » at [seen], the status the screen showed when the user confirmed the reference's dialog: as [confirmFiatSent].
  Future<void> undoFiatSent(TradeSeen seen) =>
      _chatStep(ChatStepAction.undoFiatSent, _undoFiatSent, seen);

  Future<void> _chatStep(
    ChatStepAction action,
    TradeFiatSender? send,
    TradeSeen seen,
  ) async {
    if (send == null || isClosed || state.actionRunning) return;
    emit(state._with(chatStep: ChatStepRunning(action)));
    // After 30 s, « Still waiting for {coordinator}. Tor can take a minute. », as the payout and the take say it.
    _stillWaiting?.cancel();
    _stillWaiting = Timer(stillWaitingAfter, () {
      if (state.chatStep case ChatStepRunning(:final progress) when !isClosed) {
        emit(
          state._with(
            chatStep: ChatStepRunning(
              action,
              progress: progress,
              waitedLong: true,
            ),
          ),
        );
      }
    });
    final Result<ChatStepOutcome, ChatStepRefusal> result;
    try {
      result = await send(
        state.record,
        seen,
        onProgress: (step) {
          if (state.chatStep case ChatStepRunning(
            :final waitedLong,
          ) when !isClosed) {
            emit(
              state._with(
                chatStep: ChatStepRunning(
                  action,
                  progress: step,
                  waitedLong: waitedLong,
                ),
              ),
            );
          }
        },
      );
    } on Object {
      // A bug of the use case: the button and « Cancel » free again, the outcome said unknown, and the error passed on.
      if (!isClosed) {
        emit(
          state._with(
            chatStep: ChatStepIdle(
              notice: const ChatStepWasUnknown(),
              action: action,
            ),
          ),
        );
      }
      rethrow;
    } finally {
      _stillWaiting?.cancel();
      _stillWaiting = null;
    }
    if (isClosed) return;
    switch (result) {
      case Err(:final failure):
        emit(
          state._with(
            // A read kept before the refusal is shown: the status now.
            watch: switch (failure) {
              ChatStepStatusMoved(:final seen, :final record) ||
              ChatStepReadFailed(
                seen: final seen?,
                :final record,
              ) => TradeWatchStatus(
                record ?? state.record,
                seen,
                takePending: false,
              ),
              _ => null,
            },
            chatStep: ChatStepIdle(
              notice: ChatStepWasRefused(failure),
              action: action,
            ),
          ),
        );
      case Ok(value: final outcome):
        emit(
          state._with(
            watch: TradeWatchStatus(
              outcome.record,
              outcome.seen,
              recordProblem: outcome.recordProblem,
              takePending: false,
            ),
            chatStep: ChatStepIdle(
              notice: switch (outcome) {
                ChatStepDone() => null,
                ChatStepNotDone(:final cause) => ChatStepWasNotDone(cause),
                ChatStepOutcomeUnknown() => const ChatStepWasUnknown(),
              },
              action: action,
            ),
          ),
        );
    }
    // The watch reads again at once, so that what follows is shown as soon as the coordinator tells it.
    _signals?.add(TradeWatchSignal.readNow);
  }

  @override
  Future<void> close() async {
    _stillWaiting?.cancel();
    await suspend();
    return super.close();
  }
}
