import 'package:primitives/primitives.dart';

import '../network_garage_key.dart';
import '../repositories/robot_binding_repository.dart';

/// Whether deleting the Garage Key of a slot, by « Delete All », « Generate new » or the way out of a key that cannot be read, asks the wallet's PIN after « Delete Garage Key? ».
///
/// RoboSats asks only the confirmation.
/// Troc asks the PIN as well once a robot of the key may live on a coordinator, since deleting the key then loses robots that a coordinator knows, and whatever they hold there, unless the user kept a copy.
/// It reads the feature's database only, never the vault, and says `true` whenever it cannot tell, so that a failure never skips the PIN.
final class NeedsPinToDeleteGarageKeyUsecase {
  final RobotBindingRepository _bindings;

  const NeedsPinToDeleteGarageKeyUsecase(this._bindings);

  /// Whether the PIN is asked before the key of [key] is deleted, or, when [key] is `null` because the slot could not be read or gives no robot, before its entry is.
  ///
  /// A key needs it when a robot index of it is bound, on either network, or when it is not recorded as drawn on this device for the network of its slot.
  /// A slot that cannot be read always needs it, without a read: the keystore may give its key back later, intact and possibly with robots on coordinators, and nothing tells which key it holds.
  /// A key whose fingerprint cannot be computed, and a database that cannot be read, need it too.
  Future<bool> execute(NetworkGarageKey? key) async {
    if (key == null) return true;
    return switch (key.fingerprint) {
      Ok(value: final fingerprint) => switch (await _bindings.exposureOf(
        key.network,
        fingerprint,
      )) {
        Ok(:final value) => value.mayHaveRobotsOnCoordinators,
        Err() => true,
      },
      Err() => true,
    };
  }
}
