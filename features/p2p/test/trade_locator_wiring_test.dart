import 'dart:io';

import 'package:test/test.dart';

/// The trade screen's cubit is given each action of the chat step from the use case's method of the same meaning (#95): a slip in the composition (« Payment failed? » wired to « fiat sent ») would send the wrong action on a tap, and no screen test would see it, since they give the cubit their own fakes.
void main() {
  // Tests run with the package directory as working directory.
  final locator = File('lib/src/p2p_locator.dart').readAsStringSync();

  test('each action of the chat step is wired to its own method', () {
    for (final (argument, method) in [
      ('confirmFiatSent', 'confirmFiatSent'),
      ('undoFiatSent', 'undoFiatSent'),
      ('startDispute', 'startDispute'),
    ]) {
      expect(
        RegExp(
          '$argument:\\s*locator<ChatStepActionUsecase>\\(\\)\\.$method\\b',
        ).hasMatch(locator),
        isTrue,
        reason: argument,
      );
    }
  });

  test('the cancel is wired to the cancel use case', () {
    expect(
      RegExp(r'locator<CancelTradeUsecase>\(\)\.execute').hasMatch(locator),
      isTrue,
    );
  });
}
