import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show GarageKey, RobosatsNetwork;

import '../garage_keyring.dart';
import '../network_garage_key.dart';
import '../p2p_failure.dart';
import '../robot_binding.dart';

/// The RoboSats Garage Keys of each network and the robots derived from them (#81, design note `docs/design/garage-key-from-the-words.md`): the keys of the default wallet's words, by index, and, until the book of P2P is emptied once, the key drawn at random before #81 that the vault keeps, used only to finish its trades.
///
/// What leaves it is deliberately narrow: which keys the Garage offers, a key as a [NetworkGarageKey] (for the screens of the Garage and the robots of the trades), and robots derived from it, each with the network of its key. The bytes of a key never leave it, and its text form is made by `GarageKeyView` alone, the only class the custody gate allows to reveal it.
/// A key of the words is derived on each call and stored nowhere; the database keeps only the indexes activated and their fingerprints, and a key the words give again that does not match its fingerprint is a [GarageKeyMismatchFailure], never a key.
/// Nothing here draws a key at random: when the words cannot give one, the call fails.
abstract interface class GarageKeyRepository {
  /// Which keys the Garage of [network] offers: [LegacyGarageKeyring] while a trade of the key drawn at random is in progress, otherwise the keys of the words activated on [network], from 0 to the highest.
  ///
  /// It finishes the one-time switch first when the database emptied the book (the vault's two slots deleted, then the switch marked done), and activates key 0 when none is: so at the first opening of the Garage, key 0 is there.
  @useResult
  Future<Result<GarageKeyring, P2pFailure>> keyring(RobosatsNetwork network);

  /// The key the Garage of [network] opens on: the key drawn at random while the switch waits ([GarageKeyMissingFailure] when the vault holds none), otherwise the highest key of the words.
  ///
  /// For the screens of the Garage and for the line of an order's page that shows the robot the Garage would show; never for a new trade ([forNewTrade]).
  @useResult
  Future<Result<NetworkGarageKey, P2pFailure>> read(RobosatsNetwork network);

  /// The key of the words at [index] on [network], an index this device activated ([GarageKeyMissingFailure] otherwise), derived again and checked against the fingerprint recorded for it.
  @useResult
  Future<Result<NetworkGarageKey, P2pFailure>> derived(
    RobosatsNetwork network,
    int index,
  );

  /// The key of every new trade on [network]: the highest key of the words activated, and never another.
  ///
  /// While the switch waits for a trade of the key drawn at random to finish, a [GarageKeySwitchPendingFailure]: no new trade starts on that key, nor on any key of the words yet.
  @useResult
  Future<Result<NetworkGarageKey, P2pFailure>> forNewTrade(
    RobosatsNetwork network,
  );

  /// The key whose robot [slot] is, to finish its trade: the key drawn at random while the switch waits, otherwise the key of the words activated with that fingerprint on that network, derived again and checked against it.
  ///
  /// No such key is a [TradeKeyMissingFailure]: nothing is signed.
  @useResult
  Future<Result<NetworkGarageKey, P2pFailure>> ofSlot(RobotSlot slot);

  /// Activates the key after [after] on [network], which must be the highest activated, and gives its index: « New key ».
  ///
  /// Index 0x7fffffff has no next key ([GarageKeyLastIndexFailure]); an [after] that is no longer the highest, as after a second tap, activates nothing and is a [GarageKeyMissingFailure]; while the switch waits, a [GarageKeySwitchPendingFailure].
  @useResult
  Future<Result<int, P2pFailure>> activateNext(
    RobosatsNetwork network, {
    required int after,
  });

  /// Whether the Garage of [network] has a key to open on: `false` only while the switch waits and the vault concluded, after its full read budget, that the slot of [network] is empty.
  ///
  /// A key that cannot be read or derived is a failure, never `false`.
  @useResult
  Future<Result<bool, P2pFailure>> exists(RobosatsNetwork network);

  /// The first robot of the key [read] gives that a coordinator can be contacted with, from index 0, tagged with [network].
  @useResult
  Future<Result<NetworkRobot, P2pFailure>> firstUsableRobot(
    RobosatsNetwork network,
  );

  /// Stores [key], a key the user restores, in the vault's slot of [network], which must be empty.
  ///
  /// No screen reaches it in this version: the paste of a key from elsewhere comes back beside the keys of the words with #79.
  /// A slot that holds anything, readable or not, is a [GarageKeyAlreadyStoredFailure], and nothing is written.
  @useResult
  Future<Result<void, P2pFailure>> import(
    RobosatsNetwork network,
    GarageKey key,
  );
}
