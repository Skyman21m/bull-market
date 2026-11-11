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
/// It follows the rules of the vault: a key is generated or imported only in [GarageWithoutKey], so only after a read found no key; a stored key is never replaced, and « Generate new » deletes it first, after the user confirmed; after a failed write the slot is read again before anything is offered.
/// An action started while another is running is ignored.
class GarageCubit extends Cubit<GarageState> {
  final ReadGarageKeyUsecase _read;
  final GenerateGarageKeyUsecase _generate;
  final ImportGarageKeyUsecase _import;
  final DeleteGarageKeyUsecase _delete;

  GarageCubit(
    RobosatsNetwork network,
    this._read,
    this._generate,
    this._import,
    this._delete,
  ) : super(GarageWorking(network));

  RobosatsNetwork get _network => state.network;

  /// Reads the key of the network: when the user opens the Garage.
  Future<void> load() => _settle(failure: null, isNew: false);

  /// Draws a new key in the vault for a network that has none, on the user's request, then reads it back to show it for backup at once.
  Future<void> generate() async {
    if (state is! GarageWithoutKey) return;
    emit(GarageWorking(_network));
    switch (await _generate.execute(_network)) {
      case Ok():
        await _settle(failure: null, isNew: true);
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
        if (!isClosed) emit(GarageWithoutKey(_network));
      case Err(:final failure):
        await _settle(failure: failure, isNew: false);
    }
  }

  /// « Generate new » with a key stored: deletes it, then draws a new one; only after the user confirmed « Delete Garage Key? ».
  Future<void> replace() async {
    if (state is! GarageWithKey) return;
    await delete();
    await generate();
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
      Ok(value: final robot) => GarageWithKey(
        _network,
        key: current.key,
        robot: GarageRobotFace.of(robot),
        isNew: current.isNew,
      ),
      Err(:final failure) => GarageWithKey(
        _network,
        key: current.key,
        robot: current.robot,
        isNew: current.isNew,
        failure: failure,
      ),
    });
  }

  /// Reads the slot again and settles on what it holds, with [failure] as the outcome of the action that led here.
  Future<void> _settle({
    required P2pFailure? failure,
    required bool isNew,
  }) async {
    if (!isClosed) emit(GarageWorking(_network));
    final read = await _read.execute(_network);
    if (isClosed) return;
    emit(switch (read) {
      Ok(value: final key) => switch (key.firstUsableRobot(0)) {
        Ok(value: final robot) => GarageWithKey(
          _network,
          key: key,
          robot: GarageRobotFace.of(robot),
          isNew: isNew,
          failure: failure,
        ),
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
