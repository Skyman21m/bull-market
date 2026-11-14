import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

List<String> _names(String text) =>
    PaymentMethods.parse(text).recognized.map((m) => m.name).toList();

void main() {
  test('the fiat list is the official one, without the swap destinations', () {
    final fiat = PaymentMethods.fiat.map((m) => m.name).toList();
    expect(fiat.first, 'Advcash');
    expect(fiat.last, 'Zelle');
    expect(fiat, hasLength(95));
    expect(fiat.toSet(), hasLength(95));
    // A few places inside the list, so that two entries swapped are seen.
    expect(fiat.indexOf('Bizum'), 26);
    expect(fiat.indexOf('Instant SEPA'), 41);
    expect(fiat.indexOf('Revolut'), 71);
    expect(fiat.indexOf('Wise'), 92);
    expect(PaymentMethods.known, containsAll(PaymentMethods.fiat));
    expect(fiat, isNot(contains(PaymentMethods.notSpecified.name)));
    for (final swap in ['On-Chain BTC', 'LBTC', 'WBTC', 'RBTC']) {
      expect(fiat, isNot(contains(swap)), reason: swap);
    }
  });

  group('PaymentMethods.parse', () {
    test('recognises the methods of real orders, in list order', () {
      expect(_names('Revolut Wise Instant SEPA'), [
        'Instant SEPA',
        'Revolut',
        'Wise',
      ]);
      expect(_names('On-Chain BTC LBTC WBTC'), [
        'On-Chain BTC',
        'LBTC',
        'WBTC',
      ]);
      expect(_names('HalCash Amazon ES GiftCard Revolut Instant SEPA'), [
        'Amazon ES GiftCard',
        'HalCash',
        'Instant SEPA',
        'Revolut',
      ]);
      expect(PaymentMethods.parse('USDT USDC').hasOtherText, isFalse);
    });

    test('matches whole words, ignoring case', () {
      expect(_names('revolut'), ['Revolut']);
      expect(_names('Revolution'), isEmpty);
      expect(_names('Amazon GiftCard'), ['Amazon GiftCard']);
      expect(_names('Pouchxph'), isEmpty);
    });

    test('flags free text besides the recognised methods', () {
      final methods = PaymentMethods.parse('Instant SEPA, Sepa Standard');
      expect(methods.recognized.map((m) => m.name), ['Instant SEPA']);
      expect(methods.hasOtherText, isTrue);
      expect(PaymentMethods.parse('TED / Depósito PIX').hasOtherText, isTrue);
      expect(PaymentMethods.parse('').hasOtherText, isFalse);
      expect(PaymentMethods.parse('').recognized, isEmpty);
    });

    test('ignores emoji, as the official client does', () {
      final methods = PaymentMethods.parse('Revolut ⚡');
      expect(methods.recognized.map((m) => m.name), ['Revolut']);
      expect(methods.hasOtherText, isFalse);
    });

    test('ignores the other characters the official client removes', () {
      for (final codePoint in [
        0xE000,
        0xF8FF,
        0x1F600,
        0x1F3FF,
        0x1F910,
        0x2700,
        0x2011,
      ]) {
        final methods = PaymentMethods.parse(
          'Wise ${String.fromCharCode(codePoint)}',
        );
        expect(
          methods.hasOtherText,
          isFalse,
          reason: codePoint.toRadixString(16),
        );
      }
      expect(
        PaymentMethods.parse(
          'Wise ${String.fromCharCode(0x1F90F)}',
        ).hasOtherText,
        isTrue,
      );
    });

    test('flags reversible methods', () {
      expect(PaymentMethods.parse('PIX').hasReversible, isTrue);
      expect(PaymentMethods.parse('Wise').hasReversible, isFalse);
    });

    test('recognises the default text', () {
      expect(_names('not specified'), ['not specified']);
    });

    test('prints only the recognised names', () {
      expect(
        '${PaymentMethods.parse('Revolut call me at +33 6 00 00 00 00')}',
        'PaymentMethods(Revolut, other)',
      );
    });
  });
}
