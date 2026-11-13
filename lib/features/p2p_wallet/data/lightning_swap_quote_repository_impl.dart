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
        // The fee rate the service lists is left out: the fee is the payin less the amount. The currencies are not compared either: the code holds no value of the service's for Lightning's, and the networks of the quote are the ones asked.
        if (value.outAmountSat != amount.value ||
            value.inAmountSat < amount.value) {
          return const Err(P2pWalletServiceRefused());
        }
        return Ok(LightningSwapQuote(payin: Sats(value.inAmountSat)));
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
      retryAfter: _wait(retryAfter),
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

  /// The most bitcoin there can be, in sats: a limit above it, or below zero, is not one to show.
  static final _maxSats = BigInt.from(2100000000000000);

  /// The longest wait the port passes on: the service's `Retry-After` is any integer.
  static const _maxWait = Duration(minutes: 10);

  static Sats? _sats(BigInt? value) =>
      value == null || value.isNegative || value > _maxSats
      ? null
      : Sats(value);

  static Duration? _wait(Duration? value) => switch (value) {
    null => null,
    final wait when wait.isNegative => null,
    final wait when wait > _maxWait => _maxWait,
    final wait => wait,
  };
}
