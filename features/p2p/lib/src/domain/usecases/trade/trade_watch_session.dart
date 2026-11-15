import 'dart:async';

import 'package:primitives/primitives.dart';

import '../../p2p_failure.dart';
import '../../p2p_waits.dart';
import '../../robot_binding.dart';
import '../../robot_request_limiter.dart';
import '../../trade/trade_answer.dart';
import '../../trade/trade_cadence.dart';
import '../../trade/trade_edges.dart';
import '../../trade/trade_watch.dart';
import '../../trade_record.dart';
import 'trade_reader.dart';

/// One subscription to the watch of one trade (`WatchTradeUsecase`): its reads, their cadence and what each emits.
///
/// At most one read is in flight; the next one starts the cadence's delay after it ended ([TradeCadence]), at once when the screen asks, and none once the trade is at a terminal status.
/// Nothing runs once the subscription is cancelled: no timer, no new read; a read whose answer comes after the cancel is dropped, and the writes of an answer already being kept finish (`TradeTrailRepository.storeTrail` keeps the stored trail correct whatever their order).
/// One subscription reads a trade at a time ([TradeWatchRegistry]): the newest takes it over, the earlier one ends with [TradeWatchSuperseded], and the newest reads only once the earlier one's read in flight has ended, so that a trade never has two reads in flight.
final class TradeWatchSession {
  final TradeReader _reader;
  final RobotRequestLimiter _limiter;
  final P2pWaits _waits;
  final TradeRecord _record;
  final Stream<TradeWatchSignal> _signals;
  final StreamController<TradeWatchState> _out;
  final TradeWatchRegistry _registry;

  /// Completes when the read in flight, and the writes of its answer, have ended.
  Completer<void>? _inFlight;

  bool _onScreen;
  OpenTrade? _trade;
  RobotRequests? _requests;
  StreamSubscription<TradeWatchSignal>? _signalSubscription;
  Timer? _timer;
  bool _reading = false;
  bool _readAgain = false;
  bool _stopped = false;
  DateTime? _lastReadEnded;
  int _failedReads = 0;
  Failure? _lastReadFailure;

  /// A [TradeClosedFailure] seen once stays on every later status: the record was closed while the coordinator shows this robot as the taker.
  P2pFailure? _closedButTaken;

  TradeWatchSession(
    this._reader,
    this._limiter,
    this._waits,
    this._record,
    this._signals,
    this._out,
    this._registry, {
    required this._onScreen,
  });

  /// Opens the trade from its stored records, emits what they give, and reads at once when the trade goes on.
  Future<void> start() async {
    // The newest subscription takes the trade over, once the earlier one's read in flight has ended.
    final previous = _registry.takeOver(_record.robot, this);
    if (previous != null) await previous.supersede();
    if (_stopped) return;
    _signalSubscription = _signals.listen(_onSignal);
    final opening = await _reader.open(_record);
    if (_stopped) return;
    switch (opening) {
      case TradeNotRestorable(:final reason):
        _emit(TradeWatchUnrestorable(_record, reason));
        await _finish();
      case TradeNotOpened(:final failure):
        _emit(TradeWatchUnavailable(_record, failure));
        await _finish();
      case TradeTakeNeverSent():
        // Its request never left: closed at once, with no read.
        final closed = await _reader.closeNeverSent(_record);
        if (_stopped) return;
        _emit(switch (closed) {
          Ok(:final value) => TradeWatchTakeNeverSent(value, closed: true),
          Err(:final failure) => TradeWatchTakeNeverSent(
            _record,
            closed: false,
            recordProblem: failure,
          ),
        });
        await _finish();
      case TradeOpened(:final trade):
        _trade = trade;
        if (trade.seen.status.isTerminal) {
          // The app was killed between the trail of an end and the close of its record.
          var record = trade.record;
          P2pFailure? problem;
          if (record.isActive) {
            switch (await _reader.closeAtEnd(record)) {
              case Ok(:final value):
                record = value;
              case Err(:final failure):
                problem = failure;
            }
          }
          if (_stopped) return;
          _emit(
            TradeWatchStatus(
              record,
              trade.seen,
              recordProblem: problem,
              takePending: record.isPendingTake,
            ),
          );
          await _finish();
          return;
        }
        _requests = _limiter.open(trade.robot.identity.sessionKey);
        _emitStatus(trade, null);
        unawaited(_read());
    }
  }

  /// Stops this subscription because a newer one took its trade over: its stream says so ([TradeWatchSuperseded]) and ends; a read in flight is dropped as for a cancel.
  ///
  /// Completes once its read in flight, and the writes of its answer, have ended.
  Future<void> supersede() {
    if (!_stopped) {
      _emit(TradeWatchSuperseded(_record));
      _stopped = true;
      _timer?.cancel();
      _requests?.close();
      unawaited(_signalSubscription?.cancel());
      if (!_out.isClosed) unawaited(_out.close());
    }
    return _inFlight?.future ?? Future.value();
  }

  /// Stops everything: the subscription was cancelled.
  Future<void> stop() async {
    _stopped = true;
    _release();
    _timer?.cancel();
    _requests?.close();
    await _signalSubscription?.cancel();
  }

  void _onSignal(TradeWatchSignal signal) {
    if (_stopped) return;
    switch (signal) {
      case TradeWatchSignal.readNow:
        unawaited(_read());
      case TradeWatchSignal.onScreen || TradeWatchSignal.offScreen:
        final onScreen = signal == TradeWatchSignal.onScreen;
        if (onScreen == _onScreen) return;
        _onScreen = onScreen;
        // Waiting for the next read: it is due the new delay after the last one ended.
        if (!_reading && (_timer?.isActive ?? false)) _schedule();
    }
  }

