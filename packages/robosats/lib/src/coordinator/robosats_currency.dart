import 'package:meta/meta.dart';
import 'package:robosats/src/coordinator/currency_data.dart';

/// A currency an order can be traded in, as RoboSats numbers it in `frontend/static/assets/currencies.json`.
///
/// Fiat currencies have ids 1 to 78, gold (`XAU`) is 300 and bitcoin (`BTC`) is 1000, the currency of swaps.
@immutable
final class RobosatsCurrency {
  /// The id coordinators send and receive.
  final int id;

  /// The code the official client shows, such as `EUR`: an ISO 4217 code for fiat currencies.
  final String code;

  const RobosatsCurrency._(this.id, this.code);

  /// Every currency, in the order of the RoboSats file.
  static final List<RobosatsCurrency> all = List.unmodifiable([
    for (final MapEntry(:key, :value) in robosatsCurrencyCodes.entries)
      RobosatsCurrency._(key, value),
  ]);

  static final Map<int, RobosatsCurrency> _byId = {
    for (final currency in all) currency.id: currency,
  };

  /// The currency with this id, or `null` for an id RoboSats does not have.
  static RobosatsCurrency? fromId(int id) => _byId[id];

  /// The currency with this code, or `null`.
  static RobosatsCurrency? fromCode(String code) {
    for (final currency in all) {
      if (currency.code == code) return currency;
    }
    return null;
  }

  /// Whether this is bitcoin, the currency of swap orders: their amounts are in BTC and their payment method is a destination such as `On-Chain BTC`.
  bool get isBitcoin => id == 1000;

  @override
  bool operator ==(Object other) => other is RobosatsCurrency && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'RobosatsCurrency($id, $code)';
}
