import 'dart:async';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../p2p_failure.dart';
import '../../robot_request_limiter.dart';
import '../../trade/trade_answer.dart';
import '../../trade/trade_chat_step.dart';
import '../../trade/trade_status.dart';
import '../../trade/trade_watch.dart';
import '../../trade_record.dart';
import 'trade_reader.dart';
import 'trade_take_locks.dart';

/// Sends the actions of the chat step of a trade (9 and 10) that the user tapped, as the reference's `TradeBox/Prompts/Chat.tsx` offers them (#95, design note § 2.4): « Confirm {{amount}} {{currencyCode}} sent » ([confirmFiatSent]), « Payment failed? » ([undoFiatSent]) and « Open Dispute » ([startDispute]).
///
/// Each action, in this order, each step only once the one before it succeeded:
/// 1. the status the user saw offers the action ([ChatStepAction.offeredAt]: marked stored, from an order read, the right role and status) and is this trade's; the trade is opened from its records ([TradeReader.open]);
/// 2. one action of the order runs at a time in the process ([TradeTakeLocks], which the take, the cancel, the payout and the bond's payment share);
/// 3. the order is read again and kept ([TradeReader.readOrder], [TradeReader.advance]): the action is sent only if that read is marked stored and still offers it, so that the status shown is the status stored ([ChatStepReadFailed], [ChatStepStatusMoved] otherwise, nothing sent); a read that shows the action recorded already ([ChatStepAction.doneAt], an earlier request that landed late) is [ChatStepDone], nothing sent;
/// 4. the action is sent once through the robot's places in [RobotRequestLimiter] (a busy transport, which sends nothing, is tried again as the limiter says), and never again: an answer lost or unreadable is an outcome unknown, resolved by the read that follows, never by a second send;
/// 5. its answer is kept, then the order read again and kept: [ChatStepDone], [ChatStepNotDone] or [ChatStepOutcomeUnknown], each with the status as stored.
/// « Fiat sent » recorded is a read that shows 10 (`Chatting.fiatSent`); not recorded is a read that still shows 9: that is how the screen tells one from the other after an outcome unknown, and only a new tap of the user may send again.
/// Nothing here pays or moves the wallet's funds; nothing is printed or logged.
final class ChatStepActionUsecase {
  final CoordinatorClient _client;
  final TradeReader _reader;
  final RobotRequestLimiter _limiter;
  final TradeTakeLocks _locks;

  const ChatStepActionUsecase(
    this._client,
    this._reader,
    this._limiter,
    this._locks,
  );

  /// The buyer's « fiat sent » for the trade of [record] at [seen], the status the screen showed when the user confirmed the reference's dialog.
  ///
  /// [Err]: nothing was sent ([ChatStepRefusal]). [Ok]: the action was sent, or may have left; [ChatStepOutcome] says what it and the read after it gave.
  /// [onProgress] is told each step as it starts, for the screen to say what it waits for; one that throws is reported to the zone and stops nothing.
  Future<Result<ChatStepOutcome, ChatStepRefusal>> confirmFiatSent(
    TradeRecord record,
    TradeSeen seen, {
    void Function(ChatStepProgress step)? onProgress,
  }) => _run(
    ChatStepAction.confirmFiatSent,
    record,
    seen,
    onProgress: onProgress,
    send: (identity, lastRead) =>
        _client.confirmFiat(identity: identity, lastRead: lastRead),
  );

  /// The buyer's « Payment failed? » for the trade of [record] at [seen] (10), the status the screen showed when the user confirmed the reference's dialog: « fiat sent » taken back, 10 → 9; the same steps and outcomes as [confirmFiatSent].
  Future<Result<ChatStepOutcome, ChatStepRefusal>> undoFiatSent(
    TradeRecord record,
    TradeSeen seen, {
    void Function(ChatStepProgress step)? onProgress,
  }) => _run(
    ChatStepAction.undoFiatSent,
    record,
    seen,
    onProgress: onProgress,
    send: (identity, lastRead) =>
        _client.undoConfirmFiat(identity: identity, lastRead: lastRead),
  );

