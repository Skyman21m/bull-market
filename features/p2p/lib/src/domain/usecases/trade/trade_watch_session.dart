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
/// One subscription per trade ([TradeWatchRegistry]): a second one reads nothing ([TradeWatchAlreadyWatched]).
final class TradeWatchSession {
  final TradeReader _reader;
  final RobotRequestLimiter _limiter;
  final P2pWaits _waits;
  final TradeRecord _record;
  final Stream<TradeWatchSignal> _signals;
  final StreamController<TradeWatchState> _out;
  final TradeWatchRegistry _registry;
  bool _registered = false;

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
    if (!_registry.claim(_record.robot)) {
      _emit(TradeWatchAlreadyWatched(_record));
      await _finish();
      return;
    }
    _registered = true;
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
    _timer?.cancel();
    final trade = _trade;
    if (trade != null) await _readTrade(requests, trade);
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
    final step = await _reader.advance(trade, answer, at: at);
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

  void _release() {
    if (!_registered) return;
    _registered = false;
    _registry.release(_record.robot);
  }
}

/// The trades watched in this process, one subscription each (a lazy singleton of the composition, `P2pLocator.registerTrades`): a second subscription to a trade reads nothing, so that a trade is never read twice at once by two screens, nor its trail written from two sessions.
///
/// Refused rather than shared: the two screens would send opposite signals (shown, not shown), and a trade screen is shown once at a time.
final class TradeWatchRegistry {
  final Set<RobotSlot> _watched = {};

  /// Whether [robot]'s trade was free to watch, now watched.
  bool claim(RobotSlot robot) => _watched.add(robot);

  /// [robot]'s trade is no longer watched.
  void release(RobotSlot robot) => _watched.remove(robot);
}
