import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/repositories/robot_binding_repository.dart';
import 'package:p2p/src/domain/repositories/trade_trail_repository.dart';
import 'package:p2p/src/domain/trade/make_price_check.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/make_order_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/take_order_usecase.dart';
import 'package:p2p/src/p2p_router.dart';
import 'package:p2p/src/presentation/garage_cubit.dart';
import 'package:p2p/src/presentation/garage_state.dart';
import 'package:p2p/src/ui/garage/garage_profile.dart';
import 'package:p2p/testing.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/fakes.dart' show FakeTransport;
import 'support/harness.dart';
import 'support/make_harness.dart';
import 'support/trade_harness.dart' show HarnessKeys, TradeHarness, tradeKey;

/// The Garage, mounted under the page of a trade, moving to another robot does not stop that page (#251, security review of PR 274, C1), on the app's real composition (`P2pFeature().route` over `setUpP2pForTesting`): the orders made at the coordinator played by `ScriptedMakerCoordinator` (temple), an order taken here at the one played by `ScriptedCoordinator` (lake), never a real one.
///
/// Before the correction the panel of the trade's robot, closing when the Garage moved, released the robot, which stopped every call of it: the page read nothing more and said « Cannot reach … ».
const _net = RobosatsNetwork.testnet;

const _privacyChannel = MethodChannel('com.flutterplaza.no_screenshot_methods');

/// Lake's requests to the taker's coordinator, every other one to the maker's; the book of temple to an empty fake.
final class _Coordinators implements CoordinatorTransport {
  final ScriptedMakerCoordinator maker;
  final ScriptedCoordinator taker;
  final FakeTransport rest = FakeTransport(network: _net);
  final List<CoordinatorRequest> sent = [];

  _Coordinators(this.maker, this.taker);

  String get _takerHost =>
      Uri.parse(taker.coordinator.origins(_net).onion ?? '').host;

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    sent.add(request);
    if (request.url.host == _takerHost) return taker.send(request);
    final path = request.url.path;
    if (request.robot != null ||
        path == '/api/info/' ||
        path == '/api/limits/' ||
        path == '/api/make/') {
      return maker.send(request);
    }
    return rest.send(request);
  }
}

/// How the Garage stands while the page of the first trade is open above it.
enum _Garage { neverOpened, opened, leftByHand }

