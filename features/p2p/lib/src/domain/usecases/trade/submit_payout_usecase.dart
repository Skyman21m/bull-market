import 'dart:async';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../p2p_failure.dart';
import '../../repositories/trade_payout_repository.dart';
import '../../robot_request_limiter.dart';
import '../../trade/bolt11.dart';
import '../../trade/payout_trace.dart';
import '../../trade/trade_answer.dart';
import '../../trade/trade_payout.dart';
import '../../trade/trade_payout_outcome.dart';
import '../../trade/trade_watch.dart';
import '../../trade_record.dart';
import 'trade_keyring.dart';
import 'trade_read_order.dart';
import 'trade_reader.dart';
import 'trade_take_locks.dart';
import 'wallet_payout_destinations.dart';

/// Gives the coordinator where the buyer of a trade is to be paid: a Lightning invoice or an on-chain address, clear-signed by the robot's key (#90, design note § 2.2, § 4.4; `AGENTS.md` « The buyer's payout »).
///
/// The panel (#91) asks [ask] what to show before anything is pasted, [check] what the user pasted (or, later, what this wallet made: the same text, checked the same way), shows the [CheckedPayout] it gets, and gives that very value to [execute] on the user's confirmation.
/// [execute], in this order, each step only once the one before it succeeded:
/// 1. the payout shown is this trade's; the trade is opened from its records ([TradeReader.open]), and one action of its order runs at a time in the process ([TradeTakeLocks], which the take shares);
/// 2. the robot's key is leased from [TradeKeyring] (read back from its coordinator and unlocked away from the UI isolate, unless the trade screen's hold keeps it);
/// 3. the order is read again and kept ([TradeReader.readOrder], [TradeReader.advance]): only a status marked stored goes on;
/// 4. the destination shown is checked again against that read ([PayoutAsk.check]): a refusal, or anything the user would now see differently (a figure, a warning), sends nothing ([PayoutNoLongerValid], [PayoutChangedSinceShown]);
/// 5. the very text shown is signed (`UnlockedRobotPgpKey.signPayoutInvoice`, `signPayoutAddress`), the signed text, network and signer compared with what was shown;
/// 6. the payout is sent once, the action itself signed by the same lease's key (GHSA-22q8-9ghc-jg3h: `CoordinatorClient` signs `update_invoice` or `update_address` just before the request leaves), then the lease closed, through the robot's places in [RobotRequestLimiter] (a busy transport, which sends nothing, is tried again as the limiter says), and never again: a refusal the coordinator client decided from that read (`PayoutRefused.fromLastRead`) is followed by one more read and one more try, signed again, before anything is told;
/// 7. once the coordinator answered that it took the payout, or may have (an outcome unknown), where it came from is recorded for the contract it was signed for (schema 9, #204: from this wallet, when the text is an invoice or an address this wallet gave during this run, else pasted), before anything else; never for a refusal, whose payout the coordinator does not hold;
/// 8. its answer is kept, then the order read again and kept: [PayoutGiven], [PayoutNotTaken] or [PayoutOutcomeUnknown], each with the status as stored (or the trail on disk's own), never one made up.
/// Nothing here pays or moves the wallet's funds; nothing is printed or logged.
final class SubmitPayoutUsecase {
  final CoordinatorClient _client;
  final TradeReader _reader;
  final RobotRequestLimiter _limiter;
  final TradeKeyring _keyring;
  final TradeTakeLocks _locks;
  final Bolt11Reader _invoices;

  /// Where each contract's payout came from (schema 9, #204); `null` records nothing, as before schema 9.
  final TradePayoutRepository? _payouts;

  /// The invoices and addresses this wallet gave during this run; `null`, every payout is pasted.
  final WalletPayoutDestinations? _fromWallet;

  const SubmitPayoutUsecase(
    this._client,
    this._reader,
    this._limiter,
    this._keyring,
    this._locks,
    this._invoices, {
    this._payouts,
    this._fromWallet,
  });

