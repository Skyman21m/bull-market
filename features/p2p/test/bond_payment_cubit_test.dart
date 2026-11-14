import 'dart:async';

import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/trade/bond_payment.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade/wallet_payment.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/presentation/bond_payment_cubit.dart';
import 'package:p2p/testing.dart';
import 'package:test/test.dart';

import 'support/trade_screens.dart';

/// The use case's functions, played by the test.
final class Payments {
  final StreamController<Result<Sats, P2pWalletRefusal>> balances =
      StreamController<Result<Sats, P2pWalletRefusal>>.broadcast();
  final List<StreamController<BondPaymentWatch>> follows = [];
  Result<WalletPaymentOffered, BondPayRefusal>? offer;
  final List<Completer<Result<P2pWalletQuote, BondPayRefusal>>> quotes = [];
  final List<Completer<Result<P2pWalletPayment, BondPayRefusal>>> pays = [];
  final List<P2pWalletQuote> accepted = [];
  int checks = 0;

  /// The payment of the bond this process is making now, as the use case knows it.
  Future<void>? running;

  Stream<Result<Sats, P2pWalletRefusal>> balance(RobosatsNetwork network) =>
      balances.stream;

  Future<Result<WalletPaymentOffered, BondPayRefusal>> check(
    TradeRecord record,
    TradeSeen seen,
  ) async {
    checks++;
    return offer ?? const Err(BondPayNotAtBondStep());
  }

  Future<Result<P2pWalletQuote, BondPayRefusal>> quote(
    TradeRecord record,
    TradeSeen seen,
  ) {
    final answer = Completer<Result<P2pWalletQuote, BondPayRefusal>>();
    quotes.add(answer);
    return answer.future;
  }

  Future<Result<P2pWalletPayment, BondPayRefusal>> pay(
    TradeRecord record, {
    required P2pWalletQuote accepted,
  }) {
    this.accepted.add(accepted);
    final answer = Completer<Result<P2pWalletPayment, BondPayRefusal>>();
    pays.add(answer);
    return answer.future;
  }

  Stream<BondPaymentWatch> follow(TradeRecord record) {
    final follow = StreamController<BondPaymentWatch>();
    follows.add(follow);
    return follow.stream;
  }

  BondPaymentCubit cubit() => BondPaymentCubit(
    TradeScreenStatuses.record,
    balance,
    check,
    quote,
    pay,
    follow,
    (record) => running,
  );
}

P2pWalletQuote walletQuote() {
  final now = DateTime.now();
  final invoice = checkedBolt11InvoiceForTesting(
    bolt11: Bolt11TestInvoice(
      network: Bolt11Network.mainnet,
      sats: 3207,
      seed: 1,
      createdAt: now,
    ).text,
    amount: Sats.fromInt(3207),
    network: RobosatsNetwork.mainnet,
    expiresAt: now.add(const Duration(minutes: 3)),
    now: now,
  );
  return P2pWalletQuote(
    invoice: invoice ?? (throw StateError('no invoice')),
    payin: Sats.fromInt(3330),
    networkFee: Sats.fromInt(27),
    balance: Sats.fromInt(50000),
    quotedAt: now,
  );
}

Future<void> settle() => pumpEventQueue();

