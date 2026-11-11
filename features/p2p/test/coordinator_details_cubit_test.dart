import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/coordinator_size_limit.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/presentation/coordinator_details_cubit.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart';

/// The recorded `/api/info/` of temple on mainnet.
Map<String, Object?> templeInfo() =>
    jsonDecode(
          File(
            '../../packages/robosats/test/fixtures/coordinator/temple-mainnet-info.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

/// A transport whose answers the test gives one request at a time, in any order.
final class _QueuedTransport implements CoordinatorTransport {
  final List<
    Completer<Result<CoordinatorResponse, CoordinatorTransportFailure>>
  >
  pending = [];

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) {
    final answer =
        Completer<Result<CoordinatorResponse, CoordinatorTransportFailure>>();
    pending.add(answer);
    return answer.future;
  }

  void answerInfo(int request) => pending[request].complete(
    Ok(
      CoordinatorResponse(
        statusCode: 200,
        headers: const {'content-type': 'application/json'},
        body: utf8.encode(jsonEncode(templeInfo())),
      ),
    ),
  );

  void fail(int request) =>
      pending[request].complete(const Err(CoordinatorUnreachable()));
}

/// Lets the pending futures run.
Future<void> _idle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  final temple = coordinator('temple');

  CoordinatorDetailsCubit cubit(
    CoordinatorTransport transport, {
    Coordinator? of,
    CoordinatorInfo? known,
  }) => CoordinatorDetailsCubit(
    CoordinatorDetailsRequest(
      of ?? temple,
      RobosatsNetwork.mainnet,
      known: known,
    ),
    FetchCoordinatorInfoUsecase(CoordinatorClient(transport)),
    now: testNow,
  );

  Future<CoordinatorInfo> readInfo() async {
    final result = await CoordinatorClient(
      FakeTransport(infos: {'temple': templeInfo()}),
    ).fetchInfo(temple, RobosatsNetwork.mainnet);
    return switch (result) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
  }

  test('asks the coordinator, then shows its info', () async {
    final transport = FakeTransport(infos: {'temple': templeInfo()});
    final details = cubit(transport);
    expect(details.state.info, isA<CoordinatorInfoLoading>());

    await details.load();

    expect(
      details.state.info,
      isA<CoordinatorInfoLoaded>().having(
        (loaded) => loaded.info.numPublicBuyOrders,
        'buy orders',
        19,
      ),
    );
    expect(transport.requested, ['temple/api/info/']);
    await details.close();
  });

  test('the info the page already has is shown without asking', () async {
    final info = await readInfo();
    final transport = FakeTransport();
    final details = cubit(transport, known: info);

    expect(details.state.info, isA<CoordinatorInfoLoaded>());
    await details.load();

    expect(transport.requested, isEmpty);
    await details.close();
  });

  test(
    'a coordinator that cannot be asked is offline, and retry asks again',
    () async {
      final transport = FakeTransport(
        infos: {'temple': templeInfo()},
        failures: {'temple': const CoordinatorUnreachable()},
      );
      final details = cubit(transport);
      final states = <CoordinatorInfoStatus>[];
      final listening = details.stream.listen(
        (state) => states.add(state.info),
      );

      await details.load();
      expect(
        details.state.info,
        isA<CoordinatorInfoFailed>().having(
          (failed) => failed.failure,
          'failure',
          isA<CoordinatorUnreachable>(),
        ),
      );

      transport.failures.clear();
      await details.retry();
      await _idle();

      expect(states, [
        isA<CoordinatorInfoFailed>(),
        isA<CoordinatorInfoLoading>(),
        isA<CoordinatorInfoLoaded>(),
      ]);
      expect(transport.requested, ['temple/api/info/', 'temple/api/info/']);
      await listening.cancel();
      await details.close();
    },
  );

  test('a coordinator of another node is offline too', () async {
    final info = templeInfo()
      ..['node_id'] =
          '03ab3468f06d3aac93992ef7ae79bce083e18617dc760f09ef687d7bca89667a15';
    final details = cubit(FakeTransport(infos: {'temple': info}));

    await details.load();

    expect(
      details.state.info,
      isA<CoordinatorInfoFailed>().having(
        (failed) => failed.failure,
        'failure',
        isA<CoordinatorNodeIdMismatch>(),
      ),
    );
    await details.close();
  });

  test('retry does nothing unless the coordinator failed', () async {
    final transport = FakeTransport(infos: {'temple': templeInfo()});
    final loading = cubit(transport);
    await loading.retry();
    expect(loading.state.info, isA<CoordinatorInfoLoading>());
    expect(transport.requested, isEmpty);

    await loading.load();
    await loading.retry();
    expect(loading.state.info, isA<CoordinatorInfoLoaded>());
    expect(transport.requested, hasLength(1));
    await loading.close();
  });

  test('an answer to an older request is dropped', () async {
    final transport = _QueuedTransport();
    final details = cubit(transport);

    final first = details.load();
    final second = details.load();
    await _idle();
    expect(transport.pending, hasLength(2));

    // The latest request fails first, then the older one answers: the screen keeps the latest.
    transport.fail(1);
    await second;
    transport.answerInfo(0);
    await first;

    expect(details.state.info, isA<CoordinatorInfoFailed>());
    await details.close();
  });

  test('closing before the coordinator answers drops the answer', () async {
    final transport = FakeTransport(
      infos: {'temple': templeInfo()},
      held: {'temple'},
    );
    final details = cubit(transport);
    final loading = details.load();
    await details.close();

    transport.release('temple');
    // An answer handled after `close` would throw from `emit`.
    await loading;
    expect(details.state.info, isA<CoordinatorInfoLoading>());
  });

  test(
    'the size limit is read from the federation entry and the clock',
    () async {
      final founder = cubit(FakeTransport());
      expect(founder.state.sizeLimit.sats, CoordinatorSizeLimit.mature);
      await founder.close();

      // Gumpellite joined on 2026-11-06, four days before the clock of the tests.
      final young = cubit(FakeTransport(), of: coordinator('gumpellite'));
      expect(young.state.sizeLimit.sats, 250000);
      expect(young.state.sizeLimit.isLarge, isFalse);
      await young.close();
    },
  );
}
