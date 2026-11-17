import 'package:robosats/robosats.dart';

import '../../../../public/p2p_wallet_port.dart';
import '../../trade/make_price_check.dart';

/// Compares the chosen coordinator's price of a bitcoin with the wallet's own, in the create form, before the order is made (#181, the owner's decision of 2026-11-17; [MakePriceCheck]): it reads the wallet's price ([P2pWalletPort.bitcoinRate]) and nothing else, moves nothing, and never stops the make.
///
/// The read leaves the device outside Tor, as the wallet's own screens read the price, unless the wallet's pricer holds it from less than a minute before or is already reading it (`P2pWalletPort.bitcoinRate` says what it carries). The form (`MakeOrderCubit`) asks it only while an amount above zero is typed and the chosen coordinator gives a price for the order's currency, before any robot exists: when the amount is first typed, when the currency changes, and when the coordinator's limits are read again (another host or the same one chosen, or « Create order » pressed with limits more than 3 minutes old), each time only if the form's last read of that currency is 3 minutes old or more; and at each « Retry »; never when the form opens, never for « Clear form », never in a loop. What it tells the price service, whatever the user then does: the IP address, the time, and the currency asked (which a currency other than the display currency makes distinctive), even when no order is made; and since orders are public (the book, Nostr) with their currency, amount and time, the price service alone could tie an IP address to an order by the time for a currency little traded.
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