  /// What the coordinator asks of the buyer of [record] at [seen], the status the screen shows (marked stored): the amounts and options the panel shows.
  Result<PayoutAsk, PayoutCheckRefusal> ask(
    TradeRecord record,
    TradeSeen seen,
  ) => PayoutAsk.of(record, seen);

  /// [destination] decoded and checked for the trade of [record] at [seen], now: the value to show, then to give to [execute].
  Result<CheckedPayout, PayoutCheckRefusal> check(
    TradeRecord record,
    TradeSeen seen,
    PayoutDestination destination,
  ) => switch (PayoutAsk.of(record, seen)) {
    Err(:final failure) => Err(failure),
    Ok(:final value) => value.check(
      destination,
      now: _reader.now(),
      reader: _invoices,
    ),
  };

  /// Signs and sends [shown], the payout the user confirmed, for the trade of [record].
  ///
  /// [Err]: nothing was sent ([PayoutNotSent]). [Ok]: the payout was sent, or may have left; [PayoutSubmission] says what it and the read after it gave.
  ///
  /// [onProgress] is told each step as it starts ([PayoutProgress]), for the panel to say what it waits for; it changes nothing of what is done: one that throws is reported to the zone, never stops a payout under way (review of #132).
  Future<Result<PayoutSubmission, PayoutNotSent>> execute(
    TradeRecord record,
    CheckedPayout shown, {
    void Function(PayoutProgress step)? onProgress,
  }) async {
    final tell = onProgress == null ? null : _told(onProgress);
    if (!shown.isFor(record)) return const Err(PayoutOfAnotherTrade());
    final OpenTrade trade;
    switch (await _reader.open(record)) {
      case TradeOpened(trade: final opened):
        trade = opened;
      case TradeNotRestorable(:final reason):
        return Err(PayoutTradeUnrestorable(reason));
      case TradeNotOpened(:final failure):
        return Err(PayoutTradeUnavailable(failure));
      case TradeTakeNeverSent():
        return const Err(PayoutOfAnotherTrade());
    }
    // Another action of the order (a take, a cancel, a payout) may hold it: the wait is said for what it is; a free order goes on at once, before anything is drawn.
    tell?.call(PayoutProgress.waitingForOrder);
    return _locks.run(
      record.network,
      trade.coordinator,
      record.orderId,
      // An action of the trade: the watch sends no read while it runs (#141).
      () => _reader.duringAction(record, () async {
        final requests = _limiter.open(trade.robot.identity.sessionKey);
        try {
          return await _submit(
            requests,
            trade,
            shown,
            retried: false,
            onProgress: tell,
          );
        } finally {
          requests.close();
        }
      }),
    );
  }

  /// [onProgress], which reports to the zone what it throws instead of stopping the step it announces.
  static void Function(PayoutProgress step) _told(
    void Function(PayoutProgress step) onProgress,
  ) => (step) {
    try {
      onProgress(step);
    } on Object catch (error, stack) {
      Zone.current.handleUncaughtError(error, stack);
    }
  };

