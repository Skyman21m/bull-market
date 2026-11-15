import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/ui/widgets/word_fit_text.dart';

/// [WordFitText]: its text scale lowered just enough for its longest word to fit, a word being what lies between breaking spaces, and never under the text's own size (second pass of the review of #145). The test font draws each glyph as a square of the text's size.
void main() {
  Future<double> scaleOf(
    WidgetTester tester,
    String text, {
    required double width,
    required double scale,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: width,
              child: WordFitText(text, style: const TextStyle(fontSize: 10)),
            ),
          ),
        ),
      ),
    );
    return tester.widget<Text>(find.byType(Text)).textScaler!.scale(10) / 10;
  }

  testWidgets('a text whose words fit keeps the user\'s scale', (tester) async {
    expect(await scaleOf(tester, 'ab cd ef', width: 100, scale: 3), 3);
  });

  testWidgets(
    'a group joined by non-breaking spaces is one word: the scale is lowered for the whole group, not its pieces',
    (tester) async {
      // « 1 234 567,1234 », 14 glyphs: 420 wide at ×3, in a room of 200.
      final scale = await scaleOf(
        tester,
        'de 1 234 567,1234 EUR',
        width: 200,
        scale: 3,
      );
      expect(scale * 10 * 14, lessThanOrEqualTo(200));
      expect(scale, greaterThan(1));
      // The same with U+00A0, whose pieces alone (« 1 », « 234 ») would fit at ×3.
      expect(
        await scaleOf(tester, 'de 1 234 567 EUR', width: 200, scale: 3),
        lessThan(3),
      );
    },
  );

  testWidgets(
    'never under the text\'s own size: a word too wide even then keeps a scale of 1, or the user\'s when smaller',
    (tester) async {
      // 30 glyphs: 300 wide at ×1, in a room of 100.
      final long = 'x' * 30;
      expect(await scaleOf(tester, long, width: 100, scale: 3), 1);
      expect(await scaleOf(tester, long, width: 100, scale: 0.8), 0.8);
    },
  );
}
