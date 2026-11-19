import 'package:primitives/primitives.dart';

import '../../p2p_failure.dart';
import '../../robot_binding.dart';
import '../../trade/trade_renewal.dart';
import '../../trade_record.dart';

/// `MakeOrderUsecase.renewalsOf`, which the locator gives the use case.
typedef RenewalsOf =
    Stream<Result<OrderRenewals, P2pFailure>> Function(TradeRecord record);

/// The robot the Garage moves to after a renewal of the order of a « Last order #N » the user tapped (#227): read from the device only, nothing sent.
///
/// The orders made here after an order with its very terms, on its coordinator ([OrderRenewals.since], from `MakeOrderUsecase.renewalsOf`), are its renewals, or an order made again by hand with the same terms, which this device cannot tell apart (functional review of #220, R1).
/// The Garage shows the robot of such an order once this device sees its bond locked ([OrderMadeSince.bondLocked]: public, paused, or further), never while it waits for its bond (the owner's decision of 2026-11-19, on #227).
/// One whose bond was already seen locked when the Garage started following is left alone, so that coming back from the order opened, the Garage still shows that order's robot.
final class FollowRenewalUsecase {
  final RenewalsOf _renewalsOf;

  const FollowRenewalUsecase(this._renewalsOf);

  /// The robot of each order made here since [record] with its terms whose bond this device sees locked after the first list it read, the newest when several are seen locked at once; nothing while the records or the terms cannot be read, and nothing at all for an order not made here (no terms kept of it).
  Stream<RobotSlot> execute(TradeRecord record) async* {
    // The robots of the orders whose bond was seen locked: from the first list read, which only sets them, then from each later one.
    Set<RobotSlot>? seen;
    await for (final result in _renewalsOf(record)) {
      if (result case Ok(value: final renewals)) {
        final locked = [
          for (final made in renewals.since)
            if (made.bondLocked) made.record.robot,
        ];
        final known = seen;
        if (known == null) {
          seen = locked.toSet();
          continue;
        }
        final fresh = [
          for (final robot in locked)
            if (!known.contains(robot)) robot,
        ];
        known.addAll(fresh);
        // Oldest first: the last is the newest.
        if (fresh.lastOrNull case final robot?) yield robot;
      }
    }
  }
}