void main() {
  late TradeSeen seen;

  setUpAll(() async {
    seen = await (await TradeScreenStatuses.make()).bondStep();
  });

  test(
    'start: the balance and a payment made earlier looked for, once; nothing quoted',
    () async {
      final payments = Payments();
      final cubit = payments.cubit()
        ..start()
        ..start();
      payments.balances.add(Ok(Sats.fromInt(50000)));
      payments.follows.single.add(const BondPaymentNone());
      await settle();
      expect(cubit.state.balance, isA<Ok<Sats, P2pWalletRefusal>>());
      expect(cubit.state.step, isA<BondPayIdle>());
      expect(payments.follows, hasLength(1));
      expect(payments.quotes, isEmpty);
      await cubit.close();
    },
  );

  test('the offer is checked once per status shown', () async {
    final payments = Payments();
    final cubit = payments.cubit();
    await cubit.offerFor(seen);
    await cubit.offerFor(seen);
    expect(payments.checks, 1);
    expect(cubit.state.offer, isA<Err<void, BondPayRefusal>>());
    await cubit.close();
  });

  test(
    'ask, confirm: one quote, one payment, then the payment followed',
    () async {
      final payments = Payments();
      final cubit = payments.cubit()..start();
      payments.follows.single.add(const BondPaymentNone());
      await settle();

      final asking = cubit.ask(seen);
      unawaited(cubit.ask(seen));
      expect(cubit.state.step, isA<BondPayQuoting>());
      final quote = walletQuote();
      payments.quotes.single.complete(Ok(quote));
      await asking;
      expect(cubit.state.step, isA<BondPayConfirming>());

      final paying = cubit.confirm();
      unawaited(cubit.confirm());
      expect(cubit.state.step, isA<BondPaySending>());
      expect(payments.accepted, [same(quote)]);
      payments.pays.single.complete(
        Ok(P2pWalletPayment(id: 'swap', paymentHash: testPaymentHash)),
      );
      await paying;
      expect(payments.follows, hasLength(2));
      payments.follows.last.add(
        BondPaymentFollowed(
          P2pWalletPayment(id: 'swap', paymentHash: testPaymentHash),
          const P2pWalletPaymentSent(),
        ),
      );
      await settle();
      expect(cubit.state.step, isA<BondPayFollowing>());
      await cubit.close();
    },
  );

  test('dismiss: back to the offer, nothing paid', () async {
    final payments = Payments();
    final cubit = payments.cubit()..start();
    payments.follows.single.add(const BondPaymentNone());
    await settle();
    final asking = cubit.ask(seen);
    payments.quotes.single.complete(Ok(walletQuote()));
    await asking;
    cubit.dismiss();
    expect(cubit.state.step, isA<BondPayIdle>());
    await cubit.confirm();
    expect(payments.pays, isEmpty);
    await cubit.close();
  });

  test(
    'a refusal that moved nothing: back to the offer with its reason',
    () async {
      final payments = Payments();
      final cubit = payments.cubit()..start();
      payments.follows.single.add(const BondPaymentNone());
      await settle();
      final asking = cubit.ask(seen);
      payments.quotes.single.complete(
        Err(
          BondPayWalletRefused(
            P2pWalletUnderMinimum(minimum: Sats.fromInt(1000)),
          ),
        ),
      );
      await asking;
      expect(
        cubit.state.step,
        isA<BondPayIdle>().having(
          (idle) => idle.refused,
          'refused',
          isA<BondPayWalletRefused>(),
        ),
      );
      await cubit.close();
    },
  );

  test(
    'a broadcast whose outcome is unknown is followed, never paid again',
    () async {
      final payments = Payments();
      final cubit = payments.cubit()..start();
      payments.follows.single.add(const BondPaymentNone());
      await settle();
      final asking = cubit.ask(seen);
      payments.quotes.single.complete(Ok(walletQuote()));
      await asking;
      final paying = cubit.confirm();
      final payment = P2pWalletPayment(
        id: 'swap',
        paymentHash: testPaymentHash,
      );
      payments.pays.single.complete(
        Err(BondPayWalletRefused(P2pWalletBroadcastUnknown(payment))),
      );
      await paying;
      expect(payments.follows, hasLength(2));
      payments.follows.last.add(
        BondPaymentFollowed(payment, const P2pWalletPaymentBroadcastUnknown()),
      );
      await settle();
      expect(cubit.state.step, isA<BondPayFollowing>());
      await cubit.ask(seen);
      expect(payments.quotes, hasLength(1));
      await cubit.close();
    },
  );

  test(
    'a payment found that moved nothing and is not signed may be tried again; a signed one may not',
    () async {
      final payments = Payments();
      final cubit = payments.cubit()..start();
      final payment = P2pWalletPayment(
        id: 'swap',
        paymentHash: testPaymentHash,
      );
      payments.follows.single.add(
        BondPaymentFollowed(
          payment,
          const P2pWalletPaymentFailed(P2pWalletFunds.notSent),
        ),
      );
      await settle();
      expect(cubit.state.step, isA<BondPayIdle>());
      payments.follows.single.add(
        BondPaymentFollowed(payment, const P2pWalletPaymentSigned()),
      );
      await settle();
      expect(cubit.state.step, isA<BondPayFollowing>());
      await cubit.close();
    },
  );

  test('records that cannot be read: nothing offered', () async {
    final payments = Payments();
    final cubit = payments.cubit()..start();
    payments.follows.single.add(
      const BondPaymentUnreadable(P2pWalletUnavailable()),
    );
    await settle();
    expect(cubit.state.step, isA<BondPayUnreadable>());
    await cubit.ask(seen);
    expect(payments.quotes, isEmpty);
    await cubit.close();
  });

  test(
    'opened again while this process pays the bond: being sent, then followed once it ends; never offered meanwhile',
    () async {
      final payments = Payments();
      final running = Completer<void>();
      payments.running = running.future;
      final cubit = payments.cubit()..start();
      expect(cubit.state.step, isA<BondPaySending>());
      expect(payments.follows, isEmpty);
      await cubit.ask(seen);
      expect(payments.quotes, isEmpty);
      payments.running = null;
      running.complete();
      await settle();
      expect(payments.follows, hasLength(1));
      payments.follows.single.add(
        BondPaymentFollowed(
          P2pWalletPayment(id: 'swap', paymentHash: testPaymentHash),
          const P2pWalletPaymentSent(),
        ),
      );
      await settle();
      expect(cubit.state.step, isA<BondPayFollowing>());
      await cubit.close();
    },
  );

  test(
    'a payment being prepared by this process is being sent; one left by an earlier run may be tried again',
    () async {
      final payments = Payments();
      final cubit = payments.cubit()..start();
      final payment = P2pWalletPayment(
        id: 'swap',
        paymentHash: testPaymentHash,
      );
      payments.running = Completer<void>().future;
      payments.follows.single.add(
        BondPaymentFollowed(payment, const P2pWalletPaymentPreparing()),
      );
      await settle();
      expect(cubit.state.step, isA<BondPaySending>());
      payments.running = null;
      payments.follows.single.add(
        BondPaymentFollowed(payment, const P2pWalletPaymentPreparing()),
      );
      await settle();
      expect(cubit.state.step, isA<BondPayIdle>());
      await cubit.close();
    },
  );

  test(
    'a payment of the invoice made by the wallet\'s own screens: paid elsewhere, never offered again',
    () async {
      final payments = Payments();
      final cubit = payments.cubit()..start();
      payments.follows.single.add(const BondPaymentNone());
      await settle();
      final asking = cubit.ask(seen);
      payments.quotes.single.complete(Ok(walletQuote()));
      await asking;
      final paying = cubit.confirm();
      payments.pays.single.complete(
        const Err(
          BondPayWalletRefused(
            P2pWalletPaymentExists(progress: P2pWalletPaymentSent()),
          ),
        ),
      );
      await paying;
      expect(cubit.state.step, isA<BondPayPaidElsewhere>());
      await cubit.ask(seen);
      expect(payments.quotes, hasLength(1));
      await cubit.close();
    },
  );

  test('a payment sent for a while says it still waits', () async {
    final payments = Payments();
    final cubit = BondPaymentCubit(
      TradeScreenStatuses.record,
      payments.balance,
      payments.check,
      payments.quote,
      payments.pay,
      payments.follow,
      (record) => null,
      stillWaitingAfter: const Duration(milliseconds: 10),
    )..start();
    payments.follows.single.add(const BondPaymentNone());
    await settle();
    final asking = cubit.ask(seen);
    payments.quotes.single.complete(Ok(walletQuote()));
    await asking;
    unawaited(cubit.confirm());
    expect((cubit.state.step as BondPaySending).slow, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect((cubit.state.step as BondPaySending).slow, isTrue);
    await cubit.close();
  });

  test('a preparation left by an earlier run that ends while a new payment is sent does not offer to pay again', () async {
    final payments = Payments();
    final cubit = payments.cubit()..start();
    final earlier = P2pWalletPayment(id: 'earlier', paymentHash: testPaymentHash);
    payments.follows.single.add(
      BondPaymentFollowed(earlier, const P2pWalletPaymentPreparing()),
    );
    await settle();
    expect(cubit.state.step, isA<BondPayIdle>());
    final asking = cubit.ask(seen);
    payments.quotes.single.complete(Ok(walletQuote()));
    await asking;
    unawaited(cubit.confirm());
    expect(cubit.state.step, isA<BondPaySending>());
    // The earlier follow, if it were still listened to, would say the old order expired with nothing sent.
    if (!payments.follows.single.isClosed) {
      payments.follows.single.add(
        BondPaymentFollowed(
          earlier,
          const P2pWalletPaymentExpired(P2pWalletFunds.notSent),
        ),
      );
    }
    await settle();
    expect(cubit.state.step, isA<BondPaySending>());
    await cubit.confirm();
    expect(payments.pays, hasLength(1));
    await cubit.close();
  });

  test('a payment answered sent stays sent when the follow finds nothing yet', () async {
    final payments = Payments();
    final cubit = payments.cubit()..start();
    payments.follows.single.add(const BondPaymentNone());
    await settle();
    final asking = cubit.ask(seen);
    payments.quotes.single.complete(Ok(walletQuote()));
    await asking;
    final paying = cubit.confirm();
    payments.pays.single.complete(
      Ok(P2pWalletPayment(id: 'swap', paymentHash: testPaymentHash)),
    );
    await paying;
    expect(cubit.state.step, isA<BondPayFollowing>());
    payments.follows.last.add(const BondPaymentNone());
    await settle();
    expect(
      cubit.state.step,
      isA<BondPayFollowing>().having(
        (f) => f.progress,
        'progress',
        isA<P2pWalletPaymentSent>(),
      ),
    );
    await cubit.close();
  });

  test('an error of the payment leaves « Sending » for « cannot tell », follows again, and goes on', () async {
    final payments = Payments();
    final cubit = payments.cubit()..start();
    payments.follows.single.add(const BondPaymentNone());
    await settle();
    final asking = cubit.ask(seen);
    payments.quotes.single.complete(Ok(walletQuote()));
    await asking;
    final paying = cubit.confirm();
    payments.pays.single.completeError(StateError('a bug'));
    await expectLater(paying, throwsStateError);
    expect(cubit.state.step, isA<BondPayUnreadable>());
    expect(payments.follows, hasLength(2));
    await cubit.close();
  });

  test('closed while a payment runs: nothing emitted after', () async {
    final payments = Payments();
    final cubit = payments.cubit()..start();
    payments.follows.single.add(const BondPaymentNone());
    await settle();
    final asking = cubit.ask(seen);
    payments.quotes.single.complete(Ok(walletQuote()));
    await asking;
    final paying = cubit.confirm();
    await cubit.close();
    payments.pays.single.complete(
      Ok(P2pWalletPayment(id: 'swap', paymentHash: testPaymentHash)),
    );
    await expectLater(paying, completes);
  });
}
