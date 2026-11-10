import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

/// Reads what a coordinator says about itself, and checks that it is the coordinator of the federation list.
final class FetchCoordinatorInfoUsecase {
  final CoordinatorClient _client;

  const FetchCoordinatorInfoUsecase(this._client);

  /// `/api/info/` of [coordinator] on [network]: a network or a Lightning node other than the federation list gives is a [CoordinatorIdentityFailure].
  Future<Result<CoordinatorInfo, CoordinatorFailure>> execute(
    Coordinator coordinator,
    RobosatsNetwork network,
  ) => _client.fetchInfo(coordinator, network);
}
