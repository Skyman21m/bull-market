import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show GarageKey;

import '../../domain/garage_key_text.dart';

/// The one place a Garage Key reaches the clipboard: it writes the text `GarageKeyView` gives it, and empties the clipboard [clearAfter] later if it still holds that key.
///
/// One object for the whole feature, registered once, so that the clipboard is emptied even after the screen that copied the key is gone, and at once when the app is torn down (its lifecycle detaches): best effort, since swiping the app away usually kills the process before it runs.
/// Until then it keeps the key as a [GarageKey], never its text, and tells whether the clipboard still holds it by reading what the clipboard holds and parsing it: a key the user replaced with something else is left alone.
/// That read brings another app's clip into memory, for the time of the comparison; Android turns a clip that is not text, such as a content URI, into text to answer it, and Android 12 and later may show « pasted from your clipboard » when the clip came from another app.
/// When the clipboard cannot be read, as on Android 10 and later while the app is in the background, it is emptied anyway: a key left there is worse than another clip lost.
///
/// What the 30 seconds do not protect: the clip is not flagged sensitive, because Flutter's `Clipboard.setData` cannot set `ClipDescription.EXTRA_IS_SENSITIVE` and the app has no platform channel for it yet (issue #56; the wallet's BIP85 copy has the same gap).
/// So from Android 13 the system shows a preview of the copied key at each copy, and a keyboard with a clipboard history may keep its own copy, which clearing the clipboard does not remove.
/// A key still on the clipboard when the app is killed stays there.
final class GarageKeyClipboard {
  /// How long a copied key may stay on the clipboard, as the wallet does for the BIP85 entropy it copies.
  static const clearAfter = Duration(seconds: 30);

  Timer? _clear;

  /// The key copied last, until the clipboard is emptied of it.
  GarageKey? _copied;

  /// Clears at once when the app is torn down.
  late final AppLifecycleListener _lifecycle;

  /// The locator creates it when the Garage first needs it.
  GarageKeyClipboard() {
    _lifecycle = AppLifecycleListener(
      onDetach: () => unawaited(_clearIfStillHolds()),
    );
  }

  /// Writes [text], the `robo1…` form of [key], to the clipboard, and arms its clearing; `false` when the platform refused it.
  ///
  /// A refused write changes nothing: the clearing of a key copied before stays armed.
  Future<bool> copy(GarageKey key, String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } on Exception {
      return false;
    }
    _clear?.cancel();
    _copied = key;
    _clear = Timer(clearAfter, () => unawaited(_clearIfStillHolds()));
    return true;
  }

  /// Whether a key copied is waiting to be cleared.
  bool get isArmed => _clear?.isActive ?? false;

  Future<void> _clearIfStillHolds() async {
    _clear?.cancel();
    _clear = null;
    final key = _copied;
    _copied = null;
    if (key == null) return;
    String? held;
    try {
      held = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } on Exception {
      held = null;
    }
    final stillHolds =
        held == null ||
        switch (GarageKey.parse(normalizeGarageKeyText(held))) {
          Ok(:final value) => value == key,
          Err() => false,
        };
    if (!stillHolds) return;
    try {
      await Clipboard.setData(const ClipboardData(text: ''));
    } on Exception {
      // Nothing more can be done from the app: the platform keeps the clip.
    }
  }

  /// Clears at once what the timer would clear later, and stops listening to the app's lifecycle: when the feature is torn down.
  Future<void> dispose() async {
    _lifecycle.dispose();
    await _clearIfStillHolds();
  }
}
