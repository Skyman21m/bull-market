import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/wallet_failure.dart';
import 'package:bb_mobile/features/p2p_garage_key/derived_garage_key_adapter.dart';
import 'package:convert/convert.dart' show hex;
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart'
    show P2pGarageKeyRefusal, P2pGarageKeyRefusalReason, RobosatsNetwork;
import 'package:primitives/primitives.dart';
import 'package:secrets/secrets.dart';
import 'package:secrets/testing.dart';

/// The shell's adapter of the Garage Key derived from the words (#81, design note `docs/design/garage-key-from-the-words.md` § 1, § 2), over the real vault and the public test phrase « abandon ×11 about »: it gives the design note's vectors, so it calls `derive.garageKey` (BIP85's HEX child of the same words, which `derive.bip85.hex` gives, is other bytes), from the default wallet of the network's environment, and refuses, never draws, when the words cannot give a key.
void main() {
  const words = [
    'abandon',
    'abandon',
    'abandon',
    'abandon',
    'abandon',
    'abandon',
    'abandon',
    'abandon',
    'abandon',
    'abandon',
    'abandon',
    'about',
  ];
  const mainnet0 =
      'f7286792c19ad8ad15fe2ebd0f6af77d0ed73a583963a1029476084b1471b9fc';
  const mainnet1 =
      'a2f8f6a28eb4f267a3d415aa1f178a3ab8819bf8de21253f1077dc9e85f9f4a3';
  const testnet0 =
      '643a18b0fdad04fe3b5a02b5723884fbed7f2bc0a9da0cf70570fbe72d4d4215';

  late Secrets secrets;

  setUp(() {
    FakeSecureStoragePlatform().install();
    secrets = Secrets(scratchDirectory: () async => '.');
  });

  Future<Secret> stored({String? passphrase}) async =>
      switch (await secrets.import(words: words, passphrase: passphrase)) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };

  String hexOf(Result<GarageKeyMaterial, P2pGarageKeyRefusal> result) =>
      switch (result) {
        Ok(:final value) => hex.encode(value.bytes),
        Err(:final failure) => throw StateError('${failure.reason}'),
      };

  test(
    'it gives the vectors of the design note, per network and index',
    () async {
      final secret = await stored();
      final adapter = DerivedGarageKeyAdapter(
        secrets,
        () => _Wallets({
          Environment.mainnet: secret.id.hex,
          Environment.testnet: secret.id.hex,
        }),
      );
      expect(
        hexOf(await adapter.garageKey(RobosatsNetwork.mainnet, index: 0)),
        mainnet0,
      );
      expect(
        hexOf(await adapter.garageKey(RobosatsNetwork.mainnet, index: 1)),
        mainnet1,
      );
      expect(
        hexOf(await adapter.garageKey(RobosatsNetwork.testnet, index: 0)),
        testnet0,
      );
      // The other path of the same 32 bytes' shape, which the custody gate does not fence: not what the adapter gives.
      final bip85 = switch (await secret.derive.bip85.hex(
        numBytes: 32,
        index: 0,
      )) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };
      expect(bip85, isNot(mainnet0));
      expect(bip85, isNot(testnet0));
    },
  );

  test(
    'the environment is the network\'s: testnet asks the testnet wallet only',
    () async {
      final secret = await stored();
      final wallets = _Wallets({Environment.mainnet: secret.id.hex});
      final adapter = DerivedGarageKeyAdapter(secrets, () => wallets);
      expect(
        await adapter.garageKey(RobosatsNetwork.testnet, index: 0),
        isA<Err<GarageKeyMaterial, P2pGarageKeyRefusal>>().having(
          (err) => err.failure.reason,
          'reason',
          P2pGarageKeyRefusalReason.noDefaultWallet,
        ),
      );
      expect(wallets.asked, [Environment.testnet]);
    },
  );

  test('a passphrase is refused, and nothing is drawn or stored', () async {
    final secret = await stored(passphrase: 'TREZOR');
    final adapter = DerivedGarageKeyAdapter(
      secrets,
      () => _Wallets({Environment.mainnet: secret.id.hex}),
    );
    expect(
      await adapter.garageKey(RobosatsNetwork.mainnet, index: 0),
      isA<Err<GarageKeyMaterial, P2pGarageKeyRefusal>>().having(
        (err) => err.failure.reason,
        'reason',
        P2pGarageKeyRefusalReason.passphrase,
      ),
    );
  });

  test(
    'an index outside 0 … 2^31−1 is a bug, before any wallet is read',
    () async {
      final wallets = _Wallets(const {});
      final adapter = DerivedGarageKeyAdapter(secrets, () => wallets);
      for (final index in [-1, 0x80000000]) {
        expect(
          () => adapter.garageKey(RobosatsNetwork.mainnet, index: index),
          throwsArgumentError,
        );
      }
      expect(wallets.asked, isEmpty);
    },
  );
}

/// The default Bitcoin wallet of each environment given, by its secret's fingerprint; it records the environments asked.
final class _Wallets implements WalletRepository {
  final Map<Environment, String> defaults;
  final List<Environment?> asked = [];

  _Wallets(this.defaults);

  @override
  Future<Result<List<Wallet>, WalletFailure>> getWallets({
    Environment? environment,
    bool? onlyDefaults,
    bool? onlyBitcoin,
    bool? onlyLiquid,
    bool sync = false,
  }) async {
    asked.add(environment);
    final fingerprint = defaults[environment];
    return Ok([
      if (fingerprint != null && onlyDefaults == true && onlyBitcoin == true)
        Wallet(
          origin: 'default',
          label: 'Secure Bitcoin',
          network: environment == Environment.testnet
              ? Network.bitcoinTestnet
              : Network.bitcoinMainnet,
          isDefault: true,
          masterFingerprint: fingerprint,
          xpubFingerprint: fingerprint,
          scriptType: ScriptType.bip84,
          xpub: 'xpub',
          externalPublicDescriptor: 'desc',
          internalPublicDescriptor: 'desc',
          signer: SignerEntity.local,
          signerDevice: null,
          balanceSat: BigInt.zero,
        ),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
