import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_answer.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_storable.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:p2p/src/domain/trade/trade_tolerances.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/trade/wallet_payment.dart';
import 'package:p2p/src/testing/bolt11_test_invoice.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/trade_orders.dart';

/// The stored forms of a trade (second review of #106): which trail may replace the stored one, the binding of a trail to its trade, a recovered trail through a restart, an end through a restart, the take's own answer as the only start, and the refusals of a restore.
void main() {
  late TradeTerms buyer;
  late TradeTerms seller;
  late Bolt11TestDecoder decoder;
  late Bolt11Reader reader;

  setUpAll(() async {
    buyer = await tradeTerms();
    seller = await tradeTerms(role: TradeRole.seller);
  });

  setUp(() {
    decoder = Bolt11TestDecoder();
    reader = Bolt11Reader(decoder);
  });

  Future<TradeAnswer> answer(
    Map<String, Object?> json, {
    List<Bolt11TestInvoice> invoices = const [],
  }) async {
    invoices.forEach(decoder.add);
    return readAnswer(json);
  }

  TradeStatus next(
    TradeStatus previous,
    TradeAnswer answer, {
    TradeTerms? terms,
    DateTime? now,
  }) => TradeStatus.from(
    previous: previous,
    answer: answer,
    terms: terms ?? buyer,
    now: now ?? tradeNow,
    reader: reader,
  );

  Future<TradeStatus> taken({
    Bolt11TestInvoice? bond,
    TradeTerms? terms,
  }) async {
    final invoice = bond ?? bondInvoice();
    decoder.add(invoice);
    return TradeStatus.afterTake(
      await takeStarted(
        orderJson(3, bond: invoice, role: (terms ?? buyer).role),
      ),
      terms: terms ?? buyer,
      now: tradeNow,
      reader: reader,
    );
  }

  TradeStatus restored(
    TradeStatus status, {
    required TradeTerms terms,
    DateTime? now,
  }) => switch (TradeTrail.restore(
    status.trail.record,
    terms: terms,
    now: now ?? tradeNow,
  )) {
    Ok(:final value) => TradeStatus.beforeFirstRead(value),
    Err(:final failure) => fail('$failure'),
  };

  bool offered(TradeStatus status, InvoiceStep step) =>
      walletPaymentFor(
            accepted: Sats.fromInt(1 << 40),
            status: status,
            step: step,
            now: tradeNow,
          )
          is WalletPaymentOffered;

  TradeTrailRecord edited(
    TradeTrailRecord r, {
    int? version,
    String? network,
    String? alias,
    int? orderId,
    String? role,
    String? position,
    int? readAtMicros,
    String? bondHash,
    bool clearBondHash = false,
    String? escrowHash,
    bool clearEscrowHash = false,
    int? bondStepSeenAtMicros,
    bool clearBondStepSeenAt = false,
    bool clearBondStepDeadline = false,
    bool? breached,
    bool? historyUnknown,
  }) => TradeTrailRecord(
    version: version ?? r.version,
    network: network ?? r.network,
    coordinatorAlias: alias ?? r.coordinatorAlias,
    orderId: orderId ?? r.orderId,
    role: role ?? r.role,
    position: position ?? r.position,
    readAtMicros: readAtMicros ?? r.readAtMicros,
    bondHash: clearBondHash ? null : bondHash ?? r.bondHash,
    escrowHash: clearEscrowHash ? null : escrowHash ?? r.escrowHash,
    deadlineMicros: r.deadlineMicros,
    bondStepSeenAtMicros: clearBondStepSeenAt
        ? null
        : bondStepSeenAtMicros ?? r.bondStepSeenAtMicros,
    bondStepDeadlineMicros: clearBondStepDeadline
        ? null
        : r.bondStepDeadlineMicros,
    breached: breached ?? r.breached,
    historyUnknown: historyUnknown ?? r.historyUnknown,
  );

  group('which trail record may replace the stored one', () {
    test('every violation of the rule is refused, with its reason', () async {
      final pre = await taken();
      final later = tradeNow.add(const Duration(seconds: 30));
      final swapped = next(
        pre,
        await answer(
          orderJson(3, bond: bondInvoice(seed: 7)),
          invoices: [bondInvoice(seed: 7)],
        ),
        now: later,
      );
      final stored = swapped.trail.record;
      expect(stored.breached, isTrue);
      final at = stored.readAtMicros + 1;
      final cases = <TrailReplacementRefusal, TradeTrailRecord>{
        TrailReplacementRefusal.olderVersion: edited(
          stored,
          version: stored.version - 1,
          readAtMicros: at,
        ),
        TrailReplacementRefusal.otherTrade: edited(
          stored,
          orderId: 43,
          readAtMicros: at,
        ),
        TrailReplacementRefusal.earlierRead: pre.trail.record,
        TrailReplacementRefusal.breachCleared: edited(
          stored,
          breached: false,
          readAtMicros: at,
        ),
        TrailReplacementRefusal.historyChanged: edited(
          stored,
          historyUnknown: true,
          readAtMicros: at,
        ),
        TrailReplacementRefusal.hashChanged: edited(
          stored,
          bondHash: bondInvoice(seed: 7).facts.paymentHash,
          readAtMicros: at,
        ),
        TrailReplacementRefusal.preTakeForgotten: edited(
          stored,
          clearBondStepSeenAt: true,
          readAtMicros: at,
        ),
        TrailReplacementRefusal.malformed: edited(
          stored,
          position: 'somewhere',
          readAtMicros: at,
        ),
      };
      for (final MapEntry(key: reason, value: record) in cases.entries) {
        expect(record.whyNotReplace(stored), reason, reason: '$reason');
        expect(record.mayReplace(stored), isFalse);
      }
      // A cleared hash and a forgotten pre-take deadline are refused too.
      expect(
        edited(
          stored,
          clearBondHash: true,
          readAtMicros: at,
        ).whyNotReplace(stored),
        TrailReplacementRefusal.hashChanged,
      );
      expect(
        edited(
          stored,
          clearBondStepDeadline: true,
          readAtMicros: at,
        ).whyNotReplace(stored),
        TrailReplacementRefusal.preTakeForgotten,
      );
      // The pre-take's last read moved back.
      expect(
        edited(
          stored,
          bondStepSeenAtMicros: (stored.bondStepSeenAtMicros ?? 0) - 1,
          readAtMicros: at,
        ).whyNotReplace(stored),
        TrailReplacementRefusal.preTakeForgotten,
      );
      // An escrow hash set stays set.
      final sellerPre = await taken(terms: seller);
      final six = next(
        sellerPre,
        await answer(
          orderJson(6, role: TradeRole.seller, escrow: escrowInvoice()),
          invoices: [escrowInvoice()],
        ),
        terms: seller,
        now: later,
      );
      expect(
        edited(
          six.trail.record,
          clearEscrowHash: true,
          readAtMicros: six.trail.record.readAtMicros + 1,
        ).whyNotReplace(six.trail.record),
        TrailReplacementRefusal.hashChanged,
      );
    });

    test(
      'the position: along the edges, from the start of a recovered trade, or with a breach; an end is never left',
      () async {
        final pre = await taken();
        final later = tradeNow.add(const Duration(seconds: 30));
        final six = next(pre, await answer(orderJson(6)), now: later);
        final record = six.trail.record;
        expect(record.whyNotReplace(pre.trail.record), isNull);
        // Back from 6 to the start, the pins dropped (the reviewer's GAP-P6): refused.
        expect(
          edited(
            record,
            position: 'start',
            clearBondHash: true,
            readAtMicros: record.readAtMicros + 1,
          ).whyNotReplace(record),
          TrailReplacementRefusal.hashChanged,
        );
        expect(
          edited(
            record,
            position: 'start',
            readAtMicros: record.readAtMicros + 1,
          ).whyNotReplace(record),
          TrailReplacementRefusal.positionMoved,
        );
        // From 6 back to the pre-take: no edge, refused; with a breach recorded, the trail may say so.
        expect(
          edited(
            record,
            position: 'bondStep',
            readAtMicros: record.readAtMicros + 1,
          ).whyNotReplace(record),
          TrailReplacementRefusal.positionMoved,
        );
        // A breached trail may stand anywhere but out of an end: an unexpected edge is a breach the trail remembers, and a breached trail is never paid on.
        expect(
          edited(
            record,
            position: 'bondStep',
            breached: true,
            readAtMicros: record.readAtMicros + 1,
          ).whyNotReplace(record),
          isNull,
        );
        // An end is never left, even with a breach.
        final ended = next(six, const TradeOrderCancelled(), now: later);
        expect(
          edited(
            ended.trail.record,
            position: 'chatting',
            breached: true,
            readAtMicros: ended.trail.record.readAtMicros + 1,
          ).whyNotReplace(ended.trail.record),
          TrailReplacementRefusal.positionMoved,
        );
        // The pre-take back after a pause is an edge.
        final paused = next(pre, const TradeOrderNotAvailable(), now: later);
        final back = next(
          paused,
          await answer(orderJson(3)),
          now: later.add(const Duration(seconds: 5)),
        );
        expect(back.trail.record.whyNotReplace(paused.trail.record), isNull);
        // A recovered trade's first answer may be anywhere.
        final found = TradeStatus.beforeFirstRead(
          TradeTrail.recovered(buyer, tradeNow),
        );
        final foundAt9 = next(found, await answer(orderJson(9)), now: later);
        expect(foundAt9.trail.record.whyNotReplace(found.trail.record), isNull);
        // The same record written twice may replace itself.
        expect(record.mayReplace(record), isTrue);
      },
    );
  });

  test(
    'a refused answer records its read, so that no later write looks older (mutant S17)',
    () async {
      final pre = await taken();
      final later = tradeNow.add(const Duration(minutes: 1));
      final refused = next(
        pre,
        await answer(orderJson(3, role: TradeRole.seller)),
        now: later,
      );
      expect(refused.has<TradeRoleMismatch>(), isTrue);
      expect(refused.trail.readAt, later);
      expect(refused.trail.record.whyNotReplace(pre.trail.record), isNull);
    },
  );

  test(
    'a trail belongs to its trade: other terms are refused by from and by restore',
    () async {
      final pre = await taken();
      final mixed = next(pre, await answer(orderJson(6)), terms: seller);
      expect(mixed.has<TradeOrderMismatch>(), isTrue);
      expect(mixed.trail, pre.trail);
      expect(offered(mixed, InvoiceStep.bond), isFalse);
      expect(switch (TradeTrail.restore(
        pre.trail.record,
        terms: seller,
        now: tradeNow,
      )) {
        Err(:final failure) => failure,
        Ok() => null,
      }, isA<TradeRecordOfAnotherTrade>());
    },
  );

  test(
    'a recovered trail stays recovered through a restart: the wallet never pays on it (mutant Q07)',
    () async {
      final found = TradeStatus.beforeFirstRead(
        TradeTrail.recovered(seller, tradeNow),
      );
      final first = next(
        found,
        await answer(orderJson(3, role: TradeRole.seller)),
        terms: seller,
      );
      final resumed = restored(first, terms: seller);
      expect(resumed.trail.historyUnknown, isTrue);
      final escrow = escrowInvoice();
      final six = next(
        resumed,
        await answer(
          orderJson(6, role: TradeRole.seller, escrow: escrow),
          invoices: [escrow],
        ),
        terms: seller,
      );
      expect(six.has<TradeHistoryUnknown>(), isTrue);
      expect(offered(six, InvoiceStep.escrow), isFalse);
    },
  );

  test(
    'after the first answer of a recovered trade, the edges apply (mutant Q16)',
    () async {
      final found = TradeStatus.beforeFirstRead(
        TradeTrail.recovered(buyer, tradeNow),
      );
      final atNine = next(found, await answer(orderJson(9)));
      expect(atNine.has<TradeStatusUnexpected>(), isFalse);
      final backToSix = next(atNine, await answer(orderJson(6)));
      expect(backToSix.has<TradeStatusUnexpected>(), isTrue);
    },
  );

  test('an end stays an end through a restart (the reviewer\'s P7)', () async {
    final pre = await taken();
    final cancelled = next(pre, const TradeOrderCancelled());
    final resumed = restored(cancelled, terms: buyer);
    expect(resumed.isTerminal, isTrue);
    final after = next(resumed, await answer(orderJson(6)));
    expect(identical(after, resumed), isTrue);
    expect(offered(after, InvoiceStep.bond), isFalse);
  });

  test(
    'error 1044 right after the take becomes final after the longest pre-take (the reviewer\'s GAP-P1)',
    () async {
      final pending = TradeStatus.beforeFirstRead(
        TradeTrail.forPendingTake(buyer, tradeNow),
      );
      final onHold = next(pending, const TradeOrderNotAvailable());
      expect(onHold, isA<PreTakeUnavailable>());
      final gone = tradeNow
          .add(TradeTolerances.longestPreTake)
          .add(TradeTolerances.coordinatorLoops);
      expect(
        next(
          onHold,
          const TradeOrderNotAvailable(),
          now: gone.subtract(const Duration(seconds: 1)),
        ),
        isA<PreTakeUnavailable>(),
      );
      final threeDaysLater = tradeNow.add(const Duration(days: 3));
      expect(
        next(onHold, const TradeOrderNotAvailable(), now: threeDaysLater),
        isA<TakenByAnother>(),
      );
    },
  );

  test(
    'restoring the terms: a coordinator gone, or not on the network, has its own refusal (mutant Q03)',
    () {
      final r = buyer.record;
      TradeTermsRecord changed({String? alias, String? network}) =>
          TradeTermsRecord(
            version: r.version,
            network: network ?? r.network,
            coordinatorAlias: alias ?? r.coordinatorAlias,
            orderId: r.orderId,
            role: r.role,
            type: r.type,
            currencyId: r.currencyId,
            amount: r.amount,
            isRange: r.isRange,
            premiumPercent: r.premiumPercent,
            explicitSatoshis: r.explicitSatoshis,
            bondSizePercent: r.bondSizePercent,
            escrowSeconds: r.escrowSeconds,
            bookPrice: r.bookPrice,
            takerFee: r.takerFee,
          );
      Object? refusal(TradeTermsRecord record) =>
          switch (TradeTerms.restore(record)) {
            Err(:final failure) => failure,
            Ok() => null,
          };
      expect(refusal(changed(alias: 'nobody')), isA<TradeCoordinatorGone>());
      final mainnetOnly = Federation.robosats.coordinators.firstWhere(
        (coordinator) => !coordinator.isOn(RobosatsNetwork.testnet),
      );
      expect(
        refusal(changed(alias: mainnetOnly.shortAlias, network: 'testnet')),
        isA<TradeCoordinatorGone>(),
      );
      expect(refusal(changed(network: 'regtest')), isA<TradeRecordMalformed>());
    },
  );

  test(
    'only the trade\'s own domain and use cases name the fresh trails and the take\'s start',
    () {
      final names = RegExp(
        r'\b(forPendingTake|afterTake|TradeTrail\.recovered|TradeTrail\._fresh)\b',
      );
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final path = file.path.replaceAll(r'\', '/');
        if (path.startsWith('lib/src/domain/trade/') ||
            path.startsWith('lib/src/domain/usecases/trade/') ||
            path.startsWith('lib/src/testing/')) {
          continue;
        }
        expect(names.hasMatch(file.readAsStringSync()), isFalse, reason: path);
      }
      final status = File(
        'lib/src/domain/trade/trade_status.dart',
      ).readAsStringSync();
      // No public fresh trail but those three: the take's start is private.
      expect(status.contains('factory TradeTrail.atTake'), isFalse);
      expect(status.contains('factory TradeTrail._fresh('), isTrue);
    },
  );

  test('the take\'s own answer starts the trade', () async {
    final first = await taken();
    expect(first, isA<WaitingForTakerBond>());
    expect(first.warnings, isEmpty);
    expect(first.trail.position, TradePosition.bondStep);
    expect(offered(first, InvoiceStep.bond), isTrue);
  });
}