  /// « Open Dispute » for the trade of [record] at [seen] (9 or 10), the status the screen showed when the user agreed to the reference's dialog: refused before its time ([ChatStepTooEarly], [ChatStepAction.disputeOpensAt], by this device's clock; the coordinator's 1054 stays the judge), then the same steps and outcomes as [confirmFiatSent].
  Future<Result<ChatStepOutcome, ChatStepRefusal>> startDispute(
    TradeRecord record,
    TradeSeen seen, {
    void Function(ChatStepProgress step)? onProgress,
  }) => _run(
    ChatStepAction.dispute,
    record,
    seen,
    onProgress: onProgress,
    send: (identity, lastRead) =>
        _client.openDispute(identity: identity, lastRead: lastRead),
  );

  Future<Result<ChatStepOutcome, ChatStepRefusal>> _run(
    ChatStepAction action,
    TradeRecord record,
    TradeSeen seen, {
    required Future<Result<TradeActionOutcome, OrderActionFailure>> Function(
      RobotIdentity identity,
      CoordinatorOrder lastRead,
    )
    send,
    void Function(ChatStepProgress step)? onProgress,
  }) async {
    final tell = onProgress == null ? null : _told(onProgress);
    final shown = seen.order;
    if (shown == null || !action.offeredAt(seen)) {
      return const Err(ChatStepNotOffered());
    }
    if (_tooEarly(action, seen) case final opensAt?) {
      return Err(ChatStepTooEarly(opensAt, opensAt.difference(_reader.now())));
    }
    final OpenTrade trade;
    switch (await _reader.open(record)) {
      case TradeOpened(trade: final opened):
        trade = opened;
      case TradeNotRestorable(:final reason):
        return Err(ChatStepTradeUnrestorable(reason));
      case TradeNotOpened(:final failure):
        return Err(ChatStepTradeUnavailable(failure));
      case TradeTakeNeverSent():
        return const Err(ChatStepOfAnotherTrade());
    }
    final terms = trade.terms;
    if (shown.id != terms.orderId ||
        shown.coordinator != terms.coordinator ||
        shown.network != terms.network) {
      return const Err(ChatStepOfAnotherTrade());
    }
    // Another action of the order may hold it: the wait is said for what it is; a free order goes on at once.
    tell?.call(ChatStepProgress.waitingForOrder);
    return _locks.run(
      record.network,
      trade.coordinator,
      record.orderId,
      () async {
        final requests = _limiter.open(trade.robot.identity.sessionKey);
        try {
          return await _send(requests, trade, action, send, tell);
        } finally {
          requests.close();
        }
      },
    );
  }

