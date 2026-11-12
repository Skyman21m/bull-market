import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../domain/network_garage_key.dart';
import '../domain/p2p_failure.dart';
import '../domain/usecases/delete_garage_key_usecase.dart';
import '../domain/usecases/generate_garage_key_usecase.dart';
import '../domain/usecases/import_garage_key_usecase.dart';
import '../domain/usecases/read_garage_key_usecase.dart';
import 'garage_state.dart';

/// The Garage of one network: the Garage Key of that network in the vault, the robot shown, and the actions of the user on them.
///
/// It touches the vault only when a method is called: [load] when the user opens the Garage, the others on an explicit action of the user.
/// It follows the rules of the vault: a key is generated or imported only in [GarageWithoutKey], so only after a read found no key or a delete the vault confirmed; a stored key is never replaced, and « Generate new » deletes it first, after the user confirmed; after a failed write the slot is read again before anything is offered.
/// An action started while another is running is ignored.
/// An action the user started finishes in the vault even when the user leaves the Garage, but a closed cubit never reads the vault again.
///
/// A key is shown without the PIN only right after the vault drew it, while the user stays in the Garage with the app in the foreground the whole time from the tap on « Generate Garage Key » or « Generate new » ([GarageWithKey.showWithoutPin]); a pasted key never is.
/// [conceal], called whenever the app is hidden or paused, ends that for this key: it hides a key shown, and a hide while the vault is still deleting or drawing keeps the key behind the PIN when it arrives; leaving the Garage closes the cubit.
/// From then on, until the user saw the key and pressed « Continue » or deleted it, [UnacknowledgedGarageKeys] makes each visit show the backup alert, with the key behind the PIN.
class GarageCubit extends Cubit<GarageState> {
  final ReadGarageKeyUsecase _read;
  final GenerateGarageKeyUsecase _generate;
  final ImportGarageKeyUsecase _import;
  final DeleteGarageKeyUsecase _delete;
  final UnacknowledgedGarageKeys _unacknowledged;

  /// Whether the app was hidden or paused since the user asked for a new key: the key then arrives behind the PIN.
  bool _concealedSinceAsked = false;

  GarageCubit(
    RobosatsNetwork network,
    this._read,
    this._generate,
    this._import,
    this._delete,
    this._unacknowledged,
  ) : super(GarageWorking(network));

  RobosatsNetwork get _network => state.network;

  /// Reads the key of the network: when the user opens the Garage.
  Future<void> load() => _settle(failure: null, isNew: false);

  /// Draws a new key in the vault for a network that has none, on the user's request, then reads it back to show it for backup at once, unless the app was hidden meanwhile.
  Future<void> generate() async {
    if (state is! GarageWithoutKey) return;
    _concealedSinceAsked = false;
    await _draw();
  }

  Future<void> _draw() async {
    if (state is! GarageWithoutKey) return;
    emit(GarageWorking(_network));
    switch (await _generate.execute(_network)) {
      // A key whose history could not be recorded (`GarageKeyHistory.unknown`) is told to the user by the step that makes robots usable, which does not exist yet.
      case Ok():
        // Remembered before anything else, so that a user who left meanwhile gets the backup alert at the next visit.
        _unacknowledged._networks.add(_network);
        await _settle(failure: null, isNew: true, justDrawn: true);
      case Err(:final failure):
        await _settle(failure: failure, isNew: false);
    }
  }

  /// Stores the key whose `robo1…` form is [text], which the user pasted or typed, for a network that has none.
  ///
  /// Text that is not a key changes nothing in the vault and leaves the Garage without a key, with the reason; the text itself is not kept.
  Future<void> import(String text) async {
    if (state is! GarageWithoutKey) return;
    emit(GarageWorking(_network));
    switch (await _import.execute(_network, text: text)) {
      case Ok():
        await _settle(failure: null, isNew: true);
      case Err(failure: final GarageKeyInvalidFailure failure):
        if (!isClosed) emit(GarageWithoutKey(_network, failure: failure));
      case Err(:final failure):
        await _settle(failure: failure, isNew: false);
    }
  }

  /// Deletes the key of the network, whatever its entry holds: only after the user confirmed « Delete Garage Key? ».
  ///
  /// The key of the other network is never touched.
  Future<void> delete() async {
    if (state is GarageWorking || state is GarageWithoutKey) return;
    emit(GarageWorking(_network));
    switch (await _delete.execute(_network)) {
      case Ok():
        _unacknowledged._networks.remove(_network);
        if (!isClosed) emit(GarageWithoutKey(_network));
      case Err(:final failure):
        await _settle(failure: failure, isNew: false);
    }
  }

  /// « Generate new » with a key stored: deletes it, then draws a new one; only after the user confirmed « Delete Garage Key? ».
  ///
  /// A hide of the app at any time from here, during the delete as during the draw, keeps the new key behind the PIN.
  Future<void> replace() async {
    if (state is! GarageWithKey) return;
    _concealedSinceAsked = false;
    await delete();
    await _draw();
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
  Future<void> _settle({
    required P2pFailure? failure,
    required bool isNew,
    bool justDrawn = false,
  }) async {
    if (isClosed) return;
    emit(GarageWorking(_network));
    final read = await _read.execute(_network);
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
