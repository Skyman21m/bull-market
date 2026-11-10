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
}
