import 'trade_edges.dart';

/// How often the order of an active trade is read, by where the trade stands: the reference client's cadence (#87, design note § 3.8; a maker's statuses, #178).
///
/// The reference, at commit ff1998c, keeps a delay per status (`statusToDelay`, `frontend/src/contexts/GarageContext.tsx:38-60`), multiplies it by 5 when the order's page is not the one shown (`:135`), and looks every 5 s whether that delay has passed since the last read ended (`:136`, `:160-169`, `defaultDelay` 5,000 ms): so a read starts at the first tick of 5 s at or after the delay.
/// It stops reading an order that ended: one shown at 4, 5, 12, 14, 17 or 18, or answered with an error (`frontend/src/models/Slot.model.ts:216-223`), so the delays it lists for 14, 17 and 18 are never waited.
/// Here the delay is the reference's, multiplied by 5 off-screen, then rounded up to the next multiple of 5 s, as the reference's tick makes it; a terminal position is never read again.
abstract final class TradeCadence {
  /// The reference's tick.
  static const Duration tick = Duration(seconds: 5);

  /// How much slower the reads are while the trade's screen is not the one shown, the app being in the foreground.
  static const int offScreenFactor = 5;

  /// The reference's delay for the status of [position], before the factor and the tick, or `null` for a position that is never read again.
  ///
  /// The take's start and error 1044 during the pre-take are read as the pre-take is (3, 3 s): the first is the take whose answer is awaited, the second a pre-take that may come back (the reference stops at that error; this app reads on until the pre-take is certainly gone, `TradeStatus.from`). A maker's start, the first read of the order it made, is read as the bond it gives is (0, 3 s).
  /// A maker's own statuses have the reference's delays (design note `docs/design/phase-3-making-an-order.md` § 3.8): 3 s at 0, 35 s at 1, 180 s at 2.
  static Duration? referenceDelay(TradePosition position) => switch (position) {
    TradePosition.start ||
    TradePosition.makerBondStep ||
    TradePosition.bondStep ||
    TradePosition.preTakeUnavailable => const Duration(seconds: 3),
    TradePosition.public => const Duration(seconds: 35),
    TradePosition.paused => const Duration(seconds: 180),
    TradePosition.waitingForBoth ||
    TradePosition.waitingForEscrow ||
    TradePosition.waitingForPayout => const Duration(seconds: 8),
    TradePosition.chatting ||
    TradePosition.fiatSent ||
    TradePosition.sendingSats => const Duration(seconds: 10),
    TradePosition.inDispute => const Duration(seconds: 100),
    TradePosition.routingFailed => const Duration(seconds: 30),
    TradePosition.waitingDisputeResolution => const Duration(seconds: 300),
    TradePosition.succeeded ||
    TradePosition.makerLostDispute ||
    TradePosition.takerLostDispute ||
    TradePosition.expired ||
    TradePosition.cancelled ||
    TradePosition.publicAgain ||
    TradePosition.notAvailable => null,
  };

  /// How long after a read ends the next one starts, at [position], with the trade's screen shown or not; `null` when the trade is not read again.
  static Duration? delayAfter(
    TradePosition position, {
    required bool onScreen,
  }) {
    final base = referenceDelay(position);
    if (base == null) return null;
    final delay = onScreen ? base : base * offScreenFactor;
    final ticks =
        (delay.inMicroseconds + tick.inMicroseconds - 1) ~/ tick.inMicroseconds;
    return tick * ticks;
  }
}
