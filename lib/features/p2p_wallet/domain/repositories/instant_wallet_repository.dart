import 'package:bb_mobile/features/p2p_wallet/domain/entities/instant_wallet.dart';
import 'package:meta/meta.dart';
import 'package:p2p/p2p.dart';

/// The wallet's Instant Payments wallet, read with the wallet's own readers: nothing here signs, broadcasts or creates anything.
abstract interface class InstantWalletRepository {
  /// The default Liquid wallet of the wallet's active network, from the wallet's records, without a sync.
  ///
  /// [P2pWalletNoInstantWallet] when there is none, [P2pWalletUnavailable] when the records cannot be read.
  @useResult
  Future<Result<InstantWallet, P2pWalletRefusal>> read();

  /// The wallet [walletId] each time the app finishes a sync of it; this starts no sync.
  ///
  /// [P2pWalletUnavailable] when a sync shows that wallet is no longer the default Liquid wallet (listening again reads the one that is). A sync whose wallet cannot be read gives nothing; the stream ends when the wallet's own stream of syncs does.
  Stream<Result<InstantWallet, P2pWalletRefusal>> watchSyncs(String walletId);

  /// The Liquid network fee of sending [amount] from [wallet], at the rate the wallet uses for every Liquid send.
  ///
  /// It is read from a transaction built and never signed nor broadcast, to the wallet's own first address, as the Pay feature prices a payin before its order exists.
  /// [P2pWalletNotEnoughBalance] when the wallet cannot cover [amount] and the fee, [P2pWalletNeedsConsolidation] when it holds too many coins, [P2pWalletUnavailable] for any other failure.
  @useResult
  Future<Result<Sats, P2pWalletRefusal>> estimateNetworkFee(
    InstantWallet wallet,
    Sats amount,
  );
}
