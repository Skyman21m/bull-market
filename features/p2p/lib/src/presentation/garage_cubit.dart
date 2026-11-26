import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../domain/garage_key_fingerprint.dart';
import '../domain/garage_keyring.dart';
import '../domain/garage_opening.dart';
import '../domain/network_garage_key.dart';
import '../domain/p2p_failure.dart';
import '../domain/robot_binding.dart';
import '../domain/trade_record.dart';
import '../domain/usecases/import_garage_key_usecase.dart';
import '../domain/usecases/new_garage_key_usecase.dart';
import '../domain/usecases/read_garage_key_usecase.dart';
import '../domain/usecases/trade/follow_trades_usecase.dart';
import 'garage_state.dart';

/// The Garage of one network (#81, design note `docs/design/garage-key-from-the-words.md` § 6, § 8): the Garage Keys of the default wallet's words, the key and the robot shown, and the actions of the user on them.
///
/// It reads the keys only when a method is called: [load] when the user opens the Garage, the others on an explicit action of the user. At the first opening, key 0 is there: nothing to generate, back up or delete, since the words remake every key.
/// It opens on the highest key, the key of every new trade. [previousKey] and [nextKey] move between the keys this device activated, from 0 to the highest, and never create one; [newKey], after the user confirmed « New key? », activates the next key and shows it. No move between keys asks the PIN: only showing a key's text does, on the screen.
/// While a trade of the key drawn at random before #81 is in progress, it shows that key alone, without arrows of keys or « New key », only to finish those trades.
/// An action started while another is running is ignored, and a closed cubit reads nothing again.
///
/// The robot shown follows the device's records of the key shown (#227, #251, [FollowTradesUsecase], design note `docs/design/phase-3-fresh-robot.md` § 4.1), as the reference's Garage does (`Garage.ensureReusableSlot`, `models/Garage.model.ts:233-298`, commit babf62e): it opens on [GarageNavigation.robotOf] over the records (the robot of the newest trade in progress whose bond was locked, made or taken here; else the robot of the « Last order #N » line under it, or the fresh robot when that order has served; else the first usable robot), and applies it again after each write of the records while it is shown, so that a trade that ends served moves it to the fresh robot. Nothing is sent when it moves.
/// The arrows and a tap on « Last order #N » ([showOrderRobot]) leave it on a robot by hand, kept in [GarageNavigation] for the run of the app: the rule applies again after a restart, once a trade of the key ends in a trade or a dispute, or once a trade of the key has its bond seen locked (the owner's decisions of 2026-11-19, #227).
class GarageCubit extends Cubit<GarageState> {
  final ReadGarageKeyUsecase _read;
  final NewGarageKeyUsecase _newKey;

  /// The paste of a key from elsewhere, which no screen reaches in this version (it comes back beside the keys of the words with #79).
  final ImportGarageKeyUsecase _import;

  /// [FollowTradesUsecase.execute]: the records the robot shown follows; `null` where the feature holds no trades.
  final Stream<Result<GarageRecords, P2pFailure>> Function(
    NetworkGarageKey key,
  )?
  _tradesOf;

  /// Where the user left the Garage by hand, for the whole run of the app: the locator's one object.
  final GarageNavigation _navigation;

  /// The records followed since the key was read, until another key is read or the Garage is left.
  StreamSubscription<Result<GarageRecords, P2pFailure>>? _following;

  /// The last records read, of the key shown; `null` before the first.
  Result<GarageRecords, P2pFailure>? _records;

  /// `WatchTradeUsecase.readOnce`: one read of a trade, as its page reads it when it opens (#251, step 0); `null` where the feature holds no trades.
  final Future<void> Function(TradeRecord record)? _readOnce;

  /// The robot the Garage opened on in this visit, the one whose open record it may read once.
  RobotSlot? _openedOn;

  /// Whether this visit already read an open record once (#251, step 0): never twice in a visit.
  bool _readOnceAsked = false;

  /// Whether « New key » is running: a second tap is ignored.
  bool _activating = false;

  GarageCubit(
    RobosatsNetwork network,
    this._read,
    this._newKey,
    this._import, {
    this._tradesOf,
    GarageNavigation? navigation,
    this._readOnce,
  }) : _navigation = navigation ?? GarageNavigation(),
       super(GarageWorking(network));

  RobosatsNetwork get _network => state.network;

  /// Reads the keys of the network and shows the highest: when the user opens the Garage, and on « Retry ».
  Future<void> load() async {
    if (_activating) return;
    await _settle(failure: null);
  }

