import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_answer.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart';
import 'package:p2p/src/domain/trade/trade_storable.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:p2p/src/domain/trade/trade_tolerances.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/trade/wallet_payment.dart';
import 'package:p2p/src/testing/bolt11_test_invoice.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart';
import 'support/trade_orders.dart';

/// A decoder with a bug: it throws an `Error`, not an `Exception`.
final class _ThrowsError implements Bolt11Decoder {
  const _ThrowsError();

  @override
  Result<Bolt11Invoice, Bolt11Refusal> decode(String invoice) =>
      throw StateError('decoder bug');
}

/// The scenarios of the first independent review of #106 (R1 to R10), and the tests that kill the mutants it found surviving (M01, M13, M15, M16 in `trade_status_test.dart`, M22), each as it must now end.
void main() {
  late TradeTerms buyer;
  late TradeTerms seller;
  late Bolt11TestDecoder decoder;
  late Bolt11Reader reader;
  final takenAt = tradeNow.subtract(const Duration(seconds: 5));

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

  TradeStatus atTake() =>
      TradeStatus.beforeFirstRead(TradeTrail.atTake(takenAt));

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

  WalletPaymentDecision pay(
    TradeStatus status,
    InvoiceStep step, {
    int accepted = 1 << 40,
  }) => walletPaymentFor(
    accepted: Sats.fromInt(accepted),
    status: status,
    step: step,
    now: tradeNow,
  );

  /// [status] after a restart: its trail and the terms stored, then read back.
  TradeStatus restarted(TradeStatus status) {
    final trail = switch (TradeTrail.restore(status.trail.record)) {
      Ok(:final value) => value,
      Err(:final failure) => fail('$failure'),
    };
    return TradeStatus.beforeFirstRead(trail);
  }

  TradeTerms restoredTerms(TradeTerms terms) =>
      switch (TradeTerms.restore(terms.record)) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };

  test(
    'R1: after a restart, the pinned escrow and a breach still hold',
    () async {
      final escrowA = escrowInvoice(seed: 2);
      final escrowB = escrowInvoice(seed: 3);
      final bond = bondInvoice();
      final pre = next(
        atTake(),
        await answer(
          orderJson(3, bond: bond, role: TradeRole.seller),
          invoices: [bond],
        ),
        terms: seller,
      );
      final six = next(
        pre,
        await answer(
          orderJson(6, role: TradeRole.seller, escrow: escrowA),
          invoices: [escrowA],
        ),
        terms: seller,
      );
      expect(pay(six, InvoiceStep.escrow), isA<WalletPaymentOffered>());
      // Restarted: the terms and the trail read back, then escrow B.
      final terms = restoredTerms(seller);
      final afterRestart = next(
        restarted(six),
        await answer(
          orderJson(6, role: TradeRole.seller, escrow: escrowB),
          invoices: [escrowB],
        ),
        terms: terms,
      );
      expect(afterRestart.has<InvoiceHashChanged>(), isTrue);
      // The pinned hash is the first one, not the latest (mutant M13).
      expect(afterRestart.trail.escrowHash, escrowA.facts.paymentHash);
      expect(
        pay(afterRestart, InvoiceStep.escrow),
        isA<WalletPaymentRefused>(),
      );
      // A breach survives a restart too: escrow A again is still never paid from this wallet.
      final backToA = next(
        restarted(afterRestart),
        await answer(
          orderJson(6, role: TradeRole.seller, escrow: escrowA),
          invoices: [escrowA],
        ),
        terms: terms,
      );
      expect(backToA.trail.breached, isTrue);
      expect(backToA.has<CoordinatorInconsistent>(), isTrue);
      // The invoice itself says it did not pass every check (mutant M09).
      expect(switch (backToA.invoice) {
        final CheckedInvoice invoice => invoice.passedEveryCheck,
        _ => null,
      }, isFalse);
      expect(pay(backToA, InvoiceStep.escrow), isA<WalletPaymentRefused>());
      // The pinned hash is the first one, not the latest (mutant M13).
      expect(backToA.trail.escrowHash, escrowA.facts.paymentHash);
      // A trade with no trail is a recovered one: the wallet never pays on it.
      final recovered = next(
        TradeStatus.beforeFirstRead(TradeTrail.recovered(tradeNow)),
        await answer(
          orderJson(6, role: TradeRole.seller, escrow: escrowB),
          invoices: [escrowB],
        ),
        terms: terms,
      );
      expect(recovered.has<TradeHistoryUnknown>(), isTrue);
      expect(pay(recovered, InvoiceStep.escrow), isA<WalletPaymentRefused>());
    },
  );

  test(
    'R2: a pause during the pre-take is not an end: 3 → 1044 → 3 → 6',
    () async {
      final bond = bondInvoice();
      final pre = next(
        atTake(),
        await answer(orderJson(3, bond: bond), invoices: [bond]),
      );
      final paused = next(pre, const TradeOrderNotAvailable());
      expect(paused, isA<PreTakeUnavailable>());
      expect(paused.isTerminal, isFalse);
      // Across a restart as well.
      final unpaused = next(
        restarted(paused),
        await answer(orderJson(3, bond: bond)),
        now: tradeNow.add(const Duration(seconds: 30)),
      );
      expect(unpaused, isA<WaitingForTakerBond>());
      expect(unpaused.warnings, isEmpty);
      expect(pay(unpaused, InvoiceStep.bond), isA<WalletPaymentOffered>());
      final locked = next(unpaused, await answer(orderJson(6)));
      expect(locked, isA<WaitingForBoth>());
      expect(locked.warnings, isEmpty);
      // Another invoice after the pause is a breach.
      final other = bondInvoice(seed: 8);
      final swapped = next(
        paused,
        await answer(orderJson(3, bond: other), invoices: [other]),
      );
      expect(swapped.has<InvoiceHashChanged>(), isTrue);
      expect(swapped.trail.breached, isTrue);
    },
  );

  test('R3: a taker fee above the ceiling refuses the take', () async {
    final [order] = await parseOrders([
      bookOrder(
        id: tradeOrderId,
        type: 0,
        amount: bookAmount,
        satoshisNow: bookSats,
        makerSeed: 1,
      ),
    ]);
    Result<TradeTerms, TradeTermsRefusal> take(double fee) =>
        TradeTerms.take(order, network: RobosatsNetwork.mainnet, takerFee: fee);
    expect(take(0.5), isA<Err<TradeTerms, TradeTermsRefusal>>());
    expect(switch (take(0.5)) {
      Err(:final failure) => failure,
      Ok() => null,
    }, isA<TakerFeeTooHigh>());
    expect(
      take(TradeTolerances.takerFeeCeiling),
      isA<Ok<TradeTerms, TradeTermsRefusal>>(),
    );
    expect(switch (take(TradeTolerances.takerFeeCeiling + 1e-9)) {
      Err(:final failure) => failure,
      Ok() => null,
    }, isA<TakerFeeTooHigh>());
    expect(switch (take(-0.001)) {
      Err(:final failure) => failure,
      Ok() => null,
    }, isA<TradeTermsUnusable>());
  });

  test(
    'R4: the wallet is offered only the invoice of the current status',
    () async {
      final bond = bondInvoice();
      final pre = next(
        atTake(),
        await answer(orderJson(3, bond: bond), invoices: [bond]),
      );
      expect(pay(pre, InvoiceStep.bond), isA<WalletPaymentOffered>());
      // After a breach, the status left in place is not payable.
      final refused = next(
        pre,
        await answer(orderJson(3, bond: bond, role: TradeRole.seller)),
      );
      expect(pay(refused, InvoiceStep.bond), isA<WalletPaymentRefused>());
      // After the bond locked, there is no bond to pay.
      final six = next(pre, await answer(orderJson(6)));
      expect(
        pay(six, InvoiceStep.bond),
        isA<WalletPaymentRefused>().having(
          (refusal) => refusal.reason,
          'reason',
          WalletPaymentRefusal.noInvoice,
        ),
      );
      // Nor an escrow at the bond step.
      expect(
        pay(pre, InvoiceStep.escrow),
        isA<WalletPaymentRefused>().having(
          (refusal) => refusal.reason,
          'reason',
          WalletPaymentRefusal.noInvoice,
        ),
      );
    },
  );

  test(
    'R5: only the state machine builds a checked invoice (a part of its library)',
    () {
      final source = File(
        'lib/src/domain/trade/checked_invoice.dart',
      ).readAsStringSync();
      expect(source, startsWith("part of 'trade_status.dart';"));
      expect(source.contains('StepInvoice _checkStepInvoice('), isTrue);
      expect(source.contains(RegExp(r'\bcheckStepInvoice\(')), isFalse);
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final text = file.readAsStringSync();
        if (file.path.endsWith('trade/trade_status.dart') ||
            file.path.endsWith('trade/checked_invoice.dart')) {
          continue;
        }
        expect(text.contains('CheckedInvoice._'), isFalse, reason: file.path);
      }
    },
  );

  test(
    'R6: a decoder that throws an Error gives an unusable invoice',
    () async {
      final status = TradeStatus.from(
        previous: atTake(),
        answer: await answer(orderJson(3)),
        terms: buyer,
        now: tradeNow,
        reader: const Bolt11Reader(_ThrowsError()),
      );
      expect(status.has<InvoiceUnreadable>(), isTrue);
      expect(pay(status, InvoiceStep.bond), isA<WalletPaymentRefused>());
    },
  );

  test(
    'R7: the cleaner\'s expiry on a missing hold invoice is an honest edge',
    () async {
      final pre = next(
        atTake(),
        await answer(orderJson(3), invoices: [bondInvoice()]),
      );
      final nine = next(
        next(next(pre, await answer(orderJson(6))), await answer(orderJson(8))),
        await answer(orderJson(9)),
      );
      expect(nine, isA<Chatting>());
      for (final from in [nine, next(nine, await answer(orderJson(10)))]) {
        final five = next(from, await answer(orderJson(5)));
        expect(five, isA<Expired>());
        expect(five.warnings, isEmpty);
        expect(five.trail.breached, isFalse);
      }
      for (final role in TradeRole.values) {
        for (final from in [
          TradePosition.waitingForEscrow,
          TradePosition.waitingForPayout,
        ]) {
          expect(TradeEdges.allows(role, from, TradePosition.expired), isTrue);
        }
      }
    },
  );

  test('R8: a first read after the take at a late status is refused', () async {
    final first14 = next(atTake(), await answer(orderJson(14)));
    expect(first14, isA<StatusUnknown>());
    expect(first14.has<TradeStatusUnexpected>(), isTrue);
    final first6 = next(atTake(), await answer(orderJson(6)));
    expect(first6, isA<WaitingForBoth>());
    expect(first6.has<TradeStatusUnexpected>(), isTrue);
  });

  test(
    'R9: a bond 2.5 % off the book\'s price is flagged (the tolerance is 2 %)',
    () async {
      final moved = (bookBond * 1.025).floor();
      final bond = bondInvoice(sats: moved, seed: 4);
      final pre = next(
        atTake(),
        await answer(orderJson(3, bond: bond), invoices: [bond]),
      );
      expect(pre.has<BondAmountOutsideOrder>(), isTrue);
    },
  );

  test(
    'R10: the wallet pays at most what the confirmation stated: its ceiling, bond × 1.02 + 1 sat',
    () async {
      final honest = (bookBond * 1.005).floor();
      final bond = bondInvoice(sats: honest, seed: 6);
      final pre = next(
        atTake(),
        await answer(orderJson(3, bond: bond), invoices: [bond]),
      );
      expect(pre.warnings, isEmpty);
      expect(
        pay(pre, InvoiceStep.bond, accepted: bookBond),
        isA<WalletPaymentRefused>(),
      );
      final ceiling = (bookBond * (1 + TradeTolerances.price) + 1).floor();
      expect(
        pay(pre, InvoiceStep.bond, accepted: ceiling),
        isA<WalletPaymentOffered>(),
      );
    },
  );

  test('M01: the tolerances keep their stated values', () {
    expect(TradeTolerances.price, 0.02);
    expect(TradeTolerances.roundingSats, 1);
    expect(TradeTolerances.feeSats, 1);
    expect(TradeTolerances.walletPaymentMargin, const Duration(seconds: 60));
    expect(TradeTolerances.fiatAmount, 5e-9);
    expect(TradeTolerances.percent, 0.005);
    expect(TradeTolerances.takerFeeCeiling, 0.01);
    expect(TradeTolerances.coordinatorLoops, const Duration(minutes: 1));
  });

  test('M13: the first hash of each step is the one pinned', () async {
    final first = bondInvoice(seed: 1);
    final second = bondInvoice(seed: 2);
    final pre = next(
      atTake(),
      await answer(orderJson(3, bond: first), invoices: [first]),
    );
    final swapped = next(
      pre,
      await answer(orderJson(3, bond: second), invoices: [second]),
    );
    expect(swapped.trail.bondHash, first.facts.paymentHash);
  });

  test('M15: a regtest invoice on a testnet trade is unusable', () async {
    final testnet = await tradeTerms(network: RobosatsNetwork.testnet);
    final regtest = bondInvoice(network: Bolt11Network.regtest);
    decoder.add(regtest);
    final status = TradeStatus.from(
      previous: atTake(),
      answer: TradeOrderRead(
        await readOrder(
          orderJson(3, bond: regtest),
          network: RobosatsNetwork.testnet,
        ),
      ),
      terms: testnet,
      now: tradeNow,
      reader: reader,
    );
    expect(status.has<InvoiceWrongNetwork>(), isTrue);
  });

  test(
    'M22: a range order whose answer does not give the amount taken has changed terms',
    () async {
      final terms = await tradeTerms(range: true);
      final last = (bookSats * 1.2).round();
      final bond = bondInvoice(sats: last * 3 ~/ 100);
      final status = next(
        atTake(),
        await answer(
          orderJson(3, range: true, bond: bond, changes: {'amount': null}),
          invoices: [bond],
        ),
        terms: terms,
      );
      expect(status.has<TradeTermsChanged>(), isTrue);
    },
  );

  test('the records print no hash', () async {
    final bond = bondInvoice();
    final pre = next(
      atTake(),
      await answer(orderJson(3, bond: bond), invoices: [bond]),
    );
    final record = pre.trail.record;
    expect(record.bondHash, bond.facts.paymentHash);
    expect('$record'.contains(bond.facts.paymentHash), isFalse);
    expect(record, isA<TradeTrailRecord>());
  });
}
