import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../p2p_failure.dart';
import '../../robot_request_limiter.dart';
import '../../trade/trade_answer.dart';
import '../../trade/trade_pause.dart';
import '../../trade/trade_watch.dart';
import '../../trade_record.dart';
import 'pauses_in_flight.dart';
import 'trade_keyring.dart';
import 'trade_reader.dart';
import 'trade_take_locks.dart';

/// Pauses the public order of a trade made here, or makes its paused order public again, as the user tapped it (#184, design note `docs/design/phase-3-making-an-order.md` § 1.6, § 2.2, § 3.4): the pause button of `Prompts/PublicWait.tsx` at 1 and « Unpause Order » of `Prompts/Paused.tsx` at 2, one tap, no dialog, as the reference (`TradeBox/index.tsx:310-313`).
///
/// **The request has no direction**: the reference sends `{"action":"pause"}` for both buttons and the coordinator toggles 1 and 2 whatever the maker saw (`Logics.pause_unpause_public_order`, `api/logics.py:1758-1783`), so a request sent twice undoes itself, and a request sent after the order was paused or resumed elsewhere goes the other way. A paused order cannot be taken (`follow_invoices.py:243-261` finalizes a take only on a public order); a public one can, with the maker's bond at stake. So, in this order, each step only once the one before it succeeded:
/// 1. the status the user saw offers it ([PauseWanted.of]: a maker's public or paused order read at that very status, marked stored, this robot shown as the maker) and the trade was made here; what the user asked ([PauseWanted]) is taken from that status, never from the request; the trade is opened from its records ([TradeReader.open]) and the order seen is its own;
/// 2. one action of the order runs at a time in the process ([TradeTakeLocks], which the take, the cancel, the payout, the bond's payment and the chat step share): a second tap, another screen of the same trade, waits for the first to end and then reads the order the first left;
/// 3. the order is read again and kept ([TradeReader.readOrder], [TradeReader.advance]); the request is sent only if that read is marked stored and still shows the status the user saw ([PauseStatusMoved] otherwise, with the status now, nothing sent), so that a pause never leaves for an order already paused, paused elsewhere, taken or expired;
/// 4. the request is sent once through the robot's places in [RobotRequestLimiter] (a busy transport, which sends nothing, is tried again as the limiter says), and never again: an answer lost, unreadable or late is an outcome unknown, resolved by the reads that follow, never by a second request;
/// 5. the order is read again and kept (the answer, accepted or refused, only says what the coordinator did with the request); the status then shown is compared with what the user asked ([PauseWanted.reachedAt]): [PauseDone] only when a status marked stored shows the order where the user asked, never because the request was accepted; [PauseNotReached] when the coordinator accepted it and the order is read elsewhere (toggled twice or the other way, taken, expired, or a coordinator that answers falsely), so that the screen says when the order stayed or became public again; [PauseNotDone] when it was refused or never left; [PauseOutcomeUnknown] otherwise.
/// The request is signed by the robot's key, leased from [TradeKeyring] for it ([TradeKeyring.signWith], GHSA-22q8-9ghc-jg3h); a key that cannot be had sends nothing, and is told as a pause not done.
/// While it runs, the pause is known to [PausesInFlight] ([running]), so that a screen of the trade opened meanwhile shows it running and gives its outcome rather than a second tap.
/// Nothing here pays or moves the wallet's funds; nothing is printed or logged.
final class PauseOrderUsecase {
  final CoordinatorClient _client;
  final TradeReader _reader;
  final RobotRequestLimiter _limiter;
  final TradeTakeLocks _locks;
  final PausesInFlight _inFlight;
  final TradeKeyring _keyring;

  const PauseOrderUsecase(
    this._client,
    this._reader,
    this._limiter,
    this._locks,
    this._inFlight,
    this._keyring,
  );

  /// The pause of [record]'s order this process is sending now, `null` when none runs.
  PauseInFlight? running(TradeRecord record) => _inFlight.running(record);

  /// What stays uncertain for [record]'s order after a pause or an unpause whose outcome was unknown, once [seen] is taken into account when given ([PauseUncertainty]); `null` when nothing does.
  PauseUncertainty? uncertainty(TradeRecord record, [TradeSeen? seen]) =>
      seen == null
      ? _inFlight.uncertainty(record)
      : _inFlight.observe(record, seen);

  /// Pauses or unpauses the order of [record] as [seen] showed it, the status the screen showed when the user tapped.
  ///
  /// [Err]: nothing was sent ([PauseRefusal]). [Ok]: the request was sent, or may have left; [PauseOutcome] says what it and the read after it gave.
  Future<Result<PauseOutcome, PauseRefusal>> execute(
    TradeRecord record,
    TradeSeen seen,
  ) async {
    final shown = seen.order;
    final wanted = PauseWanted.of(seen);
    if (record.origin != TradeOrigin.madeHere ||
        shown == null ||
        wanted == null) {
      return const Err(PauseNotOffered());
    }
    return _inFlight.run(record, wanted, () async {
      try {
        final result = await _open(record, shown, wanted);
        // An outcome unknown leaves the order uncertain for every screen of it, until reads settle it.
        if (result case Ok(value: final PauseOutcomeUnknown unknown)) {
          _inFlight.unknown(
            record,
            unknown.requestLeftAt ?? _reader.now(),
            unknown.seen,
          );
        }
        return result;
      } on Object {
        // A bug below: the request may have left; uncertain, from now.
        _inFlight.unknown(record, _reader.now(), null);
        rethrow;
      }
    });
  }

