import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../domain/garage_key_fingerprint.dart';
import '../domain/garage_opening.dart';
import '../domain/network_garage_key.dart';
import '../domain/p2p_failure.dart';
import '../domain/robot_binding.dart';
import '../domain/trade_record.dart';
import '../domain/usecases/delete_garage_key_usecase.dart';
import '../domain/usecases/generate_garage_key_usecase.dart';
import '../domain/usecases/import_garage_key_usecase.dart';
import '../domain/usecases/needs_pin_to_delete_garage_key_usecase.dart';
import '../domain/usecases/read_garage_key_usecase.dart';
import '../domain/usecases/trade/follow_trades_usecase.dart';
import 'garage_state.dart';

/// Asks the user the wallet's re-authentication, its PIN, and completes with `true` only when the user passed it: what the screen lends [GarageCubit] for a delete that needs it.
typedef GarageReauthenticator = Future<bool> Function();

/// The Garage of one network: the Garage Key of that network in the vault, the robot shown, and the actions of the user on them.
///
/// It touches the vault only when a method is called: [load] when the user opens the Garage, the others on an explicit action of the user.
/// It follows the rules of the vault: a key is generated or imported only in [GarageWithoutKey], so only after a read found no key or a delete the vault confirmed; a stored key is never replaced, and « Generate new » deletes it first, after the user confirmed; after a failed write the slot is read again before anything is offered.
/// An action started while another is running is ignored.
/// An action the user started finishes in the vault even when the user leaves the Garage, but a closed cubit never reads the vault again.
///
/// Deleting a key, by « Delete All », « Generate new » or the way out of a key that cannot be read, asks the wallet's PIN once a robot of the key may live on a coordinator, as [NeedsPinToDeleteGarageKeyUsecase] reads it from the feature's database when the user deletes, and always for a slot that cannot be read; RoboSats asks only the confirmation.
/// The PIN comes after « Delete Garage Key? », which the screen asks first, and before anything is deleted; a PIN the user leaves, or no PIN to ask, deletes nothing and leaves the screen as it was, but for a hide of the app meanwhile, which [conceal] still applies.
///
/// A key is shown without the PIN only right after the vault drew it, while the user stays in the Garage with the app in the foreground the whole time from the tap on « Generate Garage Key » or « Generate new » ([GarageWithKey.showWithoutPin]); a pasted key never is.
/// [conceal], called whenever the app is hidden or paused, ends that for this key: it hides a key shown, and a hide while the vault is still deleting or drawing keeps the key behind the PIN when it arrives; leaving the Garage closes the cubit.
/// From then on, until the user saw the key and pressed « Continue » or deleted it, [UnacknowledgedGarageKeys] makes each visit show the backup alert, with the key behind the PIN.
///
/// The robot shown follows the device's records of the key (#227, #251, [FollowTradesUsecase], design note `docs/design/phase-3-fresh-robot.md` § 4.1), as the reference's Garage does (`Garage.ensureReusableSlot`, `models/Garage.model.ts:233-298`, commit babf62e): it opens on [GarageNavigation.robotOf] over the records (the robot of the newest trade in progress whose bond was locked, made or taken here; else the robot of the « Last order #N » line under it, or the fresh robot when that order has served; else the first usable robot), and applies it again after each write of the records while it is shown, so that a trade that ends served moves it to the fresh robot. Nothing is sent when it moves.
/// The arrows and a tap on « Last order #N » ([showOrderRobot]) leave it on a robot by hand, kept in [GarageNavigation] for the run of the app: the rule applies again after a restart, once a trade of the key ends in a trade or a dispute, or once a trade of the key has its bond seen locked (the owner's decisions of 2026-11-19, #227).
class GarageCubit extends Cubit<GarageState> {
  final ReadGarageKeyUsecase _read;
  final GenerateGarageKeyUsecase _generate;
  final ImportGarageKeyUsecase _import;
  final DeleteGarageKeyUsecase _delete;
  final NeedsPinToDeleteGarageKeyUsecase _needsPin;
  final UnacknowledgedGarageKeys _unacknowledged;

  /// [FollowTradesUsecase.execute]: the records the robot shown follows; `null` where the feature holds no trades.
  final Stream<Result<GarageRecords, P2pFailure>> Function(
    NetworkGarageKey key,
  )?
  _tradesOf;

  /// Where the user left the Garage by hand, for the whole run of the app: the locator's one object.
  final GarageNavigation _navigation;

  /// The records followed since the key was read, until the slot is read again, the key is deleted or the Garage is left.
  StreamSubscription<Result<GarageRecords, P2pFailure>>? _following;

