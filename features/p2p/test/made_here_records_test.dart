import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/trade_trail_repository.dart';
import 'package:p2p/src/domain/trade/active_trade.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_storable.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/usecases/trade/trade_reader.dart';
import 'package:p2p/src/testing/bolt11_test_invoice.dart';
import 'package:primitives/primitives.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/maker_orders.dart';
import 'support/trade_harness.dart';
import 'support/trade_orders.dart';

/// A trade made here, as schema 8 lets `confirmMake` write it and `watchActiveTrades` list it (#176), is never read by the use cases of a take as a take (#178): never opened from a taker's terms, read, confirmed or closed; the make use case opens it from its own terms (#179).
void main() {
  T valueOf<T>(Result<T, P2pFailure> result) => switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => fail('$failure'),
  };

  test(
    'a confirmed make, its first trail written, is listed and opened as unrestorable, and nothing is sent',
    () async {
      final harness = await TradeHarness.start();
      final reserved = valueOf(
        await harness.robots.robotForNewTrade(
          harness.network,
          coordinator('temple'),
        ),
      );
      final make = valueOf(
        await harness.records.recordPendingMake(
          reserved.reservation,
          role: TradeRole.buyer,
        ),
      );
      final terms = madeTerms(network: harness.network);
      expect(
        await harness.trails.recordMakerTerms(make, terms.side.maker.record),
        isA<Ok>(),
      );
      final record = valueOf(
        await harness.records.confirmMake(make, orderId: terms.orderId),
      );
      // The first trail, as the make use case is to write it from the first read (#179).
      final bond = makerBondInvoice(network: Bolt11Network.testnet);
      final first = TradeStatus.afterMake(
        await readAnswer(
          makerOrderJson(0, bond: bond),
          network: harness.network,
        ),
        terms: terms,
        now: tradeNow,
        reader: Bolt11Reader(Bolt11TestDecoder([bond])),
      );
      expect(first, isA<WaitingForMakerBond>());
      expect(
        valueOf(await harness.trails.storeTrail(record, first.trail.record)),
        isA<TrailStored>(),
      );
      final sent = harness.coordinator.requests.length;

      expect(
        await harness.reader.open(record),
        isA<TradeNotRestorable>().having(
          (opening) => opening.reason,
          'reason',
          isA<TradeRecordMalformed>(),
        ),
      );
      final listed = valueOf(await harness.list.execute(harness.network).first);
      expect(listed, hasLength(1));
      expect(listed.single.standing, isA<ActiveTradeUnrestorable>());
      final watched = harness.watchOf(record);
      await harness.settle();
      expect(watched.states.single, isA<TradeWatchUnrestorable>());
      await watched.subscription.cancel();

      // Nothing was sent, and the record is still open: neither confirmed again nor closed as a take not made.
      expect(harness.coordinator.requests.length, sent);
      final active = await harness.activeRecords();
      expect(active, [record]);
      expect(active.single.closedAt, isNull);
    },
  );
}
