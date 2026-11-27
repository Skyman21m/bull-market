import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../network_garage_key.dart';
import '../../p2p_failure.dart';
import '../../robot_binding.dart';
import '../../robot_key_compute_port.dart';
import '../../trade_record.dart';
import '../read_robot_on_coordinator_usecase.dart';
import 'trade_reader.dart';

/// The unlocked OpenPGP keys of the robots of the trades, kept no longer than their screens (#90, design note § 3.4).
///
/// The pair of a robot is not stored: a [lease] reads the robot back from the coordinator of its binding, its pair proven by its token (`ReadRobotOnCoordinatorUsecase.provenPairOf`), then unlocks it with the token away from the UI isolate (`RobotKeyComputePort.unlock`: two works of 32 MiB of SHA-256 for a key of the official client or of this app).
/// The key is kept per robot of a trade while a [hold] or a lease of it is open, and dropped as soon as none is:
/// - the trade screen takes a hold (`HoldTradeKeyUsecase`) while it is shown and the app in the foreground, and releases it when it closes or the app is hidden or paused, taking a new one on return; a hold unlocks nothing by itself, it only keeps a key that a lease unlocked;
/// - the payout use case takes a lease to sign the payout and its request, and closes it as soon as the request has ended; without a hold, the key is unlocked for that payout only and dropped when its lease closes;
/// - every request of a robot that changes a state is signed by its key since the fix of GHSA-22q8-9ghc-jg3h (RoboSats pull request 2955): the make, the take, the cancel, the pause, the chat step's actions, the payout and the token to rate the coordinator each take a lease through [signWith] (a robot reserved for a new trade through [leaseRobot]), which `CoordinatorClient` signs with just before the request leaves, and close it as soon as the request has ended, its busy retries included, each signed again;
/// - two screens of one trade hold one key, kept while either holds it; a lease open when the last hold is released keeps the key until it closes (the app sent to the background during a signature), and the key is dropped then.
/// One unlock at a time per robot, shared by the leases that come meanwhile; an unlock that failed, or threw, is not kept, so the next lease tries again; an entry dropped is emptied, and a closed lease holds neither the key nor the entry.
/// Dropping a key forgets it: the package gives no way to wipe its secret values, which the garbage collector reclaims later without clearing them (a limit stated in `AGENTS.md`).
/// Nothing here is printed, logged or stored. One for the feature (a lazy singleton of the composition), so that every trade use case, made anew for each use, shares the keys; `robot_bindings_architecture_test.dart` pins who may take a hold or a lease, and who names the unlocked key.
final class TradeKeyring {
  final ReadRobotOnCoordinatorUsecase _robots;
  final RobotKeyComputePort _keys;
  final Map<RobotSlot, _Entry> _entries = {};

  TradeKeyring(this._robots, this._keys);

  /// Keeps the key of the robot of [record], once a lease unlocks it, until the hold returned is released.
  TradeKeyHold hold(TradeRecord record) {
    final slot = record.robot;
    (_entries[slot] ??= _Entry()).holds++;
    return TradeKeyHold._(this, slot);
  }

  /// The unlocked key of the robot of [trade], read back and unlocked unless a hold or another lease keeps it already.
  ///
  /// [Err] when it could not be had, with its cause: a [P2pFailure] of the read (the binding, the limiter, a robot released, the work that could not start), a `CoordinatorFailure` of the coordinator's answer (`RobotUnknown`, `RobotPgpKeyNotProven`, …), or a `PgpFailure` of the unlock; nothing is kept then.
  /// Close the lease as soon as the key is no longer needed.
  Future<Result<TradeKeyLease, Failure>> lease(OpenTrade trade) =>
      _lease(trade.record.robot, trade.robot);

  /// The unlocked key of [robot], a robot reserved for a new trade and put on its coordinator, for the signature of its make or its take: as [lease], kept under the robot's own slot.
  Future<Result<TradeKeyLease, Failure>> leaseRobot(NetworkRobot robot) =>
      _lease(robot.slot, robot);

  /// [action] run with the key of the lease [leased] gives, the lease closed as soon as [action] has ended, for an action of a robot that `CoordinatorClient` signs (GHSA-22q8-9ghc-jg3h).
  ///
  /// When the key cannot be had, [action] does not run, so nothing is sent, and the failure is returned as the result of an action never sent: a [P2pFailure] as the outer [Err] (the binding, the limiter, a robot released, the work that could not start), a `CoordinatorFailure` of the read back as an `OrderActionRefused` of it (the coordinator unreachable, the robot unknown or its pair not proven), and anything else, an unlock that failed, as an `OrderActionRefused` of `ActionSignatureRefused` with `ActionSignatureRefusal.notSigned`.
  static Future<Result<Result<T, OrderActionFailure>, P2pFailure>> signWith<T>(
    Future<Result<TradeKeyLease, Failure>> leased,
    Future<Result<Result<T, OrderActionFailure>, P2pFailure>> Function(
      UnlockedRobotPgpKey key,
    )
    action,
  ) async {
    final TradeKeyLease lease;
    switch (await leased) {
      case Err(failure: final P2pFailure failure):
        return Err(failure);
      case Err(failure: final CoordinatorFailure failure):
        return Ok(Err(OrderActionRefused(failure)));
      case Err():
        return const Ok(
          Err(
            OrderActionRefused(
              ActionSignatureRefused(ActionSignatureRefusal.notSigned),
            ),
          ),
        );
      case Ok(:final value):
        lease = value;
    }
    try {
      return await action(lease.key);
    } finally {
      lease.close();
    }
  }

