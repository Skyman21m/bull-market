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
        'Espèces F2F €',
        'Virement bancaire',
        'Überweisung',
        // Arabic, Hebrew, Persian with its zero width non-joiner between two letters, Chinese, Hindi.
        'تحويل بنكي',
        'העברה בנקאית',
        'کارت‌به‌کارت',
        '银行转账',
        'बैंक ट्रांसफर',
        // Vietnamese written with two combining marks after its letter, a keycap, an emoji with its variation selector, a family joined by zero width joiners, a skin tone.
        'Tiến măt',
        '1️⃣',
        '❤️ Revolut',
        '👨‍👩‍👧',
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
        '​',
        '​​​',
        '‌',
        '‍',
        '️',
        '́',
        '⁠',
        '﻿',
        '­',
        'ㅤ',
        '⠀',
        '\u{e0041}\u{e0042}',
        ' ́ ',
      ]) {
        expect(isShownAsWritten(text), isFalse, reason: jsonEncode(text));
      }
    });

    test(
      'an invisible character, a space other than U+0020, a private use character or a noncharacter is refused anywhere',
      () {
        for (final hidden in [
          ' ',
          ' ',
          ' ',
          ' ',
          ' ',
          ' ',
          ' ',
          '　',
          '⠀',
          '­',
          '͏',
          'ᅟ',
          'ᅠ',
          '឴',
          '឵',
          '᠋',
          '᠎',
          '​',
          '⁠',
          '⁡',
          '⁤',
          '⁪',
          '⁯',
          'ㅤ',
          'ﾠ',
          '﻿',
          '￹',
          '￻',
          '؀',
          '۝',
          '܏',
          '࣢',
          '\u{110bd}',
          '\u{13430}',
          '\u{1bca0}',
          '\u{1d173}',
          // The tag block, which can carry a hidden text.
          '\u{e0001}',
          '\u{e0020}',
          '\u{e0041}',
          '\u{e007f}',
          '',
          '',
          '\u{f0000}',
          '\u{10fffd}',
          '﷐',
          '﷯',
          '￾',
          '￿',
          '\u{1fffe}',
          '\u{10ffff}',
        ]) {
          for (final text in ['SEPA${hidden}Revolut', '${hidden}SEPA', 'SEPA$hidden']) {
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
        'SEPA ',
        'SEPA ‮Revolut',
        'SEPA ⁦Revolut',
        'SEPA‏',
        'SEPA‎',
        'SEPA؜',
        'SEPA\ud800',
      ]) {
        expect(isShownAsWritten(text), isFalse, reason: jsonEncode(text));
      }
    });

    test('a joiner only alone between two characters that are seen', () {
      for (final text in [
        '‌SEPA',
        'SEPA‌',
        'SE‌‌PA',
        'SEPA ‍Revolut',
        'SEPA‍ Revolut',
        'SE‍́PA',
        'SE‍️PA',
      ]) {
        expect(isShownAsWritten(text), isFalse, reason: jsonEncode(text));
      }
      expect(isShownAsWritten('SE‌PA'), isTrue);
    });

    test('a variation selector only right after a character that is seen', () {
      for (final text in [
        '️SEPA',
        'SEPA ️',
        'SEPA️️',
        'SÉ️PA',
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
          '́SEPA',
          'SEPA ́',
          'a‍́',
          'á́́́',
          // A text piled up over its neighbours.
          'Z${'̶̷̸' * 5}algo',
        ]) {
          expect(isShownAsWritten(text), isFalse, reason: jsonEncode(text));
        }
        expect(isShownAsWritten('á̂̃'), isTrue);
        expect(isShownAsWritten('á̂̃b́'), isTrue);
      },
    );
  });
}
