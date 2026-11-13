import 'dart:async';

import 'package:bb_mobile/features/p2p_wallet/domain/entities/instant_wallet.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/entities/lightning_swap_quote.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/instant_wallet_repository.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/lightning_swap_quote_repository.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/usecases/quote_invoice_payment_usecase.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/usecases/watch_instant_balance_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';

import 'support/fakes.dart';

/// The order of the quote: what is checked before the swap service is asked, the arithmetic of the quote, and what the balance stream gives.
void main() {
  late _Wallets wallets;
  late _Quotes quotes;
  late QuoteInvoicePaymentUsecase usecase;

  setUp(() {
    wallets = _Wallets();
    quotes = _Quotes();
    usecase = QuoteInvoicePaymentUsecase(wallets, quotes, () => testNow);
  });

  P2pWalletRefusal refusalOf(Result<P2pWalletQuote, P2pWalletRefusal> r) =>
      switch (r) {
        Err(:final failure) => failure,
        Ok() => throw StateError('quoted'),
      };

  group('a quote', () {
    test(
      'itemises the service fee, the network fee, the total and what stays',
      () async {
        final invoice = testInvoice();
        final result = await usecase.execute(invoice);
        final quote = switch (result) {
          Ok(:final value) => value,
          Err() => throw StateError('refused'),
        };
        expect(quote.invoice, same(invoice));
        expect(quote.amount, Sats.fromInt(600));
        expect(quote.payin, Sats.fromInt(603));
        expect(quote.serviceFee, Sats.fromInt(3));
        expect(quote.serviceFeeBasisPoints, 50);
        expect(quote.networkFee, Sats.fromInt(26));
        expect(quote.total, Sats.fromInt(629));
        expect(quote.balance, Sats.fromInt(10000));
        expect(quote.remaining, Sats.fromInt(9371));
        expect(quote.quotedAt, testNow);
        // The service is asked the invoice's amount on its network, and the fee is estimated for the payin.
        expect(quotes.asked, [(RobosatsNetwork.mainnet, Sats.fromInt(600))]);
        expect(wallets.estimated, [Sats.fromInt(603)]);
      },
    );

    test('may leave nothing in the wallet', () async {
      wallets.wallet = _wallet(balance: 629);
      final result = await usecase.execute(testInvoice());
      expect(result, isA<Ok<P2pWalletQuote, P2pWalletRefusal>>());
      expect(
        (result as Ok<P2pWalletQuote, P2pWalletRefusal>).value.remaining,
        Sats.zero,
      );
    });
  });

  group('refused before the service is asked:', () {
    test('an expired invoice', () async {
      for (final expiresIn in [Duration.zero, const Duration(seconds: -1)]) {
        expect(
          refusalOf(await usecase.execute(testInvoice(expiresIn: expiresIn))),
          isA<P2pWalletInvoiceExpired>(),
        );
      }
      expect(wallets.reads, 0);
      expect(quotes.asked, isEmpty);
    });

    test('no Instant Payments wallet, or one that cannot be read', () async {
      for (final refusal in const [
        P2pWalletNoInstantWallet(),
        P2pWalletUnavailable(),
      ]) {
        wallets.readError = refusal;
        expect(refusalOf(await usecase.execute(testInvoice())), same(refusal));
      }
      expect(quotes.asked, isEmpty);
    });

    test('an invoice of the other network', () async {
      expect(
        refusalOf(
          await usecase.execute(testInvoice(network: RobosatsNetwork.testnet)),
        ),
        isA<P2pWalletWrongNetwork>(),
      );
      wallets.wallet = _wallet(isTestnet: true);
      expect(
        refusalOf(await usecase.execute(testInvoice())),
        isA<P2pWalletWrongNetwork>(),
      );
      expect(
        await usecase.execute(testInvoice(network: RobosatsNetwork.testnet)),
        isA<Ok<P2pWalletQuote, P2pWalletRefusal>>(),
      );
      expect(quotes.asked, [(RobosatsNetwork.testnet, Sats.fromInt(600))]);
    });

    test('a wallet that does not sign here', () async {
      wallets.wallet = _wallet(signsHere: false);
      expect(
        refusalOf(await usecase.execute(testInvoice())),
        isA<P2pWalletUnavailable>(),
      );
      expect(quotes.asked, isEmpty);
    });

    test('a balance under the invoice', () async {
      wallets.wallet = _wallet(balance: 599);
      expect(
        refusalOf(await usecase.execute(testInvoice())),
        isA<P2pWalletNotEnoughBalance>()
            .having((r) => r.available, 'available', Sats.fromInt(599))
            .having((r) => r.needed, 'needed', Sats.fromInt(600)),
      );
      expect(quotes.asked, isEmpty);
    });
  });

  group('refused after the service answered:', () {
    test('its own refusal, as it is', () async {
      final refusal = P2pWalletUnderMinimum(minimum: Sats.fromInt(1000));
      quotes.answer = Err(refusal);
      expect(refusalOf(await usecase.execute(testInvoice())), same(refusal));
      expect(wallets.estimated, isEmpty);
    });

    test('a balance under the payin', () async {
      wallets.wallet = _wallet(balance: 602);
      expect(
        refusalOf(await usecase.execute(testInvoice())),
        isA<P2pWalletNotEnoughBalance>()
            .having((r) => r.available, 'available', Sats.fromInt(602))
            .having((r) => r.needed, 'needed', Sats.fromInt(603)),
      );
      expect(wallets.estimated, isEmpty);
    });

    test('a balance under the payin and the network fee', () async {
      wallets.wallet = _wallet(balance: 628);
      expect(
        refusalOf(await usecase.execute(testInvoice())),
        isA<P2pWalletNotEnoughBalance>()
            .having((r) => r.available, 'available', Sats.fromInt(628))
            .having((r) => r.needed, 'needed', Sats.fromInt(629)),
      );
    });

    test('the wallet\'s refusal to build the payment', () async {
      for (final refusal in [
        const P2pWalletNeedsConsolidation(),
        const P2pWalletUnavailable(),
        P2pWalletNotEnoughBalance(
          available: Sats.fromInt(10000),
          needed: Sats.fromInt(603),
        ),
      ]) {
        wallets.feeError = refusal;
        expect(refusalOf(await usecase.execute(testInvoice())), same(refusal));
      }
    });
  });

  group('the balance', () {
    test('is given at once, then at each sync that changes it', () async {
      final watch = WatchInstantBalanceUsecase(wallets);
      final seen = <Result<Sats, P2pWalletRefusal>>[];
      final subscription = watch
          .execute(RobosatsNetwork.mainnet)
          .listen(seen.add);
      await pumpEventQueue();
      wallets.syncs.add(_wallet(balance: 10000));
      wallets.syncs.add(_wallet(balance: 9371));
      wallets.syncs.add(_wallet(balance: 9371));
      wallets.syncs.add(_wallet(balance: 9971));
      await pumpEventQueue();
      expect(seen.map(_sats), [10000, 9371, 9971]);
      expect(wallets.watched, ['instant']);
      await subscription.cancel();
    });

    test('stops following the syncs at once when cancelled', () async {
      final watch = WatchInstantBalanceUsecase(wallets);
      final subscription = watch
          .execute(RobosatsNetwork.mainnet)
          .listen((_) {});
      await pumpEventQueue();
      expect(wallets.syncs.hasListener, isTrue);
      // An `async*` body waiting for the next sync would not end here until one came.
      await subscription.cancel().timeout(const Duration(seconds: 1));
      expect(wallets.syncs.hasListener, isFalse);
    });

    test('skips a sync that fails, and gives the next one', () async {
      final watch = WatchInstantBalanceUsecase(wallets);
      final seen = <Result<Sats, P2pWalletRefusal>>[];
      final subscription = watch
          .execute(RobosatsNetwork.mainnet)
          .listen(seen.add);
      await pumpEventQueue();
      wallets.syncs
        ..addError(StateError('sync failed'))
        ..add(_wallet(balance: 42));
      await pumpEventQueue();
      expect(seen.map(_sats), [10000, 42]);
      await subscription.cancel();
    });

    test('ends on a refusal', () async {
      final watch = WatchInstantBalanceUsecase(wallets);
      wallets.readError = const P2pWalletNoInstantWallet();
      expect(await watch.execute(RobosatsNetwork.mainnet).toList(), [
        isA<Err<Sats, P2pWalletRefusal>>().having(
          (err) => err.failure,
          'failure',
          isA<P2pWalletNoInstantWallet>(),
        ),
      ]);
      wallets
        ..readError = null
        ..wallet = _wallet(isTestnet: true);
      expect(await watch.execute(RobosatsNetwork.mainnet).toList(), [
        isA<Err<Sats, P2pWalletRefusal>>().having(
          (err) => err.failure,
          'failure',
          isA<P2pWalletWrongNetwork>(),
        ),
      ]);
      expect(wallets.watched, isEmpty);
    });
  });
}