  Future<Result<PauseOutcome, PauseRefusal>> _open(
    TradeRecord record,
    CoordinatorOrder shown,
    PauseWanted wanted,
  ) async {
    final OpenTrade trade;
    switch (await _reader.open(record)) {
      case TradeOpened(trade: final opened):
        trade = opened;
      case TradeNotRestorable(:final reason):
        return Err(PauseTradeUnrestorable(reason));
      case TradeNotOpened(:final failure):
        return Err(PauseTradeUnavailable(failure));
      case TradeTakeNeverSent():
        return const Err(PauseOfAnotherTrade());
    }
    final terms = trade.terms;
    if (shown.id != terms.orderId ||
        shown.coordinator != terms.coordinator ||
        shown.network != terms.network) {
      return const Err(PauseOfAnotherTrade());
    }
    return _locks.run(
      record.network,
      trade.coordinator,
      record.orderId,
      // An action of the trade: the watch sends no read while it runs (#141).
      () => _reader.duringAction(record, () async {
        final requests = _limiter.open(trade.robot.identity.sessionKey);
        try {
          return await _send(requests, trade, wanted);
        } finally {
          requests.close();
        }
      }),
    );
  }

  Future<Result<PauseOutcome, PauseRefusal>> _send(
    RobotRequests requests,
    OpenTrade trade,
    PauseWanted wanted,
  ) async {
    final record = trade.record;
    final robot = trade.robot;
    var current = trade;
    P2pFailure? problem;

    // The order as it is now, kept: the request leaves only if this read still shows the status the user saw.
    // Superseded (a read of the watch that left before the action began answered after it left), it is read once more: no read of the watch leaves while the action runs, so the second read cannot be superseded; if it is, nothing is sent (#141).
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
          return Err(PauseReadFailed(cause: failure));
        case Ok(value: final result):
          switch (TradeAnswer.ofRead(result)) {
            case final read?:
              answer = read;
            case null:
              return Err(
                PauseReadFailed(
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
    final fresh = current.seen;
    if (!step.stored) {
      return Err(
        PauseReadFailed(
          cause: step.recordProblem,
          seen: fresh,
          record: current.record,
        ),
      );
    }
    // Paused or resumed elsewhere, taken, expired, cancelled: the toggle would not do what the user asked, so nothing is sent.
    final lastRead = fresh.order;
    if (lastRead == null || PauseWanted.of(fresh) != wanted) {
      return Err(PauseStatusMoved(fresh, record: current.record));
    }

    // Sent once: never again by this use case, whatever the outcome.
    final actionTimes = _reader.request();
    final sent = await TradeKeyring.signWith(
      _keyring.lease(trade),
      (key) => requests.send(
        record.network,
        trade.coordinator,
        () => _reader.timed(
          actionTimes,
          () => _client.pauseOrder(
            identity: robot.identity,
            key: key,
            lastRead: lastRead,
          ),
        ),
        isBusy: _answeredBusy,
      ),
    );

    // A read after it. The answer itself is the coordinator's read of the order once toggled (`api/views.py:695`), checked by the package (`parseTradeActionAnswer`), but it is not kept as the status shown: only the read sent after the request is. What this gains: an answer lost on the way back is resolved at once by that read (done when it shows the order where the user asked), and a request with no direction is said done only from a read, never from its own answer. It does not catch a coordinator that lies: the read comes from the same coordinator (functional review of #184, R2).
    final readAfter = _reader.request();
    final read = await _reader.readOrder(
      requests,
      record,
      robot,
      trade.coordinator,
      times: readAfter,
    );
    // Whether the read after was stored: what it shows is then where the order is after the request; otherwise the status shown is still the read before it.
    var readAfterStored = false;
    if (read case Ok(value: final result)) {
      if (TradeAnswer.ofRead(result) case final after?) {
        final kept = await _reader.advance(
          current,
          after,
          at: _reader.now(),
          request: readAfter,
          keepsTime: true,
        );
        current = kept.trade;
        problem ??= kept.recordProblem;
        readAfterStored = kept.stored;
      }
    }
    final now = current.seen;
    // Where the user asked, by the read after, stored: done, whatever the answer said (an answer lost whose request landed).
    if (readAfterStored && wanted.reachedAt(now)) {
      return Ok(PauseDone(wanted, current.record, now, recordProblem: problem));
    }
    return Ok(switch (sent) {
      // Accepted, and the read after shows the order elsewhere: the screen says where; without a read after stored, the outcome is unknown.
      Ok(value: Ok()) when readAfterStored => PauseNotReached(
        wanted,
        current.record,
        now,
        recordProblem: problem,
      ),
      Ok(value: Ok()) => PauseOutcomeUnknown(
        wanted,
        current.record,
        now,
        recordProblem: problem,
        requestLeftAt: actionTimes.leftAt,
      ),
      Ok(value: Err(failure: OrderActionRefused(:final cause))) => PauseNotDone(
        wanted,
        current.record,
        now,
        cause: cause,
        recordProblem: problem,
      ),
      Ok(value: Err(failure: OrderActionOutcomeUnknown())) =>
        PauseOutcomeUnknown(
          wanted,
          current.record,
          now,
          recordProblem: problem,
          requestLeftAt: actionTimes.leftAt,
        ),
      // Busy every time, or the robot released: the request never reached the coordinator.
      Err(:final failure) => PauseNotDone(
        wanted,
        current.record,
        now,
        cause: failure,
        recordProblem: problem,
      ),
    });
  }

  /// Whether the transport answered the request busy: nothing reached the coordinator.
  static bool _answeredBusy(
    Result<TradeActionOutcome, OrderActionFailure> answer,
  ) => switch (answer) {
    Err(failure: OrderActionRefused(cause: CoordinatorTransportBusy())) => true,
    _ => false,
  };
}
