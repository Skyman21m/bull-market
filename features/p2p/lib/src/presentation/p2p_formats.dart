import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/taker_estimate.dart';

/// How the P2P screens write numbers and durations: the rules of the official client, in the conventions of the user's language.
///
/// Amounts keep 4 significant digits and ranges are written `min-max`, as `amountToString` does in the official client; separators and percent signs follow the locale.
final class P2pFormats {
  final P2pLocalizations _l10n;
  final String _locale;

  P2pFormats(this._l10n) : _locale = _l10n.localeName;

  factory P2pFormats.of(BuildContext context) =>
      P2pFormats(P2pLocalizations.of(context));

  /// An amount in the currency of an order, rounded to 4 significant digits.
  String amount(FiatAmount amount) {
    final rounded = double.parse(amount.value.toStringAsPrecision(4));
    return (NumberFormat.decimalPattern(
      _locale,
    )..maximumFractionDigits = 8).format(rounded);
  }

  /// The amount of an order: `100` for a fixed amount, `50-300` for a range.
  String orderAmount(OrderAmount amount) => switch (amount) {
    FixedOrderAmount(:final amount) => this.amount(amount),
    RangeOrderAmount(:final min, :final max) =>
      '${this.amount(min)}-${this.amount(max)}',
  };

  /// A number of sats, with the thousands separator of the locale.
  String sats(int sats) => NumberFormat.decimalPattern(_locale).format(sats);

  /// The sats of an estimate: one number, or `min-max` for a range.
  String estimate(TakerEstimate estimate) => estimate.isRange
      ? '${sats(estimate.minSats)}-${sats(estimate.maxSats)}'
      : sats(estimate.maxSats);

  /// A price per bitcoin, rounded to the unit as the official client shows it.
  String price(double price) =>
      NumberFormat.decimalPattern(_locale).format(price.round());

  /// The premium of an order with its sign and percent sign, such as `+2.0%`: at least one decimal, at most 4 like the official client.
  String premium(Premium premium) {
    final text = _percent(premium.percent, minDecimals: 1, maxDecimals: 4);
    return premium.percent > 0 ? '+$text' : text;
  }

  /// The premium as a bare number, for a sentence that writes the percent sign itself.
  String premiumNumber(Premium premium) =>
      (NumberFormat.decimalPattern(_locale)
            ..minimumFractionDigits = 1
            ..maximumFractionDigits = 4)
          .format(premium.percent);

  /// The bond of an order, such as `3%`.
  String bond(BondSize bond) =>
      _percent(bond.percent, minDecimals: 0, maxDecimals: 2);

  /// A fee given as a fraction, in percent with 3 decimals like the fee row of the official client: `0.00025` is `0.025%`.
  String fee(double fraction) =>
      _percent(fraction * 100, minDecimals: 3, maxDecimals: 3);

  /// A rate already in percent, such as the on-chain payout fee.
  String rate(double percent) =>
      _percent(percent, minDecimals: 0, maxDecimals: 2);

  String _percent(
    double percent, {
    required int minDecimals,
    required int maxDecimals,
  }) =>
      (NumberFormat.percentPattern(_locale)
            ..minimumFractionDigits = minDecimals
            ..maximumFractionDigits = maxDecimals)
          .format(percent / 100);

  /// The time left on the expiry ring of the book: whole hours, or minutes under one hour, rounded as the official client does.
  String ringTime(Duration left) {
    final millis = left.inMilliseconds.abs();
    final hours = (millis / Duration.millisecondsPerHour).round();
    if (hours > 0) return _l10n.p2pDurationHours('$hours');
    final minutes = (millis / Duration.millisecondsPerMinute).round();
    return _l10n.p2pDurationMinutes('$minutes');
  }

  /// The deposit time of an order: `3h`, `1h 30m` or `45m`.
  String depositTime(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes - hours * 60;
    if (hours > 0 && minutes > 0) {
      return _l10n.p2pDurationHoursMinutes('$hours', _twoDigits(minutes));
    }
    if (hours > 0) return _l10n.p2pDurationHours('$hours');
    return _l10n.p2pDurationMinutes(_twoDigits(minutes));
  }

  /// The live countdown of an order: `17h 04m 12s`.
  String countdown(Duration left) {
    final hours = left.inHours;
    final minutes = left.inMinutes - hours * 60;
    final seconds = left.inSeconds - left.inMinutes * 60;
    return _l10n.p2pCountdownHms(
      '$hours',
      _twoDigits(minutes),
      _twoDigits(seconds),
    );
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}
