import 'package:bb_mobile/features/p2p_wallet/domain/usecases/read_wallet_rate_usecase.dart';
import 'package:bull_pricer/bull_pricer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';
import 'package:primitives/primitives.dart' show BitcoinNetwork;

/// The wallet's own price of a bitcoin for the P2P feature (#180): over a pricer the test plays, never the price service.
void main() {
  final fetchedAt = DateTime.utc(2026, 11, 17, 12);
  RobosatsCurrency currency(String code) =>
      RobosatsCurrency.fromCode(code) ?? (throw StateError('no $code'));

  test(
    'each currency the wallet prices is asked of its pricer, on the trade\'s network, and the price given as read',
    () async {
      final asked = <(BitcoinNetwork, SupportedCurrency)>[];
      final usecase = ReadWalletRateUsecase(({
        required network,
        required currency,
      }) async {
        asked.add((network, currency));
        return Ok(
          BitcoinPrice(
            currency: currency,
            fiatAmount: 71657,
            fetchedAt: fetchedAt,
          ),
        );
      });
      // The wallet's list, `SupportedCurrency` of `packages/bull_pricer`, written out: a change of it changes the rule's reference.
      for (final code in ['USD', 'CAD', 'MXN', 'CRC', 'EUR', 'ARS', 'COP']) {
        final rate = await usecase.execute(
          RobosatsNetwork.mainnet,
          currency(code),
        );
        expect(
          rate,
          isA<P2pWalletRateRead>().having((r) => r.price, 'price', 71657),
          reason: code,
        );
      }
      expect(SupportedCurrency.codes, [
        'USD',
        'CAD',
        'MXN',
        'CRC',
        'EUR',
        'ARS',
        'COP',
      ]);
      expect(asked.map((a) => a.$1).toSet(), {BitcoinNetwork.mainnet});
      expect(asked.map((a) => a.$2.code), [
        'USD',
        'CAD',
        'MXN',
        'CRC',
        'EUR',
        'ARS',
        'COP',
      ]);
      final _ = await usecase.execute(RobosatsNetwork.testnet, currency('EUR'));
      expect(asked.last.$1, BitcoinNetwork.testnet);
    },
  );

  test(
    'a currency the wallet does not price: not priced, and nothing asked',
    () async {
      var asked = 0;
      final usecase = ReadWalletRateUsecase(({
        required network,
        required currency,
      }) async {
        asked++;
        return const Err(PricerNetworkFailure());
      });
      for (final code in ['GBP', 'BRL', 'XAU', 'BTC']) {
        expect(
          await usecase.execute(RobosatsNetwork.mainnet, currency(code)),
          isA<P2pWalletRateNotPriced>(),
          reason: code,
        );
      }
      expect(asked, 0);
    },
  );

  test('a price that cannot be read: unavailable, whatever failed', () async {
    for (final failure in <PricerFailure>[
      const PricerNetworkFailure(),
      const PricerRateLimitedFailure(),
      const PricerUnexpectedFailure(),
      const PricerUnsupportedNetworkFailure(),
    ]) {
      final usecase = ReadWalletRateUsecase(
        ({required network, required currency}) async => Err(failure),
      );
      expect(
        await usecase.execute(RobosatsNetwork.mainnet, currency('USD')),
        isA<P2pWalletRateUnavailable>(),
        reason: '$failure',
      );
    }
    final throwing = ReadWalletRateUsecase(
      ({required network, required currency}) async =>
          throw const FormatException('no price'),
    );
    expect(
      await throwing.execute(RobosatsNetwork.mainnet, currency('USD')),
      isA<P2pWalletRateUnavailable>(),
    );
  });
}
