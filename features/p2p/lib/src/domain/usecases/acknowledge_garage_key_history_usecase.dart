import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';

import '../network_garage_key.dart';
import '../p2p_failure.dart';
import '../repositories/robot_binding_repository.dart';

/// Records that the user acknowledged the unknown history of a Garage Key on one network: its robots may already live on coordinators, and each may now be bound to one.
///
/// Call it only from the user's explicit acknowledgement in the Garage, never on the user's behalf, at startup or in the background.
/// It is the only caller of `RobotBindingRepository.recordAcknowledgedKey` (`robot_bindings_architecture_test.dart`).
final class AcknowledgeGarageKeyHistoryUsecase {
  final RobotBindingRepository _bindings;

  const AcknowledgeGarageKeyHistoryUsecase(this._bindings);

  /// Records the acknowledgement of the key of [key] on the network of its slot.
  ///
  /// A key recorded as drawn on this device keeps that record, and a key already acknowledged keeps its first acknowledgement; a later import of the key makes its history unknown again.
  /// A key whose fingerprint cannot be computed, or a record that cannot be written, is a failure, and nothing is recorded.
  @useResult
  Future<Result<void, P2pFailure>> execute(NetworkGarageKey key) async =>
      switch (key.fingerprint) {
        Ok(value: final fingerprint) => await _bindings.recordAcknowledgedKey(
          key.network,
          fingerprint,
        ),
        Err(:final failure) => Err(failure),
      };
}
