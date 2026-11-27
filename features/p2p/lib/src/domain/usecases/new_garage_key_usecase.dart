import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../p2p_failure.dart';
import '../repositories/garage_key_repository.dart';

/// « New internal Garage Key » (#81, design note `docs/design/garage-key-from-the-words.md` § 6): activates the internal Garage Key after the highest one and selects it, so that new trades take it; nothing is erased, the earlier keys stay in the Garage, each finishing its trades and selectable again for new ones.
///
/// Call it only from the user's explicit confirmation, never at startup or in the background.
final class NewGarageKeyUsecase {
  final GarageKeyRepository _repository;

  const NewGarageKeyUsecase(this._repository);

  /// Activates the key after [after], the highest key of [network] the screen showed, and gives its index.
  ///
  /// When [after] is no longer the highest (a second tap, or another screen first), nothing is activated: a [GarageKeyMissingFailure], and the Garage reads its keys again. Index 0x7fffffff has no next key ([GarageKeyLastIndexFailure]).
  @useResult
  Future<Result<int, P2pFailure>> execute(
    RobosatsNetwork network, {
    required int after,
  }) => _repository.activateNext(network, after: after);
}
