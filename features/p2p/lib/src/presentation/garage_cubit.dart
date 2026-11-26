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
import '../domain/usecases/delete_garage_key_usecase.dart';
import '../domain/usecases/import_garage_key_usecase.dart';
import '../domain/usecases/needs_pin_to_delete_garage_key_usecase.dart';
import '../domain/usecases/new_garage_key_usecase.dart';
import '../domain/usecases/read_garage_key_usecase.dart';
import '../domain/usecases/trade/follow_trades_usecase.dart';
import 'garage_state.dart';

/// Asks the user the wallet's re-authentication, its PIN, and completes with `true` only when the user passed it: what the screen lends [GarageCubit] for a delete that needs it.
typedef GarageReauthenticator = Future<bool> Function();

/// The Garage of one network (#81, design note `docs/design/garage-key-from-the-words.md` § 6, § 8): the Garage Keys of the default wallet's words and the external key, the key and the robot shown, and the actions of the user on them.
///
/// It reads the keys only when a method is called: [load] when the user opens the Garage, the others on an explicit action of the user. At the first opening, key 0 is there: nothing to generate or back up, since the words remake every key.
/// It opens on the key selected on the network, the key of every new trade (the owner's decisions of 2026-11-26): at the first opening, the external key when the vault keeps one, otherwise key 0. [previousKey] and [nextKey] select the key before or after, among the keys of the words this device activated and then the external key, one position after the highest, and never create one; [newKey], after the user confirmed « New Garage Key », activates the key of the words after the highest, from whichever key is shown, and selects it. No move between keys asks the PIN: only showing a key's text does, on the screen.
/// The external key is pasted in « Robot recovery » ([import]) when the vault keeps none, and removed ([delete]) after « Delete Garage Key? » and, when a robot of it may live on a coordinator, the wallet's PIN, as before #81; the keys of the words are never deleted.
/// An action started while another is running is ignored, and a closed cubit reads nothing again.
///
/// The robot shown follows the device's records of the key shown (#227, #251, [FollowTradesUsecase], design note `docs/design/phase-3-fresh-robot.md` § 4.1), as the reference's Garage does (`Garage.ensureReusableSlot`, `models/Garage.model.ts:233-298`, commit babf62e): it opens on [GarageNavigation.robotOf] over the records (the robot of the newest trade in progress whose bond was locked, made or taken here; else the robot of the « Last order #N » line under it, or the fresh robot when that order has served; else the first usable robot), and applies it again after each write of the records while it is shown, so that a trade that ends served moves it to the fresh robot. Nothing is sent when it moves.
/// The arrows and a tap on « Last order #N » ([showOrderRobot]) leave it on a robot by hand, kept in [GarageNavigation] for the run of the app: the rule applies again after a restart, once a trade of the key ends in a trade or a dispute, or once a trade of the key has its bond seen locked (the owner's decisions of 2026-11-19, #227).
class GarageCubit extends Cubit<GarageState> {
  final ReadGarageKeyUsecase _read;
  final NewGarageKeyUsecase _newKey;

  final ImportGarageKeyUsecase _import;
  final DeleteGarageKeyUsecase _delete;
  final NeedsPinToDeleteGarageKeyUsecase _needsPin;

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

  /// Whether an action on the keys is running (a move between keys, « New key », a paste, a delete with its PIN): a second tap is ignored, and the state a delete decided on is the one it deletes.
  bool _activating = false;

  GarageCubit(
    RobosatsNetwork network,
    this._read,
    this._newKey,
    this._import,
    this._delete,
    this._needsPin, {
    this._tradesOf,
    GarageNavigation? navigation,
    this._readOnce,
  }) : _navigation = navigation ?? GarageNavigation(),
       super(GarageWorking(network));

  RobosatsNetwork get _network => state.network;

  /// Reads the keys of the network and shows the one selected: when the user opens the Garage, and on « Retry ».
  Future<void> load() async {
    if (_activating) return;
    await _settle(failure: null);
  }

