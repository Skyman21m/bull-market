import 'package:bb_mobile/core/entities/signer_device_entity.dart';
import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/wallet/domain/consolidation_required_exception.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/insufficient_funds_exception.dart';
import 'package:bb_mobile/core/wallet/domain/no_spendable_utxo_exception.dart';
import 'package:bb_mobile/core/wallet/domain/wallet_failure.dart';
import 'package:bb_mobile/features/p2p_wallet/data/instant_wallet_repository_impl.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/entities/instant_wallet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';

import 'support/fakes.dart';

/// The Instant Payments wallet through the wallet's own readers (fakes), and every failure of theirs as a refusal of the port.
void main() {
  late FakeGetWallets getWallets;
  late FakeWatchSyncs syncs;
  late FakeGetAddressAtIndex addresses;
  late FakeLiquidWallet liquid;
  late InstantWalletRepositoryImpl repository;

  setUp(() {
    getWallets = FakeGetWallets(Ok([testWallet()]));
    syncs = FakeWatchSyncs();
    addresses = FakeGetAddressAtIndex();
    liquid = FakeLiquidWallet();
    repository = InstantWalletRepositoryImpl(
      getWallets,
      syncs,
      addresses,
      liquid,
    );
  });

  tearDown(() => syncs.finished.close());

  P2pWalletRefusal refusalOf<T>(Result<T, P2pWalletRefusal> result) =>
      switch (result) {
        Err(:final failure) => failure,
        Ok() => throw StateError('not refused'),
      };

  InstantWallet walletOf(Result<InstantWallet, P2pWalletRefusal> result) =>
      switch (result) {
        Ok(:final value) => value,
        Err() => throw StateError('refused'),
      };

  group('read', () {
    test(
      'is the default Liquid wallet, its balance, network and signer',
      () async {
        getWallets.answer = Ok([
          testWallet(origin: 'secure', isLiquid: false, balance: 1),
          testWallet(origin: 'other', isDefault: false, balance: 2),
          testWallet(balance: 7777),
        ]);
        final wallet = walletOf(await repository.read());
        expect(wallet.id, 'instant');
        expect(wallet.balance, Sats.fromInt(7777));
        expect(wallet.isTestnet, isFalse);
        expect(wallet.signsHere, isTrue);
        // The wallet's records, without a sync: the port starts none.
        expect(getWallets.calls, [
          (onlyDefaults: true, onlyLiquid: true, sync: false),
        ]);
        getWallets.answer = Ok([testWallet(isTestnet: true)]);
        expect(walletOf(await repository.read()).isTestnet, isTrue);
      },
    );

    test('says when the wallet cannot pay without a device or a key', () async {
      for (final wallet in [
        testWallet(signer: SignerEntity.none),
        testWallet(signer: SignerEntity.remote),
        testWallet(signerDevice: SignerDeviceEntity.jade),
      ]) {
        getWallets.answer = Ok([wallet]);
        expect(walletOf(await repository.read()).signsHere, isFalse);
      }
    });

    test('refuses with no Instant Payments wallet', () async {
      for (final answer in <Result<List<Wallet>, WalletFailure>>[
        const Err(NoWalletsFoundFailure()),
        Ok([testWallet(isDefault: false)]),
        Ok([testWallet(isLiquid: false)]),
      ]) {
        getWallets.answer = answer;
        expect(
          refusalOf(await repository.read()),
          isA<P2pWalletNoInstantWallet>(),
        );
      }
    });

    test('refuses with records it cannot read', () async {
      getWallets.answer = const Err(WalletStorageFailure('locked'));
      expect(refusalOf(await repository.read()), isA<P2pWalletUnavailable>());
      getWallets.error = StateError('thrown');
      expect(refusalOf(await repository.read()), isA<P2pWalletUnavailable>());
      getWallets
        ..error = null
        ..answer = Ok([testWallet(balance: -1)]);
      expect(refusalOf(await repository.read()), isA<P2pWalletUnavailable>());
    });
  });

  group('watchSyncs', () {
    int? balanceOf(Result<InstantWallet, P2pWalletRefusal> result) =>
        switch (result) {
          Ok(:final value) => value.balance.value.toInt(),
          Err() => null,
        };

    test('gives the wallet after each sync of it', () async {
      final seen = <Result<InstantWallet, P2pWalletRefusal>>[];
      final subscription = repository.watchSyncs('instant').listen(seen.add);
      syncs.finished
        ..add(testWallet(balance: 9371))
        ..add(testWallet(origin: 'other', balance: 1))
        // A balance the wallet should never hold is no balance: skipped.
        ..add(testWallet(balance: -1))
        ..add(testWallet(balance: 9971));
      await pumpEventQueue();
      expect(seen.map(balanceOf), [9371, 9971]);
      expect(syncs.watched, ['instant']);
      await subscription.cancel();
    });

    test('says when the wallet is no longer the default Liquid one', () async {
      for (final changed in [
        testWallet(isDefault: false, balance: 5),
        testWallet(isLiquid: false, balance: 5),
      ]) {
        final seen = <Result<InstantWallet, P2pWalletRefusal>>[];
        final subscription = repository.watchSyncs('instant').listen(seen.add);
        syncs.finished.add(changed);
        await pumpEventQueue();
        expect(seen, [
          isA<Err<InstantWallet, P2pWalletRefusal>>().having(
            (err) => err.failure,
            'failure',
            isA<P2pWalletUnavailable>(),
          ),
        ]);
        await subscription.cancel();
      }
    });

    test('lets the wallet\'s stream go at once when cancelled', () async {
      final subscription = repository.watchSyncs('instant').listen((_) {});
      expect(syncs.finished.hasListener, isTrue);
      await subscription.cancel().timeout(const Duration(seconds: 1));
      expect(syncs.finished.hasListener, isFalse);
    });
  });

  group('estimateNetworkFee', () {
    final wallet = InstantWallet(
      id: 'instant',
      balance: Sats.fromInt(10000),
      isTestnet: false,
      signsHere: true,
    );

    test(
      'reads the fee of an unsigned transaction to the wallet\'s first address, at 25 sat/kwu',
      () async {
        liquid.fee = 31;
        expect(
          await repository.estimateNetworkFee(wallet, Sats.fromInt(603)),
          isA<Ok<Sats, P2pWalletRefusal>>().having(
            (ok) => ok.value,
            'fee',
            Sats.fromInt(31),
          ),
        );
        expect(addresses.calls, [(walletId: 'instant', index: 0)]);
        expect(liquid.builds, [
          (
            walletId: 'instant',
            address: 'lq1fakeaddress0',
            amountSat: 603,
            feeRate: 25,
          ),
        ]);
      },
    );

    test('says the wallet needs at least the amount, and more than it has', () async {
      liquid.buildError = InsufficientFundsException('short');
      expect(
        refusalOf(
          await repository.estimateNetworkFee(wallet, Sats.fromInt(20000)),
        ),
        isA<P2pWalletNotEnoughBalance>()
            .having((r) => r.available, 'available', Sats.fromInt(10000))
            .having((r) => r.needed, 'needed', Sats.fromInt(20000)),
      );
    });

    test('maps the wallet\'s exceptions to refusals', () async {
      for (final (error, matcher) in [
        (
          InsufficientFundsException('InsufficientFunds { missing_sats: 21 }'),
          isA<P2pWalletNotEnoughBalance>()
              .having((r) => r.available, 'available', Sats.fromInt(10000))
              .having((r) => r.needed, 'needed', Sats.fromInt(10001)),
        ),
        (
          NoSpendableUtxoException('none'),
          isA<P2pWalletNotEnoughBalance>().having(
            (r) => r.needed,
            'needed',
            Sats.fromInt(10001),
          ),
        ),
        (
          ConsolidationRequiredException('too many inputs'),
          isA<P2pWalletNeedsConsolidation>(),
        ),
        (Exception('lwk'), isA<P2pWalletUnavailable>()),
        ('a thrown string', isA<P2pWalletUnavailable>()),
      ]) {
        liquid.buildError = error;
        final refusal = refusalOf(
          await repository.estimateNetworkFee(wallet, Sats.fromInt(603)),
        );
        expect(refusal, matcher, reason: '$error');
        expect(refusal.logMessage, isNull);
      }
      liquid.buildError = null;
      addresses.error = Exception('no metadata');
      expect(
        refusalOf(
          await repository.estimateNetworkFee(wallet, Sats.fromInt(603)),
        ),
        isA<P2pWalletUnavailable>(),
      );
    });
  });
}
