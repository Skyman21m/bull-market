import 'dart:async';

import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/bond_payment.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade/wallet_payment.dart';
import 'package:p2p/src/presentation/bond_payment_cubit.dart';
import 'package:p2p/testing.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/trade_screens.dart';

/// The use case's functions, played by the test.
final class Payments {
  final balances = StreamController<Result<Sats, P2pWalletRefusal>>.broadcast();
  final follows = <StreamController<BondPaymentWatch>>[];
  Result<WalletPaymentOffered, BondPayRefusal>? offer;
  final quotes = <Completer<Result<P2pWalletQuote, BondPayRefusal>>>[];
  final pays = <Completer<Result<P2pWalletPayment, BondPayRefusal>>>[];
  final List<P2pWalletQuote> accepted = [];
  int checks = 0;

  Stream<Result<Sats, P2pWalletRefusal>> balance(RobosatsNetwork network) =>
      balances.stream;

  Future<Result<WalletPaymentOffered, BondPayRefusal>> check(
    record,
    seen,
  ) async {
    checks++;
    return offer ?? const Err(BondPayNotAtBondStep());
  }

  Future<Result<P2pWalletQuote, BondPayRefusal>> quote(record, seen) {
    final answer = Completer<Result<P2pWalletQuote, BondPayRefusal>>();
    quotes.add(answer);
    return answer.future;
  }

  Future<Result<P2pWalletPayment, BondPayRefusal>> pay(
    record, {
    required P2pWalletQuote accepted,
  }) {
    this.accepted.add(accepted);
    final answer = Completer<Result<P2pWalletPayment, BondPayRefusal>>();
    pays.add(answer);
    return answer.future;
  }

  Stream<BondPaymentWatch> follow(record) {
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
    amount: const Sats(3207),
    network: RobosatsNetwork.mainnet,
    expiresAt: now.add(const Duration(minutes: 3)),
    now: now,
  );
  return P2pWalletQuote(
    invoice: invoice ?? (throw StateError('no invoice')),
    payin: const Sats(3330),
    networkFee: const Sats(27),
    balance: const Sats(50000),
    quotedAt: now,
  );
}

Future<void> settle() => pumpEventQueue();

void main() {
  late TradeSeen seen;

  setUpAll(() async {
    seen = await (await TradeScreenStatuses.make()).bondStep();
  });

  test('start: the balance and a payment made earlier looked for, once; nothing quoted', () async {
    final payments = Payments();
    final cubit = payments.cubit()
      ..start()
      ..start();
    payments.balances.add(const Ok(Sats(50000)));
    payments.follows.single.add(const BondPaymentNone());
    await settle();
    expect(cubit.state.balance, isA<Ok<Sats, P2pWalletRefusal>>());
    expect(cubit.state.step, isA<BondPayIdle>());
    expect(payments.follows, hasLength(1));
    expect(payments.quotes, isEmpty);
    await cubit.close();
  });

  test('the offer is checked once per status shown', () async {
    final payments = Payments();
    final cubit = payments.cubit();
    await cubit.offerFor(seen);
    await cubit.offerFor(seen);
    expect(payments.checks, 1);
    expect(cubit.state.offer, isA<Err<void, BondPayRefusal>>());
    await cubit.close();
  });

  test('ask, confirm: one quote, one payment, then the payment followed', () async {
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
  });

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

  test('a refusal that moved nothing: back to the offer with its reason', () async {
    final payments = Payments();
    final cubit = payments.cubit()..start();
    payments.follows.single.add(const BondPaymentNone());
    await settle();
    final asking = cubit.ask(seen);
    payments.quotes.single.complete(
      const Err(BondPayWalletRefused(P2pWalletUnderMinimum(minimum: Sats(1000)))),
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
  });

  test('a broadcast whose outcome is unknown is followed, never paid again', () async {
    final payments = Payments();
    final cubit = payments.cubit()..start();
    payments.follows.single.add(const BondPaymentNone());
    await settle();
    final asking = cubit.ask(seen);
    payments.quotes.single.complete(Ok(walletQuote()));
    await asking;
    final paying = cubit.confirm();
    final payment = P2pWalletPayment(id: 'swap', paymentHash: testPaymentHash);
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
  });

  test('a payment found that moved nothing and is not signed may be tried again; a signed one may not', () async {
    final payments = Payments();
    final cubit = payments.cubit()..start();
    final payment = P2pWalletPayment(id: 'swap', paymentHash: testPaymentHash);
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
  });

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