int _sats(Result<Sats, P2pWalletRefusal> result) => switch (result) {
  Ok(:final value) => value.value.toInt(),
  Err() => -1,
};

InstantWallet _wallet({
  int balance = 10000,
  bool isTestnet = false,
  bool signsHere = true,
}) => InstantWallet(
  id: 'instant',
  balance: Sats.fromInt(balance),
  isTestnet: isTestnet,
  signsHere: signsHere,
);

final class _Wallets implements InstantWalletRepository {
  InstantWallet wallet = _wallet();
  P2pWalletRefusal? readError;
  P2pWalletRefusal? feeError;
  int fee = 26;
  int reads = 0;
  final List<Sats> estimated = [];
  final List<String> watched = [];
  final StreamController<InstantWallet> syncs = StreamController.broadcast();

  @override
  Future<Result<InstantWallet, P2pWalletRefusal>> read() async {
    reads++;
    if (readError case final refusal?) return Err(refusal);
    return Ok(wallet);
  }

  @override
  Stream<InstantWallet> watchSyncs(String walletId) {
    watched.add(walletId);
    return syncs.stream;
  }

  @override
  Future<Result<Sats, P2pWalletRefusal>> estimateNetworkFee(
    InstantWallet wallet,
    Sats amount,
  ) async {
    estimated.add(amount);
    if (feeError case final refusal?) return Err(refusal);
    return Ok(Sats.fromInt(fee));
  }
}

final class _Quotes implements LightningSwapQuoteRepository {
  Result<LightningSwapQuote, P2pWalletRefusal> answer = Ok(
    LightningSwapQuote(payin: Sats.fromInt(603), feeBasisPoints: 50),
  );
  final List<(RobosatsNetwork, Sats)> asked = [];

  @override
  Future<Result<LightningSwapQuote, P2pWalletRefusal>> quote({
    required RobosatsNetwork network,
    required Sats amount,
  }) async {
    asked.add((network, amount));
    return answer;
  }
}