  Future<Result<ChatStepOutcome, ChatStepRefusal>> _send(
    RobotRequests requests,
    OpenTrade trade,
    ChatStepAction action,
    Future<Result<TradeActionOutcome, OrderActionFailure>> Function(
      RobotIdentity identity,
      CoordinatorOrder lastRead,
    )
    send,
    void Function(ChatStepProgress step)? tell,
  ) async {
    final record = trade.record;
    final robot = trade.robot;
    var current = trade;
    P2pFailure? problem;
    Future<void> keep(TradeAnswer answer, {DateTime? requestedAt}) async {
      final step = await _reader.advance(
        current,
        answer,
        at: _reader.now(),
        requestedAt: requestedAt,
      );
      current = step.trade;
      problem ??= step.recordProblem;
    }

    // The order as it is now, kept: the action leaves only if this read still offers it.
    tell?.call(ChatStepProgress.readingOrder);
    final requestedAt = _reader.now();
    final TradeAnswer answer;
    switch (await _reader.readOrder(
      requests,
      record,
      robot,
      trade.coordinator,
    )) {
      case Err(:final failure):
        return Err(ChatStepReadFailed(cause: failure));
      case Ok(value: final result):
        switch (TradeAnswer.ofRead(result)) {
          case final read?:
            answer = read;
          case null:
            return Err(
              ChatStepReadFailed(
                cause: switch (result) {
                  Err(:final failure) => failure,
                  Ok() => null,
                },
              ),
            );
        }
    }
    final step = await _reader.advance(
      current,
      answer,
      at: _reader.now(),
      requestedAt: requestedAt,
    );
    current = step.trade;
    problem ??= step.recordProblem;
    final fresh = current.seen;
    if (!step.stored) {
      return Err(
        ChatStepReadFailed(
          cause: step.recordProblem,
          seen: fresh,
          record: current.record,
        ),
      );
    }
    // Recorded already (a request of an earlier tap that landed late): done, nothing sent again.
    if (action.doneAt(fresh)) {
      return Ok(ChatStepDone(current.record, fresh, recordProblem: problem));
    }
    final lastRead = fresh.order;
    if (lastRead == null || !action.offeredAt(fresh)) {
      return Err(ChatStepStatusMoved(fresh, record: current.record));
    }
    if (_tooEarly(action, fresh) case final opensAt?) {
      return Err(ChatStepTooEarly(opensAt, opensAt.difference(_reader.now())));
    }

    // Sent once: never again by this use case, whatever the outcome.
    tell?.call(ChatStepProgress.sending);
    final sent = await requests.send(
      record.network,
      trade.coordinator,
      () => send(robot.identity, lastRead),
      isBusy: _answeredBusy,
    );

    // The answer first, then a read after it.
    tell?.call(ChatStepProgress.readingAfter);
    if (sent case Ok(value: Ok(:final value))) {
      await keep(TradeOrderRead(value.order));
    }
    final readFrom = _reader.now();
    final read = await _reader.readOrder(
      requests,
      record,
      robot,
      trade.coordinator,
    );
    if (read case Ok(value: final result)) {
      if (TradeAnswer.ofRead(result) case final after?) {
        await keep(after, requestedAt: readFrom);
      }
    }
    // The read after shows the action recorded (an earlier request that landed, or this one whose answer was lost or refused as busy after a late landing): done, whatever the answer said, so that no notice contradicts the status shown.
    if (action.doneAt(current.seen)) {
      return Ok(
        ChatStepDone(current.record, current.seen, recordProblem: problem),
      );
    }
    return Ok(switch (sent) {
      Ok(value: Ok()) => ChatStepDone(
        current.record,
        current.seen,
        recordProblem: problem,
      ),
      Ok(value: Err(failure: OrderActionRefused(:final cause))) =>
        ChatStepNotDone(
          current.record,
          current.seen,
          cause: cause,
          recordProblem: problem,
        ),
      Ok(value: Err(failure: OrderActionOutcomeUnknown())) =>
        ChatStepOutcomeUnknown(
          current.record,
          current.seen,
          recordProblem: problem,
        ),
      // Busy every time, or the robot released: the action never reached the coordinator.
      Err(:final failure) => ChatStepNotDone(
        current.record,
        current.seen,
        cause: failure,
        recordProblem: problem,
      ),
    });
  }

  /// When « Open Dispute » becomes possible at [seen], if that is still ahead by this device's clock; `null` for any other action, or once the time has come.
  DateTime? _tooEarly(ChatStepAction action, TradeSeen seen) {
    if (action != ChatStepAction.dispute) return null;
    final status = seen.status;
    if (status is! Chatting) return null;
    final opensAt = ChatStepAction.disputeOpensAt(status);
    return _reader.now().isBefore(opensAt) ? opensAt : null;
  }

  /// [onProgress], which reports to the zone what it throws instead of stopping the step it announces.
  static void Function(ChatStepProgress step) _told(
    void Function(ChatStepProgress step) onProgress,
  ) => (step) {
    try {
      onProgress(step);
    } on Object catch (error, stack) {
      Zone.current.handleUncaughtError(error, stack);
    }
  };

  /// Whether the transport answered the action busy: nothing reached the coordinator.
  static bool _answeredBusy(
    Result<TradeActionOutcome, OrderActionFailure> answer,
  ) => switch (answer) {
    Err(failure: OrderActionRefused(cause: CoordinatorTransportBusy())) => true,
    _ => false,
  };
}
