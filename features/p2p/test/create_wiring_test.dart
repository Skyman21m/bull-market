import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:p2p/public/p2p_wallet_port.dart';
import 'package:p2p/src/domain/usecases/has_garage_key_usecase.dart';
import 'package:p2p/src/presentation/make_order_cubit.dart';
import 'package:p2p/testing.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';
import 'package:test/test.dart';

import 'support/fakes.dart' show FakeTransport;

/// Where the composition registers the create form's cubit (#181, security review R5, R7 M21): only with the Garage, whose `registerGarageKeys` registers `HasGarageKeyUsecase` before it calls `registerTrades`, where the cubit is; so a composition that holds the cubit always holds what it asks for a Garage Key, and one without the Garage holds neither (and `P2pRouter.createPage` is never built there). With or without the wallet's port, the cubit is made: without it, no price check.
void main() {
  final usd = RobosatsCurrency.fromCode('USD') ?? (throw StateError('USD'));

  GetIt compose({required bool garage, P2pWalletPort? wallet}) {
    if (garage) FakeSecureStoragePlatform().install();
    final locator = GetIt.asNewInstance();
    addTearDown(locator.reset);
    final tor = StreamController<P2pTorState>.broadcast();
    addTearDown(tor.close);
    setUpP2pForTesting(
      locator,
      transport: FakeTransport(network: RobosatsNetwork.mainnet),
      torStates: () => tor.stream,
      clock: () => DateTime.utc(2026, 11, 17),
      garageKeys: garage
          ? Secrets(scratchDirectory: () async => '.').garageKeys()
          : null,
      wallet: wallet,
    );
    return locator;
  }

  test('without the Garage: neither the cubit nor the vault\'s question', () {
    final locator = compose(garage: false);
    expect(locator.isRegistered<MakeOrderCubit>(), isFalse);
    expect(locator.isRegistered<HasGarageKeyUsecase>(), isFalse);
  });

  for (final wallet in [false, true]) {
    test(
      'with the Garage, ${wallet ? 'with' : 'without'} the wallet\'s port: the cubit is made, and the vault\'s question with it',
      () async {
        final locator = compose(
          garage: true,
          wallet: wallet ? FakeP2pWalletPort(Ok(Sats.fromInt(1))) : null,
        );
        expect(locator.isRegistered<HasGarageKeyUsecase>(), isTrue);
        final cubit = locator<MakeOrderCubit>(
          param1: RobosatsNetwork.mainnet,
          param2: usd,
        );
        addTearDown(cubit.close);
        expect(cubit.state.network, RobosatsNetwork.mainnet);
        expect(cubit.state.currency, usd);
      },
    );
  }
}
