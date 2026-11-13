import 'package:bb_mobile/features/p2p_wallet/domain/entities/lightning_swap_quote.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/lightning_swap_quote_repository.dart';
import 'package:bb_mobile/features/swap/public/swap_facade.dart';
import 'package:p2p/p2p.dart';

/// The swap service's quotes, asked through the Swap feature's facade, as the wallet's send screen asks them for a Lightning invoice (`GetSendSwapQuoteUsecase`).
///
/// `SwapFacade.getQuote` sends the service's `getBestSwapOption` the amount, `isInAmountFixed` and the two networks, over the wallet's own connection to the service: it writes no record and creates no order (`createOrderSwap` is another call).
/// This class logs nothing; the Swap feature logs the quote's environment, route and amount at the `info` level (debug console only) and the type of a failure at the `warning` level.
class LightningSwapQuoteRepositoryImpl implements LightningSwapQuoteRepository {
  final SwapFacade _swaps;

  const LightningSwapQuoteRepositoryImpl(this._swaps);

  @override
  Future<Result<LightningSwapQuote, P2pWalletRefusal>> quote({
    required RobosatsNetwork network,
    required Sats amount,
  }) async {
    final answer = await _swaps.getQuote(
      environment: switch (network) {
        RobosatsNetwork.mainnet => OrderSwapEnvironment.mainnet,
        RobosatsNetwork.testnet => OrderSwapEnvironment.testnet,
      },
      amountSat: amount.value,
      // The invoice's amount is what the service pays out; it adds its fee to the payin.
      isInAmountFixed: false,
      inNetwork: OrderSwapNetwork.liquid,
      outNetwork: OrderSwapNetwork.lightning,
    );
    switch (answer) {
      case Ok(:final value):
        if (value.outAmountSat != amount.value ||
            value.inAmountSat < amount.value ||
            value.feeBasisPoints < 0) {
          return const Err(P2pWalletServiceRefused());
        }
        return Ok(
          LightningSwapQuote(
            payin: Sats(value.inAmountSat),
            feeBasisPoints: value.feeBasisPoints,
          ),
        );
      case Err(:final failure):
        return Err(refusalOf(failure));
    }
  }

  /// The port's refusal for a failure of the Swap feature: its limit and wait carried as numbers, never its text.
  static P2pWalletRefusal refusalOf(SwapFailure failure) => switch (failure) {
    // `ERR_ORD_LMT001`: the service's `messageData.limit`, and its operator for the side.
    SwapAmountOutOfBoundsFailure(isMinimum: true, :final limitAmountSat) =>
      P2pWalletUnderMinimum(minimum: _sats(limitAmountSat)),
    SwapAmountOutOfBoundsFailure(isMinimum: false, :final limitAmountSat) =>
      P2pWalletOverMaximum(maximum: _sats(limitAmountSat)),
    SwapAmountOutOfBoundsFailure(isMinimum: null) =>
      const P2pWalletOutsideServiceLimits(),
    SwapRateLimitedFailure(:final retryAfter) => P2pWalletServiceBusy(
      retryAfter: retryAfter,
    ),
    SwapNetworkFailure() ||
    SwapTimeoutFailure() => const P2pWalletServiceUnreachable(),
    // A refused route, a request or answer the service or the wallet found invalid, « app update required » (HTTP 418), and what a quote cannot meet (the order failures, the store, the price).
    SwapNoPaymentOptionFailure() ||
    SwapValidationFailure() ||
    SwapProviderFailure() ||
    SwapUnexpectedFailure() ||
    SwapOrderNotFoundFailure() ||
    SwapOrderExpiredFailure() ||
    SwapCreationUnknownFailure() ||
    SwapOrderMismatchFailure() ||
    SwapInvalidStateFailure() ||
    SwapStorageFailure() ||
    SwapPriceUnavailableFailure() => const P2pWalletServiceRefused(),
  };

  static Sats? _sats(BigInt? value) =>
      value == null || value.isNegative ? null : Sats(value);
}
