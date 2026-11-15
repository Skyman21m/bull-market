import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_receive_address_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/wallet_failure.dart';
import 'package:meta/meta.dart';
import 'package:p2p/p2p.dart';

/// A new address of the wallet's default Bitcoin wallet (« Secure Bitcoin ») for an on-chain payout (#90), as the wallet's Receive screen gives one with « New address » (`GetReceiveAddressUsecase`, `generateNew: true`).
///
/// A new address each time (owner's decision of 2026-11-15), so that the address given to a coordinator is one the user gave no one else. It reveals the next address of the wallet, creates nothing at any service and sends nothing; it is the one boundary where the wallet's failures become the port's refusals, without their text. It logs nothing.
class ReceiveWalletAddressUsecase {
  final GetWalletsUsecase _getWallets;
  final GetReceiveAddressUsecase _addresses;

  const ReceiveWalletAddressUsecase(this._getWallets, this._addresses);

  @useResult
  Future<Result<P2pWalletAddress, P2pWalletRefusal>> execute(
    RobosatsNetwork network,
  ) async {
    final Result<List<Wallet>, WalletFailure> wallets;
    try {
      wallets = await _getWallets.execute(
        onlyDefaults: true,
        onlyBitcoin: true,
      );
    } catch (_) {
      return const Err(P2pWalletUnavailable());
    }
    final Wallet wallet;
    switch (wallets) {
      case Err(failure: NoWalletsFoundFailure()):
        return const Err(P2pWalletNoBitcoinWallet());
      case Err():
        return const Err(P2pWalletUnavailable());
      case Ok(:final value):
        final found = value
            .where((wallet) => wallet.isDefault && wallet.isBitcoin)
            .firstOrNull;
        if (found == null) return const Err(P2pWalletNoBitcoinWallet());
        wallet = found;
    }
    if (wallet.isTestnet != (network == RobosatsNetwork.testnet)) {
      return const Err(P2pWalletWrongNetwork());
    }
    try {
      final address = await _addresses.execute(
        walletId: wallet.id,
        generateNew: true,
      );
      if (address.address.isEmpty) return const Err(P2pWalletUnavailable());
      return Ok(P2pWalletAddress(address.address));
    } catch (_) {
      return const Err(P2pWalletUnavailable());
    }
  }
}
