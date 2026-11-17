import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

/// Reads a coordinator's `/api/limits/` anonymously, with no robot, as the book reads its orders: the price of a bitcoin and the order size bounds in each currency, which the create form (#181) shows and judges the amount with (`components/MakerForm/MakerForm.tsx:106-131`, commit ff1998c).
///
/// What the make then sends is judged again by `MakeOrderUsecase` on a read of its own, just before the make; this read only fills the form.
final class FetchCoordinatorLimitsUsecase {
  final CoordinatorClient _client;

  const FetchCoordinatorLimitsUsecase(this._client);

  Future<Result<CurrencyLimits, CoordinatorFailure>> execute(
    Coordinator coordinator,
    RobosatsNetwork network,
  ) => _client.fetchLimits(coordinator, network);
}
