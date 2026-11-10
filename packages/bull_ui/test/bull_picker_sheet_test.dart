import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_app.dart';

void main() {
  group('BullPickerSheet', () {
    testWidgets('a long title wraps and keeps the close button on screen', (
      tester,
    ) async {
      const title = 'Sélectionner la devise de paiement pour cet échange';
      tester.view
        ..physicalSize = const Size(320, 640)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        wrapWithTheme(
          BullPickerSheet<String>(
            title: title,
            options: const ['EUR', 'USD'],
            isSelected: (option) => option == 'EUR',
            label: (option) => option,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final titleSize = tester.getSize(find.text(title));
      final lineHeight = tester.getSize(find.text('EUR')).height;
      expect(titleSize.height, greaterThan(lineHeight));
      final close = tester.getRect(find.byIcon(Icons.close));
      expect(close.right, lessThanOrEqualTo(320));
    });

    testWidgets('a short title stays on one centred line', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          BullPickerSheet<String>(
            title: 'Theme',
            options: const ['Light', 'Dark'],
            isSelected: (option) => option == 'Dark',
            label: (option) => option,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.text('Theme'));
      expect(text.textAlign, TextAlign.center);
      // Centred in the width left between the leading gap and the close button.
      final title = tester.getCenter(find.text('Theme'));
      final sheet = tester.getRect(find.byType(BullPickerSheet<String>));
      expect((title.dx - sheet.center.dx).abs(), lessThan(40));
    });
  });
}