  /// The last records read, of the key shown; `null` before the first.
  Result<GarageRecords, P2pFailure>? _records;

  /// `WatchTradeUsecase.readOnce`: one read of a trade, as its page reads it when it opens (#251, step 0); `null` where the feature holds no trades.
  final Future<void> Function(TradeRecord record)? _readOnce;

  /// The robot the Garage opened on in this visit, the one whose open record it may read once.
  RobotSlot? _openedOn;

  /// Whether this visit already read an open record once (#251, step 0): never twice in a visit.
  bool _readOnceAsked = false;

  /// Whether the app was hidden or paused since the user asked for a new key: the key then arrives behind the PIN.
  bool _concealedSinceAsked = false;

  /// Whether a delete or a « Generate new » is running, its PIN included: the state does not show it while the PIN is asked, so that leaving the PIN leaves the screen as it was, and a second tap is ignored by this.
  bool _deleting = false;

  /// Whether the key this cubit drew could not be recorded as drawn on this device: said on the robot step and the profile until the key is deleted.
  bool _drawUnrecorded = false;

  GarageCubit(
    RobosatsNetwork network,
    this._read,
    this._generate,
    this._import,
    this._delete,
    this._needsPin,
    this._unacknowledged, {
    this._tradesOf,
    GarageNavigation? navigation,
    this._readOnce,
  }) : _navigation = navigation ?? GarageNavigation(),
       super(GarageWorking(network));

  RobosatsNetwork get _network => state.network;

  /// Reads the key of the network: when the user opens the Garage, and on « Retry » when the vault could not say.
  ///
  /// Ignored while a delete or a « Generate new » runs, its PIN included, so that the state it decided on is the one it deletes: « Retry » could otherwise turn a slot that could not be read into a key read since.
  Future<void> load() async {
    if (_deleting) return;
    await _settle(failure: null, isNew: false);
  }

  /// Draws a new key in the vault for a network that has none, on the user's request, then reads it back to show it for backup at once, unless the app was hidden meanwhile.
  Future<void> generate() async {
    if (_deleting || state is! GarageWithoutKey) return;
    _concealedSinceAsked = false;
    await _draw();
  }

  Future<void> _draw() async {
    if (state is! GarageWithoutKey) return;
    emit(GarageWorking(_network));
    switch (await _generate.execute(_network)) {
      case Ok(value: final history):
        // Remembered before anything else, so that a user who left meanwhile gets the backup alert at the next visit.
        _unacknowledged._networks.add(_network);
        // The key is stored all the same, of unknown history: the screens say so, and its robots are treated as coming from elsewhere.
        _drawUnrecorded = history == GarageKeyHistory.unknown;
        await _settle(failure: null, isNew: true, justDrawn: true);
      case Err(:final failure):
        await _settle(failure: failure, isNew: false);
    }
  }

  /// Stores the key whose `robo1…` form is [text], which the user pasted or typed, for a network that has none.
  ///
  /// Text that is not a key changes nothing in the vault and leaves the Garage without a key, with the reason; the text itself is not kept.
  Future<void> import(String text) async {
    if (_deleting || state is! GarageWithoutKey) return;
    emit(GarageWorking(_network));
    _drawUnrecorded = false;
    switch (await _import.execute(_network, text: text)) {
      case Ok():
        await _settle(failure: null, isNew: true);
      case Err(failure: final GarageKeyInvalidFailure failure):
        if (!isClosed) emit(GarageWithoutKey(_network, failure: failure));
      case Err(:final failure):
        await _settle(failure: failure, isNew: false);
    }
  }

  /// Deletes the key of the network, whatever its entry holds: only after the user confirmed « Delete Garage Key? », then, when a robot of the key may live on a coordinator, passed [reauthenticate], the wallet's PIN.
  ///
  /// Without [reauthenticate], such a key is not deleted.
  /// The key of the other network is never touched.
  Future<void> delete({required GarageReauthenticator? reauthenticate}) async {
    if (_deleting || state is GarageWorking || state is GarageWithoutKey) {
      return;
    }
    _deleting = true;
    try {
      if (await _mayDelete(reauthenticate)) await _deleteKey();
    } finally {
      _deleting = false;
    }
  }

