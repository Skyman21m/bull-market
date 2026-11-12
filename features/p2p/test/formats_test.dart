import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/src/presentation/p2p_formats.dart';
import 'package:robosats/robosats.dart';

FiatAmount fiat(double value) =>
    FiatAmount.tryCreate(value) ?? (throw ArgumentError('$value'));

void main() {
  final en = P2pFormats(lookupP2pLocalizations(const Locale('en')));
  final fr = P2pFormats(lookupP2pLocalizations(const Locale('fr')));

  test('amounts keep 4 significant digits, ranges are min-max', () {
    expect(en.amount(fiat(100)), '100');
    expect(en.amount(fiat(1234.56)), '1,235');
    expect(en.amount(fiat(12345)), '12,350');
    expect(en.amount(fiat(0.0021)), '0.0021');
    expect(
      en.orderAmount(
        RangeOrderAmount.tryCreate(fiat(50), fiat(300)) ??
            (throw StateError('range')),
      ),
      '50-300',
    );
    expect(fr.amount(fiat(1234.56)), '1 235');
  });

  test('how far Tor has got is a whole percentage in the language', () {
    expect(en.torProgress(0), '0%');
    expect(en.torProgress(42), '42%');
    expect(en.torProgress(99), '99%');
    expect(fr.torProgress(42), '42\u00a0%');
  });

  test('premium is signed, bond and fees are percentages', () {
    expect(en.premium(Premium.tryCreate(2) ?? (throw StateError(''))), '+2.0%');
    expect(
      en.premium(Premium.tryCreate(-0.125) ?? (throw StateError(''))),
      '-0.125%',
    );
    expect(
      fr.premium(Premium.tryCreate(2) ?? (throw StateError(''))),
      '+2,0 %',
    );
    expect(en.bond(BondSize.tryCreate(3) ?? (throw StateError(''))), '3%');
    expect(
      en.premiumOverMarket(Premium.tryCreate(2) ?? (throw StateError(''))),
      '2%',
    );
    expect(
      en.premiumOverMarket(Premium.tryCreate(1.257) ?? (throw StateError(''))),
      '1.26%',
    );
    expect(en.swapFee(3.443594014752762), '3.4%');
    expect(en.swapFee(1.2), '1.2%');
    expect(en.fee(0.00025), '0.025%');
    expect(en.fee(0.00175), '0.175%');
  });

  test('durations read as the official client writes them', () {
    expect(en.ringTime(const Duration(hours: 16, minutes: 40)), '17h');
    expect(en.ringTime(const Duration(minutes: 12)), '12m');
    expect(fr.ringTime(const Duration(minutes: 12)), '12 min');
    expect(en.depositTime(const Duration(hours: 3)), '3h');
    expect(en.depositTime(const Duration(minutes: 90)), '1h 30m');
    expect(en.depositTime(const Duration(minutes: 45)), '45m');
    expect(
      en.countdown(const Duration(hours: 17, minutes: 4, seconds: 12)),
      '17h 04m 12s',
    );
    expect(
      fr.countdown(const Duration(hours: 17, minutes: 4, seconds: 12)),
      '17 h 04 min 12 s',
    );
  });

  test('sats and prices take the separators of the locale', () {
    expect(en.sats(106900), '106,900');
    expect(en.price(93330.4), '93,330');
    expect(fr.sats(106900), '106 900');
  });

  test('the numbers of the coordinator dialog', () {
    // `toPrecision(3)`, as the official client writes the on-chain fee there.
    expect(en.swapFeeRate(3.443594014752762), '3.44%');
    expect(en.swapFeeRate(0.5), '0.500%');
    expect(en.swapFeeRate(12.345), '12.3%');
    expect(en.swapFeeRate(100), '100%');
    expect(en.swapFeeRate(0), '0.00%');
    expect(fr.swapFeeRate(3.443594014752762), '3,44\u00a0%');
    // A size limit need not be whole.
    expect(en.satsAmount(928232.5), '928,232.5');
    expect(en.satsAmount(6000000), '6,000,000');
    expect(fr.satsAmount(6000000), fr.sats(6000000));
    expect(en.count(2348), '2,348');
    expect(en.btc(0.23644465), '0.23644465');
    expect(en.btc(196.68313773), '196.68313773');
    expect(en.btc(0), '0.00000000');
    expect(fr.btc(0.5), '0,50000000');
    expect(en.nonKycPremium(0.95), '0.95%');
    expect(en.nonKycPremium(1), '1%');
    expect(en.nonKycPremium(-0.5), '-0.5%');
  });

  test(
    'a swap amount, in BTC, is written in sats as the official client does',
    () {
      expect(en.btcAmountInSats(FixedOrderAmount(fiat(0.0512))), '5,120,000');
      expect(
        en.btcAmountInSats(
          RangeOrderAmount.tryCreate(fiat(0.01), fiat(0.05)) ??
              (throw StateError('range')),
        ),
        '1,000,000-5,000,000',
      );
      // Rounded to the sat, as `Math.round`.
      expect(en.btcAmountInSats(FixedOrderAmount(fiat(0.0000012345))), '123');
      expect(en.btcAmountInSats(FixedOrderAmount(fiat(0.0000012355))), '124');
      expect(
        fr.btcAmountInSats(FixedOrderAmount(fiat(0.0512))),
        fr.sats(5120000),
      );
    },
  );

  test('the depth chart writes its centre and ticks', () {
    // The centre of the premium axis: a whole number, the median it is cut to.
    expect(en.chartCenterPremium(2), '2%');
    expect(en.chartCenterPremium(-1), '-1%');
    expect(en.chartCenterPremium(12), '12%');
    expect(en.chartCenterPremium(0), '0%');
    expect(fr.chartCenterPremium(2), '2\u00a0%');
    // Premium ticks: `${value}%`.
    expect(en.chartPremium(-2.5), '-2.5%');
    expect(en.chartPremium(10), '10%');
    expect(fr.chartPremium(-2.5), '-2,5\u00a0%');
    // Price ticks: thousands and millions shortened, every decimal kept.
    expect(en.chartPrice(93500), '93.5K');
    expect(en.chartPrice(93020), '93.02K');
    expect(en.chartPrice(1200000), '1.2M');
    expect(en.chartPrice(950), '950');
    expect(fr.chartPrice(93500), contains('93,5'));
    // Bitcoin ticks: a plain number.
    expect(en.chartBtc(0.065), '0.065');
    expect(en.chartBtc(2), '2');
    expect(fr.chartBtc(0.065), '0,065');
  });
}
