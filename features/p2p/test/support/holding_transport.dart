import 'dart:async';

import 'package:p2p/src/domain/usecases/trade/pause_order_usecase.dart';
import 'package:p2p/testing.dart' show ScriptedMakerCoordinator;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'make_harness.dart';

/// A transport in front of [inner] that holds the next `pause` request on its way, before it reaches the coordinator, until the test releases it (#184, after its functional review): a pause in flight, as long as the test wants, to see what a cancel, a watch or a screen opened again does meanwhile.
final class HoldingTransport implements CoordinatorTransport {
  final ScriptedMakerCoordinator inner;
  Completer<void>? _hold;

  /// The pause requests that left this device, held or not.
  int pausesSent = 0;

  HoldingTransport(this.inner);

  /// Holds the next pause request until [release].
  void holdNextPause() => _hold = Completer<void>();

  Completer<void>? _held;

  /// Lets the held pause reach the coordinator.
  void release() {
    final held = _held;
    _held = null;
    held?.complete();
  }

  static bool _isPause(CoordinatorRequest request) =>
      request.method == CoordinatorHttpMethod.post &&
      String.fromCharCodes(request.body ?? const []).contains('"pause"');

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    if (_isPause(request)) {
      pausesSent++;
      final hold = _hold;
      if (hold != null) {
        _hold = null;
        _held = hold;
        await hold.future;
      }
    }
    return inner.send(request);
  }
}

/// The pause use case of [harness] whose requests go through [transport], sharing everything else with the harness's use cases (the reader, the limiter, the order's lock, the pauses in flight).
PauseOrderUsecase pauseThrough(
  MakeHarness harness,
  HoldingTransport transport,
) => PauseOrderUsecase(
  CoordinatorClient(transport, clock: () => harness.now),
  harness.reader,
  harness.limiter,
  harness.locks,
  harness.pausesInFlight,
  harness.keyring,
);
