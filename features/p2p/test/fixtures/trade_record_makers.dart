// Ways to make a `TradeRecord` that a check reading names alone misses, for `test/trade_record_test.dart`: each one must be found.
// Never imported by the feature; the analyzer resolves it in that test only.
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade_record.dart' as domain;
import 'package:p2p/src/domain/trade_record.dart';

typedef Recorded = TradeRecord;

TradeRecord byAlias(RobotSlot robot, DateTime at) => Recorded(
  robot: robot,
  coordinatorAlias: 'temple',
  coordinatorOnion: 'http://temple.onion',
  orderId: 1,
  role: TradeRole.buyer,
  origin: TradeOrigin.takenHere,
  takenAt: at,
  confirmedAt: at,
  closedAt: null,
);

TradeRecord byShorthand(RobotSlot robot, DateTime at) => .new(
  robot: robot,
  coordinatorAlias: 'temple',
  coordinatorOnion: 'http://temple.onion',
  orderId: 1,
  role: TradeRole.buyer,
  origin: TradeOrigin.takenHere,
  takenAt: at,
  confirmedAt: at,
  closedAt: null,
);

Object byPrefixedTearOff() => domain.TradeRecord.new;

Object byAliasTearOff() => Recorded.new;
