import 'package:bb_mobile/features/p2p_wallet/domain/repositories/wallet_payment_repository.dart';
import 'package:meta/meta.dart';
import 'package:p2p/p2p.dart';

/// The payment the wallet started for a payment hash, in any state, from its records: what a restart reads before anything could pay again.
class FindWalletPaymentUsecase {
  final WalletPaymentRepository _payments;

  const FindWalletPaymentUsecase(this._payments);

  @useResult
  Future<Result<P2pWalletPaymentFound?, P2pWalletRefusal>> execute(
    String paymentHash,
  ) => _payments.find(paymentHash);
}