  /// « Generate new » with a key stored: deletes it, then draws a new one; only after the user confirmed « Delete Garage Key? », then passed [reauthenticate] when the delete needs it, once for both.
  ///
  /// A hide of the app at any time from here, during the PIN and the delete as during the draw, keeps the new key behind the PIN.
  Future<void> replace({required GarageReauthenticator? reauthenticate}) async {
    if (_deleting || state is! GarageWithKey) return;
    _deleting = true;
    _concealedSinceAsked = false;
    try {
      if (!await _mayDelete(reauthenticate)) return;
      await _deleteKey();
      await _draw();
    } finally {
      _deleting = false;
    }
  }

  /// Whether the key shown may be deleted now: at once when no robot of it may live on a coordinator, as the feature's database says at this moment, and otherwise only once the user passed [reauthenticate]; never without it, and never when this cubit was closed meanwhile.
  ///
  /// A slot that cannot be read hands no key to the use case, which then always asks the PIN.
  /// Nothing is emitted here but what the database said; a PIN the user leaves leaves the screen as it was, but for a hide of the app meanwhile.
  /// An [Error] of the database read is a bug (AGENTS.md, rule 11): it is not caught, the delete throws, and nothing is deleted.
  Future<bool> _mayDelete(GarageReauthenticator? reauthenticate) async {
    final needsPin = await _needsPin.execute(switch (state) {
      GarageWithKey(:final key) => key,
      _ => null,
    });
    if (isClosed) return false;
    _showDeletionNeedsPin(needsPin);
    if (!needsPin) return true;
    if (reauthenticate == null) return false;
    return await reauthenticate() && !isClosed;
  }

  /// Shows on the state whether the delete of a key needs the PIN, as the database just said, when it differs from what the state shows; the rest of the state is kept as it is.
  void _showDeletionNeedsPin(bool needsPin) {
    final current = state;
    if (current is GarageWithKey && current.deletionNeedsPin != needsPin) {
      emit(
        current.copyWith(deletionNeedsPin: needsPin, failure: current.failure),
      );
    }
  }

  Future<void> _deleteKey() async {
    if (isClosed) return;
    // The orders of the key deleted are followed no more (review of #229, R4).
    _stopFollowing();
    emit(GarageWorking(_network));
    switch (await _delete.execute(_network)) {
      case Ok():
        _unacknowledged._networks.remove(_network);
        _navigation.forget(_network);
        _drawUnrecorded = false;
        if (!isClosed) emit(GarageWithoutKey(_network));
      case Err(:final failure):
        await _settle(failure: failure, isNew: false);
    }
  }

  /// The app was hidden or paused, whatever the Garage shows: a key shown without the PIN is hidden, and a key still being drawn will arrive behind the PIN; from now on the key is shown only behind it.
  void conceal() {
    _concealedSinceAsked = true;
    final current = state;
    if (current is! GarageWithKey || !current.showWithoutPin) return;
    emit(current.copyWith(showWithoutPin: false));
  }

  /// The user saw the key shown for backup and pressed « Continue »: it no longer waits, and from now on it is shown only behind the PIN, on the profile.
  void acknowledgeBackup() {
    final current = state;
    if (current is! GarageWithKey || !current.awaitsBackup) return;
    _unacknowledged._networks.remove(_network);
    emit(current.copyWith(awaitsBackup: false, showWithoutPin: false));
  }

  /// Shows the next robot of the key: the first usable one after the robot shown, left there by hand.
  void next() => _move((key, index) => key.firstUsableRobot(index + 1));

  /// Shows the previous robot of the key: the last usable one before the robot shown, left there by hand.
  void previous() => _move((key, index) => key.lastUsableRobot(index - 1));

  /// A tap on « Last order #N » of [record] (#227), before its trade opens: shows the robot of that order when it is a robot of the key shown, as the reference shows the robot whose last order it is (`basic/GaragePage/GarageKeyProfile.tsx:214-230`), and leaves the Garage there by hand (#251, § 4.1, step 4); an order of another Garage Key or network changes nothing.
  ///
  /// The robot tapped stays shown, leaving the Garage and coming back included, until the app restarts, a trade of the key ends in a trade or a dispute, a trade of the key has its bond seen locked after it (a renewal of that order, for one), or the user moves with the arrows.
  /// Nothing is read from a coordinator here: the panel of the robot shown reads what it reads for a robot shown with the arrows.
  void showOrderRobot(TradeRecord record) {
    final current = state;
    if (isClosed || current is! GarageWithKey) return;
    if (current.key.robotOf(record.robot) case final robot?
        when robot.accountIndex != current.robot.index) {
      _navigation.leave(current.key, robot.slot, _records);
      emit(_showing(current, robot));
    }
  }

