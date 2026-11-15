import 'package:bb_mobile/core/entities/signer_device_entity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_address.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_receive_address_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/wallet_failure.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/usecases/receive_wallet_address_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';

import 'support/fakes.dart';

/// A new address of the wallet's Bitcoin wallet for an on-chain payout (#90), over fakes of the wallet's readers.
void main() {
  late FakeGetWallets wallets;
  late _Addresses addresses;
  late ReceiveWalletAddressUsecase usecase;

  setUp(() {
    wallets = FakeGetWallets(
      Ok([testWallet(origin: 'secure', isLiquid: false)]),
    );
    addresses = _Addresses();
    usecase = ReceiveWalletAddressUsecase(wallets, addresses);
  });

  P2pWalletRefusal refusalOf(Result<P2pWalletAddress, P2pWalletRefusal> r) =>
      switch (r) {
        Ok() => throw StateError('given'),
        Err(:final failure) => failure,
      };

  test('is a new address of the default Bitcoin wallet, each time', () async {
    wallets.answer = Ok([
      testWallet(),
      testWallet(origin: 'other', isLiquid: false, isDefault: false),
      testWallet(origin: 'secure', isLiquid: false),
    ]);
    for (final expected in ['bc1qnew1', 'bc1qnew2']) {
      expect(
        await usecase.execute(RobosatsNetwork.mainnet),
        isA<Ok<P2pWalletAddress, P2pWalletRefusal>>().having(
          (ok) => ok.value.address,
          'address',
          expected,
        ),
      );
    }
    expect(addresses.calls, [
      (walletId: 'secure', generateNew: true),
      (walletId: 'secure', generateNew: true),
    ]);
    expect(wallets.calls.first.onlyDefaults, isTrue);
  });

  test('a hardware wallet gives its address too: it only receives', () async {
    wallets.answer = Ok([
      testWallet(
        origin: 'secure',
        isLiquid: false,
        signerDevice: SignerDeviceEntity.jade,
      ),
    ]);
    expect(await usecase.execute(RobosatsNetwork.mainnet), isA<Ok>());
  });

  test('on testnet, from a testnet wallet only', () async {
    expect(
      refusalOf(await usecase.execute(RobosatsNetwork.testnet)),
      isA<P2pWalletWrongNetwork>(),
    );
    wallets.answer = Ok([
      testWallet(origin: 'secure', isLiquid: false, isTestnet: true),
    ]);
    expect(await usecase.execute(RobosatsNetwork.testnet), isA<Ok>());
    expect(addresses.calls, hasLength(1));
  });

  test('says when there is no Bitcoin wallet', () async {
    for (final answer in <Result<List<Wallet>, WalletFailure>>[
      const Err(NoWalletsFoundFailure()),
      Ok([testWallet()]),
      Ok([testWallet(origin: 'secure', isLiquid: false, isDefault: false)]),
    ]) {
      wallets.answer = answer;
      expect(
        refusalOf(await usecase.execute(RobosatsNetwork.mainnet)),
        isA<P2pWalletNoBitcoinWallet>(),
      );
    }
    expect(addresses.calls, isEmpty);
  });

  test('says when the wallet cannot be read or give an address', () async {
    wallets.answer = const Err(WalletStorageFailure('locked'));
    expect(
      refusalOf(await usecase.execute(RobosatsNetwork.mainnet)),
      isA<P2pWalletUnavailable>(),
    );
    wallets
      ..answer = Ok([testWallet(origin: 'secure', isLiquid: false)])
      ..error = StateError('thrown');
    expect(
      refusalOf(await usecase.execute(RobosatsNetwork.mainnet)),
      isA<P2pWalletUnavailable>(),
    );
    wallets.error = null;
    for (final failing in [StateError('no metadata'), '']) {
      addresses.answer = failing;
      final refusal = refusalOf(await usecase.execute(RobosatsNetwork.mainnet));
      expect(refusal, isA<P2pWalletUnavailable>(), reason: '$failing');
      expect(refusal.logMessage, isNull);
    }
  });

  test('prints none of the address', () async {
    expect(const P2pWalletAddress('bc1qsecret').toString(), 'P2pWalletAddress');
  });
}

/// The wallet's receive address use case: a new address each call, or what the test says (an error thrown, or an empty address).
final class _Addresses implements GetReceiveAddressUsecase {
  Object? answer;
  final List<({String walletId, bool generateNew})> calls = [];

  @override
  Future<WalletAddress> execute({
    required String walletId,
    bool generateNew = false,
  }) async {
    calls.add((walletId: walletId, generateNew: generateNew));
    final given = answer;
    if (given is Error) throw given;
    return WalletAddress(
      walletId: walletId,
      index: calls.length,
      address: given is String ? given : 'bc1qnew${calls.length}',
      createdAt: testNow,
      updatedAt: testNow,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