  /// Shows the key before the one shown, down to key 0; nothing for the key drawn at random or key 0.
  Future<void> previousKey() async {
    final current = state;
    if (_activating || current is! GarageWithKey) return;
    final index = current.key.index;
    if (index == null || index == 0) return;
    await _settle(failure: null, index: index - 1);
  }

  /// Shows the key after the one shown, up to the highest, and never creates one: on the highest key it does nothing.
  Future<void> nextKey() async {
    final current = state;
    if (_activating || current is! GarageWithKey) return;
    final (index, highest) = (current.key.index, current.highest);
    if (index == null || highest == null || index >= highest) return;
    await _settle(failure: null, index: index + 1);
  }

  /// « New key », after the user confirmed « New key? »: activates the key after the highest one and shows it, with its robot 0 or the robot its records give; only from the highest key, never from an earlier one or from the key drawn at random.
  ///
  /// When the key could not be activated, the keys are read again and the Garage says why, on the highest key.
  Future<void> newKey() async {
    final current = state;
    if (_activating || current is! GarageWithKey || current.isLegacy) return;
    final highest = current.highest;
    if (highest == null || current.key.index != highest) return;
    _activating = true;
    try {
      _stopFollowing();
      emit(GarageWorking(_network));
      switch (await _newKey.execute(_network, after: highest)) {
        case Ok(:final value):
          await _settle(failure: null, index: value);
        case Err(:final failure):
          await _settle(failure: failure);
      }
    } finally {
      _activating = false;
    }
  }

  /// Stores the key whose `robo1…` form is [text], which the user pasted or typed, in the vault's slot of a network that has none.
  ///
  /// No screen calls it in this version: « Robot recovery » comes back beside the keys of the words with #79. Text that is not a key changes nothing in the vault; the text itself is not kept.
  Future<void> import(String text) async {
    if (_activating || state is! GarageWithoutKey) return;
    emit(GarageWorking(_network));
    switch (await _import.execute(_network, text: text)) {
      case Ok():
        await _settle(failure: null);
      case Err(failure: final GarageKeyInvalidFailure failure):
        if (!isClosed) emit(GarageWithoutKey(_network, failure: failure));
      case Err(:final failure):
        await _settle(failure: failure);
    }
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

  /// Reads the keys of the network and settles on the key at [index] (the highest when not given), with [failure] as the outcome of the action that led here; a closed cubit reads nothing.
  ///
  /// The robot the records give is read before the state is built, so that no panel of another robot is built, and reads its coordinator, in between.
  /// An [Error] of the records is a bug (AGENTS.md, rule 11): it is not caught, and the Garage stays on its wait.
  Future<void> _settle({required P2pFailure? failure, int? index}) async {
    if (isClosed) return;
    _stopFollowing();
    emit(GarageWorking(_network));
    final int? highest;
    switch (await _read.keyring(_network)) {
      case Ok(value: LegacyGarageKeyring()):
        highest = null;
      case Ok(value: DerivedGarageKeyring(highest: final top)):
        highest = top;
      case Err(failure: final readFailure):
        if (!isClosed) {
          emit(GarageUnknown(_network, readFailure, actionFailure: failure));
        }
        return;
    }
    if (isClosed) return;
    final read = highest == null
        ? await _read.execute(_network)
        : await _read.derived(
            _network,
            index == null || index > highest ? highest : index,
          );
    if (isClosed) return;
    final made = switch (read) {
      Ok(value: final key) => await _startFollowing(key),
      Err() => null,
    };
    if (isClosed) return;
    final robot = switch (read) {
      Ok(value: final key) =>
        made != null
            ? Ok<NetworkRobot, P2pFailure>(made)
            : key.firstUsableRobot(0),
      Err(failure: final readFailure) => Err<NetworkRobot, P2pFailure>(
        readFailure,
      ),
    };
    _openedOn = switch (robot) {
      Ok(:final value) => value.slot,
      Err() => null,
    };
    emit(switch ((read, robot)) {
      (Ok(value: final key), Ok(value: final shown)) => GarageWithKey(
        _network,
        key: key,
        robot: GarageRobotFace.of(shown),
        highest: highest,
        failure: failure,
        ordersNotServed: _ordersNotServedOf(shown.slot),
      ),
      (Err(failure: GarageKeyMissingFailure()), _) when highest == null =>
        GarageWithoutKey(_network, failure: failure),
      (_, Err(failure: final robotFailure)) => GarageUnknown(
        _network,
        robotFailure,
        actionFailure: failure,
      ),
      // A key read whose robot could not be derived is the case above; a read that failed gives the robot its failure.
      (Err(failure: final readFailure), Ok()) => GarageUnknown(
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
