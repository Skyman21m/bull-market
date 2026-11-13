import 'package:bb_mobile/features/p2p_wallet/domain/entities/instant_wallet.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/instant_wallet_repository.dart';
import 'package:p2p/p2p.dart';

/// What the Instant Payments wallet can spend, for a trade on a network: now, then after each sync of the wallet that the app finishes.
class WatchInstantBalanceUsecase {
  final InstantWalletRepository _wallets;

  const WatchInstantBalanceUsecase(this._wallets);

  /// The balance of the Instant Payments wallet for a trade on [network], then each balance that differs from the last one given; a refusal ends the stream.
  Stream<Result<Sats, P2pWalletRefusal>> execute(
    RobosatsNetwork network,
  ) async* {
    final InstantWallet wallet;
    switch (await _wallets.read()) {
      case Ok(:final value):
        wallet = value;
      case Err(:final failure):
        yield Err(failure);
        return;
    }
    if (wallet.refusalFor(network) case final refusal?) {
      yield Err(refusal);
      return;
    }
    var last = wallet.balance;
    yield Ok(last);
    await for (final synced in _wallets.watchSyncs(wallet.id)) {
      if (synced.balance == last) continue;
      last = synced.balance;
      yield Ok(last);
    }
  }
}
