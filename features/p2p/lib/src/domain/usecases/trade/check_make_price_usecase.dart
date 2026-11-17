import 'package:robosats/robosats.dart';

import '../../../../public/p2p_wallet_port.dart';
import '../../trade/make_price_check.dart';

/// Compares the chosen coordinator's price of a bitcoin with the wallet's own, in the create form, before the order is made (#181, the owner's decision of 2026-11-17; [MakePriceCheck]): it reads the wallet's price ([P2pWalletPort.bitcoinRate]) and nothing else, moves nothing, and never stops the make.
///
/// The read leaves the device outside Tor, as the wallet's own screens read the price, unless the wallet's pricer holds it from less than a minute before or is already reading it (`P2pWalletPort.bitcoinRate` says what it carries): the form asks it once the chosen coordinator's limits are read for the order's currency, before any robot exists and before anything is sent to the coordinator with one, again when the currency or the coordinator changes, and at « Retry »; never in a loop.
final class CheckMakePriceUsecase {
  final P2pWalletPort _wallet;

  const CheckMakePriceUsecase(this._wallet);

  /// The check of [coordinatorPrice], a price `MakerTerms.create` takes, for [currency] on [network].
  Future<MakePriceCheck> execute(
    RobosatsNetwork network,
    RobosatsCurrency currency,
    double coordinatorPrice,
  ) async => MakePriceCheck.of(
    currency: currency,
    coordinatorPrice: coordinatorPrice,
    wallet: await _wallet.bitcoinRate(network, currency),
  );
}
