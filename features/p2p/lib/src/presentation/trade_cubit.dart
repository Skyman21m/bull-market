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

/// [WatchTradeUsecase.lastStored], which the locator gives the cubit (#152).
typedef TradeLastStored = TradeSeen? Function(TradeRecord record);

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
  /// Whether it has run [TradeCubit.stillWaitingAfter]: the screen adds « Still waiting for {coordinator}. Tor can take a minute. ».
  final bool waitedLong;

  const CancelRunning({this.waitedLong = false});
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
  final TradeLastStored? _lastStored;
  final TradeFiatSender? _undoFiatSent;
  final TradeFiatSender? _startDispute;
  StreamSubscription<TradeWatchState>? _subscription;

  /// How long an action of the chat step runs before the screen adds « Still waiting for {coordinator}. Tor can take a minute. », as the payout's (`PayoutCubit.stillWaitingAfter`).
  static const stillWaitingAfter = Duration(seconds: 30);
  Timer? _stillWaiting;
  StreamController<TradeWatchSignal>? _signals;
  bool _onScreen = true;

  /// [confirmFiatSent] and [undoFiatSent] are `null` where the screen offers no action of the chat step; [lastStored], where the screen shows nothing again when it opens the trade anew.
  TradeCubit(
    TradeRecord record,
    this._watch,
    this._cancel, {
    this._confirmFiatSent,
    this._undoFiatSent,
    this._startDispute,
    this._lastStored,
  }) : super(TradeScreenState(record));

  /// Whether the screen may offer « Confirm {{amount}} {{currencyCode}} sent ».
  bool get offersFiatSent => _confirmFiatSent != null;

  /// Whether the screen may offer « Payment failed? ».
  bool get offersUndoFiatSent => _undoFiatSent != null;

  /// Whether the screen may offer « Open Dispute ».
  bool get offersDispute => _startDispute != null;

  /// Whether a watch subscription is open: for the tests.
  @visibleForTesting
  bool get watching => _subscription != null;

  /// What [TradeLastStored] gives for this trade now, `null` without one: for the tests of the composition.
  @visibleForTesting
  TradeSeen? get lastStoredNow => _lastStored?.call(state.record);

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
            emit(
              state._with(
                watch: kept,
                chatStep: _chatStepAfter(kept),
                cancel: _cancelAfter(kept),
              ),
            );
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
    // The action the notice is about: « Payment failed? »'s notice stays at 10, where « fiat sent »'s would be done (review of #95's third pull request).
    if (chatStep.action.doneAt(seen) || moved) {
      return const ChatStepIdle();
    }
    return null;
  }

  /// What a cancel's notice becomes once the watch gives [watch], by the same rule as an action of the chat step's: gone when the status shows the ask recorded (`asked_for_cancel`), the order cancelled, or another position than the one the notice was given at; kept otherwise, a running cancel included.
  TradeCancelState? _cancelAfter(TradeWatchState watch) {
    final cancel = state.cancel;
    if (cancel is! CancelIdle || cancel.notice == null) return null;
    if (watch is! TradeWatchStatus) return null;
    final seen = watch.seen;
    final shown = state.seen;
    final moved =
        shown != null && shown.status.position != seen.status.position;
    final recorded = switch (seen.status) {
      Chatting(:final askedToCancel) => askedToCancel,
      Cancelled() => true,
      _ => false,
    };
    if (recorded || moved) return const CancelIdle();
    return null;
  }

  /// [watch], or, when it is the stored trail's own status ([StatusUnknown]: the watch opened the trade anew, on the app's return or on a new screen, and its first read is not in, or has failed since) and that trail is the very one the newest status this run stored was stored with, that status, with what [watch] says of its reads: the screen does not fall back to its wait for a status this run has already read, as the official client keeps the order it shows while it reads it again (`frontend/src/basic/OrderPage/index.tsx:76-96`, `models/Order.model.ts:264-281`) (#152).
  ///
  /// The status kept is the newest this run stored for the trade ([TradeLastStored]): every status marked [TradeSeen.stored] is stored there by `TradeReader.keep`, the status this screen shows included, so it is the only source, and it gives nothing once a newer answer was accepted and its trail not stored (review of #152). Only a status marked stored (the one rule of #117 for an invoice or a payment), never one whose trail is not the stored trail (another position, or the same position stored by a later write), and never under a write that failed ([TradeWatchStatus.recordProblem]: the trail on disk's own status is shown then, as before). Without [TradeLastStored], nothing is kept. The watch gives such a status only once it has opened the trade with the Garage Key there now, so a robot gone, or another key, never gets it. Nothing is sent from it alone: the actions read the order first, and « Cancel » sends that status's guard, as the reference cancels from the order it holds.
  /// The watch's own status is never marked stored (`TradeReader.open` and `keep` give the trail's own status unmarked by design): requiring `stored` of it, as this did before, kept nothing.
  TradeWatchState _keepingWhatWasRead(TradeWatchState watch) {
    if (watch is! TradeWatchStatus ||
        watch.seen.status is! StatusUnknown ||
        watch.recordProblem != null) {
      return watch;
    }
    final onDisk = watch.seen.status.trail;
    final kept = _lastStored?.call(state.record);
    if (kept == null ||
        !kept.stored ||
        kept.status.position != onDisk.position ||
        kept.status.trail.readAt.microsecondsSinceEpoch !=
            onDisk.readAt.microsecondsSinceEpoch) {
      return watch;
    }
    return TradeWatchStatus(
      watch.record,
      kept,
      failedReads: watch.failedReads,
      lastReadFailure: watch.lastReadFailure,
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
    // After 30 s, the long wait's line, as for an action of the chat step.
    final longWait = Timer(stillWaitingAfter, () {
      if (!isClosed && state.cancel is CancelRunning) {
        emit(state._with(cancel: const CancelRunning(waitedLong: true)));
      }
    });
    final Result<CancelOutcome, CancelRefusal> result;
    try {
      result = await _cancel(state.record, seen, bondLoss: bondLoss);
    } on Object {
      // A bug of the use case: « Cancel » free again, the outcome said unknown, and the error passed on.
      if (!isClosed) {
        emit(state._with(cancel: const CancelIdle(notice: CancelWasUnknown())));
      }
      rethrow;
    } finally {
      longWait.cancel();
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

  /// Opens a dispute at [seen], the status the screen showed when the user agreed to the reference's dialog: as [confirmFiatSent].
  Future<void> startDispute(TradeSeen seen) =>
      _chatStep(ChatStepAction.dispute, _startDispute, seen);

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
        // A read kept before the refusal is shown: the status now.
        final read = switch (failure) {
          ChatStepStatusMoved(:final seen, :final record) ||
          ChatStepReadFailed(seen: final seen?, :final record) ||
          ChatStepTooEarly(seen: final seen?, :final record) =>
            TradeWatchStatus(record ?? state.record, seen, takePending: false),
          _ => null,
        };
        emit(
          state._with(
            watch: read,
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
