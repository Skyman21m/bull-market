import 'package:p2p/src/domain/trade/trade_chat_step.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/testing.dart' show ScriptedFault, ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/trade_harness.dart';

/// Taking an order as seller (#96): the escrow invoice and its checks at 6 and 7, the wait at 8, and « Confirm {{amount}} {{currencyCode}} received » at 10, sent once from a fresh read that still shows « fiat sent », a lost answer resolved by a read and never by a second send; over the coordinator the tests play (never a real coordinator, never money).
void main() {
  const confirms = ScriptedRequest.confirm;

  int sent(TradeHarness app, ScriptedRequest kind) =>
      app.coordinator.received.where((k) => k == kind).length;

  /// A buy order taken on a fresh run, its bond locked, then [move]d by the coordinator, and the status a read stored.
  Future<(TradeHarness, TradeRecord, TradeSeen)> seller({
    void Function(TradeHarness app)? before,
    void Function(TradeHarness app)? move,
    int orderId = 42,
  }) async {
    final app = await TradeHarness.start(orderType: 0, orderId: orderId);
    before?.call(app);
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
    expect(record.role, TradeRole.seller);
    final run = app.watchOf(record);
    await app.settle();
    app.coordinator.lockBond(app.robot(0));
    move?.call(app);
    await app.elapse(const Duration(seconds: 10));
    final last = run.lastStatus;
    await run.subscription.cancel();
    expect(last.stored, isTrue);
    return (app, last.record, last.seen);
  }

  CheckedInvoice checked(StepInvoice? invoice) => switch (invoice) {
    final CheckedInvoice checked => checked,
    final other => fail('not a checked invoice: $other'),
  };

  group('the escrow', () {
    test(
      'at 6: the escrow invoice of the trade\'s sats and the taker fee, every check passed, shown as is',
      () async {
        final (app, _, seen) = await seller();
        final status = seen.status;
        expect(status, isA<WaitingForBoth>());
        status as WaitingForBoth;
        expect(status.role, TradeRole.seller);
        final escrow = checked(status.escrow);
        expect(escrow.step, InvoiceStep.escrow);
        expect(escrow.warnings, isEmpty);
        expect(status.warnings, isEmpty);
        expect(escrow.mayShow, isTrue);
        final invoice = app.coordinator.escrowInvoice;
        expect(escrow.bolt11, invoice?.text);
        // `Logics.escrow_amount`: the frozen sats and the taker's fee, rounded.
        expect(
          escrow.amount.value.toInt(),
          106900 + (106900 * 0.00175).round(),
        );
        expect(escrow.orderAmount, status.tradeSatoshis);
        expect(status.currency.code, 'EUR');
        expect(status.escrowDuration, const Duration(hours: 3));
      },
    );

    test('at 7 (the buyer\'s payout in first): the same invoice', () async {
      final (app, _, seen) = await seller(
        move: (app) => app.coordinator.moveTo(7),
      );
      final status = seen.status;
      expect(status, isA<WaitingForEscrow>());
      expect(
        checked(status.invoice).bolt11,
        app.coordinator.escrowInvoice?.text,
      );
      expect(status.warnings, isEmpty);
    });

    test(
      'an escrow invoice for more than the trade\'s sats and its fee: never shown as payable, at most behind « Show anyway »',
      () async {
        final (_, _, seen) = await seller(
          before: (app) => app.coordinator.escrowInvoiceSats = 106900 + 500,
        );
        final escrow = checked(seen.status.invoice);
        expect(escrow.mayShow, isFalse);
        expect(escrow.mayShowAnyway, isTrue);
        expect(
          escrow.warnings,
          containsAll([
            isA<EscrowAmountMismatch>(),
            isA<TakerFeeAboveAnnounced>(),
          ]),
        );
        expect(escrow.passedEveryCheck, isFalse);
      },
    );

    test(
      'an invoice whose amount is not the escrow the order says: the invoice\'s own check',
      () async {
        final (_, _, seen) = await seller(
          before: (app) {
            app.coordinator.escrowInvoiceSats = 106900 + 200;
            app.coordinator.escrowSatoshisAnswered =
                106900 + (106900 * 0.00175).round();
          },
        );
        final escrow = checked(seen.status.invoice);
        expect(escrow.warnings, contains(isA<InvoiceAmountMismatch>()));
        expect(escrow.mayShow, isFalse);
      },
    );

    test(
      'a coordinator whose trade sats are not the escrow: the amounts disagree, not shown as payable',
      () async {
        final (_, _, seen) = await seller(
          before: (app) => app.coordinator.tradeSatoshisAnswered = 100000,
        );
        final escrow = checked(seen.status.invoice);
        expect(escrow.warnings, contains(isA<EscrowAmountMismatch>()));
        expect(escrow.mayShow, isFalse);
      },
    );

    test('locked at 6: 8, the seller waits; at 7: 9, the chat', () async {
      final (_, _, eight) = await seller(
        move: (app) => app.coordinator.lockEscrow(),
      );
      expect(eight.status, isA<WaitingForPayout>());
      expect((eight.status as WaitingForPayout).role, TradeRole.seller);
      expect(eight.status.invoice, isNull);
      final (_, _, nine) = await seller(
        move: (app) => app.coordinator
          ..moveTo(7)
          ..lockEscrow(),
      );
      expect(
        nine.status,
        isA<Chatting>()
            .having((s) => s.role, 'role', TradeRole.seller)
            .having((s) => s.fiatSent, 'fiatSent', isFalse),
      );
    });
  });

  group('« Confirm … received »', () {
    Future<(TradeHarness, TradeRecord, TradeSeen)> atTen() => seller(
      move: (app) => app.coordinator
        ..lockEscrow()
        ..moveTo(10),
    );

    test(
      'offered at 10 only, once « fiat sent » is recorded; never to the buyer',
      () async {
        final (_, _, ten) = await atTen();
        expect(ChatStepAction.confirmFiatReceived.offeredAt(ten), isTrue);
        expect(ChatStepAction.confirmFiatSent.offeredAt(ten), isFalse);
        expect(ChatStepAction.undoFiatSent.offeredAt(ten), isFalse);
        final (_, _, nine) = await seller(
          move: (app) => app.coordinator
            ..lockEscrow()
            ..moveTo(9),
        );
        expect(ChatStepAction.confirmFiatReceived.offeredAt(nine), isFalse);
        // Not marked stored: never.
        expect(
          ChatStepAction.confirmFiatReceived.offeredAt(
            TradeSeen(ten.status, order: ten.order),
          ),
          isFalse,
        );
        // From no order read: never.
        expect(
          ChatStepAction.confirmFiatReceived.offeredAt(
            TradeSeen(ten.status, order: null, stored: true),
          ),
          isFalse,
        );
      },
    );

    test(
      'the roles hold: the buyer at 10 is not offered « … received » and nothing is sent; the seller at 9 is not offered « … sent » and nothing is sent',
      () async {
        // The buyer of a sell order, at 10 with « fiat sent » recorded.
        final app = await TradeHarness.start();
        final taken = await app.takeShown();
        final record = TradeHarness.recordOf(taken);
        final run = app.watchOf(record);
        await app.settle();
        app.coordinator
          ..lockBond(app.robot(0))
          ..moveTo(10);
        await app.elapse(const Duration(seconds: 10));
        final buyerTen = run.lastStatus;
        await run.subscription.cancel();
        expect(buyerTen.seen.stored, isTrue);
        expect(buyerTen.seen.order?.isFiatSent, isTrue);
        expect(
          ChatStepAction.confirmFiatReceived.offeredAt(buyerTen.seen),
          isFalse,
        );
        app.coordinator.requests.clear();
        expect(
          await app.chat.confirmFiatReceived(buyerTen.record, buyerTen.seen),
          isA<Err<ChatStepOutcome, ChatStepRefusal>>().having(
            (err) => err.failure,
            'refusal',
            isA<ChatStepNotOffered>(),
          ),
        );
        expect(app.coordinator.requests, isEmpty);

        // The seller at 9.
        final (sellerApp, sellerRecord, nine) = await seller(
          move: (app) => app.coordinator
            ..lockEscrow()
            ..moveTo(9),
        );
        expect(ChatStepAction.confirmFiatSent.offeredAt(nine), isFalse);
        sellerApp.coordinator.requests.clear();
        expect(
          await sellerApp.chat.confirmFiatSent(sellerRecord, nine),
          isA<Err<ChatStepOutcome, ChatStepRefusal>>().having(
            (err) => err.failure,
            'refusal',
            isA<ChatStepNotOffered>(),
          ),
        );
        expect(sellerApp.coordinator.requests, isEmpty);
      },
    );

    test(
      'sent once, after a fresh read; 13 shown once the escrow is released',
      () async {
        final (app, record, seen) = await atTen();
        final steps = <ChatStepProgress>[];
        app.coordinator.requests.clear();
        final outcome = switch (await app.chat.confirmFiatReceived(
          record,
          seen,
          onProgress: steps.add,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(outcome, isA<ChatStepDone>());
        expect(
          outcome.seen.status,
          isA<SendingSats>().having((s) => s.role, 'role', TradeRole.seller),
        );
        expect(app.coordinator.status, 13);
        expect(app.coordinator.escrowSettlements, 1);
        // The read before, the robot read back for the key the release is signed with (GHSA-22q8-9ghc-jg3h), the release once, the read after.
        expect(app.coordinator.received, [
          ScriptedRequest.order,
          ScriptedRequest.robot,
          confirms,
          ScriptedRequest.order,
        ]);
        expect(steps, [
          ChatStepProgress.waitingForOrder,
          ChatStepProgress.readingOrder,
          ChatStepProgress.sending,
          ChatStepProgress.readingAfter,
        ]);
        // Done: the same status seen sends nothing again, and the status now does not offer it.
        expect(
          ChatStepAction.confirmFiatReceived.offeredAt(outcome.seen),
          isFalse,
        );
        final again = await app.chat.confirmFiatReceived(record, seen);
        expect(sent(app, confirms), 1);
        expect(
          again,
          isA<Ok<ChatStepOutcome, ChatStepRefusal>>().having(
            (ok) => ok.value,
            'outcome',
            isA<ChatStepDone>(),
          ),
        );
        expect(app.coordinator.escrowSettlements, 1);
      },
    );

    test('an on-chain payout: 14 at once, done', () async {
      final (app, record, seen) = await atTen();
      app.coordinator.onchainPayout = true;
      final result = await app.chat.confirmFiatReceived(record, seen);
      expect(
        result,
        isA<Ok<ChatStepOutcome, ChatStepRefusal>>().having(
          (ok) => ok.value.seen.status,
          'status',
          isA<Succeeded>(),
        ),
      );
    });

    test(
      'from a status seen at 9, or the buyer\'s, nothing is read or sent',
      () async {
        final (app, record, nine) = await seller(
          move: (app) => app.coordinator
            ..lockEscrow()
            ..moveTo(9),
        );
        app.coordinator.requests.clear();
        expect(
          await app.chat.confirmFiatReceived(record, nine),
          isA<Err<ChatStepOutcome, ChatStepRefusal>>().having(
            (err) => err.failure,
            'refusal',
            isA<ChatStepNotOffered>(),
          ),
        );
        expect(app.coordinator.requests, isEmpty);
      },
    );

    test(
      'the order moved since the status seen (a dispute): nothing sent, the status now shown',
      () async {
        final (app, record, seen) = await atTen();
        app.coordinator.moveTo(11);
        final result = await app.chat.confirmFiatReceived(record, seen);
        expect(
          result,
          isA<Err<ChatStepOutcome, ChatStepRefusal>>().having(
            (err) => err.failure,
            'refusal',
            isA<ChatStepStatusMoved>().having(
              (r) => r.seen.status,
              'status',
              isA<InDispute>(),
            ),
          ),
        );
        expect(sent(app, confirms), 0);
      },
    );

    test(
      'the coordinator answers 200 at 10 without settling the escrow: unknown, never done, never sent again',
      () async {
        final (app, record, seen) = await atTen();
        app.coordinator.confirmFallsThrough = true;
        final outcome = switch (await app.chat.confirmFiatReceived(
          record,
          seen,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(outcome, isA<ChatStepOutcomeUnknown>());
        expect(outcome.seen.status, isA<Chatting>());
        expect(sent(app, confirms), 1);
        expect(app.coordinator.escrowSettlements, 0);
      },
    );

    test(
      'an answer lost after the coordinator acted: the read after shows 13, so done; sent once',
      () async {
        final (app, record, seen) = await atTen();
        app.coordinator.failNext(confirms, ScriptedFault.answerLost);
        final outcome = switch (await app.chat.confirmFiatReceived(
          record,
          seen,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(outcome, isA<ChatStepDone>());
        expect(outcome.seen.status, isA<SendingSats>());
        expect(sent(app, confirms), 1);
        expect(app.coordinator.escrowSettlements, 1);
      },
    );

    test(
      'refused with 1028 (the escrow not above the payout): not done, said as the coordinator\'s refusal',
      () async {
        final (app, record, seen) = await atTen();
        app.coordinator.escrowBelowPayout = true;
        final outcome = switch (await app.chat.confirmFiatReceived(
          record,
          seen,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(
          outcome,
          isA<ChatStepNotDone>().having(
            (o) => o.cause,
            'cause',
            isA<EscrowBelowPayout>(),
          ),
        );
        expect(sent(app, confirms), 1);
      },
    );

    test('the order seen is another trade\'s: nothing read or sent', () async {
      final (app, record, _) = await atTen();
      final (_, _, other) = await seller(
        orderId: 43,
        move: (app) => app.coordinator
          ..lockEscrow()
          ..moveTo(10),
      );
      final foreign = TradeSeen(
        other.status,
        order: switch (other.order) {
          final order? => order,
          null => fail('no order'),
        },
        stored: true,
      );
      app.coordinator.requests.clear();
      final result = await app.chat.confirmFiatReceived(record, foreign);
      expect(result, isA<Err<ChatStepOutcome, ChatStepRefusal>>());
      expect(sent(app, confirms), 0);
    });
  });

  group('the end, for the seller', () {
    test(
      'the stars at 13, 14 and 15 for the seller (the reference\'s « Trade finished! »), not before',
      () async {
        for (final (status, offered) in [
          (10, false),
          (13, true),
          (14, true),
          (15, true),
        ]) {
          final (_, _, seen) = await seller(
            move: (app) => app.coordinator
              ..lockEscrow()
              ..moveTo(10)
              ..moveTo(status),
          );
          expect(
            ChatStepAction.rate.offeredAt(seen),
            offered,
            reason: '$status',
          );
        }
        expect(
          ChatStepAction.ratedAt(
            TradeRole.buyer,
            CoordinatorOrderStatus.sendingSats,
          ),
          isFalse,
        );
        expect(
          ChatStepAction.ratedAt(
            TradeRole.seller,
            CoordinatorOrderStatus.sendingSats,
          ),
          isTrue,
        );
      },
    );

    test('a rating at 13 is sent once, from a read still at 13', () async {
      final (app, record, seen) = await seller(
        move: (app) => app.coordinator
          ..lockEscrow()
          ..moveTo(13),
      );
      final rating = PlatformRating.of(4) ?? fail('rating');
      final result = await app.chat.rate(record, seen, rating);
      expect(
        result,
        isA<Ok<ChatStepOutcome, ChatStepRefusal>>().having(
          (ok) => ok.value,
          'outcome',
          isA<ChatStepDone>(),
        ),
      );
      expect(app.coordinator.platformRating, 4);
    });
  });
}
