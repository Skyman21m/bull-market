import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:p2p/p2p.dart'
    show
        P2pGarageKeyPort,
        P2pGarageKeyRefusal,
        P2pGarageKeyRefusalReason,
        RobosatsNetwork;
import 'package:primitives/primitives.dart';
import 'package:secrets/secrets.dart';

/// The P2P feature's Garage Key, derived from the words of the default Bitcoin wallet (#81, design note `docs/design/garage-key-from-the-words.md` § 1, § 2): the one place of the app that calls `secret.derive.garageKey`, as the custody gate checks (file, class, method and shape of the call).
///
/// It finds the default wallet as the BIP85 use cases do (`DeriveNextBip85HexFromDefaultWalletUsecase`: the default Bitcoin wallets of an environment, the first one, its secret fetched by its fingerprint), the environment being the one of the network asked, which the P2P tab takes from the wallet's own setting: so a testnet key comes from the testnet wallet's words, and never from the mainnet one's.
/// It never calls `secret.derive.bip85`, whose `hex` gives 32 bytes of the same shape from another path, and never draws a key: every case where the words cannot give it is a [P2pGarageKeyRefusal].
/// It holds no key and logs nothing; `AppLocator.setupP2p` builds it under the same flag as the vault's Garage Key handle, so never in the WorkManager isolate, and hands it to `P2pFeature.setup` alone, never to a container.
final class DerivedGarageKeyAdapter implements P2pGarageKeyPort {
  final Secrets _secrets;

  /// The wallet's repository, resolved at the first derivation, once every part of the app is registered.
  final WalletRepository Function() _wallets;

  DerivedGarageKeyAdapter(this._secrets, this._wallets);

  @override
  Future<Result<GarageKeyMaterial, P2pGarageKeyRefusal>> garageKey(
    RobosatsNetwork network, {
    required int index,
  }) async {
    if (index < 0 || index > 0x7fffffff) {
      throw ArgumentError.value(
        index,
        'index',
        'must be between 0 and 0x7fffffff',
      );
    }
    final List<Wallet> wallets;
    switch (await _wallets().getWallets(
      onlyDefaults: true,
      onlyBitcoin: true,
      environment: _environmentOf(network),
    )) {
      case Ok(:final value):
        wallets = value;
      case Err():
        return const Err(
          P2pGarageKeyRefusal(P2pGarageKeyRefusalReason.unreadable),
        );
    }
    if (wallets.isEmpty) {
      return const Err(
        P2pGarageKeyRefusal(P2pGarageKeyRefusalReason.noDefaultWallet),
      );
    }
    final id = Fingerprint.tryParse(wallets.first.masterFingerprint);
    if (id == null) {
      return const Err(
        P2pGarageKeyRefusal(P2pGarageKeyRefusalReason.unreadable),
      );
    }
    final Secret secret;
    switch (await _secrets.fetch(id)) {
      case Ok(:final value):
        secret = value;
      case Err(:final failure):
        return Err(_refusalOf(failure));
    }
    return switch (await secret.derive.garageKey(
      network: _slotOf(network),
      index: index,
    )) {
      Ok(:final value) => Ok(value),
      Err(:final failure) => Err(_refusalOf(failure)),
    };
  }

  /// The environment of the wallet whose words give the key of [network].
  static Environment _environmentOf(RobosatsNetwork network) =>
      switch (network) {
        RobosatsNetwork.mainnet => Environment.mainnet,
        RobosatsNetwork.testnet => Environment.testnet,
      };

  /// The network step of the BIP85 path: `0'` for mainnet, `1'` for testnet.
  static GarageKeySlot _slotOf(RobosatsNetwork network) => switch (network) {
    RobosatsNetwork.mainnet => GarageKeySlot.mainnet,
    RobosatsNetwork.testnet => GarageKeySlot.testnet,
  };

  /// What a failure of the vault means for the Garage; none is ever a reason to draw a key.
  static P2pGarageKeyRefusal _refusalOf(SecretFailure failure) =>
      P2pGarageKeyRefusal(switch (failure) {
        PassphraseUnsupportedFailure() => P2pGarageKeyRefusalReason.passphrase,
        MnemonicRequiredFailure() => P2pGarageKeyRefusalReason.noWords,
        KeystoreLockedFailure() => P2pGarageKeyRefusalReason.locked,
        _ => P2pGarageKeyRefusalReason.unreadable,
      });
}
