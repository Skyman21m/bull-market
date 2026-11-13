import 'package:bb_mobile/core/primitives/payment_network.dart';
import 'package:bb_mobile/features/p2p_wallet/data/lightning_swap_quote_repository_impl.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/entities/lightning_swap_quote.dart';
import 'package:bb_mobile/features/swap/public/swap_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';

import 'support/fakes.dart';

/// The swap service's quote through the Swap feature's facade (a fake: no test reaches the service), and every failure of that facade as a refusal of the port.
void main() {
  late FakeSwapFacade swaps;
  late LightningSwapQuoteRepositoryImpl repository;

  setUp(() {
    swaps = FakeSwapFacade(FakeSwapFacade.quoteOf());
    repository = LightningSwapQuoteRepositoryImpl(swaps);
  });

  Future<Result<LightningSwapQuote, P2pWalletRefusal>> ask({
    RobosatsNetwork network = RobosatsNetwork.mainnet,
    int amount = 600,
  }) => repository.quote(network: network, amount: Sats.fromInt(amount));

  test(
    'asks the amount paid out, Liquid to Lightning, on the invoice\'s network',
    () async {
      final answer = await ask();
      expect(
        answer,
        isA<Ok<LightningSwapQuote, P2pWalletRefusal>>().having(
          (ok) => (ok.value.payin, ok.value.feeBasisPoints),
          'payin and rate',
          (Sats.fromInt(603), 50),
        ),
      );
      await ask(network: RobosatsNetwork.testnet, amount: 400);
      expect(swaps.quotes, [
        (
          environment: OrderSwapEnvironment.mainnet,
          amountSat: BigInt.from(600),
          isInAmountFixed: false,
          inNetwork: OrderSwapNetwork.liquid,
          outNetwork: OrderSwapNetwork.lightning,
        ),
        (
          environment: OrderSwapEnvironment.testnet,
          amountSat: BigInt.from(400),
          isInAmountFixed: false,
          inNetwork: OrderSwapNetwork.liquid,
          outNetwork: OrderSwapNetwork.lightning,
        ),
      ]);
    },
  );

  test('refuses an answer that does not quote the invoice\'s amount', () async {
    for (final (label, answer) in [
      ('pays out less', FakeSwapFacade.quoteOf(out: 599)),
      ('pays out more', FakeSwapFacade.quoteOf(out: 601)),
      ('asks a payin below the amount', FakeSwapFacade.quoteOf(payin: 599)),
      ('a negative rate', FakeSwapFacade.quoteOf(basisPoints: -1)),
    ]) {
      swaps.answer = answer;
      expect(
        await ask(),
        isA<Err<LightningSwapQuote, P2pWalletRefusal>>().having(
          (err) => err.failure,
          'failure',
          isA<P2pWalletServiceRefused>(),
        ),
        reason: label,
      );
    }
    swaps.answer = FakeSwapFacade.quoteOf(payin: 600, basisPoints: 0);
    expect(await ask(), isA<Ok<LightningSwapQuote, P2pWalletRefusal>>());
  });

  group('maps each failure of the Swap feature', () {
    // `ERR_ORD_LMT001`, as `OrderSwapRepositoryImpl` reads it: the limit of `messageData` in sats, and its operator for the side.
    test('a limit, with the number the service gives', () {
      expect(
        LightningSwapQuoteRepositoryImpl.refusalOf(
          SwapAmountOutOfBoundsFailure(
            limitAmountSat: BigInt.from(1000),
            isMinimum: true,
            logMessage: 'Amount too low',
          ),
        ),
        isA<P2pWalletUnderMinimum>().having(
          (r) => r.minimum,
          'minimum',
          Sats.fromInt(1000),
        ),
      );
      expect(
        LightningSwapQuoteRepositoryImpl.refusalOf(
          SwapAmountOutOfBoundsFailure(
            limitAmountSat: BigInt.from(5000000),
            isMinimum: false,
          ),
        ),
        isA<P2pWalletOverMaximum>().having(
          (r) => r.maximum,
          'maximum',
          Sats.fromInt(5000000),
        ),
      );
      expect(
        LightningSwapQuoteRepositoryImpl.refusalOf(
          const SwapAmountOutOfBoundsFailure(isMinimum: true),
        ),
        isA<P2pWalletUnderMinimum>().having((r) => r.minimum, 'minimum', null),
      );
      expect(
        LightningSwapQuoteRepositoryImpl.refusalOf(
          SwapAmountOutOfBoundsFailure(
            limitAmountSat: BigInt.from(-1),
            isMinimum: false,
          ),
        ),
        isA<P2pWalletOverMaximum>().having((r) => r.maximum, 'maximum', null),
      );
      // No operator: the side is unknown, and the limit is not guessed into one.
      expect(
        LightningSwapQuoteRepositoryImpl.refusalOf(
          SwapAmountOutOfBoundsFailure(limitAmountSat: BigInt.from(1000)),
        ),
        isA<P2pWalletOutsideServiceLimits>(),
      );
    });

    test('a wait the service asks', () {
      expect(
        LightningSwapQuoteRepositoryImpl.refusalOf(
          const SwapRateLimitedFailure(retryAfter: Duration(seconds: 12)),
        ),
        isA<P2pWalletServiceBusy>().having(
          (r) => r.retryAfter,
          'retryAfter',
          const Duration(seconds: 12),
        ),
      );
      expect(
        LightningSwapQuoteRepositoryImpl.refusalOf(
          const SwapRateLimitedFailure(),
        ),
        isA<P2pWalletServiceBusy>().having(
          (r) => r.retryAfter,
          'retryAfter',
          null,
        ),
      );
    });

    test('a service out of reach', () {
      for (final failure in const [
        SwapNetworkFailure('HTTP 503'),
        SwapTimeoutFailure('receive timeout'),
      ]) {
        expect(
          LightningSwapQuoteRepositoryImpl.refusalOf(failure),
          isA<P2pWalletServiceUnreachable>(),
          reason: '$failure',
        );
      }
    });

    test('everything else, as a refusal of the service', () {
      for (final failure in const <SwapFailure>[
        SwapNoPaymentOptionFailure(
          inNetwork: PaymentNetwork.liquid,
          outNetwork: PaymentNetwork.lightning,
        ),
        SwapValidationFailure(field: 'amount'),
        SwapProviderFailure('App update required'),
        SwapUnexpectedFailure('Missing RPC result'),
        SwapOrderNotFoundFailure(),
        SwapOrderExpiredFailure(),
        SwapCreationUnknownFailure(),
        SwapOrderMismatchFailure(),
        SwapInvalidStateFailure(),
        SwapStorageFailure(),
        SwapPriceUnavailableFailure(),
      ]) {
        expect(
          LightningSwapQuoteRepositoryImpl.refusalOf(failure),
          isA<P2pWalletServiceRefused>(),
          reason: '$failure',
        );
      }
    });

    test('through a quote, with no text of the service', () async {
      swaps.answer = const Err(SwapTimeoutFailure('connection timeout'));
      final answer = await ask();
      final refusal = switch (answer) {
        Err(:final failure) => failure,
        Ok() => throw StateError('quoted'),
      };
      expect(refusal, isA<P2pWalletServiceUnreachable>());
      expect(refusal.logMessage, isNull);
      expect('$refusal', 'P2pWalletServiceUnreachable');
    });
  });
}
