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
          // The object replacement character, the Khitan filler, a code point of the wholly unassigned planes 4 to 13.
          '\ufffc',
          '\u{16fe4}',
          '\u{40000}',
          '\u{dfffd}',
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

    test(
      'the emoji sequences whose variation selector comes before a joiner (functional review of #181, C1)',
      () {
        String of(List<int> codes) => String.fromCharCodes(codes);
        for (final codes in [
          // A rainbow flag, a heart on fire, a couple with a heart, an eye in a speech bubble.
          [0x1F3F3, 0xFE0F, 0x200D, 0x1F308],
          [0x2764, 0xFE0F, 0x200D, 0x1F525],
          [0x1F468, 0x200D, 0x2764, 0xFE0F, 0x200D, 0x1F468],
          [0x1F441, 0xFE0F, 0x200D, 0x1F5E8, 0xFE0F],
          // A transgender flag, a mending heart, a kiss, a man in a turban, a polar bear, a technologist with a skin tone.
          [0x1F3F3, 0xFE0F, 0x200D, 0x26A7, 0xFE0F],
          [0x2764, 0xFE0F, 0x200D, 0x1FA79],
          [0x1F469, 0x200D, 0x2764, 0xFE0F, 0x200D, 0x1F48B, 0x200D, 0x1F468],
          [0x1F473, 0x200D, 0x2642, 0xFE0F],
          [0x1F43B, 0x200D, 0x2744, 0xFE0F],
          [0x1F9D1, 0x1F3FD, 0x200D, 0x1F4BB],
        ]) {
          expect(isShownAsWritten(of(codes)), isTrue, reason: '$codes');
          expect(
            isShownAsWritten('Revolut ${of(codes)}'),
            isTrue,
            reason: '$codes',
          );
        }
        // Still refused: a joiner first, last, doubled, after an invisible character, or after a selector that follows nothing seen.
        for (final codes in [
          [0x200D, 0x1F308],
          [0x1F3F3, 0xFE0F, 0x200D],
          [0x1F3F3, 0xFE0F, 0x200D, 0x200D, 0x1F308],
          [0x1F3F3, 0x200B, 0x200D, 0x1F308],
          [0x1F3F3, 0xFE0F, 0xFE0F, 0x200D, 0x1F308],
          [0x20, 0xFE0F, 0x200D, 0x1F308],
          [0x1F3F3, 0xFE0F, 0x200D, 0x20, 0x1F308],
          [0x1F3F3, 0xFE0F, 0x200D, 0xFE0F],
        ]) {
          expect(isShownAsWritten(of(codes)), isFalse, reason: '$codes');
        }
      },
    );

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
      // Between two Latin letters or digits a joiner joins nothing: refused (security review of #181); in Persian it shapes the word.
      for (final text in [
        'SE\u200cPA',
        'Revo\u200dlut',
        'Revo\ufe0f\u200dlut',
        'e\u0301\u200dl',
        '1\u200d2',
        '\u0394\u200d\u03b1',
        '\u0411\u200c\u0430',
      ]) {
        expect(isShownAsWritten(text), isFalse, reason: jsonEncode(text));
      }
      expect(
        isShownAsWritten('\u06a9\u0627\u0631\u062a\u200c\u0628\u0647'),
        isTrue,
      );
      // Inside an Indic cluster, a joiner may come before the virama of the letter's script (the Bengali ra-phala; second security review of #181, R9), never before another mark, a virama of another script, or after a Latin letter.
      expect(isShownAsWritten('\u09b0\u200d\u09cd\u09af'), isTrue);
      expect(isShownAsWritten('\u0930\u200d\u094d\u092f'), isTrue);
      expect(isShownAsWritten('\u09b0\u09be\u200d\u09cd\u09af'), isTrue);
      for (final text in [
        '\u09b0\u200d\u09be',
        '\u09b0\u200d\u094d\u09af',
        '\u0930\u200d\u09cd\u092f',
        'a\u200d\u094d',
        'r\u200d\u09cd\u09af',
        '\u09b0\u200d\u200d\u09cd\u09af',
        '\u09b0\u200d\u09cd\u09cd\u09cd\u09cd\u09cd\u09cd\u09cd\u09af',
        '\u200d\u09cd\u09af',
        ' \u200d\u09cd\u09af',
      ]) {
        expect(isShownAsWritten(text), isFalse, reason: jsonEncode(text));
      }
      // A pile of joiner and virama pairs on one letter is counted as its marks, the joiner starting no new count (third security pass of #181, #182): six pass, as six marks do, seven do not, and a pile never resets the count of the marks before it.
      String pile(int pairs) =>
          '\u09b0${'\u200d\u09cd' * pairs}\u09af';
      expect(isShownAsWritten(pile(maxCombiningMarks)), isTrue);
      for (final text in [
        pile(maxCombiningMarks + 1),
        pile(40),
        '\u09b0\u09be\u09be\u09be\u09be\u09be\u09be\u200d\u09cd\u09af',
      ]) {
        expect(isShownAsWritten(text), isFalse, reason: jsonEncode(text));
      }
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
      'a combining mark not at the start, nor after a space or a joiner, and at most six after one character seen, in every script counted',
      () {
        expect(maxCombiningMarks, 6);
        const over = maxCombiningMarks + 1;
        for (final text in [
          '\u0301SEPA',
          'SEPA \u0301',
          'a\u200d\u0301',
          'a${'\u0301' * over}',
          // Alone, or first, in the scripts the review found uncounted (security review of #181).
          '\u064b',
          '\u0489',
          '\u0610Revolut',
          // Piled up in those scripts.
          'a${'\u0610' * over}',
          'a${'\u0489' * over}',
          '\u05d1${'\u0591' * over}',
          '\u0e01${'\u0e48' * over}',
          '\u0915${'\u0901' * over}',
          '\u0b95${'\u0bcd' * over}',
          // A text piled up over its neighbours.
          'Z${'\u0336\u0337\u0338' * 5}algo',
        ]) {
          expect(isShownAsWritten(text), isFalse, reason: jsonEncode(text));
        }
        expect(isShownAsWritten('a\u0301\u0302\u0303'), isTrue);
        expect(isShownAsWritten('a\u0301\u0302\u0303\u0304'), isTrue);
        expect(isShownAsWritten('a${'\u0301' * maxCombiningMarks}'), isTrue);
        expect(isShownAsWritten('a\u0301\u0302\u0303b\u0301'), isTrue);
      },
    );

    test(
      'real names of payment methods, the reviewers\' list: none legitimate refused, the refusals on purpose kept',
      () {
        for (final (name, text, kept) in [
          (
            'Arabic',
            '\u062a\u062d\u0648\u064a\u0644 \u0628\u0646\u0643\u064a',
            true,
          ),
          ('Arabic with harakat', '\u0628\u064e\u0646\u0652\u0643', true),
          (
            'Arabic, Vodafone Cash',
            '\u0641\u0648\u062f\u0627\u0641\u0648\u0646 \u0643\u0627\u0634',
            true,
          ),
          (
            'Persian with ZWNJ',
            '\u06a9\u0627\u0631\u062a\u200c\u0628\u0647\u200c\u06a9\u0627\u0631\u062a',
            true,
          ),
          ('Hindi, UPI', '\u092f\u0942\u092a\u0940\u0906\u0908', true),
          (
            'Hindi with nukta',
            '\u092c\u0948\u0902\u0915 \u091f\u094d\u0930\u093e\u0902\u0938\u092b\u093c\u0930',
            true,
          ),
          ('Hindi with ZWJ', '\u0915\u094d\u200d\u0937', true),
          ('Hindi with ZWNJ', '\u0915\u094d\u200c\u0937', true),
          (
            'Thai, PromptPay',
            '\u0e1e\u0e23\u0e49\u0e2d\u0e21\u0e40\u0e1e\u0e22\u0e4c',
            true,
          ),
          (
            'Thai',
            '\u0e42\u0e2d\u0e19\u0e40\u0e07\u0e34\u0e19\u0e1c\u0e48\u0e32\u0e19\u0e18\u0e19\u0e32\u0e04\u0e32\u0e23',
            true,
          ),
          ('Chinese, Alipay', '\u652f\u4ed8\u5b9d', true),
          ('Chinese, WeChat Pay', '\u5fae\u4fe1\u652f\u4ed8', true),
          ('Korean', '\uce74\uce74\uc624\ud398\uc774', true),
          ('Korean, decomposed jamo', '\u1112\u1161\u11ab', true),
          ('Japanese', '\u9280\u884c\u632f\u8fbc', true),
          (
            'Japanese, decomposed kana',
            '\u30d8\u309a\u30a4\u30d8\u309a\u30a4',
            true,
          ),
          ('full-width Latin', '\uff30\uff41\uff59\uff30\uff41\uff59', true),
          ('emoji', '\u{1f4b5}', true),
          ('emoji with a skin tone', '\u{1f44d}\u{1f3fd}', true),
          ('family', '\u{1f468}\u200d\u{1f469}\u200d\u{1f467}', true),
          ('technologist', '\u{1f9d1}\u200d\u{1f4bb}', true),
          (
            'technologist with a skin tone',
            '\u{1f9d1}\u{1f3fd}\u200d\u{1f4bb}',
            true,
          ),
          ('rainbow flag', '\u{1f3f3}\ufe0f\u200d\u{1f308}', true),
          ('heart on fire', '\u2764\ufe0f\u200d\u{1f525}', true),
          (
            'couple with a heart',
            '\u{1f468}\u200d\u2764\ufe0f\u200d\u{1f468}',
            true,
          ),
          (
            'eye in a speech bubble',
            '\u{1f441}\ufe0f\u200d\u{1f5e8}\ufe0f',
            true,
          ),
          ('bearded man', '\u{1f9d4}\u200d\u2642\ufe0f', true),
          ('polar bear', '\u{1f43b}\u200d\u2744\ufe0f', true),
          ('keycap', '1\ufe0f\u20e3', true),
          ('French flag', '\u{1f1eb}\u{1f1f7}', true),
          ('telephone as text', '\u260e\ufe0e', true),
          ('French, decomposed', 'Espe\u0300ces', true),
          ('French, decomposed transfer', 'Vire\u0301ment SEPA', true),
          ('Vietnamese, decomposed', 'Chuye\u0302\u0309n khoa\u0309n', true),
          ('Vietnamese, decomposed 2', 'Nga\u0302n ha\u0300ng', true),
          ('Hebrew with niqqud', '\u05d1\u05b7\u05bc\u05e0\u05b0\u05e7', true),
          ('Sinhala with ZWJ', '\u0dc1\u0dca\u200d\u0dbb\u0dd3', true),
          ('Bengali', '\u09ac\u09bf\u0995\u09be\u09b6', true),
          ('Tamil', '\u0b95\u0bc2\u0b95\u0bc1\u0bb3\u0bcd \u0baa\u0bc7', true),
          ('Amharic', '\u1274\u120c\u1265\u122d', true),
          ('Burmese', '\u1000\u1031\u1015\u1031\u1038', true),
          (
            'Khmer',
            '\u17a2\u17c1\u179f\u17ca\u17b8\u179b\u17b8\u178a\u17b6',
            true,
          ),
          ('Greek', '\u03a4\u03c1\u03ac\u03c0\u03b5\u03b6\u03b1', true),
          ('Russian', '\u0421\u0431\u0435\u0440\u0431\u0430\u043d\u043a', true),
          ('ASCII', 'Cash App', true),
          ('typographic apostrophe', 'Bank\u2019s transfer', true),
          (
            'Hebrew with dagesh, vowel, cantillation and meteg',
            '\u05d1\u05bc\u05b8\u05a3\u05bd',
            true,
          ),
          ('Bengali ra-phala', '\u09b0\u200d\u09cd\u09af', true),
          ('Bengali, RAB', '\u09b0\u200d\u09cd\u09af\u09be\u09ac', true),
          (
            'Bengali, Bank transfer with ra-phala',
            '\u09ac\u09cd\u09af\u09be\u0999\u09cd\u0995 \u09b0\u200d\u09cd\u09af\u09be\u09aa\u09bf\u09a1',
            true,
          ),
          (
            'Hebrew shin with its dot, dagesh, vowel, meteg and cantillation',
            '\u05e9\u05bc\u05c1\u05b8\u05bd\u0591\u05dc',
            true,
          ),
          (
            'Hebrew, the same with a second accent',
            '\u05e9\u05bc\u05c1\u05b8\u05bd\u0591\u05a3',
            true,
          ),
          ('Tibetan stack', '\u0f56\u0f66\u0f92\u0fb2\u0f74\u0f56\u0f66', true),
          (
            'flag of England (tags)',
            '\u{1f3f4}\u{e0067}\u{e0062}\u{e0065}\u{e006e}\u{e0067}\u{e007f}',
            false,
          ),
          (
            'Malayalam, old chillu',
            '\u0d28\u0d4d\u200d \u0d2c\u0d3e\u0d19\u0d4d\u0d15\u0d4d',
            false,
          ),
          ('Mongolian free variation selector', '\u182e\u180b\u1823', false),
          ('joiner then a space', 'a\u200d b', false),
          ('zero width space alone', '\u200b', false),
          ('ideographic space', '\u9280\u884c\u3000\u632f\u8fbc', false),
        ]) {
          expect(isShownAsWritten(text), kept, reason: name);
        }
      },
    );
  });
}