void main() {
  final l10n = lookupP2pLocalizations(const Locale('en'));

  /// The first trade, A, made here or taken here; its page kept open above the tab; a second order, B, made, its bond locked and written; then A moves on at its coordinator. The number of reads of A's order by A's robot in the two minutes after, and where A's trail stands.
  Future<(int, String?)> journey(
    WidgetTester tester, {
    required _Garage garage,
    required bool takenHere,
  }) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 2600 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    FakeSecureStoragePlatform().install();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_privacyChannel, (call) async => true);
    addTearDown(
      () => messenger.setMockMethodCallHandler(_privacyChannel, null),
    );
    var now = DateTime.utc(2026, 11, 14, 9);
    final robots = TradeHarness.robotsOf(_net);
    final maker = ScriptedMakerCoordinator(
      network: _net,
      robots: robots,
      clock: () => now,
    );
    final taker = ScriptedCoordinator(
      network: _net,
      robots: robots,
      clock: () => now,
      alias: 'lake',
    );
    final transport = _Coordinators(maker, taker);
    final locator = GetIt.asNewInstance();
    setUpP2pForTesting(
      locator,
      transport: transport,
      torStates: () => Stream.value(P2pTorState.ready),
      clock: () => now,
      garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
      wallet: FakeP2pWalletPort(Ok(Sats.fromInt(50000)))
        ..rate = P2pWalletRateRead(91711.15),
      robotKeys: HarnessKeys(),
      bolt11Decoder: maker.decoder,
    );
    final router = GoRouter(
      initialLocation: P2pFeature.path,
      routes: [const P2pFeature().route(locator, network: (_) => _net)],
    );

    Future<void> settle([int rounds = 8]) async {
      for (var i = 0; i < rounds; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<T> wait<T>(Future<T> Function() run) async {
      late T value;
      Object? error;
      var done = false;
      unawaited(
        run().then(
          (v) {
            value = v;
            done = true;
          },
          onError: (Object e) {
            error = e;
            done = true;
          },
        ),
      );
      for (var i = 0; i < 400 && !done; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      if (error case final error?) throw error;
      if (!done) throw StateError('never done');
      return value;
    }

    final fingerprint = switch (GarageKeyFingerprint.of(tradeKey)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
    await wait(
      () async => (
        await locator<GarageKeyRepository>().import(_net, tradeKey),
        await locator<RobotBindingRepository>().recordGeneratedKey(
          _net,
          fingerprint,
        ),
      ),
    );
    await tester.pumpWidget(routerHarness(router));
    await settle();

    Future<TradeRecord> make(double amount) async {
      final request = MakeHarness.request(amount: amount);
      return switch (await wait(
        () => locator<MakeOrderUsecase>().execute(
          request,
          coordinator: maker.coordinator,
          network: _net,
          seen: MakePriceSeen.of(
            currency: request.currency,
            coordinatorPrice: maker.prices[request.currency.id] ?? 1,
          ),
        ),
      )) {
        Ok(value: MakeStarted(:final record)) => record,
        final other => throw StateError('$other'),
      };
    }

    Future<void> push(TradeRecord record) async {
      unawaited(
        router.pushNamed(P2pRouter.tradeName, extra: P2pTradeRouteArgs(record)),
      );
      await settle(12);
    }

    Future<void> back() async {
      await tester.binding.handlePopRoute();
      await settle(12);
    }

    int shown() => switch (BlocProvider.of<GarageCubit>(
      tester.element(find.byType(GarageProfile, skipOffstage: false)),
    ).state) {
      GarageWithKey(:final robot) => robot.index,
      final other => throw StateError('$other'),
    };

    // A: taken here at lake, or made here at temple; its bond locked and read by its page.
    final TradeRecord first;
    if (takenHere) {
      final book = await wait(
        () => CoordinatorClient(
          transport,
          clock: () => now,
        ).fetchBook(taker.coordinator, _net),
      );
      final order = switch (book) {
        Ok(value: OrderBook(orders: [final order, ...])) => order,
        final other => throw StateError('$other'),
      };
      first = switch (await wait(
        () => locator<TakeOrderUsecase>().execute(order, network: _net),
      )) {
        Ok(value: final TakeStarted started) => started.record,
        final other => throw StateError('$other'),
      };
      taker.lockBond(robots[first.robot.accountIndex]);
    } else {
      first = await make(100);
      maker.lockMakerBond(first.orderId);
    }
    await push(first);
    await back();

    // The Garage, mounted under the pages, on A.
    if (garage != _Garage.neverOpened) {
      await tester.tap(find.text(l10n.p2pNavGarage));
      await settle();
      await tester.pump(const Duration(seconds: 6));
      await settle(20);
      expect(shown(), first.robot.accountIndex);
      if (garage == _Garage.leftByHand) {
        await tester.tap(find.byTooltip(l10n.p2pGarageNextAccount));
        await settle(12);
        await tester.tap(find.byTooltip(l10n.p2pGaragePreviousAccount));
        await settle(12);
        expect(shown(), first.robot.accountIndex);
      }
    }

    // A's page open above, kept.
    await push(first);
    // B made, its bond locked and written: its page opened over A's, then left.
    final second = await make(130);
    maker.lockMakerBond(second.orderId);
    await push(second);
    await back();
    if (garage != _Garage.neverOpened) {
      // The Garage, under A's page, moved to B: A's panel closed.
      expect(shown(), second.robot.accountIndex);
    }

    // A moves on at its coordinator, then two minutes of A's page.
    final aRobot = robots[first.robot.accountIndex].sessionKey;
    final readsBefore = transport.sent
        .where(
          (request) =>
              request.robot == aRobot &&
              request.url.path == '/api/order/' &&
              request.method == CoordinatorHttpMethod.get,
        )
        .length;
    if (takenHere) {
      taker.moveTo(7);
    } else {
      maker.take(first.orderId, robots[5]);
    }
    for (var i = 0; i < 24; i++) {
      now = now.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      await settle(2);
    }
    final reads =
        transport.sent
            .where(
              (request) =>
                  request.robot == aRobot &&
                  request.url.path == '/api/order/' &&
                  request.method == CoordinatorHttpMethod.get,
            )
            .length -
        readsBefore;
    expect(find.textContaining('Cannot reach'), findsNothing);
    final position = switch (await wait(
      () => locator<TradeTrailRepository>().historyOf(first),
    )) {
      Ok(:final value) => value.trail?.position,
      Err(:final failure) => throw StateError('$failure'),
    };
    await tester.pumpWidget(const SizedBox.shrink());
    await settle();
    await tester.pump(const Duration(seconds: 61));
    await locator.reset();
    return (reads, position);
  }

  for (final takenHere in [false, true]) {
    final what = takenHere ? 'taken here' : 'made here';
    testWidgets(
      'an order $what, its page open above the Garage: the Garage moving to another order\'s robot, after it opened on it or was left on it by hand, the page reads on as often as without the Garage and shows the trade moved on, never « Cannot reach »',
      (tester) async {
        final witness = await journey(
          tester,
          garage: _Garage.neverOpened,
          takenHere: takenHere,
        );
        expect(witness.$1, greaterThan(0));
        expect(witness.$2, takenHere ? 'waitingForEscrow' : 'waitingForBoth');
        for (final garage in [_Garage.opened, _Garage.leftByHand]) {
          expect(
            await journey(tester, garage: garage, takenHere: takenHere),
            witness,
            reason: garage.name,
          );
        }
      },
    );
  }
}
