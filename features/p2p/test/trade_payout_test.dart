import 'dart:async';
import 'dart:convert';

import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_payout.dart';
import 'package:p2p/src/domain/trade/trade_payout_outcome.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_tolerances.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/trade_keyring.dart';
import 'package:p2p/src/domain/usecases/trade/trade_reader.dart';
import 'package:p2p/testing.dart'
    show Bolt11TestInvoice, ScriptedFault, ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/key_output.dart';
import 'support/trade_harness.dart';

/// The buyer's payout (#90): the trade's keyring and its lifetime, the checks before anything is signed, what is signed and sent, and what each answer gives, over the coordinator the tests play (never a real coordinator, never a real invoice, address or key).
void main() {
  // The order of the scripted coordinator, fixed once the bond locks: 106,900 sats, a taker fee of 187 sats (0.175 %, rounded as `api/logics.py:666-668`), so the buyer receives 106,713.
  const buyerSats = 106713;
  // `floor(106713 − 106713 × 1000 / 10⁶)` = `floor(106606.287)`.
  const askedWithDefaultBudget = 106606;
  // BIP-173's own test vectors, which no wallet of the project holds.
  const testnetAddress = 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx';
  const mainnetAddress = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';
  const payouts = ScriptedRequest.payout;

  final defaultBudget = RoutingBudgetPpm.referenceDefault;

  int sent(TradeHarness app, ScriptedRequest kind) =>
      app.coordinator.received.where((k) => k == kind).length;

  /// A trade taken on a fresh run, its bond locked, and the status at 6 as a read stored it.
  Future<(TradeHarness, TradeRecord, TradeSeen)> atSix({
    bool swap = false,
    int? moveTo,
    bool payoutExpired = false,
  }) async {
    final app = await TradeHarness.start();
    app.coordinator.swapAllowed = swap;
    app.coordinator.payoutExpired = payoutExpired;
    final taken = await app.takeShown();
    expect(
      taken,
      isA<Ok<TakeOutcome, TakeRefusal>>().having(
        (ok) => ok.value,
        'outcome',
        isA<TakeStarted>(),
      ),
    );
    final record = TradeHarness.recordOf(taken);
    final run = app.watchOf(record);
    await app.settle();
    app.coordinator.lockBond(app.robot(0));
    if (moveTo != null) app.coordinator.moveTo(moveTo);
    await app.elapse(const Duration(seconds: 5));
    final status = run.lastStatus;
    await run.subscription.cancel();
    expect(status.stored, isTrue);
    expect(status.record.robot, record.robot);
    return (app, status.record, status.seen);
  }

  var seed = 900;

  /// An invoice of [sats] on [network], made by the test and readable by the coordinator's decoder, made now for [expiry].
  Bolt11TestInvoice invoiceOf(
    TradeHarness app, {
    required int sats,
    Bolt11Network network = Bolt11Network.testnet,
    Duration expiry = const Duration(days: 2),
    DateTime? createdAt,
  }) {
    final invoice = Bolt11TestInvoice(
      network: network,
      sats: sats,
      seed: seed++,
      createdAt: createdAt ?? app.now,
      expiry: expiry,
    );
    app.coordinator.decoder.add(invoice);
    return invoice;
  }

  CheckedPayout checked(Result<CheckedPayout, PayoutCheckRefusal> result) =>
      switch (result) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('refused: $failure'),
      };

  Matcher refusedWith<T>() => isA<Err<CheckedPayout, PayoutCheckRefusal>>()
      .having((err) => err.failure, 'refusal', isA<T>());

  Future<OpenTrade> opened(TradeHarness app, TradeRecord record) async =>
      switch (await app.reader.open(record)) {
        TradeOpened(:final trade) => trade,
        final other => throw StateError('$other'),
      };

  group('the checks before anything is signed', () {
    test(
      'the amount asked is the reference\'s, from trade_satoshis and the budget, to the sat',
      () async {
        final (app, record, seen) = await atSix();
        final ask = switch (app.payout.ask(record, seen)) {
          Ok(:final value) => value,
          Err(:final failure) => throw StateError('$failure'),
        };
        expect(ask.buyerSats, Sats.fromInt(buyerSats));
        expect(ask.isNewInvoice, isFalse);
        expect(
          ask.invoiceSatsFor(defaultBudget),
          Sats.fromInt(askedWithDefaultBudget),
        );
        expect(
          ask.invoiceSatsFor(RoutingBudgetPpm.of(0) ?? defaultBudget),
          Sats.fromInt(buyerSats),
        );
        // 99,998 ppm: 106713 − 10671.086... = 96041.91..., floored (CPython: `int(106713 - 106713.0 * (99998 / 1000000))`).
        expect(
          ask.invoiceSatsFor(RoutingBudgetPpm.of(99998) ?? defaultBudget),
          Sats.fromInt(96041),
        );
        expect(ask.onchain, isNull);
        expect(ask.onchainRefusal, SwapRefusal.disabled);

        // The exact amount passes; one sat more or less does not.
        for (final (sats, passes) in [
          (askedWithDefaultBudget, true),
          (askedWithDefaultBudget - 1, false),
          (askedWithDefaultBudget + 1, false),
          (buyerSats, false),
        ]) {
          final invoice = invoiceOf(app, sats: sats);
          final result = app.payout.check(
            record,
            seen,
            PayoutInvoiceText(invoice.text, budget: defaultBudget),
          );
          expect(
            result,
            passes
                ? isA<Ok<CheckedPayout, PayoutCheckRefusal>>()
                : refusedWith<PayoutInvoiceAmountNotAsked>(),
            reason: '$sats',
          );
        }
        // With no budget, the whole amount.
        final whole = invoiceOf(app, sats: buyerSats);
        expect(
          app.payout.check(
            record,
            seen,
            PayoutInvoiceText(
              whole.text,
              budget: RoutingBudgetPpm.of(0) ?? defaultBudget,
            ),
          ),
          isA<Ok<CheckedPayout, PayoutCheckRefusal>>(),
        );
      },
    );

    test(
      'the network, the reading, the reference\'s lightning: prefix, and the expiry at its bound',
      () async {
        final (app, record, seen) = await atSix();
        PayoutInvoiceText text(String invoice) =>
            PayoutInvoiceText(invoice, budget: defaultBudget);

        for (final network in [
          Bolt11Network.mainnet,
          Bolt11Network.signet,
          Bolt11Network.regtest,
        ]) {
          final other = invoiceOf(
            app,
            sats: askedWithDefaultBudget,
            network: network,
          );
          expect(
            app.payout.check(record, seen, text(other.text)),
            refusedWith<PayoutInvoiceOfAnotherNetwork>(),
            reason: network.name,
          );
        }
        expect(
          app.payout.check(record, seen, text('lntb1notaninvoice')),
          refusedWith<PayoutInvoiceUnreadable>(),
        );
        expect(
          app.payout.check(record, seen, text(' ')),
          refusedWith<PayoutInvoiceUnreadable>(),
        );

        // The prefix is taken off, case included, as the reference does; what is shown and signed is the invoice alone.
        final invoice = invoiceOf(app, sats: askedWithDefaultBudget);
        final shown = checked(
          app.payout.check(record, seen, text('lightning:${invoice.text}')),
        );
        expect(shown.text, invoice.text);
        expect(
          app.payout.check(record, seen, text('LIGHTNING:${invoice.text}')),
          refusedWith<PayoutInvoiceUnreadable>(),
        );

        // Expired at the very second it expires; one second before, it passes.
        final expiring = invoiceOf(
          app,
          sats: askedWithDefaultBudget,
          expiry: const Duration(minutes: 10),
        );
        app.now = expiring.facts.expiresAt.subtract(const Duration(seconds: 1));
        expect(
          app.payout.check(record, seen, text(expiring.text)),
          isA<Ok<CheckedPayout, PayoutCheckRefusal>>(),
        );
        app.now = expiring.facts.expiresAt;
        expect(
          app.payout.check(record, seen, text(expiring.text)),
          refusedWith<PayoutInvoiceExpired>(),
        );
      },
    );

    test(
      'an invoice that expires before the step and a day more is said, never refused, to the second',
      () async {
        final (app, record, seen) = await atSix();
        final deadline = switch (seen.status) {
          WaitingForBoth(:final deadline) => deadline,
          final other => throw StateError('$other'),
        };
        final enough = deadline
            .add(TradeTolerances.payoutInvoiceAfterStep)
            .difference(app.now);
        final atBound = checked(
          app.payout.check(
            record,
            seen,
            PayoutInvoiceText(
              invoiceOf(app, sats: askedWithDefaultBudget, expiry: enough).text,
              budget: defaultBudget,
            ),
          ),
        );
        expect(atBound.warnings, isEmpty);
        final short = checked(
          app.payout.check(
            record,
            seen,
            PayoutInvoiceText(
              invoiceOf(
                app,
                sats: askedWithDefaultBudget,
                expiry: enough - const Duration(seconds: 1),
              ).text,
              budget: defaultBudget,
            ),
          ),
        );
        expect(short.warnings, [PayoutWarning.invoiceMayExpireFirst]);
        expect(TradeTolerances.payoutInvoiceAfterStep, const Duration(hours: 24));
      },
    );

    test(
      'only a status a read stored, at a step that takes a payout, of this robot as buyer',
      () async {
        final (app, record, seen) = await atSix();
        final invoice = PayoutInvoiceText(
          invoiceOf(app, sats: askedWithDefaultBudget).text,
          budget: defaultBudget,
        );
        expect(
          app.payout.check(
            record,
            TradeSeen(seen.status, order: seen.order),
            invoice,
          ),
          refusedWith<PayoutNeedsARead>(),
        );
        expect(
          app.payout.check(
            record,
            TradeSeen(seen.status, order: null, stored: true),
            invoice,
          ),
          refusedWith<PayoutNeedsARead>(),
        );

        // At 7 the payout is in: nothing more is asked.
        app.coordinator.moveTo(7);
        final run = app.watchOf(record);
        await app.settle();
        final atSeven = run.lastStatus.seen;
        await run.subscription.cancel();
        expect(atSeven.status, isA<WaitingForEscrow>());
        expect(
          app.payout.check(record, atSeven, invoice),
          refusedWith<PayoutNotAsked>(),
        );
      },
    );

    test('an address only where the swap is offered, of the trade\'s network', () async {
      final (app, record, seen) = await atSix();
      final rate = MiningFeeRate.of(3.5);
      if (rate == null) throw StateError('no rate');
      expect(
        app.payout.check(
          record,
          seen,
          PayoutAddressText(testnetAddress, rate: rate),
        ),
        refusedWith<PayoutOnchainNotOffered>(),
      );

      final (swap, swapRecord, swapSeen) = await atSix(swap: true);
      final ask = switch (swap.payout.ask(swapRecord, swapSeen)) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };
      final onchain = ask.onchain;
      if (onchain == null) throw StateError('no swap offered');
      expect(onchain.invoiceAmount, Sats.fromInt(buyerSats));
      expect(onchain.swapFeePercent, 0.75);
      expect(onchain.suggestedRate, rate);
      // `floor(106713 × 0.75 / 100)` = `floor(800.3475)`.
      expect(onchain.swapFeeSats, 800);
      expect(onchain.miningFeeSatsFor(rate), 980);
      // `int(106713 − 800.3475 − 980)`.
      expect(onchain.sentSatsFor(rate), 104932);

      final shown = checked(
        swap.payout.check(
          swapRecord,
          swapSeen,
          PayoutAddressText(testnetAddress, rate: rate),
        ),
      );
      expect(shown, isA<CheckedPayoutAddress>());
      expect(shown.text, testnetAddress);
      expect((shown as CheckedPayoutAddress).sentSats, 104932);
      expect(shown.warnings, isEmpty);
      expect(
        swap.payout.check(
          swapRecord,
          swapSeen,
          PayoutAddressText(mainnetAddress, rate: rate),
        ),
        isA<Err<CheckedPayout, PayoutCheckRefusal>>().having(
          (err) => err.failure,
          'refusal',
          isA<PayoutAddressUnusable>().having(
            (r) => r.reason,
            'reason',
            isA<PayoutDestinationWrongNetwork>(),
          ),
        ),
      );
      // What would reach the address under 20,000 sats is said, not refused: the coordinator refuses it (4003).
      final highest = MiningFeeRate.of(500);
      if (highest == null) throw StateError('no rate');
      final dust = checked(
        swap.payout.check(
          swapRecord,
          swapSeen,
          PayoutAddressText(testnetAddress, rate: highest),
        ),
      );
      expect(dust.warnings, [PayoutWarning.sentBelowMinimum]);
    });
  });

  group('what is signed and sent', () {
    test(
      'at 6: the very text shown, signed and sent once, then the trade at 7 as a read stored it',
      () async {
        final (app, record, seen) = await atSix();
        final invoice = invoiceOf(app, sats: askedWithDefaultBudget);
        final shown = checked(
          app.payout.check(
            record,
            seen,
            PayoutInvoiceText('lightning:${invoice.text}', budget: defaultBudget),
          ),
        );
        final bodies = <Map<String, Object?>>[];
        app.coordinator.onRequest = (request) {
          final body = request.body;
          if (body == null) return;
          final decoded = jsonDecode(utf8.decode(body));
          if (decoded is Map<String, Object?> &&
              decoded['action'] == 'update_invoice') {
            bodies.add(decoded);
          }
        };

        final result = await app.payout.execute(record, shown);
        expect(
          result,
          isA<Ok<PayoutSubmission, PayoutNotSent>>().having(
            (ok) => ok.value,
            'outcome',
            isA<PayoutGiven>()
                .having((g) => g.seen.status, 'status', isA<WaitingForEscrow>())
                .having((g) => g.seen.stored, 'stored', isTrue)
                .having((g) => g.recordProblem, 'problem', isNull),
          ),
        );
        expect(sent(app, payouts), 1);
        expect(app.coordinator.payoutsRecorded, [invoice.text]);
        // The body is the reference client's; its signed text is the invoice shown, split as the coordinator splits it.
        final body = bodies.single;
        expect(body['routing_budget_ppm'], 1000);
        final signedMessage = body['invoice'];
        expect(signedMessage, isA<String>());
        expect(
          (signedMessage as String).startsWith(
            '-----BEGIN PGP SIGNED MESSAGE-----\nHash: SHA512\n\n${invoice.text}\n',
          ),
          isTrue,
        );
        // Signed without a hold: the key was unlocked for that signature, then dropped.
        expect(app.keys.unlocked, [app.robot(0).hashId]);
        expect(app.keyring.keepsKeyOf(record.robot), isFalse);
        expect(app.keyring.openOf(record.robot), (holds: 0, leases: 0));
      },
    );

    test('at 8 an invoice brings the chat (9); an address at 6 with the swap', () async {
      final (app, record, seen) = await atSix(moveTo: 8);
      expect(seen.status, isA<WaitingForPayout>());
      final shown = checked(
        app.payout.check(
          record,
          seen,
          PayoutInvoiceText(
            invoiceOf(app, sats: askedWithDefaultBudget).text,
            budget: defaultBudget,
          ),
        ),
      );
      expect(
        await app.payout.execute(record, shown),
        isA<Ok<PayoutSubmission, PayoutNotSent>>().having(
          (ok) => ok.value,
          'outcome',
          isA<PayoutGiven>().having(
            (g) => g.seen.status,
            'status',
            isA<Chatting>(),
          ),
        ),
      );

      final (swap, swapRecord, swapSeen) = await atSix(swap: true);
      final rate = MiningFeeRate.of(3.5);
      if (rate == null) throw StateError('no rate');
      final address = checked(
        swap.payout.check(
          swapRecord,
          swapSeen,
          PayoutAddressText(testnetAddress, rate: rate),
        ),
      );
      expect(
        await swap.payout.execute(swapRecord, address),
        isA<Ok<PayoutSubmission, PayoutNotSent>>().having(
          (ok) => ok.value,
          'outcome',
          isA<PayoutGiven>().having(
            (g) => g.seen.status,
            'status',
            isA<WaitingForEscrow>(),
          ),
        ),
      );
      expect(swap.coordinator.payoutsRecorded, [testnetAddress]);
    });

    test(
      'at 15, a new invoice once the failed one expired, without the warning of the first payout',
      () async {
        final (app, record, _) = await atSix(moveTo: 15);
        final run = app.watchOf(record);
        await app.settle();
        final notYet = run.lastStatus.seen;
        await run.subscription.cancel();
        expect(notYet.status, isA<RoutingFailed>());
        final invoice = PayoutInvoiceText(
          invoiceOf(
            app,
            sats: askedWithDefaultBudget,
            expiry: const Duration(minutes: 30),
          ).text,
          budget: defaultBudget,
        );
        expect(
          app.payout.check(record, notYet, invoice),
          refusedWith<PayoutNotAsked>(),
        );

        app.coordinator.payoutExpired = true;
        final again = app.watchOf(record);
        await app.elapse(const Duration(seconds: 30));
        final expired = again.lastStatus.seen;
        await again.subscription.cancel();
        final ask = switch (app.payout.ask(record, expired)) {
          Ok(:final value) => value,
          Err(:final failure) => throw StateError('$failure'),
        };
        expect(ask.isNewInvoice, isTrue);
        expect(ask.onchain, isNull);
        final shown = checked(app.payout.check(record, expired, invoice));
        expect(shown.warnings, isEmpty);
        expect(
          app.payout.check(
            record,
            expired,
            PayoutAddressText(
              testnetAddress,
              rate: MiningFeeRate.of(3.5) ?? (throw StateError('no rate')),
            ),
          ),
          refusedWith<PayoutOnchainNotOffered>(),
        );
        expect(
          await app.payout.execute(record, shown),
          isA<Ok<PayoutSubmission, PayoutNotSent>>().having(
            (ok) => ok.value,
            'outcome',
            isA<PayoutGiven>().having(
              (g) => g.seen.status,
              'status',
              isA<SendingSats>(),
            ),
          ),
        );
      },
    );

    test(
      'a status moved since it was shown: nothing signed, nothing sent; a figure changed: shown again',
      () async {
        final (app, record, seen) = await atSix(swap: true);
        final invoice = checked(
          app.payout.check(
            record,
            seen,
            PayoutInvoiceText(
              invoiceOf(app, sats: askedWithDefaultBudget).text,
              budget: defaultBudget,
            ),
          ),
        );
        final rate = MiningFeeRate.of(3.5);
        if (rate == null) throw StateError('no rate');
        final address = checked(
          app.payout.check(
            record,
            seen,
            PayoutAddressText(testnetAddress, rate: rate),
          ),
        );

        // The swap fee changed since the address was shown: what it receives changed.
        app.coordinator.swapFeeRate = 1.0;
        final changed = await app.payout.execute(record, address);
        expect(
          changed,
          isA<Err<PayoutSubmission, PayoutNotSent>>().having(
            (err) => err.failure,
            'refusal',
            isA<PayoutChangedSinceShown>().having(
              (c) => (c.fresh as CheckedPayoutAddress).sentSats,
              'sent',
              // `int(106713 − 1067.13 − 980)`.
              104665,
            ),
          ),
        );
        expect(sent(app, payouts), 0);
        expect(app.keys.unlocked, hasLength(1));

        // The trade moved on (a payout given elsewhere, 9): no longer asked.
        app.coordinator.moveTo(9);
        expect(
          await app.payout.execute(record, invoice),
          isA<Err<PayoutSubmission, PayoutNotSent>>().having(
            (err) => err.failure,
            'refusal',
            isA<PayoutNoLongerValid>()
                .having((n) => n.reason, 'reason', isA<PayoutNotAsked>())
                .having((n) => n.seen.status, 'status', isA<Chatting>()),
          ),
        );
        expect(sent(app, payouts), 0);
        expect(app.keyring.keepsKeyOf(record.robot), isFalse);
      },
    );
  });

  group('what each answer gives', () {
    test(
      'an answer lost: never sent again, the read after it tells whether the coordinator has it',
      () async {
        final (app, record, seen) = await atSix();
        final shown = checked(
          app.payout.check(
            record,
            seen,
            PayoutInvoiceText(
              invoiceOf(app, sats: askedWithDefaultBudget).text,
              budget: defaultBudget,
            ),
          ),
        );
        app.coordinator.failNext(payouts, ScriptedFault.answerLost);
        expect(
          await app.payout.execute(record, shown),
          isA<Ok<PayoutSubmission, PayoutNotSent>>().having(
            (ok) => ok.value,
            'outcome',
            isA<PayoutOutcomeUnknown>()
                .having((u) => u.seen.status, 'status', isA<WaitingForEscrow>())
                .having((u) => u.seen.stored, 'stored', isTrue),
          ),
        );
        expect(sent(app, payouts), 1);
        expect(app.coordinator.payoutsRecorded, hasLength(1));

        // Timed out with nothing done: still at 6, still sent once.
        final (other, otherRecord, otherSeen) = await atSix();
        final otherShown = checked(
          other.payout.check(
            otherRecord,
            otherSeen,
            PayoutInvoiceText(
              invoiceOf(other, sats: askedWithDefaultBudget).text,
              budget: defaultBudget,
            ),
          ),
        );
        other.coordinator.failNext(payouts, ScriptedFault.timedOut);
        expect(
          await other.payout.execute(otherRecord, otherShown),
          isA<Ok<PayoutSubmission, PayoutNotSent>>().having(
            (ok) => ok.value,
            'outcome',
            isA<PayoutOutcomeUnknown>().having(
              (u) => u.seen.status,
              'status',
              isA<WaitingForBoth>(),
            ),
          ),
        );
        expect(sent(other, payouts), 1);
        expect(other.coordinator.payoutsRecorded, isEmpty);
      },
    );

    test(
      'a refusal of the coordinator: nothing recorded, its kind kept, and the order read again',
      () async {
        final (app, record, seen) = await atSix(swap: true);
        final highest = MiningFeeRate.of(500);
        if (highest == null) throw StateError('no rate');
        final dust = checked(
          app.payout.check(
            record,
            seen,
            PayoutAddressText(testnetAddress, rate: highest),
          ),
        );
        final readsBefore = sent(app, ScriptedRequest.order);
        expect(
          await app.payout.execute(record, dust),
          isA<Ok<PayoutSubmission, PayoutNotSent>>().having(
            (ok) => ok.value,
            'outcome',
            isA<PayoutNotTaken>()
                .having((n) => n.cause, 'cause', isA<PayoutBelowDustLimit>())
                .having((n) => n.seen.status, 'status', isA<WaitingForBoth>()),
          ),
        );
        // The fresh read before signing, and the read after the answer.
        expect(sent(app, ScriptedRequest.order), readsBefore + 2);
        expect(app.coordinator.payoutsRecorded, isEmpty);
      },
    );

    test(
      'an invoice already given, given again at 15: refused by the coordinator (3002)',
      () async {
        final (app, record, seen) = await atSix();
        final invoice = invoiceOf(app, sats: askedWithDefaultBudget);
        final first = checked(
          app.payout.check(
            record,
            seen,
            PayoutInvoiceText(invoice.text, budget: defaultBudget),
          ),
        );
        expect(
          await app.payout.execute(record, first),
          isA<Ok<PayoutSubmission, PayoutNotSent>>().having(
            (ok) => ok.value,
            'outcome',
            isA<PayoutGiven>(),
          ),
        );
        app.coordinator
          ..moveTo(9)
          ..moveTo(10)
          ..moveTo(13)
          ..moveTo(15)
          ..payoutExpired = true;
        final run = app.watchOf(record);
        await app.settle();
        await app.elapse(const Duration(seconds: 10));
        await app.elapse(const Duration(seconds: 10));
        final atFifteen = run.lastStatus.seen;
        await run.subscription.cancel();
        expect(atFifteen.status, isA<RoutingFailed>());
        final again = checked(
          app.payout.check(
            record,
            atFifteen,
            PayoutInvoiceText(invoice.text, budget: defaultBudget),
          ),
        );
        expect(
          await app.payout.execute(record, again),
          isA<Ok<PayoutSubmission, PayoutNotSent>>().having(
            (ok) => ok.value,
            'outcome',
            isA<PayoutNotTaken>().having(
              (n) => n.cause,
              'cause',
              isA<PayoutInvoiceRefused>().having(
                (r) => r.reason,
                'reason',
                PayoutInvoiceRefusal.alreadySubmitted,
              ),
            ),
          ),
        );
        expect(app.coordinator.payoutsRecorded, [invoice.text]);
      },
    );

    test('a busy transport: tried again as the limiter says, recorded once', () async {
      final (app, record, seen) = await atSix();
      final shown = checked(
        app.payout.check(
          record,
          seen,
          PayoutInvoiceText(
            invoiceOf(app, sats: askedWithDefaultBudget).text,
            budget: defaultBudget,
          ),
        ),
      );
      app.coordinator.failNext(payouts, ScriptedFault.busy);
      expect(
        await app.payout.execute(record, shown),
        isA<Ok<PayoutSubmission, PayoutNotSent>>().having(
          (ok) => ok.value,
          'outcome',
          isA<PayoutGiven>(),
        ),
      );
      expect(sent(app, payouts), 2);
      expect(app.busyWaits, hasLength(1));
      expect(app.coordinator.payoutsRecorded, hasLength(1));
    });

    test(
      'a key that cannot be read back: nothing read, signed or sent',
      () async {
        final (app, record, seen) = await atSix();
        final shown = checked(
          app.payout.check(
            record,
            seen,
            PayoutInvoiceText(
              invoiceOf(app, sats: askedWithDefaultBudget).text,
              budget: defaultBudget,
            ),
          ),
        );
        final reads = sent(app, ScriptedRequest.order);
        app.coordinator.failNext(ScriptedRequest.robot, ScriptedFault.unreachable);
        expect(
          await app.payout.execute(record, shown),
          isA<Err<PayoutSubmission, PayoutNotSent>>().having(
            (err) => err.failure,
            'refusal',
            isA<PayoutKeyUnavailable>().having(
              (k) => k.cause,
              'cause',
              isA<CoordinatorUnreachable>(),
            ),
          ),
        );
        expect(sent(app, ScriptedRequest.order), reads);
        expect(sent(app, payouts), 0);
        expect(app.keyring.openOf(record.robot), (holds: 0, leases: 0));
      },
    );

    test(
      'two confirmations at once: one sent, the second finds the payout given',
      () async {
        final (app, record, seen) = await atSix();
        final shown = checked(
          app.payout.check(
            record,
            seen,
            PayoutInvoiceText(
              invoiceOf(app, sats: askedWithDefaultBudget).text,
              budget: defaultBudget,
            ),
          ),
        );
        final results = await Future.wait([
          app.payout.execute(record, shown),
          app.payout.execute(record, shown),
        ]);
        expect(
          results.first,
          isA<Ok<PayoutSubmission, PayoutNotSent>>().having(
            (ok) => ok.value,
            'outcome',
            isA<PayoutGiven>(),
          ),
        );
        expect(
          results.last,
          isA<Err<PayoutSubmission, PayoutNotSent>>().having(
            (err) => err.failure,
            'refusal',
            isA<PayoutNoLongerValid>(),
          ),
        );
        expect(sent(app, payouts), 1);
      },
    );

    test('nothing is printed or logged: no invoice, address, signature or key', () async {
      final (app, record, seen) = await atSix(swap: true);
      final invoice = invoiceOf(app, sats: askedWithDefaultBudget);
      final signedTexts = <String>[];
      app.coordinator.onRequest = (request) {
        final body = request.body;
        if (body != null) signedTexts.add(utf8.decode(body));
      };
      final output = await captureKeyOutput(() async {
        final hold = app.holdKey.execute(record);
        final shown = checked(
          app.payout.check(
            record,
            seen,
            PayoutInvoiceText(invoice.text, budget: defaultBudget),
          ),
        );
        final result = await app.payout.execute(record, shown);
        hold.release();
        // The values print their kind only.
        Zone.current.print('$shown $result $hold ${shown.destination}');
      });
      expect(output.contains(invoice.text), isFalse);
      expect(output.contains(invoice.text.substring(0, 40)), isFalse);
      expect(output.contains(testnetAddress), isFalse);
      expect(output.contains('PGP'), isFalse);
      expect(signedTexts, isNotEmpty);
      expectNoKeyIn(output, [tradeKey]);
    });
  });

  group('the keyring\'s lifetime', () {
    test(
      'without a hold, each lease unlocks for itself and the key is dropped when it closes',
      () async {
        final (app, record, _) = await atSix();
        final trade = await opened(app, record);
        final robotReads = sent(app, ScriptedRequest.robot);
        for (var round = 1; round <= 2; round++) {
          final lease = switch (await app.keyring.lease(trade)) {
            Ok(:final value) => value,
            Err(:final failure) => throw StateError('$failure'),
          };
          expect(app.keyring.keepsKeyOf(record.robot), isTrue);
          expect(lease.key.key.publicKey, isNotNull);
          lease.close();
          lease.close();
          expect(app.keyring.keepsKeyOf(record.robot), isFalse);
          expect(app.keyring.openOf(record.robot), (holds: 0, leases: 0));
          expect(app.keys.unlocked, hasLength(round));
          expect(sent(app, ScriptedRequest.robot), robotReads + round);
          expect(() => lease.key, throwsStateError);
        }
      },
    );

    test(
      'a hold keeps the key a lease unlocked, for every signature of the screen, until it is released',
      () async {
        final (app, record, _) = await atSix();
        final trade = await opened(app, record);
        final hold = app.holdKey.execute(record);
        // A hold alone unlocks nothing and sends nothing.
        expect(app.keyring.keepsKeyOf(record.robot), isFalse);
        expect(app.keys.unlocked, isEmpty);
        final robotReads = sent(app, ScriptedRequest.robot);
        for (var round = 0; round < 3; round++) {
          switch (await app.keyring.lease(trade)) {
            case Ok(:final value):
              value.close();
            case Err(:final failure):
              throw StateError('$failure');
          }
        }
        expect(app.keys.unlocked, hasLength(1));
        expect(sent(app, ScriptedRequest.robot), robotReads + 1);
        expect(app.keyring.keepsKeyOf(record.robot), isTrue);
        hold.release();
        expect(hold.isReleased, isTrue);
        expect(app.keyring.keepsKeyOf(record.robot), isFalse);
        expect(app.keyring.openOf(record.robot), (holds: 0, leases: 0));
        // Released twice: nothing more.
        hold.release();
        expect(app.keyring.openOf(record.robot), (holds: 0, leases: 0));
      },
    );

    test('two screens: one key, kept while either holds it', () async {
      final (app, record, _) = await atSix();
      final trade = await opened(app, record);
      final first = app.holdKey.execute(record);
      final second = app.holdKey.execute(record);
      switch (await app.keyring.lease(trade)) {
        case Ok(:final value):
          value.close();
        case Err(:final failure):
          throw StateError('$failure');
      }
      first.release();
      first.release();
      expect(app.keyring.keepsKeyOf(record.robot), isTrue);
      expect(app.keyring.openOf(record.robot), (holds: 1, leases: 0));
      second.release();
      expect(app.keyring.keepsKeyOf(record.robot), isFalse);
      expect(app.keys.unlocked, hasLength(1));
    });

    test(
      'the app sent to the background during a signature: the key is dropped once the signature is over',
      () async {
        final (app, record, seen) = await atSix();
        final shown = checked(
          app.payout.check(
            record,
            seen,
            PayoutInvoiceText(
              invoiceOf(app, sats: askedWithDefaultBudget).text,
              budget: defaultBudget,
            ),
          ),
        );
        final hold = app.holdKey.execute(record);
        final unlock = Completer<void>();
        app.keys.holdUnlock = unlock.future;
        final submitting = app.payout.execute(record, shown);
        await app.settle();
        expect(app.keyring.openOf(record.robot), (holds: 1, leases: 1));
        // Hidden or paused: the screen lets go while the unlock runs.
        hold.release();
        expect(app.keyring.keepsKeyOf(record.robot), isTrue);
        unlock.complete();
        expect(
          await submitting,
          isA<Ok<PayoutSubmission, PayoutNotSent>>().having(
            (ok) => ok.value,
            'outcome',
            isA<PayoutGiven>(),
          ),
        );
        expect(app.keyring.keepsKeyOf(record.robot), isFalse);
        expect(app.keyring.openOf(record.robot), (holds: 0, leases: 0));
      },
    );

    test(
      'leases that come while an unlock runs share it; an unlock that failed is not kept',
      () async {
        final (app, record, _) = await atSix();
        final trade = await opened(app, record);
        final unlock = Completer<void>();
        app.keys.holdUnlock = unlock.future;
        final both = Future.wait([
          app.keyring.lease(trade),
          app.keyring.lease(trade),
        ]);
        await app.settle();
        expect(app.keyring.openOf(record.robot), (holds: 0, leases: 2));
        unlock.complete();
        final leases = await both;
        expect(app.keys.unlocked, hasLength(1));
        for (final lease in leases) {
          switch (lease) {
            case Ok(:final value):
              value.close();
            case Err(:final failure):
              throw StateError('$failure');
          }
        }
        expect(app.keyring.keepsKeyOf(record.robot), isFalse);

        app.keys
          ..holdUnlock = null
          ..unlockFailure = const RobotKeyComputeFailure();
        final hold = app.holdKey.execute(record);
        expect(
          await app.keyring.lease(trade),
          isA<Err<TradeKeyLease, Failure>>().having(
            (err) => err.failure,
            'cause',
            isA<RobotKeyComputeFailure>(),
          ),
        );
        expect(app.keyring.keepsKeyOf(record.robot), isFalse);
        expect(app.keyring.openOf(record.robot), (holds: 1, leases: 0));
        app.keys.unlockFailure = null;
        switch (await app.keyring.lease(trade)) {
          case Ok(:final value):
            value.close();
          case Err(:final failure):
            throw StateError('$failure');
        }
        expect(app.keyring.keepsKeyOf(record.robot), isTrue);
        hold.release();
        expect(app.keyring.keepsKeyOf(record.robot), isFalse);
      },
    );

    test('a restart forgets every key: nothing of it is stored', () async {
      final (app, record, _) = await atSix();
      final hold = app.holdKey.execute(record);
      final trade = await opened(app, record);
      switch (await app.keyring.lease(trade)) {
        case Ok(:final value):
          value.close();
        case Err(:final failure):
          throw StateError('$failure');
      }
      expect(app.keyring.keepsKeyOf(record.robot), isTrue);
      final again = app.restart();
      expect(again.keyring.keepsKeyOf(record.robot), isFalse);
      hold.release();
    });
  });
}
