import 'dart:async';

import 'package:p2p/public/p2p_wallet_port.dart';
import 'package:p2p/src/domain/coordinator_lottery.dart';
import 'package:p2p/src/domain/coordinator_size_limit.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_host.dart';
import 'package:p2p/src/domain/trade/make_price_check.dart';
import 'package:p2p/src/domain/trade/maker_form.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/presentation/make_order_cubit.dart';
import 'package:p2p/testing.dart' show ScriptedFault, ScriptedMakerRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/make_form.dart';
import 'support/make_harness.dart';

/// The create form's cubit (#181): the default coordinator by the reference's lottery, the limits of the coordinator chosen, the price check of the owner's decision of 2026-11-17, and the make, once.
void main() {
  group('over the make use case and its scripted coordinator', () {
    /// The cubit of [harness]'s network, its only coordinator Temple of Sats, the make the real use case's.
    MakeOrderCubit cubitOver(
      MakeHarness harness, {
      CheckMakePrice? checkPrice,
      RobosatsCurrency? currency,
    }) {
      final client = CoordinatorClient(harness.coordinator);
      return MakeOrderCubit(
        harness.network,
        currency: currency ?? eur,
        listHosts: (network) => RobotHosts(network, [
          RobotHost(harness.host, refusesFirstContacts: false),
        ]),
        fetchInfo: client.fetchInfo,
        fetchLimits: client.fetchLimits,
        make: harness.make.execute,
        hasGarageKey: (_) async => const Ok(true),
        lottery: CoordinatorLottery(() => 0.5),
        now: () => harness.now,
        checkPrice: checkPrice,
      );
    }

    /// The request the form builds for 100 EUR at [premium], Revolut, « Buy ».
    MakeOrderRequest requestOf(MakeOrderState state, {String premium = '2'}) =>
        MakerFormCheck.of(
          MakerFormInput(
            type: OrderType.buy,
            currency: state.currency,
            amount: '100',
            paymentMethods: const ['Revolut'],
            premium: premium,
          ),
          coordinatorsLoaded: state.coordinatorsLoaded,
          market: state.limits,
          sizeLimitSats: state.sizeLimitSats,
        ).request ??
        (throw StateError('no request'));

    int makes(MakeHarness harness) => harness.coordinator.received
        .where((kind) => kind == ScriptedMakerRequest.make)
        .length;

    test(
      'a made order: the request of the form sent once, its trade opened at status 0 with its bond',
      () async {
        final harness = await MakeHarness.start();
        final cubit = cubitOver(harness);
        addTearDown(cubit.close);
        await cubit.start();
        await harness.settle();
        expect(cubit.state.coordinator, harness.host);
        expect(cubit.state.limits, isA<MakerFormLimitsRead>());
        final request = requestOf(cubit.state);
        await Future.wait([cubit.make(request), cubit.make(request)]);
        await harness.settle();
        expect(makes(harness), 1);
        final made = cubit.state.progress;
        expect(made, isA<MakeMade>());
        final record = (made as MakeMade).record;
        expect(record.origin, TradeOrigin.madeHere);
        expect(record.orderId, 42);
        // What the coordinator received is what the summary shows.
        final body = harness.coordinator.order(42).body;
        expect(body['amount'], 100);
        expect(body['premium'], 2);
        expect(body['payment_method'], 'Revolut');
        expect(body['type'], 0);
        expect(body['currency'], eur.id);
        expect(body['public_duration'], 86340);
        expect(body['escrow_duration'], 10800);
        expect(body['bond_size'], 3);
        final run = harness.watchOf(record);
        await harness.settle();
        expect(run.lastStatus.seen.status, isA<WaitingForMakerBond>());
        await run.subscription.cancel();
        // Made: nothing more is made, and no other coordinator is chosen.
        await cubit.make(request);
        await cubit.choose(coordinatorOf('lake'));
        expect(makes(harness), 1);
        expect(cubit.state.coordinator, harness.host);
      },
    );

    test(
      'refused before any robot: the price unknown, nothing reserved, and a make may be tried again',
      () async {
        final harness = await MakeHarness.start();
        final cubit = cubitOver(harness);
        addTearDown(cubit.close);
        await cubit.start();
        await harness.settle();
        await cubit.make(MakeHarness.request(currency: usd));
        await harness.settle();
        expect(
          cubit.state.progress,
          isA<MakeIdle>().having(
            (idle) => idle.problem,
            'problem',
            isA<MakeWasRefused>().having(
              (refused) => refused.refusal,
              'refusal',
              isA<MakePriceUnknown>(),
            ),
          ),
        );
        expect(makes(harness), 0);
        expect(await harness.allTrades(), isEmpty);
        await cubit.make(requestOf(cubit.state));
        await harness.settle();
        expect(cubit.state.progress, isA<MakeMade>());
      },
    );

    test(
      'refused by the coordinator before it made anything: not made, said, and the form free again',
      () async {
        final harness = await MakeHarness.start();
        harness.coordinator.refuseNextMake(1004);
        final cubit = cubitOver(harness);
        addTearDown(cubit.close);
        await cubit.start();
        await harness.settle();
        await cubit.make(requestOf(cubit.state));
        await harness.settle();
        expect(
          cubit.state.progress,
          isA<MakeIdle>().having(
            (idle) => idle.problem,
            'problem',
            isA<MakeWasNotMade>().having(
              (notMade) => notMade.refusal,
              'refusal',
              isA<OrderSizeRefused>(),
            ),
          ),
        );
        expect(cubit.state.locked, isFalse);
      },
    );

    test(
      'a make whose answer was lost: uncertain, the form locked, never made again',
      () async {
        final harness = await MakeHarness.start();
        harness.coordinator.failNext(
          ScriptedMakerRequest.make,
          ScriptedFault.answerLost,
        );
        final cubit = cubitOver(harness);
        addTearDown(cubit.close);
        await cubit.start();
        await harness.settle();
        final request = requestOf(cubit.state);
        await cubit.make(request);
        await harness.settle();
        expect(cubit.state.progress, isA<MakeUncertain>());
        expect(cubit.state.locked, isTrue);
        expect(await harness.pendingMakes(), hasLength(1));
        await cubit.make(request);
        await harness.settle();
        expect(makes(harness), 1);
      },
    );

    test(
      'the price compared once the limits are read, with the coordinator\'s price of the currency, before any robot',
      () async {
        final harness = await MakeHarness.start();
        final asked = <(RobosatsNetwork, RobosatsCurrency, double)>[];
        final cubit = cubitOver(
          harness,
          checkPrice: (network, currency, price) async {
            asked.add((network, currency, price));
            // No robot exists when the Bull wallet's price is read.
            expect(await harness.allTrades(), isEmpty);
            return MakePriceCheck.of(
              currency: currency,
              coordinatorPrice: price,
              wallet: P2pWalletRateRead(100000),
            );
          },
        );
        addTearDown(cubit.close);
        await cubit.start();
        await harness.settle();
        expect(asked, [(harness.network, eur, 91711.15)]);
        expect(
          cubit.state.price,
          isA<MakeFormPriceChecked>().having(
            (checked) => checked.check,
            'check',
            isA<MakePriceCompared>(),
          ),
        );
      },
    );
  });

  group('over fakes', () {
    late Map<String, CoordinatorInfo> infos;
    late CurrencyLimits limits;
    setUpAll(() async {
      limits = await limitsAt({2: 91711.15, 1: 100000});
      infos = {
        // Temple's fees above the default, its donation the most counted: the first of the lottery.
        'temple': await infoAt('temple', devfund: 50, makerFee: 0.001),
        'lake': await infoAt('lake', devfund: 0),
      };
    });

    MakeOrderCubit cubitOf(_Calls calls, {bool wallet = true}) =>
        MakeOrderCubit(
          RobosatsNetwork.mainnet,
          currency: eur,
          listHosts: (network) => RobotHosts(network, [
            for (final coordinator in Federation.robosats.on(network))
              RobotHost(
                coordinator,
                refusesFirstContacts: calls.refusing.contains(
                  coordinator.shortAlias,
                ),
              ),
          ]),
          fetchInfo: (coordinator, network) async {
            calls.infoAsked.add(coordinator.shortAlias);
            return switch (infos[coordinator.shortAlias]) {
              final info? => Ok(info),
              null => const Err(CoordinatorUnreachable()),
            };
          },
          fetchLimits: (coordinator, network) async {
            final alias = coordinator.shortAlias;
            calls.limitsAsked.add(alias);
            final held = calls.heldLimits.remove(alias);
            if (held != null) return held.future;
            if (calls.unreadable.contains(alias)) {
              return const Err(CoordinatorUnreachable());
            }
            return Ok(limits);
          },
          make: (request, {required coordinator, required network}) =>
              throw StateError('no make here'),
          hasGarageKey: (_) async => const Ok(true),
          lottery: CoordinatorLottery(() => 0.5),
          now: () => DateTime.utc(2026, 11, 17),
          checkPrice: wallet
              ? (network, currency, price) async {
                  calls.priceAsked.add((currency, price));
                  final check = MakePriceCheck.of(
                    currency: currency,
                    coordinatorPrice: price,
                    wallet: calls.rate,
                  );
                  if (!calls.holdPrices) return check;
                  final held = Completer<MakePriceCheck>();
                  calls.heldPrices.add(held);
                  return held.future;
                }
              : null,
        );

    test(
      'the default: every coordinator\'s information read, the first of the reference\'s lottery, its limits read once',
      () async {
        final calls = _Calls();
        final cubit = cubitOf(calls);
        addTearDown(cubit.close);
        expect(cubit.state.coordinatorsLoaded, isFalse);
        await cubit.start();
        await pumpEventQueue();
        expect(calls.infoAsked.toSet(), {
          for (final coordinator in Federation.robosats.on(
            RobosatsNetwork.mainnet,
          ))
            coordinator.shortAlias,
        });
        expect(cubit.state.coordinatorsLoaded, isTrue);
        expect(cubit.state.coordinator?.shortAlias, 'temple');
        expect(cubit.state.hosts.first.coordinator.shortAlias, 'temple');
        expect(cubit.state.infos.keys, containsAll(['temple', 'lake']));
        expect(calls.limitsAsked, ['temple']);
        expect(cubit.state.limits, isA<MakerFormLimitsRead>());
        expect(
          cubit.state.sizeLimitSats,
          CoordinatorSizeLimit.of(
            coordinatorOf('temple'),
            DateTime.utc(2026, 11, 17),
          ).sats,
        );
      },
    );

    test(
      'the order of the lottery is the hosts\' order, and a coordinator that refuses first contacts is never the default',
      () async {
        final calls = _Calls()..refusing.add('temple');
        final cubit = cubitOf(calls);
        addTearDown(cubit.close);
        await cubit.start();
        await pumpEventQueue();
        expect(cubit.state.hosts.first.coordinator.shortAlias, 'temple');
        expect(cubit.state.coordinator?.shortAlias, isNot('temple'));
        expect(calls.limitsAsked, [cubit.state.coordinator?.shortAlias]);
      },
    );

    test(
      'another coordinator: its limits read, a late answer of the former dropped, its price compared again',
      () async {
        final calls = _Calls();
        final cubit = cubitOf(calls);
        addTearDown(cubit.close);
        await cubit.start();
        await pumpEventQueue();
        final late = Completer<Result<CurrencyLimits, CoordinatorFailure>>();
        calls.heldLimits['temple'] = late;
        unawaited(cubit.choose(coordinatorOf('temple')));
        await pumpEventQueue();
        expect(cubit.state.limits, isA<MakerFormLimitsLoading>());
        calls.unreadable.add('lake');
        await cubit.choose(coordinatorOf('lake'));
        expect(cubit.state.coordinator?.shortAlias, 'lake');
        expect(cubit.state.limits, isA<MakerFormLimitsUnreadable>());
        late.complete(Ok(limits));
        await pumpEventQueue();
        expect(cubit.state.coordinator?.shortAlias, 'lake');
        expect(cubit.state.limits, isA<MakerFormLimitsUnreadable>());
        expect(cubit.state.price, isA<MakeFormPriceNone>());
        calls.unreadable.clear();
        // Chosen again, even the same one, its limits are read again.
        await cubit.choose(coordinatorOf('lake'));
        expect(cubit.state.limits, isA<MakerFormLimitsRead>());
        expect(calls.limitsAsked, ['temple', 'temple', 'lake', 'lake']);
        expect(calls.priceAsked.length, 2);
      },
    );

    test(
      'the price: read once per currency shown, never for a currency without a price, a late answer for a former currency dropped',
      () async {
        final calls = _Calls();
        final cubit = cubitOf(calls);
        addTearDown(cubit.close);
        await cubit.start();
        await pumpEventQueue();
        expect(calls.priceAsked, [(eur, 91711.15)]);
        calls.holdPrices = true;
        unawaited(cubit.showCurrency(usd));
        await pumpEventQueue();
        expect(cubit.state.price, isA<MakeFormPriceReading>());
        expect(calls.priceAsked.last, (usd, 100000.0));
        // GBP: the coordinator gives no price, nothing is asked.
        await cubit.showCurrency(gbp);
        expect(calls.priceAsked, hasLength(2));
        expect(cubit.state.price, isA<MakeFormPriceNone>());
        calls.heldPrices.single.complete(
          MakePriceCheck.of(
            currency: usd,
            coordinatorPrice: 100000,
            wallet: P2pWalletRateRead(100000),
          ),
        );
        await pumpEventQueue();
        expect(cubit.state.price, isA<MakeFormPriceNone>());
        expect(cubit.state.currency, gbp);
        // The same currency again asks nothing.
        await cubit.showCurrency(gbp);
        expect(calls.priceAsked, hasLength(2));
      },
    );

    test(
      'a price that could not be read: « Retry » reads once more, never while a read runs',
      () async {
        final calls = _Calls()..rate = const P2pWalletRateUnavailable();
        final cubit = cubitOf(calls);
        addTearDown(cubit.close);
        await cubit.start();
        await pumpEventQueue();
        expect(
          (cubit.state.price as MakeFormPriceChecked).check,
          isA<MakePriceUnverified>(),
        );
        calls
          ..rate = P2pWalletRateRead(91711.15)
          ..holdPrices = true;
        unawaited(cubit.retryPrice());
        unawaited(cubit.retryPrice());
        await pumpEventQueue();
        expect(calls.priceAsked, hasLength(2));
        calls.heldPrices.single.complete(
          MakePriceCheck.of(
            currency: eur,
            coordinatorPrice: 91711.15,
            wallet: calls.rate,
          ),
        );
        await pumpEventQueue();
        expect(
          (cubit.state.price as MakeFormPriceChecked).check,
          isA<MakePriceCompared>(),
        );
        // « Retry » does nothing once compared.
        await cubit.retryPrice();
        expect(calls.priceAsked, hasLength(2));
      },
    );

    test('a currency the Bull wallet does not price: no « Retry »', () async {
      final calls = _Calls()..rate = const P2pWalletRateNotPriced();
      final cubit = cubitOf(calls);
      addTearDown(cubit.close);
      await cubit.start();
      await pumpEventQueue();
      expect(
        (cubit.state.price as MakeFormPriceChecked).check,
        isA<MakePriceNotPriced>(),
      );
      await cubit.retryPrice();
      expect(calls.priceAsked, hasLength(1));
    });

    test('without the wallet\'s port, no price is read', () async {
      final calls = _Calls();
      final cubit = cubitOf(calls, wallet: false);
      addTearDown(cubit.close);
      await cubit.start();
      await pumpEventQueue();
      expect(cubit.state.price, isA<MakeFormPriceNone>());
      expect(calls.priceAsked, isEmpty);
    });

    test('a Garage Key that cannot be read is no key', () async {
      final cubit = MakeOrderCubit(
        RobosatsNetwork.mainnet,
        currency: eur,
        listHosts: (network) => RobotHosts(network, const []),
        fetchInfo: (_, _) => throw StateError('none'),
        fetchLimits: (_, _) => throw StateError('none'),
        make: (request, {required coordinator, required network}) =>
            throw StateError('none'),
        hasGarageKey: (_) async => const Err(P2pStorageFailure()),
        lottery: CoordinatorLottery(() => 0.5),
        now: () => DateTime.utc(2026, 11, 17),
      );
      addTearDown(cubit.close);
      expect(await cubit.hasGarageKey(), isFalse);
      await cubit.start();
      expect(cubit.state.coordinatorsLoaded, isTrue);
      expect(cubit.state.coordinator, isNull);
    });
  });
}

/// What the fakes of the cubit were asked, and how they answer.
final class _Calls {
  final infoAsked = <String>[];
  final limitsAsked = <String>[];
  final Map<String, Completer<Result<CurrencyLimits, CoordinatorFailure>>>
  heldLimits = {};
  final Set<String> unreadable = {};
  final Set<String> refusing = {};
  final priceAsked = <(RobosatsCurrency, double)>[];
  final heldPrices = <Completer<MakePriceCheck>>[];
  P2pWalletBitcoinRate rate = P2pWalletRateRead(91711.15);
  bool holdPrices = false;
}
