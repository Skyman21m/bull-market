import '../../trade_record.dart';
import 'trade_keyring.dart';

/// Keeps the unlocked key of a trade's robot while the trade screen is shown and the app in the foreground (#90, design note § 3.4).
///
/// The trade screen (#88, #91) calls it when it is shown in the foreground and releases the hold it returns when it closes, or when the app is hidden or paused, calling it again on return: the key, once a payout's signature has unlocked it, is then not unlocked again for every signature of the screen's session, and is dropped as soon as the screen lets go.
/// A hold unlocks nothing, reads nothing and sends nothing by itself; without one, each signature unlocks the key for itself and drops it after (`TradeKeyring`).
final class HoldTradeKeyUsecase {
  final TradeKeyring _keyring;

  const HoldTradeKeyUsecase(this._keyring);

  /// A hold on the key of the robot of [record]: release it, once, when the screen closes or the app leaves the foreground.
  TradeKeyHold execute(TradeRecord record) => _keyring.hold(record);
}
