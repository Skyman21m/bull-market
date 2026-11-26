import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../p2p_failure.dart';
import '../repositories/garage_key_repository.dart';

/// Tells whether the Garage of a network has a key to open on (#81): the key selected, an internal Garage Key or the external Garage Key.
///
/// `false` only when the key selected is the external Garage Key and the vault concluded that its slot is empty (`GarageKeyRepository.exists`), after which the take and the make say « You do not have a Garage Key » and lead to the Garage.
/// A failure is never an absence: after [GarageKeyLockedFailure], ask to unlock the device and try again; the words that cannot give a key say why ([GarageKeyNoWalletFailure], [GarageKeyPassphraseFailure], …), and nothing draws a key in its place.
final class HasGarageKeyUsecase {
  final GarageKeyRepository _repository;

  const HasGarageKeyUsecase(this._repository);

  @useResult
  Future<Result<bool, P2pFailure>> execute(RobosatsNetwork network) =>
      _repository.exists(network);
}
