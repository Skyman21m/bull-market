import 'dart:async';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../network_garage_key.dart';
import '../../p2p_failure.dart';
import '../../p2p_waits.dart';
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
/// Nothing runs once the subscription is cancelled: no timer, no new read, and a read in flight at the cancel writes nothing when it ends (its answer is dropped; the next subscription reads again).
final class TradeWatchSession {
  final TradeReader _reader;
  final RobotRequestLimiter _limiter;
  final P2pWaits _waits;
  final TradeRecord _record;
  final Stream<TradeWatchSignal> _signals;
  final StreamController<TradeWatchState> _out;

  bool _onScreen;
  OpenTrade? _trade;
  (NetworkRobot, Coordinator)? _neverSent;
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
    this._out, {
    required this._onScreen,
  });

  /// Opens the trade from its stored records, emits what they give, and reads at once when the trade goes on.
  Future<void> start() async {
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
      case TradeTakeNeverSent(:final robot, :final coordinator):
        _neverSent = (robot, coordinator);
        _requests = _limiter.open(robot.identity.sessionKey);
        _emit(TradeWatchTakeNeverSent(_record, closed: false));
        unawaited(_read());
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

  /// Stops everything: the subscription was cancelled.
  Future<void> stop() async {
    _stopped = true;
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
    _timer?.cancel();
    final trade = _trade;
    final neverSent = _neverSent;
    if (trade != null) {
      await _readTrade(requests, trade);
    } else if (neverSent != null) {
      await _readNeverSent(requests, neverSent.$1, neverSent.$2);
    }
    _reading = false;
    if (_stopped || _out.isClosed) return;
    if (_readAgain) {
      _readAgain = false;
      unawaited(_read());
      return;
    }
    _schedule();
  }

  Future<void> _readTrade(RobotRequests requests, OpenTrade trade) async {
    final read = await _reader.readOrder(
      requests,
      trade.record,
      trade.robot,
      trade.coordinator,
    );
    // Cancelled while the read was in flight: its answer is dropped, nothing is written.
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
    final step = await _reader.advance(trade, answer, at: at);
    if (_stopped) return;
    _failedReads = 0;
    _lastReadFailure = null;
    final next = step.trade;
    _trade = next;
    if (step.recordProblem case final TradeClosedFailure closed) {
      _closedButTaken = closed;
    }
    _emitStatus(next, step.recordProblem);
    if (next.seen.status.isTerminal) await _finish();
  }

  Future<void> _readNeverSent(
    RobotRequests requests,
    NetworkRobot robot,
    Coordinator coordinator,
  ) async {
    final read = await _reader.readOrder(requests, _record, robot, coordinator);
    if (_stopped) return;
    final at = _reader.now();
    _lastReadEnded = at;
    if (read case Ok(value: final result)) {
      switch (await _reader.closeNeverSent(_record, result, at: at)) {
        case Ok(:final value):
          if (_stopped) return;
          _emit(TradeWatchTakeNeverSent(value, closed: true));
          await _finish();
        case Err(:final failure):
          _emit(
            TradeWatchTakeNeverSent(
              _record,
              closed: false,
              recordProblem: failure,
            ),
          );
        case null:
          break;
      }
    }
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
    _timer?.cancel();
    _requests?.close();
    _requests = null;
    await _signalSubscription?.cancel();
    if (!_out.isClosed) await _out.close();
  }
}