  /// Selects and shows the key before the one shown: from the external key, the highest key of the words; from a key of the words, the one before, down to key 0. It is the key of new trades from then on, kept across restarts.
  Future<void> previousKey() async {
    if (_activating) return;
    switch (state) {
      case GarageWithKey(isExternal: true, :final highest):
        await _select(SelectedWordsKey(highest));
      case GarageWithKey(key: NetworkGarageKey(:final index?)) when index > 0:
        await _select(SelectedWordsKey(index - 1));
      // The external key that cannot be read, selected: back to the keys of the words.
      case GarageUnknown(:final externalHighest?):
        await _select(SelectedWordsKey(externalHighest));
      case _:
    }
  }

  /// Selects and shows the key after the one shown, up to the highest key of the words, then the external key when the vault keeps one; it never creates a key.
  Future<void> nextKey() async {
    final current = state;
    if (_activating || current is! GarageWithKey) return;
    final index = current.key.index;
    if (index == null) return;
    if (index < current.highest) {
      await _select(SelectedWordsKey(index + 1));
    } else if (current.hasExternal) {
      await _select(const SelectedExternalKey());
    }
  }

  Future<void> _select(GarageKeySelection selection) async {
    _activating = true;
    try {
      _stopFollowing();
      emit(GarageWorking(_network));
      final selected = await _read.select(_network, selection);
      await _settle(
        failure: switch (selected) {
          Ok() => null,
          Err(:final failure) => failure,
        },
      );
    } finally {
      _activating = false;
    }
  }

  /// « New key », after the user confirmed « New Garage Key »: activates the key of the words after the highest one, from whichever key is shown, the external key included, selects it and shows it, with its robot 0 or the robot its records give.
  ///
  /// When the key could not be activated, the keys are read again and the Garage says why.
  Future<void> newKey() async {
    final current = state;
    if (_activating || current is! GarageWithKey) return;
    final highest = current.highest;
    _activating = true;
    try {
      _stopFollowing();
      emit(GarageWorking(_network));
      switch (await _newKey.execute(_network, after: highest)) {
        case Ok():
          await _settle(failure: null);
        case Err(:final failure):
          await _settle(failure: failure);
      }
    } finally {
      _activating = false;
    }
  }

  /// « Recover » in « Robot recovery »: stores the key whose `robo1…` form is [text], which the user pasted or typed, as the external key of a network whose vault keeps none, then selects and shows it, as the official client shows the key it recovers.
  ///
  /// Text that is not a key changes nothing in the vault and is given back as a [GarageKeyInvalidFailure], for the dialog to say, the Garage staying as it is; the text itself is not kept. Any other outcome is the Garage's to show, and gives `null`.
  Future<P2pFailure?> import(String text) async {
    final current = state;
    if (_activating || current is! GarageWithKey || current.hasExternal) {
      return null;
    }
    _activating = true;
    try {
      _stopFollowing();
      emit(GarageWorking(_network));
      switch (await _import.execute(_network, text: text)) {
        case Ok():
          await _settle(failure: null);
          return null;
        case Err(failure: final GarageKeyInvalidFailure failure):
          await _settle(failure: null);
          return failure;
        case Err(:final failure):
          await _settle(failure: failure);
          return null;
      }
    } finally {
      _activating = false;
    }
  }

