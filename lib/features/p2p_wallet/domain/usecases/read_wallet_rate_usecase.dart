import 'package:bull_pricer/bull_pricer.dart';
import 'package:meta/meta.dart';
import 'package:p2p/p2p.dart';
import 'package:primitives/primitives.dart' show BitcoinNetwork;

/// The wallet's own price of one bitcoin in an order's currency (#180), for the P2P feature's payment rule of an order made here (the owner's decision of 2026-11-17): the price the wallet's home screen shows the balance with, from the pricer the wallet's own features read (`Pricer.getIndexPrice`, as `GetBitcoinPriceUsecase` of the Bitcoin Price feature reads it), never the coordinator's.
///
/// A currency the price service does not quote (`SupportedCurrency`: USD, CAD, MXN, CRC, EUR, ARS and COP) is [P2pWalletRateNotPriced] without a request. The trade's network picks the price service's host (testnet's on testnet), as the wallet's settings pick it for its own screens. Any failure of the pricer, an exception it throws included, is [P2pWalletRateUnavailable]: nothing is logged, since the currency would say which order the user is about to pay.
/// What reaches the price service is the pricer's own request, unless its one-minute cache holds the price: an HTTPS POST over clearnet to Bull Bitcoin's public price API, `getRate` from BTC to the currency's code (the owner accepted this request outside Tor on 2026-11-17, as the wallet already makes it). When it leaves: for the maker bond, just after the swap service's quote, which gives that service the bond's exact amount, and before the confirmation, so even when the user then goes back; in the P2P create form (#181), once the chosen coordinator's limits are read for the order's currency, before any robot exists, again for each other currency or coordinator chosen. Each « Retry » asks once more (a failure is not cached), but the pricer sends no new request while an earlier read of the same price runs (it joins it, `packages/bull_pricer/lib/src/data/pricer_repository.dart:49-51`) or while its cache holds a price under a minute old (`:21`, `:242-245`). Were one operator to see both the price service and the swap service, it could tie together the IP address, the bond's amount and the order's currency, the currency being what this request adds (an assumption of the security review of #180, not something the code establishes). The host is `api.bullbitcoin.com` (`api05.bullbitcoin.dev` on testnet), as `packages/bull_pricer/lib/src/data/datasources/pricer_api_datasource.dart:13-14` names it; the wallet's code names that same host « BullBitcoin API » (`bbApiUrl`, `lib/core/utils/constants.dart:85-86`), the base address of its exchange feature's clients (`lib/core/exchange/exchange_locator.dart:54`, `:81`, `:99`).
/// How long it waits is first the pricer's bound: 10 s for the connection, the send and the answer, and 10 s in all (`_timeout`, `packages/bull_pricer/lib/src/data/datasources/pricer_api_datasource.dart:16`, `:55-57`, `:85`), plus up to 2 s for its cache's database (`PRAGMA busy_timeout = 2000`, `packages/bull_pricer/lib/src/data/pricer_database.dart:42`); and [readBound] of its own, 15 s, in case a read never ends; the screen meanwhile says the fees are being asked. Only an `Exception` is caught: an `Error` of the pricer (`Pricer.init` not called, a price the pricer's own entity refuses) is a bug and goes on, as `AGENTS.md` rule 11 says.
class ReadWalletRateUsecase {
  /// The longest this waits for the pricer: above its own bounds (10 s for the request, 2 s for its cache, below), so that it only cuts a read that would never end; past it the price is [P2pWalletRateUnavailable] and the screen says « rate not checked » with « Retry » rather than staying on the quote (security review of #180, R5).
  static const readBound = Duration(seconds: 15);

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
      ).timeout(readBound);
    } on Exception {
      // A failure of the pricer, or no answer within [readBound] (a `TimeoutException`).
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
