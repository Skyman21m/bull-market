import 'dart:async';

import 'package:bb_mobile/core/entities/signer_device_entity.dart';
import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/fees/domain/fees_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/liquid_wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_address.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_address_at_index_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/watch_finished_wallet_syncs_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/wallet_failure.dart';
import 'package:bb_mobile/features/swap/public/swap_facade.dart';
import 'package:p2p/p2p.dart'
    show CheckedBolt11Invoice, Ok, Result, RobosatsNetwork, Sats;
import 'package:p2p/testing.dart' show checkedBolt11InvoiceForTesting;

/// The instant the tests run at.
final testNow = DateTime.utc(2026, 11, 13, 12);

/// An obviously fake invoice string of [amount] sats on [network], never a real invoice: the port's type checks its shape and amount, not its checksum nor its signature (`n` is a tenth of a satoshi).
String fakeBolt11(RobosatsNetwork network, {int amount = 600}) =>
    switch (network) {
      RobosatsNetwork.mainnet => 'lnbc',
      RobosatsNetwork.testnet => 'lntb',
    } +
    '${amount * 10}n1${'q' * 60}';

/// A checked invoice of [amount] sats on [network], expiring [expiresIn] after [testNow].
CheckedBolt11Invoice testInvoice({
  int amount = 600,
  RobosatsNetwork network = RobosatsNetwork.mainnet,
  Duration expiresIn = const Duration(minutes: 3),
}) {
  final invoice = checkedBolt11InvoiceForTesting(
    bolt11: fakeBolt11(network, amount: amount),
    amount: Sats.fromInt(amount),
    network: network,
    expiresAt: testNow.add(expiresIn),
    // Built before it expires, so that the port's own check of the expiry can be tested.
    now: testNow.add(expiresIn).subtract(const Duration(minutes: 10)),
  );
  if (invoice == null) throw StateError('the fake invoice is refused');
  return invoice;
}

/// A wallet of the wallet's own entity, as its readers return it.
Wallet testWallet({
  String origin = 'instant',
  int balance = 10000,
  bool isTestnet = false,
  bool isLiquid = true,
  bool isDefault = true,
  SignerEntity signer = SignerEntity.local,
  SignerDeviceEntity? signerDevice,
}) => Wallet(
  origin: origin,
  label: 'Instant payments',
  network: switch ((isLiquid, isTestnet)) {
    (true, false) => Network.liquidMainnet,
    (true, true) => Network.liquidTestnet,
    (false, false) => Network.bitcoinMainnet,
    (false, true) => Network.bitcoinTestnet,
  },
  isDefault: isDefault,
  masterFingerprint: 'aabbccdd',
  xpubFingerprint: 'aabbccdd',
  scriptType: ScriptType.bip84,
  xpub: 'xpub',
  externalPublicDescriptor: 'desc',
  internalPublicDescriptor: 'desc',
  signer: signer,
  signerDevice: signerDevice,
  balanceSat: BigInt.from(balance),
);

/// The wallet's `GetWalletsUsecase`, answering [answer] (or throwing [error]) and recording the filters it was asked with.
final class FakeGetWallets implements GetWalletsUsecase {
  Result<List<Wallet>, WalletFailure> answer;
  Object? error;
  final List<({bool? onlyDefaults, bool? onlyLiquid, bool sync})> calls = [];

  FakeGetWallets(this.answer);

  @override
  Future<Result<List<Wallet>, WalletFailure>> execute({
    bool? onlyDefaults,
    bool? onlyBitcoin,
    bool? onlyLiquid,
    bool sync = false,
  }) async {
    calls.add((onlyDefaults: onlyDefaults, onlyLiquid: onlyLiquid, sync: sync));
    if (error case final error?) throw error;
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The wallet's `WatchFinishedWalletSyncsUsecase`: the test adds the wallets whose sync finished.
final class FakeWatchSyncs implements WatchFinishedWalletSyncsUsecase {
  final StreamController<Wallet> finished = StreamController.broadcast();
  final List<String?> watched = [];

  @override
  Stream<Wallet> execute({String? walletId}) {
    watched.add(walletId);
    return finished.stream.where(
      (wallet) => walletId == null || wallet.id == walletId,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The wallet's `GetAddressAtIndexUsecase`, deriving a fake address and recording what it was asked.
final class FakeGetAddressAtIndex implements GetAddressAtIndexUsecase {
  Object? error;
  final List<({String walletId, int index})> calls = [];

  @override
  Future<WalletAddress> execute({
    required String walletId,
    required int index,
  }) async {
    calls.add((walletId: walletId, index: index));
    if (error case final error?) throw error;
    return WalletAddress(
      walletId: walletId,
      index: index,
      address: 'lq1fakeaddress$index',
      createdAt: testNow,
      updatedAt: testNow,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The wallet's `LiquidWalletRepository`, of which only the build of an unsigned transaction and the read of its fee may be used: any other member, signing included, fails the test.
final class FakeLiquidWallet implements LiquidWalletRepository {
  int fee = 26;
  Object? buildError;
  final List<({String walletId, String address, int? amountSat, int feeRate})>
  builds = [];

  @override
  Future<String> buildPset({
    required String walletId,
    required String address,
    int? amountSat,
    required RelativeFee feeRate,
    bool? drain,
  }) async {
    builds.add((
      walletId: walletId,
      address: address,
      amountSat: amountSat,
      feeRate: feeRate.satPerKwu,
    ));
    if (buildError case final error?) throw error;
    return 'unsigned-pset';
  }

  @override
  Future<(int, int)> getPsetSizeAndAbsoluteFees({required String pset}) async {
    if (pset != 'unsigned-pset') throw StateError('unknown pset');
    return (1000, fee);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('LiquidWalletRepository.${invocation.memberName} used');
}

/// The Swap feature's facade, of which only `getQuote` may be used: any other member, creating an order included, fails the test. No test reaches the swap service.
final class FakeSwapFacade implements SwapFacade {
  Result<OrderSwapQuote, SwapFailure> answer;
  final List<
    ({
      OrderSwapEnvironment environment,
      BigInt amountSat,
      bool isInAmountFixed,
      OrderSwapNetwork inNetwork,
      OrderSwapNetwork outNetwork,
    })
  >
  quotes = [];

  FakeSwapFacade(this.answer);

  /// A quote of the service paying out [out] sats for a payin of [payin].
  static Result<OrderSwapQuote, SwapFailure> quoteOf({
    int out = 600,
    int payin = 603,
    int basisPoints = 50,
  }) => Ok(
    OrderSwapQuote(
      inAmountSat: BigInt.from(payin),
      outAmountSat: BigInt.from(out),
      inNetwork: OrderSwapNetwork.liquid,
      outNetwork: OrderSwapNetwork.lightning,
      inCurrency: 'LBTC',
      outCurrency: 'BTC',
      feeBasisPoints: basisPoints,
      warnings: const [],
    ),
  );

  @override
  Future<Result<OrderSwapQuote, SwapFailure>> getQuote({
    required OrderSwapEnvironment environment,
    required BigInt amountSat,
    required bool isInAmountFixed,
    required OrderSwapNetwork inNetwork,
    required OrderSwapNetwork outNetwork,
  }) async {
    quotes.add((
      environment: environment,
      amountSat: amountSat,
      isInAmountFixed: isInAmountFixed,
      inNetwork: inNetwork,
      outNetwork: outNetwork,
    ));
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('SwapFacade.${invocation.memberName} used');
}
