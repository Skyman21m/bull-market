import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../garage_keyring.dart';
import '../network_garage_key.dart';
import '../p2p_failure.dart';
import '../repositories/garage_key_repository.dart';

/// The Garage Keys of a network for the screens of the Garage (#81): which keys it offers, and a key to show, with that network: `GarageKeyView` shows it behind the PIN, and the account navigator derives robot number N from it.
///
/// Call it when the user opens the Garage or moves between its keys, never in the background.
/// Hold a key no longer than the screen that uses it.
final class ReadGarageKeyUsecase {
  final GarageKeyRepository _repository;

  const ReadGarageKeyUsecase(this._repository);

  /// Which keys the Garage of [network] offers; it activates key 0 at the first visit ([GarageKeyRepository.keyring]).
  @useResult
  Future<Result<GarageKeyring, P2pFailure>> keyring(RobosatsNetwork network) =>
      _repository.keyring(network);

  /// The key the Garage of [network] opens on ([GarageKeyRepository.read]).
  @useResult
  Future<Result<NetworkGarageKey, P2pFailure>> execute(
    RobosatsNetwork network,
  ) => _repository.read(network);

  /// Selects [selection], the key the card shows and new trades take, kept across restarts ([GarageKeyRepository.select]): an arrow of the Garage Key card.
  @useResult
  Future<Result<void, P2pFailure>> select(
    RobosatsNetwork network,
    GarageKeySelection selection,
  ) => _repository.select(network, selection);

  /// The external Garage Key of [network] ([GarageKeyRepository.external]): the Garage reads it once the keyring said it is selected.
  @useResult
  Future<Result<NetworkGarageKey, P2pFailure>> external(
    RobosatsNetwork network,
  ) => _repository.external(network);

  /// Selects the internal Garage Key « Back to internal Garage Keys » returns to ([GarageKeyRepository.selectInternal]).
  @useResult
  Future<Result<void, P2pFailure>> selectInternal(RobosatsNetwork network) =>
      _repository.selectInternal(network);

  /// Records that « Your Garage Keys » was shown ([GarageKeyRepository.externalNoticeShown]).
  @useResult
  Future<Result<void, P2pFailure>> externalNoticeShown() =>
      _repository.externalNoticeShown();

  /// The key of the words at [index], derived again and checked against its fingerprint ([GarageKeyRepository.derived]).
  @useResult
  Future<Result<NetworkGarageKey, P2pFailure>> derived(
    RobosatsNetwork network,
    int index,
  ) => _repository.derived(network, index);
}
