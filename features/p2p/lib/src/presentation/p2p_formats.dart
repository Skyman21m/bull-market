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

  /// The amount of a swap order, given in BTC, as the sats the official client writes for it (`btcToSatsString`): `5,120,000`, or `min-max` for a range.
  String btcAmountInSats(OrderAmount amount) {
    // The package reads at most 1e10 BTC, so the sats fit in an int.
    String inSats(FiatAmount btc) => sats((btc.value * 100000000).round());
    return switch (amount) {
      FixedOrderAmount(:final amount) => inSats(amount),
      RangeOrderAmount(:final min, :final max) =>
        '${inSats(min)}-${inSats(max)}',
    };
  }

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

  /// A plain number in the conventions of the locale, such as the default bond in a sentence that writes the percent sign itself.
  String number(double value) => (NumberFormat.decimalPattern(
    _locale,
  )..maximumFractionDigits = 2).format(value);

  /// The premium of an order when its price is unknown, as the official client writes it: no sign, at most 2 decimals, such as `2%`.
  String premiumOverMarket(Premium premium) =>
      _percent(premium.percent, minDecimals: 0, maxDecimals: 2);

  /// The bond of an order, such as `3%`.
  String bond(BondSize bond) =>
      _percent(bond.percent, minDecimals: 0, maxDecimals: 2);

  /// A fee given as a fraction, in percent with 3 decimals like the fee row of the official client: `0.00025` is `0.025%`.
  String fee(double fraction) =>
      _percent(fraction * 100, minDecimals: 3, maxDecimals: 3);

  /// The on-chain payout fee of a coordinator, with one decimal as the official client's fee row writes it (`toFixed(1)`).
  String swapFee(double percent) =>
      _percent(percent, minDecimals: 1, maxDecimals: 1);

  /// The on-chain payout fee of the coordinator dialog, with 3 significant digits as the official client writes it there (`toPrecision(3)`): `3.44%`, `0.500%`.
  String swapFeeRate(double percent) {
    final precise = percent.toStringAsPrecision(3);
    final dot = precise.indexOf('.');
    final decimals = dot < 0 || precise.contains('e')
        ? 0
        : precise.length - dot - 1;
    return _percent(
      double.parse(precise),
      minDecimals: decimals,
      maxDecimals: decimals,
    );
  }

  /// A number of sats that need not be whole, such as the size limit of a young coordinator, which the official client prints with its decimals.
  String satsAmount(double sats) => (NumberFormat.decimalPattern(
    _locale,
  )..maximumFractionDigits = 8).format(sats);

  /// A count, such as the number of public orders of a coordinator.
  String count(int count) => NumberFormat.decimalPattern(_locale).format(count);

  /// A volume in BTC with 8 decimals, as the official client writes the volumes of a coordinator (`toFixed(8)`).
  String btc(double btc) =>
      (NumberFormat.decimalPattern(_locale)
            ..minimumFractionDigits = 8
            ..maximumFractionDigits = 8)
          .format(btc);

  /// The non-KYC premium of the last 24 hours, which the coordinator rounds to 2 decimals: `0.95%`.
  String nonKycPremium(double percent) =>
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