  /// One try: the lease, the fresh read, the check again, the signature, the request, and what it gave; once more after a refusal decided from the read, when [retried] is false.
  Future<Result<PayoutSubmission, PayoutNotSent>> _submit(
    RobotRequests requests,
    OpenTrade trade,
    CheckedPayout shown, {
    required bool retried,
    void Function(PayoutProgress step)? onProgress,
  }) async {
    final record = trade.record;
    final robot = trade.robot;
    var current = trade;
    P2pFailure? problem;
    Future<void> keep(
      TradeAnswer answer, {
      required RequestTimes request,
      bool keepsTime = false,
    }) async {
      final step = await _reader.advance(
        current,
        answer,
        at: _reader.now(),
        request: request,
        keepsTime: keepsTime,
      );
      current = step.trade;
      problem ??= step.recordProblem;
    }

    onProgress?.call(PayoutProgress.unlockingKey);
    final TradeKeyLease lease;
    switch (await _keyring.lease(trade)) {
      case Err(:final failure):
        return Err(PayoutKeyUnavailable(failure));
      case Ok(:final value):
        lease = value;
    }
    final Future<Result<PayoutOutcome, OrderActionFailure>> Function() submit;
    // The contract the payout is signed for, and what it is, for its record (#204).
    final int take;
    final ({PayoutTraceKind kind, bool fromWallet}) given;
    var sending = false;
    try {
      // The order as it is now, kept: the payout is signed from this read only.
      onProgress?.call(PayoutProgress.readingOrder);
      // Superseded (a read of the watch that left before the payout began answered after it left), it is read once more: no read of the watch leaves while the payout runs, so the second read cannot be superseded; if it is, nothing is sent (#141).
      TradeStep step;
      var reads = 0;
      do {
        reads++;
        final times = _reader.request();
        final TradeAnswer answer;
        switch (await _reader.readOrder(
          requests,
          record,
          robot,
          trade.coordinator,
          times: times,
        )) {
          case Err(:final failure):
            return Err(PayoutReadFailed(cause: failure));
          case Ok(value: final result):
            switch (TradeAnswer.ofRead(result)) {
              case final read?:
                answer = read;
              case null:
                return Err(
                  PayoutReadFailed(
                    cause: switch (result) {
                      Err(:final failure) => failure,
                      Ok() => null,
                    },
                  ),
                );
            }
        }
        step = await _reader.advance(
          current,
          answer,
          at: _reader.now(),
          request: times,
          keepsTime: true,
        );
        current = step.trade;
        problem ??= step.recordProblem;
      } while (step.superseded && reads < 2);
      final seen = current.seen;
      if (!step.stored) {
        return Err(PayoutReadFailed(cause: step.recordProblem, seen: seen));
      }
      final CheckedPayout checked;
      switch (check(current.record, seen, shown.destination)) {
        case Err(:final failure):
          return Err(PayoutNoLongerValid(failure, seen));
        case Ok(:final value):
          if (!shown.showsSameAs(value)) {
            return Err(PayoutChangedSinceShown(value, seen));
          }
          checked = value;
      }
      final lastRead = seen.order;
      if (lastRead == null) return Err(PayoutReadFailed(seen: seen));
      take = seen.status.trail.take;
      given = switch (checked) {
        CheckedPayoutInvoice(:final text) => (
          kind: PayoutTraceKind.invoice,
          fromWallet: _fromWallet?.isInvoiceOfThisWallet(text) ?? false,
        ),
        CheckedPayoutAddress(:final address) => (
          kind: PayoutTraceKind.address,
          fromWallet: _fromWallet?.isAddressOfThisWallet(address.text) ?? false,
        ),
      };

      // The very text shown, signed now, for this read; what was signed compared with what was shown before it may leave.
      bool isShown(SignedPayout signed) =>
          signed.text == shown.text &&
          signed.network == record.network &&
          signed.signer == robot.identity.hashId;
      final now = _reader.now();
      switch (checked) {
        case CheckedPayoutInvoice(:final text, :final budget):
          switch (lease.key.signPayoutInvoice(text, record.network, now: now)) {
            case Err(:final failure):
              return Err(PayoutNotSigned(failure));
            case Ok(value: final invoice):
              if (!isShown(invoice)) return const Err(PayoutNotSigned(null));
              submit = () => _client.submitPayoutInvoice(
                identity: robot.identity,
                lastRead: lastRead,
                key: lease.key,
                invoice: invoice,
                routingBudget: budget,
              );
          }
        case CheckedPayoutAddress(:final address, :final rate):
          switch (lease.key.signPayoutAddress(address, now: now)) {
            case Err(:final failure):
              return Err(PayoutNotSigned(failure));
            case Ok(value: final signedAddress):
              if (!isShown(signedAddress)) {
                return const Err(PayoutNotSigned(null));
              }
              submit = () => _client.submitPayoutAddress(
                identity: robot.identity,
                lastRead: lastRead,
                key: lease.key,
                address: signedAddress,
                miningFeeRate: rate,
              );
          }
      }
      sending = true;
    } finally {
      // Kept for the request, which the client signs as an action too; closed here on every way out before it.
      if (!sending) lease.close();
    }

    final RequestTimes submitTimes;
    final Result<Result<PayoutOutcome, OrderActionFailure>, P2pFailure> sent;
    try {
      onProgress?.call(PayoutProgress.sending);
      submitTimes = _reader.request();
      sent = await requests.send(
        record.network,
        trade.coordinator,
        () => _reader.timed(submitTimes, submit),
        isBusy: _answeredBusy,
      );
    } finally {
      lease.close();
    }

    // A refusal decided from the read, nothing sent: once more from a fresh read, signed again.
    if (sent case Ok(
      value: Err(failure: OrderActionRefused(cause: final PayoutRefused cause)),
    ) when cause.fromLastRead) {
      if (!retried) {
        return _submit(
          requests,
          current,
          shown,
          retried: true,
          onProgress: onProgress,
        );
      }
      return Err(PayoutRefusedFromRead(cause, current.seen));
    }

    // Where the payout came from, for the contract it was signed for, as soon as the coordinator took it or may have (#204): written before the answer is kept, so that the status read after it finds it. A write that fails is told as the records' other failures; its absence later reads « not given from this device », the side that alerts.
    if (_payouts case final payouts?) {
      final took = switch (sent) {
        Ok(value: Ok()) ||
        Ok(value: Err(failure: OrderActionOutcomeUnknown())) => true,
        _ => false,
      };
      if (took) {
        switch (await payouts.recordPayout(
          record,
          take: take,
          source: given.fromWallet
              ? PayoutTraceSource.thisWallet
              : PayoutTraceSource.pasted,
          kind: given.kind,
          at: _reader.now(),
        )) {
          case Ok(value: true):
            break;
          case Ok(value: false):
            problem ??= const P2pStorageFailure();
          case Err(:final failure):
            problem ??= failure;
        }
      }
    }

    // The answer first, then a read after it, which stores the status (an answer superseded is judged from itself only: what it says of the payout).
    onProgress?.call(PayoutProgress.readingAfter);
    if (sent case Ok(value: Ok(:final value))) {
      await keep(TradeOrderRead(value.order), request: submitTimes);
    }
    final readAfter = _reader.request();
    final read = await _reader.readOrder(
      requests,
      record,
      robot,
      trade.coordinator,
      times: readAfter,
    );
    if (read case Ok(value: final result)) {
      if (TradeAnswer.ofRead(result) case final answer?) {
        await keep(answer, request: readAfter, keepsTime: true);
      }
    }
    return Ok(switch (sent) {
      Ok(value: Ok()) => PayoutGiven(
        current.record,
        current.seen,
        recordProblem: problem,
      ),
      Ok(value: Err(failure: OrderActionRefused(:final cause))) =>
        PayoutNotTaken(
          current.record,
          current.seen,
          cause: cause,
          recordProblem: problem,
        ),
      Ok(value: Err(failure: OrderActionOutcomeUnknown())) =>
        PayoutOutcomeUnknown(
          current.record,
          current.seen,
          recordProblem: problem,
        ),
      // Busy every time, or the robot released: the payout never reached the coordinator.
      Err(:final failure) => PayoutNotTaken(
        current.record,
        current.seen,
        cause: failure,
        recordProblem: problem,
      ),
    });
  }

  /// Whether the transport answered the payout busy: nothing reached the coordinator.
  static bool _answeredBusy(Result<PayoutOutcome, OrderActionFailure> answer) =>
      switch (answer) {
        Err(failure: OrderActionRefused(cause: CoordinatorTransportBusy())) =>
          true,
        _ => false,
      };
}
