import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/repositories/garage_recovery_note_repository.dart';
import 'package:p2p/src/domain/repositories/robot_binding_repository.dart';
import 'package:p2p/src/domain/repositories/trade_record_repository.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/make_price_check.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/make_order_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/take_order_usecase.dart';
import 'package:p2p/src/presentation/garage_cubit.dart';
import 'package:p2p/src/presentation/garage_state.dart';
import 'package:p2p/testing.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/fakes.dart' show FakeTransport;
import 'support/harness.dart';
import 'support/make_harness.dart';
import 'support/note_relays.dart';
import 'support/trade_harness.dart' show HarnessKeys, TradeHarness, tradeKey;

/// The recovery note of the Garage Keys on the app's real composition (#81, functional review of #302, R8): `setUpP2pForTesting` registers `RecoveryNoteSync` through the locator's own lines over relays played in memory (never a real relay), and the tab, the Garage and the trade use cases reach it through their real wiring. The first showing of the P2P tab reads the key new trades take and writes the keys in use; the Garage reads the key it shows and moves when the note's floor arrives; a make and a take take their robot above the floor and write after the coordinator confirmed. The coordinators are played by `ScriptedMakerCoordinator` (temple) and `ScriptedCoordinator` (lake), never real ones.
const _net = RobosatsNetwork.testnet;

/// The `no_screenshot` plugin behind the Garage's `PrivacyScreen`.
const _privacyChannel = MethodChannel('com.flutterplaza.no_screenshot_methods');

/// Lake's requests to the taker's coordinator, every other one to the maker's; the books to an empty fake.
final class _Coordinators implements CoordinatorTransport {
  final ScriptedMakerCoordinator maker;
  final ScriptedCoordinator taker;
  final FakeTransport rest = FakeTransport(network: _net);

  _Coordinators(this.maker, this.taker);

  String get _takerHost =>
      Uri.parse(taker.coordinator.origins(_net).onion ?? '').host;

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
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

/// The composition of one test: the feature set up as the app sets it up, its Garage Key the tests' key (fake bytes) imported and recorded as drawn here, its note relays [relays].
final class _App {
  final GetIt locator;
  final FakeNoteRelays relays;
  final ScriptedMakerCoordinator maker;
  final ScriptedCoordinator taker;
  final _Coordinators transport;
  final DateTime now;

  _App._(
    this.locator,
    this.relays,
    this.maker,
    this.taker,
    this.transport,
    this.now,
  );

  static final GarageKeyFingerprint fingerprint =
      switch (GarageKeyFingerprint.of(tradeKey)) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };

  /// The relays of the coordinators of testnet.
  static final List<Uri> noteRelays = nostrRelaysOfNetwork(
    Federation.robosats,
    _net,
  );

  static _App setUp() {
    FakeSecureStoragePlatform().install();
    final now = DateTime.utc(2026, 11, 14, 9);
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
    final relays = FakeNoteRelays();
    final locator = GetIt.asNewInstance();
    addTearDown(locator.reset);
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
      noteRelays: relays,
      noteCompute: InlineNoteCompute(),
    );
    return _App._(locator, relays, maker, taker, transport, now);
  }

  /// The tests' key imported in the vault's slot of testnet, selected, and recorded as drawn here, then robot [reserved] of it reserved for a trade at temple when given, as a reservation leaves it: the answers of each, in order.
  Future<List<Result<Object?, Failure>>> keyedAnswers({int? reserved}) async =>
      [
        await locator<GarageKeyRepository>().import(_net, tradeKey),
        await locator<RobotBindingRepository>().recordGeneratedKey(
          _net,
          fingerprint,
        ),
        if (reserved != null)
          await locator<TradeRecordRepository>().reserveForNewTrade(
            RobotSlot(_net, fingerprint, reserved),
            CoordinatorIdentity.of(maker.coordinator, _net)!,
          ),
      ];

  /// [keyedAnswers], each an [Ok].
  Future<void> keyed() async =>
      expect(await keyedAnswers(), everyElement(isA<Ok<Object?, Failure>>()));

  /// The note [index] of the tests' key held by every relay of testnet.
  void holdNote(int index) {
    for (final relay in noteRelays) {
      relays.on(relay).add(noteOf(tradeKey.recoveryNostrKeyPair, index, now));
    }
  }

  /// What this device read of the note of the tests' key.
  Future<GarageNoteStanding> standing() async =>
      switch (await locator<GarageRecoveryNoteRepository>().standingOf(
        _net,
        fingerprint,
      )) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };

  /// The indexes the notes published for the tests' key say, one per publication.
  List<int> published() => [
    for (final (_, event) in relays.published)
      if (GarageRecoveryNote.latestNote(tradeKey, [event]) case final reading?)
        reading.accountIndex,
  ];
}

