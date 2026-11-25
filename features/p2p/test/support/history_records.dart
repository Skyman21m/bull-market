import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/trade_record_repository.dart';
import 'package:p2p/src/domain/repositories/trade_trail_repository.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/trade_storable.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'fakes.dart' show coordinator;

/// The records of finished orders the tests of the history write (#253), through the feature's own repositories, as the take, the make and the trade screen write them: test values only, never a real order.
final class HistoryRecords {
  final TradeRecordRepository trades;
  final TradeTrailRepository trails;
  final RobosatsNetwork network;

  const HistoryRecords(this.trades, this.trails, this.network);

  T _value<T>(Result<T, P2pFailure> result) => switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  CoordinatorIdentity _identity(String alias) =>
      switch (CoordinatorIdentity.of(coordinator(alias), network)) {
        final identity? => identity,
        null => throw StateError('$alias is not on $network'),
      };

  Future<TradeReservation> _reserve(RobotSlot robot, String alias) async =>
      switch (await trades.reserveForNewTrade(robot, _identity(alias))) {
        Ok(value: final reservation?) => reservation,
        final other => throw StateError('not reserved: $other'),
      };

  TradeTrailRecord _trail(
    String alias,
    int orderId,
    TradeRole role,
    String position,
  ) => TradeTrailRecord(
    version: TradeTrailRecord.currentVersion,
    network: network.name,
    coordinatorAlias: alias,
    orderId: orderId,
    role: role.name,
    position: position,
    readAtMicros: DateTime.utc(2026, 11, 1).microsecondsSinceEpoch,
    bondHash: null,
    escrowHash: null,
    deadlineMicros: null,
    bondStepSeenAtMicros: null,
    bondStepDeadlineMicros: null,
    breached: false,
    historyUnknown: false,
  );

  /// Order [orderId] taken here by [robot] on [alias] as [role], its terms recorded and its trail stored at [position] (none for `null`), confirmed unless [confirmed] is false, then closed unless [closed] is false.
  Future<TradeRecord> taken(
    RobotSlot robot, {
    required int orderId,
    String alias = 'temple',
    TradeRole role = TradeRole.buyer,
    String? position = 'succeeded',
    bool confirmed = true,
    bool closed = true,
  }) async {
    var record = _value(
      await trades.recordPendingTake(
        await _reserve(robot, alias),
        orderId: orderId,
        role: role,
      ),
    );
    _value(
      await trails.recordTerms(
        record,
        TradeTermsRecord(
          version: TradeTermsRecord.currentVersion,
          network: network.name,
          coordinatorAlias: alias,
          orderId: orderId,
          role: role.name,
          type: role == TradeRole.buyer ? 1 : 0,
          currencyId: 2,
          amount: 100,
          isRange: false,
          premiumPercent: 2,
          explicitSatoshis: null,
          bondSizePercent: 3,
          escrowSeconds: 10800,
          bookPrice: 93545.25,
          takerFee: 0.00175,
        ),
      ),
    );
    if (position != null) {
      _value(
        await trails.storeTrail(record, _trail(alias, orderId, role, position)),
      );
    }
    if (confirmed) record = _value(await trades.confirmTake(record));
    if (closed) record = _value(await trades.closeTrade(record));
    return record;
  }

  /// Order [orderId] made here by [robot] on [alias] as [role], its terms recorded, confirmed, its trail stored at [position], then closed unless [closed] is false.
  Future<TradeRecord> made(
    RobotSlot robot, {
    required int orderId,
    String alias = 'temple',
    TradeRole role = TradeRole.seller,
    String position = 'succeeded',
    bool closed = true,
  }) async {
    final make = _value(
      await trades.recordPendingMake(await _reserve(robot, alias), role: role),
    );
    _value(
      await trails.recordMakerTerms(
        make,
        MakerTermsRecord(
          version: MakerTermsRecord.currentVersion,
          network: network.name,
          coordinatorAlias: alias,
          role: role.name,
          type: role == TradeRole.buyer ? 0 : 1,
          currencyId: 2,
          amount: 100,
          minAmount: null,
          maxAmount: null,
          premiumPercent: 1.5,
          paymentMethod: 'Revolut SEPA',
          bondSizePercent: 3,
          publicSeconds: 86340,
          escrowSeconds: 10800,
          description: null,
          hasPassword: false,
          latitude: null,
          longitude: null,
          createdPrice: 93545.25,
          makerFee: 0.00025,
        ),
      ),
    );
    var record = _value(await trades.confirmMake(make, orderId: orderId));
    _value(
      await trails.storeTrail(record, _trail(alias, orderId, role, position)),
    );
    if (closed) record = _value(await trades.closeTrade(record));
    return record;
  }
}