  /// Removes the external key of the network, whatever its entry holds: only after the user confirmed « Delete Garage Key? », then, when a robot of the key may live on a coordinator, passed [reauthenticate], the wallet's PIN, as before #81 (RoboSats asks only the confirmation). The keys of the words are never deleted.
  ///
  /// Without [reauthenticate], such a key is not deleted. A slot that cannot be read always asks the PIN. A PIN the user leaves deletes nothing and leaves the screen as it was. Once deleted, the highest key of the words is shown.
  Future<void> delete({required GarageReauthenticator? reauthenticate}) async {
    final current = state;
    final external = switch (current) {
      GarageWithKey(isExternal: true) => true,
      GarageUnknown(externalHighest: _?) => true,
      _ => false,
    };
    if (_activating || !external) return;
    _activating = true;
    try {
      if (!await _mayDelete(reauthenticate)) return;
      _stopFollowing();
      emit(GarageWorking(_network));
      switch (await _delete.execute(_network)) {
        case Ok():
          _navigation.forget(_network);
          await _settle(failure: null);
        case Err(:final failure):
          await _settle(failure: failure);
      }
    } finally {
      _activating = false;
    }
  }

  /// Whether the external key shown may be deleted now: at once when no robot of it may live on a coordinator, as the feature's database says at this moment, and otherwise only once the user passed [reauthenticate]; never without it, and never when this cubit was closed meanwhile.
  ///
  /// A key that cannot be read hands no key to the use case, which then always asks the PIN.
  /// An [Error] of the database read is a bug (AGENTS.md, rule 11): it is not caught, the delete throws, and nothing is deleted.
  Future<bool> _mayDelete(GarageReauthenticator? reauthenticate) async {
    final needsPin = await _needsPin.execute(switch (state) {
      GarageWithKey(:final key) => key,
      _ => null,
    });
    if (isClosed) return false;
    final current = state;
    if (current is GarageWithKey && current.deletionNeedsPin != needsPin) {
      emit(
        current.copyWith(deletionNeedsPin: needsPin, failure: current.failure),
      );
    }
    if (!needsPin) return true;
    if (reauthenticate == null) return false;
    return await reauthenticate() && !isClosed;
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

  /// Reads the keys of the network and settles on the key selected, with [failure] as the outcome of the action that led here; a closed cubit reads nothing.
  ///
  /// The robot the records give is read before the state is built, so that no panel of another robot is built, and reads its coordinator, in between.
  /// An [Error] of the records is a bug (AGENTS.md, rule 11): it is not caught, and the Garage stays on its wait.
  Future<void> _settle({required P2pFailure? failure}) async {
    if (isClosed) return;
    _stopFollowing();
    emit(GarageWorking(_network));
    final GarageKeyring keyring;
    switch (await _read.keyring(_network)) {
      case Ok(:final value):
        keyring = value;
      case Err(failure: final readFailure):
        if (!isClosed) {
          emit(GarageUnknown(_network, readFailure, actionFailure: failure));
        }
        return;
    }
    if (isClosed) return;
    final read = switch (keyring.selected) {
      SelectedWordsKey(:final index) => await _read.derived(_network, index),
      SelectedExternalKey() => await _read.execute(_network),
    };
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
    final externalSelected = keyring.selected is SelectedExternalKey;
    emit(switch ((read, robot)) {
      (Ok(value: final key), Ok(value: final shown)) => GarageWithKey(
        _network,
        key: key,
        robot: GarageRobotFace.of(shown),
        highest: keyring.highest,
        keyNumbers: {
          for (final (index, fingerprint) in keyring.fingerprints.indexed)
            fingerprint: index,
        },
        hasExternal: keyring.hasExternal,
        externalKey: keyring.external,
        failure: failure,
        ordersNotServed: _ordersNotServedOf(shown.slot),
      ),
      // A key read whose robot could not be derived, or a read that failed: the failure, and for the external key the way back to the keys of the words and its way out.
      (_, Err(failure: final readFailure)) => GarageUnknown(
        _network,
        readFailure,
        actionFailure: failure,
        externalHighest: externalSelected ? keyring.highest : null,
      ),
      (Err(failure: final readFailure), Ok()) => GarageUnknown(
        _network,
        readFailure,
        actionFailure: failure,
        externalHighest: externalSelected ? keyring.highest : null,
      ),
    });
  }

  @override
  Future<void> close() async {
    _stopFollowing();
    return super.close();
  }
}
