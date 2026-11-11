import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../domain/coordinator_size_limit.dart';
import '../domain/usecases/fetch_coordinator_info_usecase.dart';

/// Where the `/api/info/` of the coordinator stands.
@immutable
sealed class CoordinatorInfoStatus {
  const CoordinatorInfoStatus();
}

/// The coordinator is being asked.
final class CoordinatorInfoLoading extends CoordinatorInfoStatus {
  const CoordinatorInfoLoading();
}

final class CoordinatorInfoLoaded extends CoordinatorInfoStatus {
  final CoordinatorInfo info;

  const CoordinatorInfoLoaded(this.info);
}

/// The coordinator could not be asked: the dialog says « Coordinator offline », as the official client does without its info.
final class CoordinatorInfoFailed extends CoordinatorInfoStatus {
  final CoordinatorFailure failure;

  const CoordinatorInfoFailed(this.failure);
}

/// The coordinator dialog: the entry of the federation list, and what the coordinator says about itself once it answers.
@immutable
final class CoordinatorDetailsState {
  final Coordinator coordinator;
  final RobosatsNetwork network;

  /// The size limit of the coordinator when the dialog opened.
  final CoordinatorSizeLimit sizeLimit;
  final CoordinatorInfoStatus info;

  const CoordinatorDetailsState({
    required this.coordinator,
    required this.network,
    required this.sizeLimit,
    required this.info,
  });

  CoordinatorDetailsState withInfo(CoordinatorInfoStatus info) =>
      CoordinatorDetailsState(
        coordinator: coordinator,
        network: network,
        sizeLimit: sizeLimit,
        info: info,
      );
}

/// What opens the dialog of one coordinator: the coordinator, the network of its book, and its info when the opening page already has it.
@immutable
final class CoordinatorDetailsRequest {
  final Coordinator coordinator;
  final RobosatsNetwork network;

  /// The `/api/info/` the page already read, shown at once instead of asking again.
  final CoordinatorInfo? known;

  const CoordinatorDetailsRequest(this.coordinator, this.network, {this.known});
}

/// Shows one coordinator and asks it for its info, unless the page that opened the dialog already has it.
class CoordinatorDetailsCubit extends Cubit<CoordinatorDetailsState> {
  final FetchCoordinatorInfoUsecase _fetchInfo;

  /// The number of the latest request: an answer to an older one is dropped.
  int _request = 0;

  CoordinatorDetailsCubit(
    CoordinatorDetailsRequest request,
    this._fetchInfo, {
    required DateTime now,
  }) : super(
         CoordinatorDetailsState(
           coordinator: request.coordinator,
           network: request.network,
           sizeLimit: CoordinatorSizeLimit.of(request.coordinator, now),
           info: switch (request.known) {
             final info? => CoordinatorInfoLoaded(info),
             null => const CoordinatorInfoLoading(),
           },
         ),
       );

  /// Asks the coordinator for its info, unless it is already shown.
  Future<void> load() async {
    if (state.info is CoordinatorInfoLoaded) return;
    await _ask();
  }

  /// Asks again a coordinator that could not be asked.
  Future<void> retry() async {
    if (state.info is! CoordinatorInfoFailed) return;
    emit(state.withInfo(const CoordinatorInfoLoading()));
    await _ask();
  }

  Future<void> _ask() async {
    final id = ++_request;
    final result = await _fetchInfo.execute(state.coordinator, state.network);
    if (isClosed || id != _request) return;
    emit(
      state.withInfo(switch (result) {
        Ok(:final value) => CoordinatorInfoLoaded(value),
        Err(:final failure) => CoordinatorInfoFailed(failure),
      }),
    );
  }
}
