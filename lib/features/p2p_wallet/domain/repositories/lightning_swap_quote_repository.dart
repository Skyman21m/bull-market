import 'package:bb_mobile/features/p2p_wallet/domain/entities/lightning_swap_quote.dart';
import 'package:meta/meta.dart';
import 'package:p2p/p2p.dart';

/// The swap service's quotes for paying Lightning from Liquid, through the Swap feature's facade.
abstract interface class LightningSwapQuoteRepository {
  /// The service's quote for paying exactly [amount] over Lightning from Liquid on [network].
  ///
  /// It sends the service the amount and the route, nothing else, and creates nothing there.
  /// An answer that does not quote exactly [amount], or asks a payin below it, is [P2pWalletServiceRefused].
  @useResult
  Future<Result<LightningSwapQuote, P2pWalletRefusal>> quote({
    required RobosatsNetwork network,
    required Sats amount,
  });
}
