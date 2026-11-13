import 'package:bb_mobile/core/fees/domain/fees_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/liquid_wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/consolidation_required_exception.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/insufficient_funds_exception.dart';
import 'package:bb_mobile/core/wallet/domain/no_spendable_utxo_exception.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_address_at_index_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/watch_finished_wallet_syncs_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/wallet_failure.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/entities/instant_wallet.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/instant_wallet_repository.dart';
import 'package:p2p/p2p.dart';

/// The Instant Payments wallet, through the wallet readers that the Pay, Sell and Autoswap features use.
///
/// The one boundary where the wallet's failures and exceptions become the port's refusals, without their text. This class logs nothing; on this path the wallet's own code logs, at the `info` level (debug console only), the absolute fee of each transaction it builds (`LwkWalletDatasource.buildPset`), and at `severe` the type of a failure to read the settings (`GetWalletsUsecase`).
class InstantWalletRepositoryImpl implements InstantWalletRepository {
  /// The rate of every Liquid send of the wallet, 0.1 sat/vB (25 sat/kwu), the network's minimum relay fee, as the Pay and Autoswap features price a payin.
  static const _liquidFeeRate = RelativeFee(25);

  final GetWalletsUsecase _getWallets;
  final WatchFinishedWalletSyncsUsecase _watchSyncs;
  final GetAddressAtIndexUsecase _getAddressAtIndex;
  final LiquidWalletRepository _liquid;

  const InstantWalletRepositoryImpl(
    this._getWallets,
    this._watchSyncs,
    this._getAddressAtIndex,
    this._liquid,
  );

  @override
  Future<Result<InstantWallet, P2pWalletRefusal>> read() async {
    final Result<List<Wallet>, WalletFailure> wallets;
    try {
      wallets = await _getWallets.execute(onlyDefaults: true, onlyLiquid: true);
    } catch (_) {
      return const Err(P2pWalletUnavailable());
    }
    switch (wallets) {
      case Err(failure: NoWalletsFoundFailure()):
        return const Err(P2pWalletNoInstantWallet());
      case Err():
        return const Err(P2pWalletUnavailable());
      case Ok(:final value):
        final wallet = value
            .where((wallet) => wallet.isDefault && wallet.isLiquid)
            .firstOrNull;
        if (wallet == null) return const Err(P2pWalletNoInstantWallet());
        return switch (_instant(wallet)) {
          final instant? => Ok(instant),
          null => const Err(P2pWalletUnavailable()),
        };
    }
  }

  @override
  Stream<Result<InstantWallet, P2pWalletRefusal>> watchSyncs(
    String walletId,
  ) =>
      // Plain operators, not an `async*` body: a cancellation must reach the wallet's stream at once.
      _watchSyncs
          .execute(walletId: walletId)
          .map<Result<InstantWallet, P2pWalletRefusal>?>(
            (wallet) => !wallet.isDefault || !wallet.isLiquid
                ? const Err(P2pWalletUnavailable())
                : switch (_instant(wallet)) {
                    final instant? => Ok(instant),
                    null => null,
                  },
          )
          .where((result) => result != null)
          .cast<Result<InstantWallet, P2pWalletRefusal>>();

  @override
  Future<Result<Sats, P2pWalletRefusal>> estimateNetworkFee(
    InstantWallet wallet,
    Sats amount,
  ) async {
    try {
      // An address of the wallet itself, derived and not revealed: the Pay feature's stand-in for a payin address that does not exist yet.
      final address = await _getAddressAtIndex.execute(
        walletId: wallet.id,
        index: 0,
      );
      final pset = await _liquid.buildPset(
        walletId: wallet.id,
        address: address.address,
        amountSat: amount.value.toInt(),
        feeRate: _liquidFeeRate,
      );
      final (_, fee) = await _liquid.getPsetSizeAndAbsoluteFees(pset: pset);
      if (fee < 0) return const Err(P2pWalletUnavailable());
      return Ok(Sats.fromInt(fee));
    } on InsufficientFundsException {
      return Err(_short(wallet, amount));
    } on NoSpendableUtxoException {
      return Err(_short(wallet, amount));
    } on ConsolidationRequiredException {
      return const Err(P2pWalletNeedsConsolidation());
    } catch (_) {
      return const Err(P2pWalletUnavailable());
    }
  }

  /// The wallet cannot cover [amount] and its fee: it needs at least [amount], and more than it has.
  static P2pWalletNotEnoughBalance _short(InstantWallet wallet, Sats amount) {
    final atLeast = wallet.balance.value + BigInt.one;
    return P2pWalletNotEnoughBalance(
      available: wallet.balance,
      needed: Sats(amount.value > atLeast ? amount.value : atLeast),
    );
  }

  /// The wallet as the port reads it, or `null` for a balance the wallet should never hold.
  static InstantWallet? _instant(Wallet wallet) => wallet.balanceSat.isNegative
      ? null
      : InstantWallet(
          id: wallet.id,
          balance: Sats(wallet.balanceSat),
          isTestnet: wallet.isTestnet,
          signsHere: wallet.signsLocally && !wallet.isHardwareWallet,
        );
}
