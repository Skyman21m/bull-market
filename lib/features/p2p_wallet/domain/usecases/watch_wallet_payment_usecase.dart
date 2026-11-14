import 'package:bb_mobile/features/p2p_wallet/domain/repositories/wallet_payment_repository.dart';
import 'package:p2p/p2p.dart';

/// The progress of a payment the wallet started, as its records change: it starts nothing and asks the swap service nothing.
class WatchWalletPaymentUsecase {
  final WalletPaymentRepository _payments;

  const WatchWalletPaymentUsecase(this._payments);

  Stream<Result<P2pWalletPaymentProgress, P2pWalletRefusal>> execute(
    P2pWalletPayment payment,
  ) => _payments.watch(payment);
}