  /// [current] showing [robot], with what the records say of its orders; the failure of the last action cleared.
  GarageWithKey _showing(GarageWithKey current, NetworkRobot robot) =>
      current.copyWith(
        robot: GarageRobotFace.of(robot),
        ordersNotServed: _ordersNotServedOf(robot.slot),
        failure: null,
      );

  /// What the last records read say of the orders of [robot] that have not served; nothing before they were read, or when they cannot be.
  Set<(String, int)> _ordersNotServedOf(RobotSlot robot) => switch (_records) {
    Ok(:final value) => value.ordersNotServedOf(robot),
    _ => const {},
  };

  /// New records of [key] while the Garage shows it: the robot the rule gives now, when it is not the one shown, as the reference's Garage moves after each poll on its page (`contexts/GarageContext.tsx:143-149`); records that cannot be read move nothing.
  void _onRecords(
    NetworkGarageKey key,
    Result<GarageRecords, P2pFailure> records,
  ) {
    _records = records;
    final current = state;
    if (isClosed || current is! GarageWithKey || current.key != key) return;
    if (records is Err) return;
    final target = switch (_navigation.robotOf(key, records)) {
      final slot? => key.robotOf(slot),
      null => switch (key.firstUsableRobot(0)) {
        Ok(:final value) => value,
        Err() => null,
      },
    };
    if (target != null && target.accountIndex != current.robot.index) {
      emit(_showing(current, target));
      return;
    }
    final GarageKeyFingerprint fingerprint;
    switch (key.fingerprint) {
      case Ok(:final value):
        fingerprint = value;
      case Err():
        return;
    }
    final notServed = _ordersNotServedOf(
      RobotSlot(_network, fingerprint, current.robot.index),
    );
    if (!_sameOrders(notServed, current.ordersNotServed)) {
      emit(
        current.copyWith(ordersNotServed: notServed, failure: current.failure),
      );
    }
  }

  static bool _sameOrders(Set<(String, int)> a, Set<(String, int)> b) =>
      a.length == b.length && a.containsAll(b);

  /// The panel of robot [index] read it on its coordinator with no active order (#251, design note `docs/design/phase-3-fresh-robot.md` § 4.1, step 0, the owner's decision 5 of 2026-11-25): when it is the robot the Garage opened on in this visit and the device holds an open record of it, made or taken here with a key drawn here, that order is read once, as its page reads it when it opens, so that an order that ended while the app did not read it closes its record; the records then written apply the rule again.
  ///
  /// At most one such read per visit, over Tor, to the coordinator that already knows that robot and its order; nothing for a robot shown by the arrows after the opening, a key from elsewhere, or records that cannot be read.
  void robotWithoutActiveOrder(int index) {
    final readOnce = _readOnce;
    final opened = _openedOn;
    final current = state;
    if (isClosed ||
        _readOnceAsked ||
        readOnce == null ||
        opened == null ||
        opened.accountIndex != index ||
        current is! GarageWithKey ||
        current.robot.index != index) {
      return;
    }
    final records = _records;
    if (records is! Ok<GarageRecords, P2pFailure>) return;
    final value = records.value;
    if (!value.keyDrawnHereOnly) return;
    final record = value.openRecordOf(opened);
    if (record == null) return;
    _readOnceAsked = true;
    unawaited(readOnce(record));
  }

  void _stopFollowing() {
    final following = _following;
    _following = null;
    if (following != null) unawaited(following.cancel());
  }

  /// Starts following the records of [key], where the feature holds trades, and gives the robot to open on: [GarageNavigation.robotOf] over the first records read, `null` for the first usable robot from index 0.
  ///
  /// The first answer is awaited before the Garage shows a robot, so that no panel of another robot is built, and reads its coordinator, in between; later answers apply the rule again ([_onRecords]).
  /// An [Error] of the records is a bug (AGENTS.md, rule 11): it is not caught, and the Garage stays on its wait.
  /// Of two reads of the vault that overlap, the later one cuts the earlier one's following before its first answer, so that the earlier [load] never completes (review of #229, R7): nothing awaits it, the screens call it without waiting.
  Future<NetworkRobot?> _startFollowing(NetworkGarageKey key) async {
    // One following at a time: another read of the vault started meanwhile has its own (review of #229, R3).
    _stopFollowing();
    _records = null;
    final tradesOf = _tradesOf;
    if (tradesOf == null) {
      return switch (_navigation.leftByHand(key)) {
        final robot? => key.robotOf(robot),
        null => null,
      };
    }
    final start = Completer<Result<GarageRecords, P2pFailure>>();
    _following = tradesOf(key).listen((records) {
      if (!start.isCompleted) {
        _records = records;
        start.complete(records);
      } else {
        _onRecords(key, records);
      }
    });
    return switch (_navigation.robotOf(key, await start.future)) {
      final robot? => key.robotOf(robot),
      null => null,
    };
  }