void main() {
  group('the first showing of the P2P tab, through the router', () {
    Future<_App> showTab(WidgetTester tester, {int? reserved}) async {
      tester.view
        ..physicalSize = const Size(390 * 3, 2600 * 3)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(_privacyChannel, (call) async => true);
      addTearDown(
        () => messenger.setMockMethodCallHandler(_privacyChannel, null),
      );
      final app = _App.setUp();
      app.holdNote(3);
      expect(
        await _wait(tester, () => app.keyedAnswers(reserved: reserved)),
        everyElement(isA<Ok<Object?, Failure>>()),
      );
      final router = GoRouter(
        initialLocation: P2pFeature.path,
        routes: [const P2pFeature().route(app.locator, network: (_) => _net)],
      );
      await tester.pumpWidget(routerHarness(router));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      return app;
    }

    testWidgets(
      'reads the key new trades take, with no robot in use (a reinstall), and writes nothing for it',
      (tester) async {
        final app = await showTab(tester);
        expect(
          await _wait(tester, app.standing),
          const GarageNoteStanding(floor: 3, read: true),
        );
        expect(app.relays.reads, hasLength(_App.noteRelays.length));
        expect(app.relays.published, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 61));
      },
    );

    testWidgets(
      'writes the note of the key in use, after reading it, with the highest index the device knows',
      (tester) async {
        final app = await showTab(tester, reserved: 1);
        expect(
          await _wait(tester, app.standing),
          const GarageNoteStanding(floor: 3, read: true),
        );
        // Robot 1 in use, the note read says 3: the note written says 3, on every relay.
        expect(app.published(), List.filled(_App.noteRelays.length, 3));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 61));
      },
    );
  });

  test(
    'the Garage, as the locator builds it, reads the key it shows, and moves to the robot of the note once the note is read',
    () async {
      final app = _App.setUp();
      await app.keyed();
      app.holdNote(3);
      final release = Completer<void>();
      for (final relay in _App.noteRelays) {
        app.relays.answers[relay] = (stored, filters) async {
          await release.future;
          return NostrRelayRead(
            events: FakeNoteRelays.matching(stored, filters),
            complete: true,
            label: 'answered',
          );
        };
      }
      final garage = app.locator<GarageCubit>(param1: _net);
      addTearDown(garage.close);
      unawaited(garage.load());
      Future<int?> shown(int index) async {
        final waited = Stopwatch()..start();
        while (waited.elapsed < const Duration(seconds: 5)) {
          if (garage.state case GarageWithKey(
            :final robot,
          ) when robot.index == index) {
            return robot.index;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        return switch (garage.state) {
          GarageWithKey(:final robot) => robot.index,
          _ => null,
        };
      }

      // Robot 0 first: the note is still being read, on every relay.
      expect(await shown(0), 0);
      expect(app.relays.reads, hasLength(_App.noteRelays.length));
      release.complete();
      // The floor recorded, the Garage moves to the robot the note names.
      expect(await shown(3), 3);
      expect(
        await app.standing(),
        const GarageNoteStanding(floor: 3, read: true),
      );
    },
  );

  test(
    'a make and a take by the composition\'s use cases take their robot above the floor of the note, and write it after the coordinator confirmed',
    () async {
      final app = _App.setUp();
      await app.keyed();
      app.holdNote(2);
      final request = MakeHarness.request();
      final made = switch (await app.locator<MakeOrderUsecase>().execute(
        request,
        coordinator: app.maker.coordinator,
        network: _net,
        seen: MakePriceSeen.of(
          currency: request.currency,
          coordinatorPrice: app.maker.prices[request.currency.id] ?? 1,
        ),
      )) {
        Ok(value: MakeStarted(:final record)) => record,
        final other => throw StateError('$other'),
      };
      expect(made.robot.accountIndex, 3);
      await _published(app, _App.noteRelays.length);
      expect(app.published(), List.filled(_App.noteRelays.length, 3));

      final book = await CoordinatorClient(
        app.transport,
        clock: () => app.now,
      ).fetchBook(app.taker.coordinator, _net);
      final order = switch (book) {
        Ok(value: OrderBook(orders: [final order, ...])) => order,
        final other => throw StateError('$other'),
      };
      final TradeRecord taken = switch (await app
          .locator<TakeOrderUsecase>()
          .execute(order, network: _net)) {
        Ok(value: final TakeStarted started) => started.record,
        final other => throw StateError('$other'),
      };
      expect(taken.robot.accountIndex, 4);
      await _published(app, 2 * _App.noteRelays.length);
      expect(app.published(), [
        ...List.filled(_App.noteRelays.length, 3),
        ...List.filled(_App.noteRelays.length, 4),
      ]);
    },
  );
}

/// Waits until [app]'s relays have [count] publications, or five seconds have passed.
Future<void> _published(_App app, int count) async {
  final waited = Stopwatch()..start();
  while (app.relays.published.length < count &&
      waited.elapsed < const Duration(seconds: 5)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Runs [run] under the test's fake clock, pumping frames until it ends.
Future<T> _wait<T>(WidgetTester tester, Future<T> Function() run) async {
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
