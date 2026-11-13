import 'dart:async';

import 'package:bb_mobile/features/p2p_wallet/domain/entities/instant_wallet.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/instant_wallet_repository.dart';
import 'package:p2p/p2p.dart';

/// What the Instant Payments wallet can spend, for a trade on a network: now, then after each sync of the wallet that the app finishes.
class WatchInstantBalanceUsecase {
  final InstantWalletRepository _wallets;

  const WatchInstantBalanceUsecase(this._wallets);

  /// The balance of the Instant Payments wallet for a trade on [network], then each balance that differs from the last one given; a refusal ends the stream.
  ///
  /// It reads the wallet when listened to, and stops following its syncs as soon as the subscription is cancelled, even while that first read runs (not an `async*` body, whose cancellation would wait for the next sync).
  /// After a refusal of the first read nothing is followed: the stream gives the refusal and ends.
  /// A sync whose wallet cannot be read is skipped: the next one gives the balance. When the wallet's stream of syncs ends, so does this one; when a sync shows that the wallet followed is no longer the Instant Payments wallet, this one ends with that refusal, and listening again reads the new one.
  Stream<Result<Sats, P2pWalletRefusal>> execute(RobosatsNetwork network) {
    StreamSubscription<Result<InstantWallet, P2pWalletRefusal>>? syncs;
    var cancelled = false;
    late final StreamController<Result<Sats, P2pWalletRefusal>> controller;

    Future<void> refuse(P2pWalletRefusal refusal) async {
      controller.add(Err(refusal));
      await controller.close();
    }

    Future<void> start() async {
      final read = await _wallets.read();
      if (cancelled) return;
      final InstantWallet wallet;
      switch (read) {
        case Ok(:final value):
          wallet = value;
        case Err(:final failure):
          return refuse(failure);
      }
      if (wallet.refusalFor(network) case final refusal?) {
        return refuse(refusal);
      }
      var last = wallet.balance;
      controller.add(Ok(last));
      syncs = _wallets
          .watchSyncs(wallet.id)
          .listen(
            (synced) {
              switch (synced) {
                case Ok(value: InstantWallet(:final balance)):
                  if (balance == last) return;
                  last = balance;
                  controller.add(Ok(last));
                case Err(:final failure):
                  unawaited(syncs?.cancel());
                  unawaited(refuse(failure));
              }
            },
            onError: (Object _) {},
            onDone: () => unawaited(controller.close()),
          );
    }

    controller = StreamController(
      onListen: () => unawaited(start()),
      onCancel: () {
        cancelled = true;
        return syncs?.cancel();
      },
    );
    return controller.stream;
  }
}
