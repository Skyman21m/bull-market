import 'package:bull_pricer/bull_pricer.dart';
import 'package:meta/meta.dart';
import 'package:p2p/p2p.dart';
import 'package:primitives/primitives.dart' show BitcoinNetwork;

/// The wallet's own price of one bitcoin in an order's currency (#180), for the P2P feature's payment rule of an order made here (the owner's decision of 2026-11-17): the price the wallet's home screen shows the balance with, from the pricer the wallet's own features read (`Pricer.getIndexPrice`, as `GetBitcoinPriceUsecase` of the Bitcoin Price feature reads it), never the coordinator's.
///
/// A currency the price service does not quote (`SupportedCurrency`: USD, CAD, MXN, CRC, EUR, ARS and COP) is [P2pWalletRateNotPriced] without a request. The trade's network picks the price service's host (testnet's on testnet), as the wallet's settings pick it for its own screens. Any failure of the pricer, an exception it throws included, is [P2pWalletRateUnavailable]: nothing is logged, since the currency would say which order the user is about to pay.
/// What reaches the price service is the pricer's own request, unless its one-minute cache holds the price: an HTTPS POST over clearnet to Bull Bitcoin's public price API, `getRate` from BTC to the currency's code (the owner accepted this request outside Tor on 2026-11-17, as the wallet already makes it).
/// How long it waits is the pricer's bound, not one of its own: 10 s for the connection, the send and the answer, and 10 s in all (`_timeout`, `packages/bull_pricer/lib/src/data/datasources/pricer_api_datasource.dart:16`, `:55-57`, `:85`), plus up to 2 s for its cache's database (`PRAGMA busy_timeout = 2000`, `packages/bull_pricer/lib/src/data/pricer_database.dart:42`); the screen meanwhile says the fees are being asked. Only an `Exception` is caught: an `Error` of the pricer (`Pricer.init` not called, a price the pricer's own entity refuses) is a bug and goes on, as `AGENTS.md` rule 11 says.
class ReadWalletRateUsecase {
  final IndexPriceReader _indexPrice;

  const ReadWalletRateUsecase(this._indexPrice);

  @useResult
  Future<P2pWalletBitcoinRate> execute(
    RobosatsNetwork network,
    RobosatsCurrency currency,
  ) async {
    final supported = SupportedCurrency.tryFromCode(currency.code);
    if (supported == null) return const P2pWalletRateNotPriced();
    final Result<BitcoinPrice, PricerFailure> price;
    try {
      price = await _indexPrice(
        network: switch (network) {
          RobosatsNetwork.mainnet => BitcoinNetwork.mainnet,
          RobosatsNetwork.testnet => BitcoinNetwork.testnet,
        },
        currency: supported,
      );
    } on Exception {
      return const P2pWalletRateUnavailable();
    }
    return switch (price) {
      Ok(value: BitcoinPrice(:final fiatAmount))
          when fiatAmount.isFinite && fiatAmount > 0 =>
        P2pWalletRateRead(fiatAmount),
      _ => const P2pWalletRateUnavailable(),
    };
  }
}
