import 'package:meta/meta.dart';

import 'garage_key_fingerprint.dart';

/// Which Garage Keys the Garage of a network offers (#81, design note `docs/design/garage-key-from-the-words.md` § 6, § 8).
///
/// It holds no key: the keys are derived again, by their index, whenever a screen or a trade needs one.
sealed class GarageKeyring {
  const GarageKeyring();
}

/// The book of P2P is not emptied yet because a trade is in progress: the Garage stays on the key drawn at random before #81, which only finishes those trades (no new trade, no other key), with one line saying so.
final class LegacyGarageKeyring extends GarageKeyring {
  const LegacyGarageKeyring();

  @override
  bool operator ==(Object other) => other is LegacyGarageKeyring;

  @override
  int get hashCode => (LegacyGarageKeyring).hashCode;

  @override
  String toString() => 'LegacyGarageKeyring()';
}

/// The keys of the words this device activated on the network, from 0 up to [highest], the key of every new trade; the earlier ones finish their trades and are shown with the arrows of the Garage Key card.
@immutable
final class DerivedGarageKeyring extends GarageKeyring {
  /// The highest index activated: the key of every new trade.
  final int highest;

  const DerivedGarageKeyring(this.highest);

  @override
  bool operator ==(Object other) =>
      other is DerivedGarageKeyring && other.highest == highest;

  @override
  int get hashCode => highest.hashCode;

  @override
  String toString() => 'DerivedGarageKeyring($highest)';
}

/// Where the one-time switch of #81 stands, for the whole book (both networks): what `p2p.sqlite` keeps in `garage_switch`.
///
/// It only moves forward: [legacy] while a trade of the key drawn at random is in progress, [emptying] once none is (the database empties its tables when it opens), [vaultPending] once they are empty (the vault's two Garage Key slots are deleted next), then [derived] for good. A database created at schema 10 starts at [derived].
enum GarageSwitchState { legacy, emptying, vaultPending, derived }

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
