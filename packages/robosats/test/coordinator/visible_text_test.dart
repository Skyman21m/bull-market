import 'dart:convert';

import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

/// What a maker may send as its payment method or description (#181, from the security review of #194): every character seen as written, at least one seen.
void main() {
  group('isShownAsWritten', () {
    test('ordinary texts of every script are kept', () {
      for (final text in [
        'SEPA',
        'Bizum Revolut Paypal Friends & Family',
        'Esp\u00e8ces F2F \u20ac',
        'Virement bancaire',
        '\u00dcberweisung',
        // Arabic, Hebrew, Persian with its zero width non-joiner between two letters, Chinese, Hindi.
        '\u062a\u062d\u0648\u064a\u0644 \u0628\u0646\u0643\u064a',
        '\u05d4\u05e2\u05d1\u05e8\u05d4 \u05d1\u05e0\u05e7\u05d0\u05d9\u05ea',
        '\u06a9\u0627\u0631\u062a\u200c\u0628\u0647\u200c\u06a9\u0627\u0631\u062a',
        '\u94f6\u884c\u8f6c\u8d26',
        '\u092c\u0948\u0902\u0915 \u091f\u094d\u0930\u093e\u0902\u0938\u092b\u0930',
        // Vietnamese written with two combining marks after its letter, a keycap, an emoji with its variation selector, a family joined by zero width joiners, a skin tone.
        'Tie\u0302\u0301n ma\u0306t',
        '1\ufe0f\u20e3',
        '❤\ufe0f Revolut',
        '👨\u200d👩\u200d👧',
        '👍🏽',
        '🐂',
        'x',
      ]) {
        expect(isShownAsWritten(text), isTrue, reason: jsonEncode(text));
      }
    });

    test('a text that shows as empty is refused', () {
      for (final text in [
        '',
        ' ',
        '   ',
        '\u200b',
        '\u200b\u200b\u200b',
        '\u200c',
        '\u200d',
        '\ufe0f',
        '\u0301',
        '\u2060',
        '\ufeff',
        '\u00ad',
        '\u3164',
        '\u2800',
        '\u{e0041}\u{e0042}',
        ' \u0301 ',
      ]) {
        expect(isShownAsWritten(text), isFalse, reason: jsonEncode(text));
      }
    });

    test(
      'an invisible character, a space other than U+0020, a private use character or a noncharacter is refused anywhere',
      () {
        for (final hidden in [
          '\u00a0',
          '\u1680',
          '\u2000',
          '\u2007',
          '\u200a',
          '\u202f',
          '\u205f',
          '\u3000',
          '\u2800',
          '\u00ad',
          '\u034f',
          '\u115f',
          '\u1160',
          '\u17b4',
          '\u17b5',
          '\u180b',
          '\u180e',
          '\u200b',
          '\u2060',
          '\u2061',
          '\u2064',
          '\u206a',
          '\u206f',
          '\u3164',
          '\uffa0',
          '\ufeff',
          '\ufff9',
          '\ufffb',
          '\u0600',
          '\u06dd',
          '\u070f',
          '\u08e2',
          '\u{110bd}',
          '\u{13430}',
          '\u{1bca0}',
          '\u{1d173}',
          // The tag block, which can carry a hidden text.
          '\u{e0001}',
          '\u{e0020}',
          '\u{e0041}',
          '\u{e007f}',
          '\ue000',
          '\uf8ff',
          '\u{f0000}',
          '\u{10fffd}',
          '\ufdd0',
          '\ufdef',
          '\ufffe',
          '\uffff',
          '\u{1fffe}',
          '\u{10ffff}',
        ]) {
          for (final text in [
            'SEPA${hidden}Revolut',
            '${hidden}SEPA',
            'SEPA$hidden',
          ]) {
            expect(isShownAsWritten(text), isFalse, reason: jsonEncode(text));
          }
        }
      },
    );

    test('what `displayText` refuses stays refused', () {
      for (final text in [
        'SEPA\tRevolut',
        'SEPA\nRevolut',
        'SEPA\u0000',
        'SEPA\u007f',
        'SEPA\u0085',
        'SEPA\u2028',
        'SEPA \u202eRevolut',
        'SEPA \u2066Revolut',
        'SEPA\u200f',
        'SEPA\u200e',
        'SEPA\u061c',
        'SEPA\ud800',
      ]) {
        expect(isShownAsWritten(text), isFalse, reason: jsonEncode(text));
      }
    });

    test('a joiner only alone between two characters that are seen', () {
      for (final text in [
        '\u200cSEPA',
        'SEPA\u200c',
        'SE\u200c\u200cPA',
        'SEPA \u200dRevolut',
        'SEPA\u200d Revolut',
        'SE\u200d\u0301PA',
        'SE\u200d\ufe0fPA',
      ]) {
        expect(isShownAsWritten(text), isFalse, reason: jsonEncode(text));
      }
      expect(isShownAsWritten('SE\u200cPA'), isTrue);
    });

    test('a variation selector only right after a character that is seen', () {
      for (final text in [
        '\ufe0fSEPA',
        'SEPA \ufe0f',
        'SEPA\ufe0f\ufe0f',
        'SE\u0301\ufe0fPA',
        '\u{e0100}x',
        'x\u{e0100}\u{e0100}',
      ]) {
        expect(isShownAsWritten(text), isFalse, reason: jsonEncode(text));
      }
      expect(isShownAsWritten('x\u{e0100}'), isTrue);
    });

    test(
      'a combining mark not at the start, nor after a space or a joiner, and at most three in a row',
      () {
        expect(maxCombiningMarks, 3);
        for (final text in [
          '\u0301SEPA',
          'SEPA \u0301',
          'a\u200d\u0301',
          'a\u0301\u0301\u0301\u0301',
          // A text piled up over its neighbours.
          'Z${'\u0336\u0337\u0338' * 5}algo',
        ]) {
          expect(isShownAsWritten(text), isFalse, reason: jsonEncode(text));
        }
        expect(isShownAsWritten('a\u0301\u0302\u0303'), isTrue);
        expect(isShownAsWritten('a\u0301\u0302\u0303b\u0301'), isTrue);
      },
    );
  });
}
