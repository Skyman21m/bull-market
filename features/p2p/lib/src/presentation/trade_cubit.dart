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

/// [ChatStepActionUsecase.confirmFiatSent], which the locator gives the cubit.
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

/// No action of the chat step runs; [notice] says what the last one gave, when one was tried and it says something.
final class ChatStepIdle extends ChatStepState {
  final ChatStepNotice? notice;

  const ChatStepIdle({this.notice});
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
  StreamSubscription<TradeWatchState>? _subscription;

  /// Whether the status shown is one kept while the trade was opened anew, its first read since not in ([_keepingWhatWasRead]): nothing is sent from it alone.
  bool _kept = false;

  /// How long an action of the chat step runs before the screen adds « Still waiting for {coordinator}. Tor can take a minute. », as the payout's (`PayoutCubit.stillWaitingAfter`).
  static const stillWaitingAfter = Duration(seconds: 30);
  Timer? _stillWaiting;
  StreamController<TradeWatchSignal>? _signals;
  bool _onScreen = true;

  /// [confirmFiatSent] is `null` where the screen offers no action of the chat step; [lastStored], where the screen shows nothing again when it opens the trade anew.
  TradeCubit(
    TradeRecord record,
    this._watch,
    this._cancel, {
    this._confirmFiatSent,
    this._lastStored,
  }) : super(TradeScreenState(record));

  /// Whether the status shown was kept while the trade was opened anew and no read came in since (#152): « Cancel » then asks for a read first, as for a status that comes from no order.
  bool get showsKept => _kept;

  /// Whether the screen may offer « Confirm {{amount}} {{currencyCode}} sent ».
  bool get offersFiatSent => _confirmFiatSent != null;

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

  /// [watch], or, when it is the stored trail's own status ([StatusUnknown]: the watch opened the trade anew, on the app's return or on a new screen, and its first read is not in, or has failed since) and that trail is the very one a status of this run was stored with, that status, with what [watch] says of its reads: the screen does not fall back to its wait for a status this run has already read, as the official client keeps the order it shows while it reads it again (`frontend/src/basic/OrderPage/index.tsx:76-96`, `models/Order.model.ts:264-281`) (#152).
  ///
  /// The status kept is the newest this run stored for the trade ([TradeLastStored]), else the one this screen shows: only a status marked [TradeSeen.stored] (the one rule of #117 for an invoice or a payment), never one whose trail is not the stored trail (another position, or the same position stored by a later write), and never under a write that failed ([TradeWatchStatus.recordProblem]: the trail on disk's own status is shown then, as before). The watch gives such a status only once it has opened the trade with the Garage Key there now, so a robot gone, or another key, never gets it. Until a read comes in, [showsKept]: nothing is sent from it alone.
  /// The watch's own status is never marked stored (`TradeReader.open` and `keep` give the trail's own status unmarked by design): requiring `stored` of it, as this did before, kept nothing.
  TradeWatchState _keepingWhatWasRead(TradeWatchState watch) {
    if (watch is! TradeWatchStatus ||
        watch.seen.status is! StatusUnknown ||
        watch.recordProblem != null) {
      _kept = false;
      return watch;
    }
    final onDisk = watch.seen.status.trail;
    bool storedWith(TradeSeen? candidate) =>
        candidate != null &&
        candidate.stored &&
        candidate.status.position == onDisk.position &&
        candidate.status.trail.readAt.microsecondsSinceEpoch ==
            onDisk.readAt.microsecondsSinceEpoch;
    final last = _lastStored?.call(state.record);
    final shown = state.seen;
    final kept = storedWith(last)
        ? last
        : storedWith(shown)
        ? shown
        : null;
    if (kept == null) {
      _kept = false;
      return watch;
    }
    _kept = true;
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
    // A status kept while the trade was opened anew, no read in since: refused as for a status that comes from no order (« Wait until the order is read again before cancelling. »), nothing sent (#152).
    if (_kept) {
      emit(
        state._with(
          cancel: const CancelIdle(
            notice: CancelWasRefused(CancelNeedsARead()),
          ),
        ),
      );
      return;
    }
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
        _kept = false;
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
  Future<void> confirmFiatSent(TradeSeen seen) async {
    final send = _confirmFiatSent;
    if (send == null || isClosed || state.actionRunning) return;
    const action = ChatStepAction.confirmFiatSent;
    emit(state._with(chatStep: const ChatStepRunning(action)));
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
            chatStep: const ChatStepIdle(notice: ChatStepWasUnknown()),
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
          ChatStepReadFailed(seen: final seen?, :final record) =>
            TradeWatchStatus(record ?? state.record, seen, takePending: false),
          _ => null,
        };
        if (read != null) _kept = false;
        emit(
          state._with(
            watch: read,
            chatStep: ChatStepIdle(notice: ChatStepWasRefused(failure)),
          ),
        );
      case Ok(value: final outcome):
        _kept = false;
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
