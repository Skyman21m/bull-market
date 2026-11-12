import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../domain/network_garage_key.dart';
import '../domain/p2p_failure.dart';
import '../domain/robot_binding.dart';
import '../domain/usecases/delete_garage_key_usecase.dart';
import '../domain/usecases/generate_garage_key_usecase.dart';
import '../domain/usecases/import_garage_key_usecase.dart';
import '../domain/usecases/needs_pin_to_delete_garage_key_usecase.dart';
import '../domain/usecases/read_garage_key_usecase.dart';
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
/// Deleting a key, by « Delete All », « Generate new » or the way out of a key that cannot be read, asks the wallet's PIN once a robot of the key may live on a coordinator, as [NeedsPinToDeleteGarageKeyUsecase] reads it from the feature's database when the user deletes; RoboSats asks only the confirmation.
/// The PIN comes after « Delete Garage Key? », which the screen asks first, and before anything is deleted; a PIN the user leaves, or no PIN to ask, deletes nothing and leaves the screen as it was.
///
/// A key is shown without the PIN only right after the vault drew it, while the user stays in the Garage with the app in the foreground the whole time from the tap on « Generate Garage Key » or « Generate new » ([GarageWithKey.showWithoutPin]); a pasted key never is.
/// [conceal], called whenever the app is hidden or paused, ends that for this key: it hides a key shown, and a hide while the vault is still deleting or drawing keeps the key behind the PIN when it arrives; leaving the Garage closes the cubit.
/// From then on, until the user saw the key and pressed « Continue » or deleted it, [UnacknowledgedGarageKeys] makes each visit show the backup alert, with the key behind the PIN.
class GarageCubit extends Cubit<GarageState> {
  final ReadGarageKeyUsecase _read;
  final GenerateGarageKeyUsecase _generate;
  final ImportGarageKeyUsecase _import;
  final DeleteGarageKeyUsecase _delete;
  final NeedsPinToDeleteGarageKeyUsecase _needsPin;
  final UnacknowledgedGarageKeys _unacknowledged;

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
    this._unacknowledged,
  ) : super(GarageWorking(network));

  RobosatsNetwork get _network => state.network;

  /// Reads the key of the network: when the user opens the Garage.
  Future<void> load() => _settle(failure: null, isNew: false);

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
        // The key is stored all the same, of unknown history: the screens say so, and its robots will ask before they reach a coordinator.
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
  /// Nothing is emitted but what the database said, so a PIN the user leaves leaves the screen as it was.
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

  /// Shows on the state whether the delete needs the PIN, as the database just said, when it differs from what the state shows; the rest of the state is kept as it is.
  void _showDeletionNeedsPin(bool needsPin) {
    final current = state;
    if (current is GarageWithKey && current.deletionNeedsPin != needsPin) {
      emit(
        current.copyWith(deletionNeedsPin: needsPin, failure: current.failure),
      );
    } else if (current is GarageUnknown &&
        current.deletionNeedsPin != needsPin) {
      emit(
        GarageUnknown(
          current.network,
          current.failure,
          actionFailure: current.actionFailure,
          deletionNeedsPin: needsPin,
        ),
      );
    }
  }

  Future<void> _deleteKey() async {
    if (isClosed) return;
    emit(GarageWorking(_network));
    switch (await _delete.execute(_network)) {
      case Ok():
        _unacknowledged._networks.remove(_network);
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

  /// Shows the next robot of the key: the first usable one after the robot shown.
  void next() => _move((key, index) => key.firstUsableRobot(index + 1));

  /// Shows the previous robot of the key: the last usable one before the robot shown.
  void previous() => _move((key, index) => key.lastUsableRobot(index - 1));

  void _move(
    Result<NetworkRobot, P2pFailure> Function(NetworkGarageKey key, int index)
    step,
  ) {
    final current = state;
    if (current is! GarageWithKey) return;
    emit(switch (step(current.key, current.robot.index)) {
      Ok(value: final robot) => current.copyWith(
        robot: GarageRobotFace.of(robot),
        failure: null,
      ),
      Err(:final failure) => current.copyWith(failure: failure),
    });
  }

  /// Reads the slot again and settles on what it holds, with [failure] as the outcome of the action that led here; a closed cubit reads nothing.
  ///
  /// A key drawn and not acknowledged yet awaits its backup; it is shown without the PIN only when this cubit has [justDrawn] it and the app was not hidden since the user asked for it.
  /// Where a delete is offered, the feature's database is read too, for whether it would ask the PIN.
  Future<void> _settle({
    required P2pFailure? failure,
    required bool isNew,
    bool justDrawn = false,
  }) async {
    if (isClosed) return;
    emit(GarageWorking(_network));
    final read = await _read.execute(_network);
    if (isClosed) return;
    // Read before the state is built, so that nothing awaited lies between the state and its emit: a hide of the app during this read keeps a key just drawn behind the PIN.
    final needsPin = switch (read) {
      Ok(value: final key) => await _needsPin.execute(key),
      // No key, or a locked keystore: no delete is offered.
      Err(failure: GarageKeyMissingFailure() || GarageKeyLockedFailure()) =>
        true,
      Err() => await _needsPin.execute(null),
    };
    if (isClosed) return;
    emit(switch (read) {
      Ok(value: final key) => switch (key.firstUsableRobot(0)) {
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
          ),
        },
        Err(failure: final robotFailure) => GarageUnknown(
          _network,
          robotFailure,
          actionFailure: failure,
          deletionNeedsPin: needsPin,
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
        deletionNeedsPin: needsPin,
      ),
    });
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