  /// One read, unless one is in flight: then another right after it.
  Future<void> _read() async {
    final requests = _requests;
    if (_stopped || requests == null) return;
    if (_reading) {
      _readAgain = true;
      return;
    }
    _reading = true;
    final inFlight = _inFlight = Completer<void>();
    _timer?.cancel();
    final trade = _trade;
    try {
      if (trade != null) await _readTrade(requests, trade);
    } finally {
      _reading = false;
      inFlight.complete();
      if (identical(_inFlight, inFlight)) _inFlight = null;
    }
    if (_stopped || _out.isClosed) return;
    if (_readAgain) {
      _readAgain = false;
      unawaited(_read());
      return;
    }
    _schedule();
  }

  Future<void> _readTrade(RobotRequests requests, OpenTrade trade) async {
    // When the read leaves: what it shows is no older than that (`TradeSeen.requestedAt`), and it never replaces the status of a request that left after it (#141).
    final requestedAt = _reader.requestLeaves();
    final read = await _reader.readOrder(
      requests,
      trade.record,
      trade.robot,
      trade.coordinator,
    );
    // Cancelled while the read was in flight: its answer is dropped.
    if (_stopped) return;
    final at = _reader.now();
    _lastReadEnded = at;
    final TradeAnswer answer;
    switch (read) {
      case Err(:final failure):
        _failed(trade, failure);
        return;
      case Ok(value: final result):
        switch (TradeAnswer.ofRead(result)) {
          case final told?:
            answer = told;
          case null:
            // An answer that says nothing of the trade keeps the last status.
            _failed(trade, switch (result) {
              Err(:final failure) => failure,
              Ok() => null,
            });
            return;
        }
    }
    final step = await _reader.advance(
      trade,
      answer,
      at: at,
      sentAt: requestedAt,
      keepsSentAt: true,
    );
    if (_stopped) return;
    _failedReads = 0;
    _lastReadFailure = null;
    final next = step.trade;
    _trade = next;
    if (step.recordProblem case final TradeClosedFailure closed) {
      _closedButTaken = closed;
    }
    if (step.takeNotMade) {
      _emit(
        TradeWatchTakeNotMade(
          next.record,
          closed: next.record.closedAt != null,
          recordProblem: step.recordProblem,
        ),
      );
      await _finish();
      return;
    }
    _emitStatus(next, step.recordProblem);
    if (next.seen.status.isTerminal) await _finish();
  }

  void _failed(OpenTrade trade, Failure? failure) {
    _failedReads++;
    _lastReadFailure = failure;
    _emitStatus(trade, null);
  }

  /// The next read, the cadence's delay after the last one ended; none at a terminal position.
  void _schedule() {
    _timer?.cancel();
    final position = _trade?.seen.status.position ?? TradePosition.start;
    final delay = TradeCadence.delayAfter(position, onScreen: _onScreen);
    if (delay == null) return;
    final ended = _lastReadEnded;
    final elapsed = ended == null
        ? Duration.zero
        : _reader.now().difference(ended);
    final left = delay - elapsed;
    if (left <= Duration.zero) {
      unawaited(_read());
      return;
    }
    _timer = _waits.start(left, () => unawaited(_read()));
  }

  void _emitStatus(OpenTrade trade, P2pFailure? problem) => _emit(
    TradeWatchStatus(
      trade.record,
      trade.seen,
      failedReads: _failedReads,
      lastReadFailure: _failedReads == 0 ? null : _lastReadFailure,
      recordProblem: problem ?? _closedButTaken,
      takePending: trade.record.isPendingTake,
    ),
  );

  void _emit(TradeWatchState state) {
    if (_stopped || _out.isClosed) return;
    _out.add(state);
  }

  /// The trade is at an end, or cannot be read: the stream ends.
  Future<void> _finish() async {
    _release();
    _timer?.cancel();
    _requests?.close();
    _requests = null;
    await _signalSubscription?.cancel();
    if (!_out.isClosed) await _out.close();
  }

  void _release() => _registry.release(_record.robot, this);
}

/// The subscriptions reading each trade in this process, one per trade (a lazy singleton of the composition, `P2pLocator.registerTrades`): the newest takes a trade over, the earlier one is superseded.
///
/// The newest rather than the first: Flutter builds the route of a screen before it disposes the previous one, so a screen that opens a trade while the previous screen's subscription is alive must read it, at once, during a bond's 150 to 200 s; the previous one is going away (review of #117).
final class TradeWatchRegistry {
  final Map<RobotSlot, TradeWatchSession> _watched = {};

  /// Makes [session] the one reading [robot]'s trade, and gives the session it replaces, if any, for it to be superseded.
  TradeWatchSession? takeOver(RobotSlot robot, TradeWatchSession session) {
    final previous = _watched[robot];
    _watched[robot] = session;
    return identical(previous, session) ? null : previous;
  }

  /// [session] no longer reads [robot]'s trade, if it still was the one.
  void release(RobotSlot robot, TradeWatchSession session) {
    if (identical(_watched[robot], session)) _watched.remove(robot);
  }

  /// Whether a subscription reads [robot]'s trade.
  bool isWatched(RobotSlot robot) => _watched.containsKey(robot);
}