  Future<Result<TradeKeyLease, Failure>> _lease(
    RobotSlot slot,
    NetworkRobot robot,
  ) async {
    final entry = _entries[slot] ??= _Entry();
    entry.leases++;
    var handedOut = false;
    try {
      // A key unlocked for another robot of the same slot is never handed out: the slot is the record's, the robot derived again from its Garage Key.
      if (entry.owner != robot.identity.hashId) {
        entry
          ..owner = robot.identity.hashId
          ..unlocking = null;
      }
      final unlocking = entry.unlocking ??= _unlock(robot);
      final Result<UnlockedRobotPgpKey, Failure> unlocked;
      try {
        unlocked = await unlocking;
      } catch (_) {
        // An `Error` of the read or the unlock is a bug (rule 11 of AGENTS.md) and reaches the caller, but the unlock that threw is not kept: the next lease tries again (review of #127).
        if (identical(entry.unlocking, unlocking)) entry.unlocking = null;
        rethrow;
      }
      switch (unlocked) {
        case Ok(:final value):
          handedOut = true;
          return Ok(TradeKeyLease._(this, slot, entry, value));
        case Err(:final failure):
          if (identical(entry.unlocking, unlocking)) entry.unlocking = null;
          return Err(failure);
      }
    } finally {
      if (!handedOut) _leaseClosed(slot, entry);
    }
  }

  Future<Result<UnlockedRobotPgpKey, Failure>> _unlock(
    NetworkRobot robot,
  ) async {
    final RobotPgpKey pair;
    switch (await _robots.provenPairOf(robot)) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: Err(:final failure)):
        return Err(failure);
      case Ok(value: Ok(:final value)):
        pair = value;
    }
    return switch (await _keys.unlock(pair, robot.identity)) {
      Err(:final failure) => Err(failure),
      Ok(value: Err(:final failure)) => Err(failure),
      Ok(value: Ok(:final value)) => Ok(value),
    };
  }

  void _holdReleased(RobotSlot slot) {
    final entry = _entries[slot];
    if (entry == null) return;
    entry.holds--;
    _dropIfUnused(slot, entry);
  }

  void _leaseClosed(RobotSlot slot, _Entry entry) {
    entry.leases--;
    _dropIfUnused(slot, entry);
  }

  void _dropIfUnused(RobotSlot slot, _Entry entry) {
    if (entry.holds > 0 || entry.leases > 0) return;
    if (identical(_entries[slot], entry)) _entries.remove(slot);
    // Emptied as it leaves the table, so that nothing that still holds the entry reaches the key (review of #127).
    entry
      ..unlocking = null
      ..owner = null;
  }

  /// Whether a key of the robot of [slot] is kept or being unlocked: for the tests of the keyring's lifetime.
  @visibleForTesting
  bool keepsKeyOf(RobotSlot slot) => _entries[slot]?.unlocking != null;

  /// How many holds and leases of the robot of [slot] are open: for the tests of the keyring's lifetime.
  @visibleForTesting
  ({int holds, int leases}) openOf(RobotSlot slot) => switch (_entries[slot]) {
    final entry? => (holds: entry.holds, leases: entry.leases),
    null => (holds: 0, leases: 0),
  };
}

/// What the keyring keeps of one robot: the open holds and leases, and the unlock, done or in flight, of the robot [owner] names.
final class _Entry {
  int holds = 0;
  int leases = 0;
  RobotHashId? owner;
  Future<Result<UnlockedRobotPgpKey, Failure>>? unlocking;
}

/// The trade screen's hold on the key of its robot: [release] it when the screen closes or the app is hidden or paused (`TradeKeyring`).
final class TradeKeyHold {
  final TradeKeyring _keyring;
  final RobotSlot _slot;
  bool _released = false;

  TradeKeyHold._(this._keyring, this._slot);

  /// Whether [release] was called.
  bool get isReleased => _released;

  /// Releases the hold, once: the key is dropped when no other hold or lease of the robot is open. A second call does nothing.
  void release() {
    if (_released) return;
    _released = true;
    _keyring._holdReleased(_slot);
  }

  @override
  String toString() => 'TradeKeyHold(released: $_released)';
}

/// The use of an unlocked key for one signature: [close] it right after.
final class TradeKeyLease {
  final TradeKeyring _keyring;
  final RobotSlot _slot;
  _Entry? _entry;
  UnlockedRobotPgpKey? _key;

  TradeKeyLease._(
    this._keyring,
    this._slot,
    this._entry,
    UnlockedRobotPgpKey key,
  ) : _key = key;

  /// The unlocked key, until [close]; a bug to ask for it after.
  UnlockedRobotPgpKey get key => switch (_key) {
    final key? => key,
    null => throw StateError('a lease used after it was closed'),
  };

  /// Closes the lease, once: the key is dropped when no hold or other lease of the robot is open. A second call does nothing.
  void close() {
    final entry = _entry;
    if (_key == null || entry == null) return;
    // Nothing of a closed lease leads back to the key: neither the key nor the keyring's entry, which holds its unlock (review of #127).
    _key = null;
    _entry = null;
    _keyring._leaseClosed(_slot, entry);
  }

  /// Whether this lease no longer holds the key nor the keyring's entry: true once closed, for the tests of the keyring's lifetime.
  @visibleForTesting
  bool get holdsNothing => _key == null && _entry == null;

  @override
  String toString() => 'TradeKeyLease(open: ${_key != null})';
}
