import 'dart:async';

import '../../p2p_waits.dart';
import '../../robot_request_limiter.dart';
import '../../trade/trade_watch.dart';
import '../../trade_record.dart';
import 'trade_reader.dart';
import 'trade_watch_session.dart';

/// Follows one active trade: its stored records restored, then its order read at the reference client's cadence while someone listens, each answer checked by the trade's state machine and kept (#87, design note § 3.8).
///
/// - The terms and the trail are restored from storage (`TradeTerms.restore`, `TradeTrail.restore`); a trade whose records are refused is emitted as [TradeWatchUnrestorable] and never resumed on a fresh trail, one that cannot be opened (no records, no key, a binding that refuses the coordinator) as [TradeWatchUnavailable], and the stream ends.
/// - The order is read through the robot's places in `RobotRequestLimiter` (a busy transport is tried again as the limiter says): at once when listened to, then the delay of `TradeCadence` after each read ended, five times slower after [TradeWatchSignal.offScreen], at once after [TradeWatchSignal.readNow] (or right after the read in flight): at most one read in flight for the subscription.
/// - After each read: `TradeStatus.from` over the last status; the trail stored only as `TradeTrailRepository.storeTrail` allows (a trail refused, as an earlier read ending late, is dropped and the stream emits from the stored trail); the record confirmed when the answer shows the robot as the taker, closed at a terminal status, and the stream ends there.
/// - A take whose answer was lost resolves here: its first read is on the trail written before the take (or `TradeTrail.forPendingTake` when the app was killed before it), and a pending take is closed only once a read shows the robot is not the taker after the time to lock the taker bond; a [TradeClosedFailure] from a later confirmation is emitted on every status, never dropped.
/// - Nothing runs in the background: the screen cancels the subscription when the app is hidden, and listens again on its return; when the subscription is cancelled no timer is left, no read starts, and a read in flight writes nothing when it ends.
///
/// Nothing here pays or acts on the order: reads only.
final class WatchTradeUsecase {
  final TradeReader _reader;
  final RobotRequestLimiter _limiter;
  final P2pWaits _waits;

  const WatchTradeUsecase(this._reader, this._limiter, this._waits);

  /// The states of the trade of [record], from its stored records then after each read, while listened to; [signals] carries what the screen says (shown or not, read now), [onScreen] whether it is shown at the start.
  Stream<TradeWatchState> execute(
    TradeRecord record, {
    Stream<TradeWatchSignal> signals = const Stream.empty(),
    bool onScreen = true,
  }) {
    late final TradeWatchSession session;
    final out = StreamController<TradeWatchState>(
      onListen: () => unawaited(session.start()),
      onCancel: () => session.stop(),
    );
    session = TradeWatchSession(
      _reader,
      _limiter,
      _waits,
      record,
      signals,
      out,
      onScreen: onScreen,
    );
    return out.stream;
  }
}
