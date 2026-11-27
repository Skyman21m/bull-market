import 'package:meta/meta.dart';

import 'garage_key_fingerprint.dart';
import 'p2p_failure.dart';

/// The Garage Key selected on a network, the key of every new trade there (#81, decided on 2026-11-26): an internal Garage Key (a key of the words) by its index, or the external Garage Key.
sealed class GarageKeySelection {
  const GarageKeySelection();
}

/// The internal Garage Key at [index], a key of the default wallet's words.
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

/// The external Garage Key: the one the vault keeps in the slot of the network, drawn at random on this device before #81 or imported.
final class SelectedExternalKey extends GarageKeySelection {
  const SelectedExternalKey();

  @override
  bool operator ==(Object other) => other is SelectedExternalKey;

  @override
  int get hashCode => (SelectedExternalKey).hashCode;

  @override
  String toString() => 'SelectedExternalKey()';
}

/// Which Garage Keys the Garage of a network offers (#81, design note `docs/design/garage-key-from-the-words.md` § 6): the internal Garage Keys this device activated, from 0 to [highest], the external Garage Key when the vault keeps one, and the one [selected]. It holds no key: the keys are derived again, or read from the vault, whenever a screen or a trade needs one.
@immutable
final class GarageKeyring {
  /// The highest internal Garage Key activated: « New internal Garage Key » activates the one after it. The external Garage Key does not count.
  ///
  /// `null` only when no internal Garage Key is activated and the words cannot give key 0 ([internalFailure]) while the vault keeps an external Garage Key: the external Garage Key stays usable, and only the internal side says why.
  final int? highest;

  /// Why the words cannot give the internal Garage Keys (no default wallet, a passphrase, a secret without words, a locked or unreadable keystore), when [highest] is `null` for that reason.
  final P2pFailure? internalFailure;

  /// The key selected, the key shown and the key of new trades.
  final GarageKeySelection selected;

  /// The last internal Garage Key selected, where « Back to internal Garage Keys » returns; `null` when none was selected yet, and the highest is then taken.
  final int? lastInternal;

  /// Whether « Your Garage Keys » is due: made due by the update to schema 10, and not shown yet; the Garage shows it on the external Garage Key, the key the vault kept, named so from then on.
  final bool externalNoticeDue;

  /// The fingerprint recorded for each index of the words, by index: which key a line of the history or of the trades is of. Never a key.
  final List<GarageKeyFingerprint> fingerprints;

  /// The fingerprint of the external key, `null` when the vault keeps none for the network or it cannot be read.
  final GarageKeyFingerprint? external;

  /// Why the external key the vault keeps for the network cannot be read, when it cannot (`null` when it can, or when the vault keeps none): its position stays, so that the user may try again or remove it.
  final P2pFailure? externalFailure;

  const GarageKeyring({
    required this.highest,
    required this.selected,
    this.internalFailure,
    this.lastInternal,
    this.externalNoticeDue = false,
    this.fingerprints = const [],
    this.external,
    this.externalFailure,
  });

  /// Whether the vault keeps an external Garage Key for the network, readable or not.
  bool get hasExternal => external != null || externalFailure != null;

  /// The internal Garage Key « Back to internal Garage Keys » selects: the last one selected, else the highest; `null` when none is activated.
  int? get internalToReturnTo => switch ((lastInternal, highest)) {
    (final last?, final highest?) when last <= highest => last,
    (_, final highest) => highest,
  };

  @override
  bool operator ==(Object other) =>
      other is GarageKeyring &&
      other.highest == highest &&
      other.selected == selected &&
      other.lastInternal == lastInternal &&
      other.externalNoticeDue == externalNoticeDue &&
      other.external == external &&
      other.internalFailure.runtimeType == internalFailure.runtimeType &&
      other.externalFailure.runtimeType == externalFailure.runtimeType;

  @override
  int get hashCode => Object.hash(highest, selected, lastInternal, external);

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
