import 'dart:async';

import 'package:flutter/services.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show GarageKey;

import '../../domain/garage_key_text.dart';

/// The one place a Garage Key reaches the clipboard: it writes the text `GarageKeyView` gives it, and empties the clipboard [clearAfter] later if it still holds that key.
///
/// One object for the whole feature, registered once, so that the clipboard is emptied even after the screen that copied the key is gone.
/// Until then it keeps the key as a [GarageKey], never its text, and tells whether the clipboard still holds it by parsing what the clipboard holds: a key the user replaced with something else is left alone.
/// When the clipboard cannot be read, as on Android 10 and later while the app is in the background, it is emptied anyway: a key left there is worse than another clip lost.
/// Flutter cannot mark a clip as sensitive (Android 13 hides such a clip from its clipboard preview), and the wallet has no channel of its own for it, so the clip is not marked.
final class GarageKeyClipboard {
  /// How long a copied key may stay on the clipboard, as the wallet does for the BIP85 entropy it copies.
  static const clearAfter = Duration(seconds: 30);

  Timer? _clear;

  /// The key copied last, until the clipboard is emptied of it.
  GarageKey? _copied;

  /// Writes [text], the `robo1…` form of [key], to the clipboard, and arms its clearing; `false` when the platform refused it.
  Future<bool> copy(GarageKey key, String text) async {
    _clear?.cancel();
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } on PlatformException {
      return false;
    }
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
    } on PlatformException {
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
    } on PlatformException {
      // Nothing more can be done from the app: the platform keeps the clip.
    }
  }

  /// Clears at once what the timer would clear later, when the feature is torn down.
  Future<void> dispose() => _clearIfStillHolds();
}
