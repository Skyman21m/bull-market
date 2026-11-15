import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';

import '../../public/p2p_wallet_port.dart';
import '../domain/trade/trade_payout.dart';
import '../domain/usecases/trade/payout_from_wallet_usecase.dart';

/// What the wallet's slot of the payout panel shows (#90).
@immutable
sealed class PayoutWalletState {
  const PayoutWalletState();
}

/// Nothing asked yet, or a tab changed: the buttons are offered.
final class PayoutWalletIdle extends PayoutWalletState {
  const PayoutWalletIdle();
}

/// The wallet is asked for [kind]'s invoice or address; [waitedLong] once it has waited [PayoutWalletCubit.stillWaitingAfter].
final class PayoutWalletMaking extends PayoutWalletState {
  final PayoutKind kind;
  final bool waitedLong;

  const PayoutWalletMaking(this.kind, {this.waitedLong = false});
}

/// The wallet gave [invoice], which the panel put in the Lightning field.
final class PayoutWalletMadeInvoice extends PayoutWalletState {
  final P2pWalletInvoice invoice;

  const PayoutWalletMadeInvoice(this.invoice);
}

/// The wallet gave [address], which the panel put in the Onchain field.
final class PayoutWalletMadeAddress extends PayoutWalletState {
  final P2pWalletAddress address;

  const PayoutWalletMadeAddress(this.address);
}

/// The wallet could not give [kind]'s invoice or address: [refusal] says why.
final class PayoutWalletRefused extends PayoutWalletState {
  final PayoutKind kind;
  final P2pWalletRefusal refusal;

  const PayoutWalletRefused(this.kind, this.refusal);
}

/// The wallet's slot of the payout panel (#90): « Generate Invoice » and « Generate New Address », one request at a time, each wait said, and what the wallet gave.
///
/// It submits nothing: what it gives goes into the panel's field, where the panel checks it as a pasted text, and the user taps « Submit ».
class PayoutWalletCubit extends Cubit<PayoutWalletState> {
  final PayoutFromWalletUsecase _wallet;
  final Duration _stillWaitingAfter;

  /// After how long a request to the wallet is said to be still waiting, as the payout's own waits (`PayoutCubit.stillWaitingAfter`).
  static const stillWaitingAfter = Duration(seconds: 30);

  Timer? _stillWaiting;

  PayoutWalletCubit(
    this._wallet, {
    this._stillWaitingAfter = PayoutWalletCubit.stillWaitingAfter,
  }) : super(const PayoutWalletIdle());

  /// An invoice of exactly [amount] for [ask]: its text, to put in the field, or `null` when the wallet refused (the state says why) or a request already runs.
  Future<String?> makeInvoice(PayoutAsk ask, Sats amount) async {
    if (!_start(PayoutKind.lightning)) return null;
    final made = await _wallet.invoice(ask, amount);
    return _end(switch (made) {
      Ok(:final value) => (PayoutWalletMadeInvoice(value), value.bolt11),
      Err(:final failure) => (
        PayoutWalletRefused(PayoutKind.lightning, failure),
        null,
      ),
    });
  }

  /// A new address of the wallet's Bitcoin wallet for [ask]'s trade: its text, to put in the field, or `null` when the wallet refused or a request already runs.
  Future<String?> makeAddress(PayoutAsk ask) async {
    if (!_start(PayoutKind.onchain)) return null;
    final made = await _wallet.address(ask.record);
    return _end(switch (made) {
      Ok(:final value) => (PayoutWalletMadeAddress(value), value.address),
      Err(:final failure) => (
        PayoutWalletRefused(PayoutKind.onchain, failure),
        null,
      ),
    });
  }

  bool _start(PayoutKind kind) {
    if (isClosed || state is PayoutWalletMaking) return false;
    emit(PayoutWalletMaking(kind));
    _stillWaiting = Timer(_stillWaitingAfter, () {
      if (!isClosed && state case PayoutWalletMaking(:final kind)) {
        emit(PayoutWalletMaking(kind, waitedLong: true));
      }
    });
    return true;
  }

  String? _end((PayoutWalletState, String?) outcome) {
    _stillWaiting?.cancel();
    _stillWaiting = null;
    if (isClosed) return null;
    final (next, text) = outcome;
    emit(next);
    return text;
  }

  @override
  Future<void> close() {
    _stillWaiting?.cancel();
    return super.close();
  }
}
