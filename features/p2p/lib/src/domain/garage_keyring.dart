import 'package:meta/meta.dart';

import 'garage_key_fingerprint.dart';
import 'p2p_failure.dart';

/// The Garage Key selected on a network, the key of every new trade there (#81, the owner's decisions of 2026-11-26): a key of the words by its index, or the external key.
sealed class GarageKeySelection {
  const GarageKeySelection();
}

/// The key of the words at [index].
@immutable
final class SelectedWordsKey extends GarageKeySelection {
  final int index;

  const SelectedWordsKey(this.index);

  @override
  bool operator ==(Object other) =>
      other is SelectedWordsKey && other.index == index;

  @override
  int get hashCode => index.hashCode;

  @override
  String toString() => 'SelectedWordsKey($index)';
}

/// The external key: the one the vault keeps in the slot of the network, drawn at random on this device before #81 or pasted from elsewhere.
final class SelectedExternalKey extends GarageKeySelection {
  const SelectedExternalKey();

  @override
  bool operator ==(Object other) => other is SelectedExternalKey;

  @override
  int get hashCode => (SelectedExternalKey).hashCode;

  @override
  String toString() => 'SelectedExternalKey()';
}

/// Which Garage Keys the Garage of a network offers (#81, design note `docs/design/garage-key-from-the-words.md` § 6): the keys of the words this device activated, from 0 to [highest], the external key when the vault keeps one, and the one [selected]. It holds no key: the keys are derived again, or read from the vault, whenever a screen or a trade needs one.
@immutable
final class GarageKeyring {
  /// The highest index of the words activated: « New key » activates the one after it, whichever key is selected. The external key does not count.
  final int highest;

  /// The key selected, the key shown and the key of new trades.
  final GarageKeySelection selected;

  /// The fingerprint recorded for each index of the words, by index: which key a line of the history or of the trades is of. Never a key.
  final List<GarageKeyFingerprint> fingerprints;

  /// The fingerprint of the external key, `null` when the vault keeps none for the network or it cannot be read.
  final GarageKeyFingerprint? external;

  /// Why the external key the vault keeps for the network cannot be read, when it cannot (`null` when it can, or when the vault keeps none): its position stays, so that the user may try again or remove it.
  final P2pFailure? externalFailure;

  const GarageKeyring({
    required this.highest,
    required this.selected,
    this.fingerprints = const [],
    this.external,
    this.externalFailure,
  });

  /// Whether the vault keeps an external key for the network, readable or not.
  bool get hasExternal => external != null || externalFailure != null;

  @override
  bool operator ==(Object other) =>
      other is GarageKeyring &&
      other.highest == highest &&
      other.selected == selected &&
      other.external == external &&
      other.externalFailure.runtimeType == externalFailure.runtimeType;

  @override
  int get hashCode => Object.hash(highest, selected, external);

  @override
  String toString() =>
      'GarageKeyring($highest, $selected, external: $hasExternal)';
}

/// A key of the words this device activated: its index and the fingerprint of the key the words gave there when it was activated, never the key.
@immutable
final class ActivatedGarageKey {
  final int index;
  final GarageKeyFingerprint fingerprint;

  const ActivatedGarageKey(this.index, this.fingerprint);

  @override
  bool operator ==(Object other) =>
      other is ActivatedGarageKey &&
      other.index == index &&
      other.fingerprint == fingerprint;

  @override
  int get hashCode => Object.hash(index, fingerprint);

  @override
  String toString() => 'ActivatedGarageKey($index)';
}
