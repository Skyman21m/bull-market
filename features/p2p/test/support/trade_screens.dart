import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_answer.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/testing.dart' show Bolt11TestDecoder, Bolt11TestInvoice;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'trade_harness.dart' show tradeKey;
import 'trade_orders.dart';

/// The statuses of the trade screens' tests, each made by the trade's state machine from an answer the reference coordinator gives (`trade_orders.dart`), never by hand: the panels are drawn from what the screen will really get.
///
/// Every trade is the book's order 42 on temple, on mainnet, taken as buyer, read at [tradeNow].
final class TradeScreenStatuses {
  final TradeTerms terms;
  final Bolt11TestInvoice invoice;
  final Bolt11Reader reader;

  /// The bond the order says at 3 (`bond_satoshis`), the invoice's amount unless given.
  final int? bondSatoshis;

  TradeScreenStatuses._(
    this.terms,
    this.invoice,
    this.reader,
    this.bondSatoshis,
  );

  /// The statuses of a take whose bond invoice is [invoice] (the book's bond on mainnet by default); with [decodable] `false`, the decoder cannot read it.
  static Future<TradeScreenStatuses> make({
    Bolt11TestInvoice? invoice,
    bool decodable = true,
    int? bondSatoshis,
  }) async {
    final bond = invoice ?? bondInvoice();
    return TradeScreenStatuses._(
      await tradeTerms(),
      bond,
      Bolt11Reader(Bolt11TestDecoder([if (decodable) bond])),
      bondSatoshis,
    );
  }

  /// The record of the trade, as the repository would give it.
  static final TradeRecord record = TradeRecord(
    robot: RobotSlot(RobosatsNetwork.mainnet, switch (GarageKeyFingerprint.of(
      tradeKey,
    )) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    }, 0),
    coordinatorAlias: 'temple',
    coordinatorOnion: switch (Federation.robosats.byAlias('temple')) {
      final temple? => temple.mainnet.onion ?? '',
      null => throw StateError('no temple'),
    },
    orderId: tradeOrderId,
    role: TradeRole.buyer,
    origin: TradeOrigin.takenHere,
    takenAt: tradeNow,
    confirmedAt: tradeNow,
    closedAt: null,
  );

  /// 3: the take's own answer, the pre-take with its bond.
  Future<TradeSeen> bondStep() async {
    final started = await takeStarted(
      orderJson(3, bond: invoice, changes: {'bond_satoshis': ?bondSatoshis}),
    );
    return TradeSeen(
      TradeStatus.afterTake(
        started,
        terms: terms,
        now: tradeNow,
        reader: reader,
      ),
      order: started.order,
      stored: true,
    );
  }

  /// [previous] after the order read as [json], [after] the take.
  Future<TradeSeen> read(
    TradeSeen previous,
    Map<String, Object?> json, {
    Duration after = const Duration(seconds: 30),
  }) async {
    final order = await readOrder(json);
    return TradeSeen(
      TradeStatus.from(
        previous: previous.status,
        answer: TradeOrderRead(order),
        terms: terms,
        now: tradeNow.add(after),
        reader: reader,
      ),
      order: order,
      stored: true,
    );
  }

  /// [previous] after the order read as [json] when the state machine refuses that answer as a whole (a return to an earlier status, another role or order): the last status stays, with its warning, from no order, as `TradeReader` keeps it.
  Future<TradeSeen> refusedRead(
    TradeSeen previous,
    Map<String, Object?> json, {
    Duration after = const Duration(seconds: 30),
  }) async {
    final seen = await read(previous, json, after: after);
    return TradeSeen(seen.status, order: null, stored: true);
  }

  /// [previous] after a refusal (1043 or 1044) that comes from no order.
  TradeSeen refused(
    TradeSeen previous,
    TradeAnswer answer, {
    Duration after = const Duration(seconds: 30),
  }) => TradeSeen(
    TradeStatus.from(
      previous: previous.status,
      answer: answer,
      terms: terms,
      now: tradeNow.add(after),
      reader: reader,
    ),
    order: null,
    stored: true,
  );

  /// 6, the bond locked, as the buyer.
  Future<TradeSeen> waitingForBoth() async =>
      read(await bondStep(), orderJson(6));

  /// 7, the buyer's payout in.
  Future<TradeSeen> waitingForEscrow() async =>
      read(await waitingForBoth(), orderJson(7));

  /// 8, the escrow locked, the buyer's payout awaited.
  Future<TradeSeen> waitingForPayout() async =>
      read(await waitingForBoth(), orderJson(8));

  /// 9, the chat.
  Future<TradeSeen> chatting() async =>
      read(await waitingForPayout(), orderJson(9));

  /// 10, « fiat sent » recorded (#95).
  Future<TradeSeen> fiatSent() async => read(await chatting(), orderJson(10));

  /// 13, the buyer being paid (#95).
  Future<TradeSeen> sendingSats() async =>
      read(await fiatSent(), orderJson(13));

  /// 14, the trade finished (#95).
  Future<TradeSeen> succeeded() async =>
      read(await sendingSats(), orderJson(14));

  /// 5, expired for [reason] (the reference's `expiry_reason`).
  Future<TradeSeen> expired({int reason = 4}) async => read(
    await waitingForBoth(),
    orderJson(5, changes: {'expiry_reason': reason}),
  );

  /// 1043 after the pre-take, which [bondLost] moves to after the bond's lock.
  Future<TradeSeen> cancelled({bool bondLost = false}) async => refused(
    bondLost ? await waitingForBoth() : await bondStep(),
    const TradeOrderCancelled(),
  );

  /// 1044 during the pre-take: the order paused, or another bond locked first, not yet certain.
  Future<TradeSeen> preTakeUnavailable() async =>
      refused(await bondStep(), const TradeOrderNotAvailable());

  /// 1044 once the pre-take is certainly over: taken by another robot.
  Future<TradeSeen> takenByAnother() async => refused(
    await bondStep(),
    const TradeOrderNotAvailable(),
    after: const Duration(hours: 1),
  );

  /// The order public again after the pre-take, this robot no longer its taker.
  Future<TradeSeen> publicAgain() async => read(await bondStep(), orderJson(1));

  /// The order public again after the bond locked: the bond is lost.
  Future<TradeSeen> bondForfeited() async =>
      read(await waitingForBoth(), orderJson(1));

  /// A watch state of [seen].
  static TradeWatchStatus watched(
    TradeSeen seen, {
    int failedReads = 0,
    P2pFailure? recordProblem,
    bool takePending = false,
  }) => TradeWatchStatus(
    record,
    seen,
    failedReads: failedReads,
    recordProblem: recordProblem,
    takePending: takePending,
  );
}

/// Before the first read of a take whose answer was lost.
extension PendingTake on TradeScreenStatuses {
  TradeSeen pending() => TradeSeen(
    TradeStatus.beforeFirstRead(TradeTrail.forPendingTake(terms, tradeNow)),
    order: null,
  );
}