  void _move(
    Result<NetworkRobot, P2pFailure> Function(NetworkGarageKey key, int index)
    step,
  ) {
    final current = state;
    if (isClosed || current is! GarageWithKey) return;
    switch (step(current.key, current.robot.index)) {
      case Ok(value: final robot):
        _navigation.leave(current.key, robot.slot, _records);
        emit(_showing(current, robot));
      case Err(:final failure):
        emit(current.copyWith(failure: failure));
    }
  }

  /// Reads the slot again and settles on what it holds, with [failure] as the outcome of the action that led here; a closed cubit reads nothing.
  ///
  /// A key drawn and not acknowledged yet awaits its backup; it is shown without the PIN only when this cubit has [justDrawn] it and the app was not hidden since the user asked for it.
  /// For a key that can be read, the feature's database is read too, for whether its delete would ask the PIN; a slot that cannot be read always asks it ([GarageUnknown.deletionNeedsPin]).
  /// An [Error] of that read is a bug (AGENTS.md, rule 11): it is not caught, and the Garage stays on its wait.
  Future<void> _settle({
    required P2pFailure? failure,
    required bool isNew,
    bool justDrawn = false,
  }) async {
    if (isClosed) return;
    _stopFollowing();
    emit(GarageWorking(_network));
    final read = await _read.execute(_network);
    if (isClosed) return;
    // Read before the state is built, so that nothing awaited lies between the state and its emit: a hide of the app during this read keeps a key just drawn behind the PIN.
    final needsPin = switch (read) {
      Ok(value: final key) => await _needsPin.execute(key),
      Err() => true,
    };
    if (isClosed) return;
    // The robot the records give (#227, #251), read before the state is built for the same reason.
    final made = switch (read) {
      Ok(value: final key) => await _startFollowing(key),
      Err() => null,
    };
    if (isClosed) return;
    _openedOn = switch (read) {
      Ok(value: final key) => switch (made != null
          ? Ok<NetworkRobot, P2pFailure>(made)
          : key.firstUsableRobot(0)) {
        Ok(value: final robot) => robot.slot,
        Err() => null,
      },
      Err() => null,
    };
    emit(switch (read) {
      Ok(value: final key) => switch (made != null
          ? Ok<NetworkRobot, P2pFailure>(made)
          : key.firstUsableRobot(0)) {
        Ok(value: final robot) => switch (_unacknowledged.waits(_network)) {
          final awaitsBackup => GarageWithKey(
            _network,
            key: key,
            robot: GarageRobotFace.of(robot),
            isNew: isNew || awaitsBackup,
            awaitsBackup: awaitsBackup,
            showWithoutPin: justDrawn && awaitsBackup && !_concealedSinceAsked,
            failure: failure,
            historyNotRecorded: _drawUnrecorded,
            deletionNeedsPin: needsPin,
            ordersNotServed: _ordersNotServedOf(robot.slot),
          ),
        },
        Err(failure: final robotFailure) => GarageUnknown(
          _network,
          robotFailure,
          actionFailure: failure,
        ),
      },
      Err(failure: GarageKeyMissingFailure()) => GarageWithoutKey(
        _network,
        failure: failure,
      ),
      Err(failure: final readFailure) => GarageUnknown(
        _network,
        readFailure,
        actionFailure: failure,
      ),
    });
  }

  @override
  Future<void> close() async {
    _stopFollowing();
    return super.close();
  }
}

/// The networks whose Garage Key was drawn in this run of the app and not acknowledged yet: in memory only, one object for the feature, which the locator creates.
///
/// The vault stores a key as soon as it draws it, and the key is never part of the wallet backup, so the Garage keeps asking the user to store it, with the backup alert and the key behind the PIN, until the user saw it and pressed « Continue », or deleted it.
/// It reveals nothing by itself: only the cubit that has just drawn the key shows it without the PIN.
/// Only [GarageCubit] writes it: its set is private to this library, and the cubit adds a network only when the vault drew its key.
/// If the app dies before the user acknowledged the key, nothing remembers it: the key is then the one of the profile, behind the PIN.
final class UnacknowledgedGarageKeys {
  final Set<RobosatsNetwork> _networks = {};

  /// Whether the key of [network] waits to be acknowledged.
  bool waits(RobosatsNetwork network) => _networks.contains(network);
}
