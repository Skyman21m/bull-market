import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show GarageKey, RobosatsNetwork;

import '../garage_key_fingerprint.dart';
import '../garage_keyring.dart';
import '../network_garage_key.dart';
import '../p2p_failure.dart';
import '../robot_binding.dart';

/// The RoboSats Garage Keys of each network and the robots derived from them (#81, design note `docs/design/garage-key-from-the-words.md`): the keys of the default wallet's words, by index, and the external key, the one the vault keeps in the slot of each network (drawn at random on this device before #81, or imported in « Robot recovery »), never derived and never mixed with the keys of the words.
///
/// What leaves it is deliberately narrow: which keys the Garage offers, a key as a [NetworkGarageKey] (for the screens of the Garage and the robots of the trades), and robots derived from it, each with the network of its key. The bytes of a key never leave it, and its text form is made by `GarageKeyView` alone, the only class the custody gate allows to reveal it.
/// A key of the words is derived on each call and stored nowhere; the database keeps only the indexes activated and their fingerprints, and a key the words give again that does not match its fingerprint is a [GarageKeyMismatchFailure], never a key.
/// Nothing here draws a key at random: when the words cannot give one, the call fails.
abstract interface class GarageKeyRepository {
  /// Which keys the Garage of [network] offers: the internal Garage Keys activated on [network], from 0 to the highest, the external Garage Key when the vault keeps one (readable or not), the one selected, the last internal one selected, and whether « Your Garage Keys » is due.
  ///
  /// It activates key 0 when none is, so at the first opening of the Garage, key 0 is there; and when no key is selected yet, it selects the external Garage Key when the vault keeps one, making « Your Garage Keys » due, otherwise key 0.
  /// Words that cannot give key 0 leave the external Garage Key as it is, with the reason in [GarageKeyring.internalFailure]; without an external Garage Key, they are the failure.
  @useResult
  Future<Result<GarageKeyring, P2pFailure>> keyring(RobosatsNetwork network);

  /// The key selected on [network] ([select]): the key the Garage opens on.
  ///
  /// For the screens of the Garage and for the line of an order's page that shows the robot the Garage would show; never for a new trade ([forNewTrade]).
  @useResult
  Future<Result<NetworkGarageKey, P2pFailure>> read(RobosatsNetwork network);

  /// The external Garage Key of [network], read from the vault's slot: for the Garage, once [keyring] said it is selected, without reading the keys again. [GarageKeyMissingFailure] when the slot is empty.
  @useResult
  Future<Result<NetworkGarageKey, P2pFailure>> external(RobosatsNetwork network);

  /// The key of the words at [index] on [network], an index this device activated ([GarageKeyMissingFailure] otherwise), derived again and checked against the fingerprint recorded for it.
  @useResult
  Future<Result<NetworkGarageKey, P2pFailure>> derived(
    RobosatsNetwork network,
    int index,
  );

  /// The key of every new trade on [network]: the key selected in the Garage Key card, a key of the words whatever its number or the external key (decided on 2026-11-26), and never another.
  ///
  /// Every key gives robots for new trades, an imported one included (decided on 2026-11-26, #81).
  @useResult
  Future<Result<NetworkGarageKey, P2pFailure>> forNewTrade(
    RobosatsNetwork network,
  );

  /// The key whose robot [slot] is, to finish its trade, whichever key is selected: the key of the words activated with that fingerprint on that network, derived again and checked against it, or the external key, when the fingerprint is its own.
  ///
  /// No such key is a [TradeKeyMissingFailure]: nothing is signed.
  @useResult
  Future<Result<NetworkGarageKey, P2pFailure>> ofSlot(RobotSlot slot);

  /// Activates the key of the words after [after] on [network], which must be the highest activated, selects it, and gives its index: « New internal Garage Key », from whichever internal Garage Key the card shows; the external Garage Key does not count.
  ///
  /// Index 0x7fffffff has no next key ([GarageKeyLastIndexFailure]); an [after] that is no longer the highest, as after a second tap, activates nothing and is a [GarageKeyMissingFailure].
  @useResult
  Future<Result<int, P2pFailure>> activateNext(
    RobosatsNetwork network, {
    required int after,
  });

  /// Selects the internal Garage Key « Back to internal Garage Keys » returns to on [network]: the last internal one selected, else the highest, activating key 0 when none is; the words' refusal when they give none.
  @useResult
  Future<Result<void, P2pFailure>> selectInternal(RobosatsNetwork network);

  /// The index of the internal Garage Key activated on [network] whose fingerprint is [fingerprint], `null` when none is: a key imported must not be one of them (review of #292).
  @useResult
  Future<Result<int?, P2pFailure>> internalIndexOf(
    RobosatsNetwork network,
    GarageKeyFingerprint fingerprint,
  );

  /// Records that « Your Garage Keys » was shown: never again on this device.
  @useResult
  Future<Result<void, P2pFailure>> externalNoticeShown();

  /// Selects [selection] on [network]: the key the card shows and new trades take, kept across restarts. A key of the words only at an index this device activated, the external key only when the vault keeps one; otherwise a [GarageKeyMissingFailure], and nothing is written.
  @useResult
  Future<Result<void, P2pFailure>> select(
    RobosatsNetwork network,
    GarageKeySelection selection,
  );

  /// Whether the Garage of [network] has a key to open on: `false` only when the key selected is the external key and the vault concluded, after its full read budget, that the slot of [network] is empty.
  ///
  /// A key that cannot be read or derived is a failure, never `false`.
  @useResult
  Future<Result<bool, P2pFailure>> exists(RobosatsNetwork network);

  /// The first robot of the key [read] gives that a coordinator can be contacted with, from index 0, tagged with [network].
  @useResult
  Future<Result<NetworkRobot, P2pFailure>> firstUsableRobot(
    RobosatsNetwork network,
  );

  /// Stores [key], a key the user pastes in « Robot recovery », in the vault's slot of [network], which must be empty, and selects it: the external key of that network.
  ///
  /// A slot that holds anything, readable or not, is a [GarageKeyAlreadyStoredFailure], and nothing is written: one external key at a time.
  @useResult
  Future<Result<void, P2pFailure>> import(
    RobosatsNetwork network,
    GarageKey key,
  );

  /// Deletes the external Garage Key of [network], whatever its entry holds, and, when it was selected, selects the last internal Garage Key selected, else the highest. The internal Garage Keys are never deleted: the words back them up.
  ///
  /// Destructive: the robots of that key are lost unless the user kept a copy of it, so call it only on the user's explicit confirmation.
  @useResult
  Future<Result<void, P2pFailure>> delete(RobosatsNetwork network);
}
