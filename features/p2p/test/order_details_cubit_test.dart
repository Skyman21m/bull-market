import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/presentation/order_details_cubit.dart';
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

void main() {
  late PublicOrder order;

  setUpAll(() async {
    [order] = await parseOrders([bookOrder(id: 1, satoshisNow: 107000)]);
  });

  OrderDetailsCubit cubit(FakeTransport transport) => OrderDetailsCubit(
    order,
    RobosatsNetwork.mainnet,
    FetchCoordinatorInfoUsecase(CoordinatorClient(transport)),
  );

  test('the fees of the host refine the estimate', () async {
    final details = cubit(FakeTransport(infos: {'temple': templeInfo()}));
    expect(details.state.estimate?.maxSats, 106893);

    await details.load();

    expect(details.state.info, isNotNull);
    expect(details.state.infoFailed, isFalse);
    expect(details.state.estimate?.maxSats, 107080);
    await details.close();
  });

  test('a host that does not answer leaves the order shown without fees', () async {
    final details = cubit(
      FakeTransport(failures: {'temple': const CoordinatorUnreachable()}),
    );

    await details.load();

    expect(details.state.info, isNull);
    expect(details.state.infoFailed, isTrue);
    expect(details.state.order, order);
    await details.close();
  });

  test('closing before the host answers drops the answer', () async {
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
    expect(details.state.info, isNull);
  });
}
