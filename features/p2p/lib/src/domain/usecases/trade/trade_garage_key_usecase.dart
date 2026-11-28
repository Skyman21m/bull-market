import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../../network_garage_key.dart';
import '../../repositories/garage_key_repository.dart';
import '../../robot_binding.dart';
import '../../trade/trade_take.dart';

/// The Garage Key a new trade uses, for « Store your garage key » (#318, decided on 2026-11-28): the reminder is shown before a make or a take only when that key is the external Garage Key, the one the vault keeps (drawn at random before #81, or imported), which nothing else backs up; a key of the wallet's words comes back with the words, and the trade goes on without it.
///
/// A make takes the key selected in the Garage Key card ([GarageKeyRepository.forNewTrade]), read when its robot is reserved, after the reminder; a take uses the robot reserved when it was prepared, whose origin its preparation keeps ([PreparedTake.externalKey]).
/// The key itself leaves here only for the copy of « Back it up! », once the wallet's re-authentication passed, and only when it is the external one: the screen hands it to the Garage's clipboard and keeps it no longer.
final class TradeGarageKeyUsecase {
  final GarageKeyRepository _keys;

  /// `TakeOrderUsecase.externalRobotOf`, the only reader of the takes prepared: the robot of a prepared take, without its token, when it was reserved from the external Garage Key.
  final RobotSlot? Function(PreparedTake prepared) _externalRobotOf;

  const TradeGarageKeyUsecase(this._keys, this._externalRobotOf);

  /// Whether a make on [network] now would take the external Garage Key: its reminder is shown then. A key that cannot be read says `true`, the reminder shown as before #318: the make that follows says why it fails.
  Future<bool> makeUsesExternalKey(RobosatsNetwork network) async =>
      switch (await _keys.forNewTrade(network)) {
        Ok(:final value) => value.index == null,
        Err() => true,
      };

  /// The external Garage Key a make on [network] would take, for the copy of « Back it up! » only; `null` when the key new trades take is a key of the words, or cannot be read.
  Future<NetworkGarageKey?> externalKeyOfMake(RobosatsNetwork network) async =>
      switch (await _keys.forNewTrade(network)) {
        Ok(:final value) when value.index == null => value,
        _ => null,
      };

  /// The external Garage Key of the robot that will take [prepared], for the copy of « Back it up! » only: the key the vault keeps for the take's network, when the robot reserved for [prepared] is still its order's, was reserved from the external key, and is derived from that key (its fingerprint); `null` otherwise.
  Future<NetworkGarageKey?> externalKeyOfTake(PreparedTake prepared) async {
    final slot = _externalRobotOf(prepared);
    if (slot == null) return null;
    return switch (await _keys.external(slot.network)) {
      Ok(:final value) => switch (value.fingerprint) {
        Ok(value: final fingerprint) when fingerprint == slot.keyFingerprint =>
          value,
        _ => null,
      },
      Err() => null,
    };
  }
}
