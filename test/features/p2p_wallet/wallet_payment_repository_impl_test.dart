import 'package:bb_mobile/features/p2p_wallet/data/wallet_payment_repository_impl.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/wallet_payment_repository.dart';
import 'package:bb_mobile/features/swap/public/swap_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';

import 'support/fakes.dart';
import 'support/payment_fakes.dart';

/// The reads of a payment (#100, W3): where each state of a wallet's swap order stands as the port says it, the watch of a payment, and the payment found again by its hash after a restart. Nothing here creates or changes an order.
void main() {
  late Journal journal;
  late FakeOrderSwaps swaps;
  late FakeWalletInvoices invoices;
  late WalletPaymentRepository payments;

  setUp(() {
    journal = Journal();
    swaps = FakeOrderSwaps(journal, () => testNow);
    invoices = FakeWalletInvoices();
    payments = WalletPaymentRepositoryImpl(swaps, invoices);
  });

  tearDown(() => swaps.close());

  OrderSwapRecord recordOf(
    OrderSwapLocalStatus status, {
    CheckedBolt11Invoice? invoice,
    String? signed,
    String? transactionId,
    String payinStatus = 'pending',
    String localId = 'local-1',
    String? note = 'RoboSats',
  }) => paymentRecord(
    localId: localId,
    destination: (invoice ?? payInvoice()).bolt11,
    status: status,
    signed: signed,
    transactionId: transactionId,
    payinStatus: payinStatus,
    note: note,
    withOrder:
        status != OrderSwapLocalStatus.creating &&
        status != OrderSwapLocalStatus.creationUnknown &&
        !(status == OrderSwapLocalStatus.failed &&
            signed == null &&
            transactionId == null),
  );

  group('each state of an order, as the port says it', () {
    test('every local status, with what the wallet knows of the funds', () {
      final cases = <(OrderSwapRecord, Matcher)>[
        (
          recordOf(OrderSwapLocalStatus.creating),
          isA<P2pWalletPaymentPreparing>(),
        ),
        (
          recordOf(OrderSwapLocalStatus.creationUnknown),
          isA<P2pWalletPaymentPreparing>(),
        ),
        (
          recordOf(OrderSwapLocalStatus.awaitingUserConfirmation),
          isA<P2pWalletPaymentPreparing>(),
        ),
        (
          recordOf(OrderSwapLocalStatus.preparingPayin),
          isA<P2pWalletPaymentPreparing>(),
        ),
        (
          recordOf(OrderSwapLocalStatus.readyToBroadcast, signed: 's'),
          isA<P2pWalletPaymentSigned>(),
        ),
        (
          recordOf(OrderSwapLocalStatus.broadcastUnknown, signed: 's'),
          isA<P2pWalletPaymentBroadcastUnknown>(),
        ),
        (
          recordOf(
            OrderSwapLocalStatus.payinBroadcast,
            signed: 's',
            transactionId: 't',
          ),
          isA<P2pWalletPaymentSent>(),
        ),
        (
          recordOf(
            OrderSwapLocalStatus.payoutInProgress,
            signed: 's',
            transactionId: 't',
          ),
          isA<P2pWalletPaymentPending>(),
        ),
        (
          recordOf(
            OrderSwapLocalStatus.completed,
            signed: 's',
            transactionId: 't',
          ),
          isA<P2pWalletPaymentPaid>(),
        ),
        (
          recordOf(
            OrderSwapLocalStatus.refunded,
            signed: 's',
            transactionId: 't',
          ),
          isA<P2pWalletPaymentRefunded>(),
        ),
        (
          recordOf(
            OrderSwapLocalStatus.failed,
            signed: 's',
            transactionId: 't',
          ),
          isA<P2pWalletPaymentRefundPending>(),
        ),
        (
          recordOf(OrderSwapLocalStatus.failed, signed: 's'),
          isA<P2pWalletPaymentFailed>().having(
            (p) => p.funds,
            'funds',
            P2pWalletFunds.maybeSent,
          ),
        ),
        (
          recordOf(OrderSwapLocalStatus.failed),
          isA<P2pWalletPaymentFailed>().having(
            (p) => p.funds,
            'funds',
            P2pWalletFunds.notSent,
          ),
        ),
        (
          recordOf(OrderSwapLocalStatus.expired),
          isA<P2pWalletPaymentExpired>().having(
            (p) => p.funds,
            'funds',
            P2pWalletFunds.notSent,
          ),
        ),
        (
          recordOf(OrderSwapLocalStatus.expired, signed: 's'),
          isA<P2pWalletPaymentExpired>().having(
            (p) => p.funds,
            'funds',
            P2pWalletFunds.maybeSent,
          ),
        ),
        (
          recordOf(
            OrderSwapLocalStatus.expired,
            signed: 's',
            transactionId: 't',
          ),
          isA<P2pWalletPaymentExpired>().having(
            (p) => p.funds,
            'funds',
            P2pWalletFunds.sent,
          ),
        ),
      ];
      // Every status of the wallet is among the cases.
      expect(
        cases.map((c) => c.$1.localStatus).toSet(),
        OrderSwapLocalStatus.values.toSet(),
      );
      for (final (record, matcher) in cases) {
        expect(
          WalletPaymentRepositoryImpl.progressOf(record),
          matcher,
          reason:
              '${record.localStatus.name} ${record.hasPreparedPayin} ${record.hasFundsMoved}',
        );
      }
    });

    test('the service\'s manual review, while the order is open', () {
      for (final record in [
        recordOf(
          OrderSwapLocalStatus.payinBroadcast,
          signed: 's',
          transactionId: 't',
          payinStatus: ' Under Review ',
        ),
        recordOf(
          OrderSwapLocalStatus.payoutInProgress,
          signed: 's',
          transactionId: 't',
          payinStatus: 'under review',
        ),
        recordOf(
          OrderSwapLocalStatus.failed,
          signed: 's',
          transactionId: 't',
          payinStatus: 'under review',
        ),
      ]) {
        expect(
          WalletPaymentRepositoryImpl.progressOf(record),
          isA<P2pWalletPaymentUnderReview>(),
          reason: record.localStatus.name,
        );
      }
      // An order that ended is not under review any more.
      expect(
        WalletPaymentRepositoryImpl.progressOf(
          recordOf(
            OrderSwapLocalStatus.refunded,
            signed: 's',
            transactionId: 't',
            payinStatus: 'under review',
          ),
        ),
        isA<P2pWalletPaymentRefunded>(),
      );
    });
  });

  group('provably unspent', () {
    test('each status, with nothing signed: this feature\'s and another feature\'s', () {
      const ours = {
        OrderSwapLocalStatus.creating: true,
        OrderSwapLocalStatus.creationUnknown: true,
        OrderSwapLocalStatus.awaitingUserConfirmation: true,
        OrderSwapLocalStatus.preparingPayin: true,
        OrderSwapLocalStatus.expired: true,
        OrderSwapLocalStatus.failed: true,
      };
      const ended = {OrderSwapLocalStatus.expired, OrderSwapLocalStatus.failed};
      for (final status in OrderSwapLocalStatus.values) {
        final signedByStatus =
            status == OrderSwapLocalStatus.readyToBroadcast ||
            status == OrderSwapLocalStatus.broadcastUnknown;
        final sentByStatus = status == OrderSwapLocalStatus.payinBroadcast;
        final record = recordOf(
          status,
          signed: signedByStatus || sentByStatus ? 's' : null,
          transactionId: sentByStatus ? 't' : null,
        );
        expect(
          WalletPaymentRepositoryImpl.isProvablyUnspent(record, ours: true),
          ours[status] ?? false,
          reason: 'ours ${status.name}',
        );
        expect(
          WalletPaymentRepositoryImpl.isProvablyUnspent(record, ours: false),
          ended.contains(status),
          reason: 'theirs ${status.name}',
        );
      }
    });

    test('a signed payin, a transaction id or a manual review is never unspent, whatever the status', () {
      for (final status in [
        OrderSwapLocalStatus.awaitingUserConfirmation,
        OrderSwapLocalStatus.preparingPayin,
        OrderSwapLocalStatus.expired,
        OrderSwapLocalStatus.failed,
      ]) {
        for (final record in [
          recordOf(status, signed: 's'),
          recordOf(status, signed: 's', transactionId: 't'),
          // A failed order with nothing signed has no service order left to be under review.
          if (status != OrderSwapLocalStatus.failed)
            recordOf(status, payinStatus: 'under review'),
        ]) {
          for (final ours in [true, false]) {
            expect(
              WalletPaymentRepositoryImpl.isProvablyUnspent(record, ours: ours),
              isFalse,
              reason: '${status.name} ${record.hasPreparedPayin} ${record.hasFundsMoved} $ours',
            );
          }
        }
      }
    });

    test(
      'the earlier orders of an invoice: their ids while all are unspent, the latest spent one otherwise',
      () async {
        final invoice = payInvoice();
        invoices.learn(invoice);
        expect(await payments.earlierAttemptsOf(invoice), _isOk(isEmpty));
        swaps
          ..hold(recordOf(OrderSwapLocalStatus.expired, localId: 'a'))
          ..hold(recordOf(OrderSwapLocalStatus.failed, localId: 'b'));
        expect(
          await payments.earlierAttemptsOf(invoice),
          _isOk(equals({'a', 'b'})),
        );
        swaps.hold(
          recordOf(
            OrderSwapLocalStatus.payoutInProgress,
            localId: 'c',
            signed: 's',
            transactionId: 't',
          ),
        );
        expect(
          await payments.earlierAttemptsOf(invoice),
          isA<Err<Set<String>, P2pWalletRefusal>>().having(
            (e) => e.failure,
            'failure',
            isA<P2pWalletPaymentExists>()
                .having((r) => r.payment?.id, 'payment', 'c')
                .having((r) => r.progress, 'progress', isA<P2pWalletPaymentPending>()),
          ),
        );
      },
    );
  });

  group('watch', () {
    test(
      'gives the progress at once, then each change, and only changes',
      () async {
        final invoice = payInvoice();
        invoices.learn(invoice);
        swaps.hold(
          recordOf(OrderSwapLocalStatus.broadcastUnknown, signed: 's'),
        );
        final seen = <Result<P2pWalletPaymentProgress, P2pWalletRefusal>>[];
        final subscription = payments
            .watch(
              P2pWalletPayment(id: 'local-1', paymentHash: invoice.paymentHash),
            )
            .listen(seen.add);
        await pumpEventQueue();
        final sent = recordOf(
          OrderSwapLocalStatus.payinBroadcast,
          signed: 's',
          transactionId: 't',
        );
        swaps
          ..update(sent)
          // A poll that changes nothing the port shows.
          ..update(sent)
          ..update(
            recordOf(
              OrderSwapLocalStatus.payoutInProgress,
              signed: 's',
              transactionId: 't',
            ),
          )
          ..update(
            recordOf(
              OrderSwapLocalStatus.refunded,
              signed: 's',
              transactionId: 't',
            ),
          );
        await pumpEventQueue();
        expect(
          [
            for (final r in seen)
              switch (r) {
                Ok(:final value) => value.runtimeType,
                Err(:final failure) => failure.runtimeType,
              },
          ],
          [
            P2pWalletPaymentBroadcastUnknown,
            P2pWalletPaymentSent,
            P2pWalletPaymentPending,
            P2pWalletPaymentRefunded,
          ],
        );
        await subscription.cancel();
      },
    );

    test(
      'ends with Unavailable for a payment that is not this feature\'s order of that hash',
      () async {
        final invoice = payInvoice();
        invoices.learn(invoice);
        for (final (record, payment) in [
          // No such record.
          (
            null,
            P2pWalletPayment(id: 'local-9', paymentHash: invoice.paymentHash),
          ),
          // Another hash.
          (
            recordOf(
              OrderSwapLocalStatus.payinBroadcast,
              signed: 's',
              transactionId: 't',
            ),
            P2pWalletPayment(id: 'local-1', paymentHash: payHash(9)),
          ),
          // An order of the wallet's own Send.
          (
            recordOf(
              OrderSwapLocalStatus.payinBroadcast,
              signed: 's',
              transactionId: 't',
              note: null,
            ),
            P2pWalletPayment(id: 'local-1', paymentHash: invoice.paymentHash),
          ),
        ]) {
          swaps.records.clear();
          if (record != null) swaps.hold(record);
          final all = await payments.watch(payment).toList();
          expect(all, hasLength(1), reason: '$record');
          expect(
            all.single,
            isA<Err<P2pWalletPaymentProgress, P2pWalletRefusal>>().having(
              (e) => e.failure,
              'failure',
              isA<P2pWalletUnavailable>(),
            ),
          );
        }
      },
    );
  });

  group('after a restart', () {
    test(
      'each interrupted state is found as it stands; a new payment is allowed only while nothing was signed',
      () async {
        for (final (record, matcher) in [
          (
            recordOf(OrderSwapLocalStatus.creating),
            isA<P2pWalletPaymentPreparing>(),
          ),
          (
            recordOf(OrderSwapLocalStatus.creationUnknown),
            isA<P2pWalletPaymentPreparing>(),
          ),
          (
            recordOf(OrderSwapLocalStatus.awaitingUserConfirmation),
            isA<P2pWalletPaymentPreparing>(),
          ),
          (
            recordOf(OrderSwapLocalStatus.readyToBroadcast, signed: 's'),
            isA<P2pWalletPaymentSigned>(),
          ),
          (
            recordOf(OrderSwapLocalStatus.broadcastUnknown, signed: 's'),
            isA<P2pWalletPaymentBroadcastUnknown>(),
          ),
          (
            recordOf(
              OrderSwapLocalStatus.payinBroadcast,
              signed: 's',
              transactionId: 't',
            ),
            isA<P2pWalletPaymentSent>(),
          ),
        ]) {
          final invoice = payInvoice();
          // A new run of the app: new objects over the same records.
          final store = FakeOrderSwaps(Journal(), () => testNow)..hold(record);
          final decoder = FakeWalletInvoices()..learn(invoice);
          final afterRestart = WalletPaymentRepositoryImpl(store, decoder);
          final found = await afterRestart.find(invoice.paymentHash);
          expect(
            found,
            isA<Ok<P2pWalletPaymentFound?, P2pWalletRefusal>>()
                .having((ok) => ok.value?.progress, 'progress', matcher)
                .having(
                  (ok) => ok.value?.payment,
                  'payment',
                  P2pWalletPayment(
                    id: 'local-1',
                    paymentHash: invoice.paymentHash,
                  ),
                ),
            reason: record.localStatus.name,
          );
          final unspent =
              record.signedPayinTransaction == null &&
              record.localPayinTransactionId == null;
          expect(
            await afterRestart.earlierAttemptsOf(invoice),
            unspent
                ? _isOk(equals({'local-1'}))
                : isA<Err<Set<String>, P2pWalletRefusal>>().having(
                    (e) => e.failure,
                    'failure',
                    isA<P2pWalletPaymentExists>(),
                  ),
            reason: record.localStatus.name,
          );
          await store.close();
        }
      },
    );

    test(
      'finds the latest of this feature\'s orders for a hash, none for another',
      () async {
        final invoice = payInvoice();
        final other = payInvoice(tag: 'p');
        invoices
          ..learn(invoice)
          ..learn(other);
        swaps
          ..hold(
            paymentRecord(
              localId: 'older',
              destination: invoice.bolt11,
              status: OrderSwapLocalStatus.refunded,
              signed: 's',
              transactionId: 't',
              createdAt: testNow.subtract(const Duration(hours: 1)),
            ),
          )
          ..hold(
            paymentRecord(
              localId: 'newer',
              destination: other.bolt11,
              createdAt: testNow,
            ),
          )
          ..hold(
            paymentRecord(
              localId: 'send',
              destination: invoice.bolt11,
              note: 'my own note',
              createdAt: testNow.add(const Duration(hours: 1)),
            ),
          );
        final found = await payments.find(invoice.paymentHash);
        expect(
          found,
          isA<Ok<P2pWalletPaymentFound?, P2pWalletRefusal>>().having(
            (ok) => ok.value?.payment.id,
            'id',
            'newer',
          ),
        );
        expect(await payments.find(payHash(9)), _isOk(isNull));
        // A hash read once is kept: the same repository answers without decoding again.
        final reads = invoices.reads.length;
        expect(await payments.find(invoice.paymentHash), isA<Ok<Object?, P2pWalletRefusal>>());
        expect(invoices.reads, hasLength(reads));
        // An order of this feature whose invoice the decoder cannot read: never « none », but Unavailable (fail closed), for the look-up and for a new payment.
        invoices.known.clear();
        final fresh = WalletPaymentRepositoryImpl(swaps, invoices);
        expect(
          await fresh.find(invoice.paymentHash),
          isA<Err<P2pWalletPaymentFound?, P2pWalletRefusal>>().having(
            (e) => e.failure,
            'failure',
            isA<P2pWalletUnavailable>(),
          ),
        );
        expect(
          await fresh.earlierAttemptsOf(payInvoice(tag: 'z', hash: payHash(7))),
          isA<Err<Set<String>, P2pWalletRefusal>>().having(
            (e) => e.failure,
            'failure',
            isA<P2pWalletUnavailable>(),
          ),
        );
      },
    );

    test(
      'records that cannot be read are Unavailable, never « none »',
      () async {
        swaps.ordersFailure = const SwapStorageFailure('disk');
        expect(
          await payments.find(payHash()),
          isA<Err<P2pWalletPaymentFound?, P2pWalletRefusal>>(),
        );
        expect(
          await payments.earlierAttemptsOf(payInvoice()),
          isA<Err<Set<String>, P2pWalletRefusal>>(),
        );
      },
    );
  });

  test('it creates, changes and refreshes nothing', () async {
    final invoice = payInvoice();
    invoices.learn(invoice);
    swaps.hold(
      recordOf(
        OrderSwapLocalStatus.payinBroadcast,
        signed: 's',
        transactionId: 't',
      ),
    );
    expect(
      await payments.find(invoice.paymentHash),
      isA<Ok<Object?, P2pWalletRefusal>>(),
    );
    expect(
      await payments.earlierAttemptsOf(invoice),
      isA<Err<Set<String>, P2pWalletRefusal>>(),
    );
    await payments
        .watch(
          P2pWalletPayment(id: 'local-1', paymentHash: invoice.paymentHash),
        )
        .first;
    expect(journal.events, isEmpty);
  });
}

/// An `Ok` whose value matches [value].
Matcher _isOk(Matcher value) => isA<Ok<Object?, P2pWalletRefusal>>().having(
  (ok) => ok.value,
  'value',
  value,
);
