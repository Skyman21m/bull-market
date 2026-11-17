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
/// [cubit]'s make of [request], with the coordinator and the price check the form shows, as the screen's press passes them.
Future<void> _makeVia(MakeOrderCubit cubit, MakeOrderRequest request) =>
    cubit.make(
      request,
      coordinator:
          cubit.state.coordinator ?? (throw StateError('no coordinator')),
      seen:
          cubit.seen() ??
          MakePriceSeen.of(currency: request.currency, coordinatorPrice: 1),
    );

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
        await Future.wait([_makeVia(cubit, request), _makeVia(cubit, request)]);
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
        await _makeVia(cubit, request);
        await cubit.choose(coordinatorOf('lake'));
        expect(makes(harness), 1);
        expect(cubit.state.coordinator, harness.host);
      },
    );

    test(
      'a press for a coordinator the form no longer shows: nothing sent, nothing said (second security review of #181, R11)',
      () async {
        final harness = await MakeHarness.start();
        final cubit = cubitOver(harness);
        addTearDown(cubit.close);
        await cubit.start();
        await harness.settle();
        final request = requestOf(cubit.state);
        await cubit.make(
          request,
          coordinator: coordinatorOf('lake'),
          seen:
              cubit.seen() ??
              MakePriceSeen.of(currency: eur, coordinatorPrice: 91711.15),
        );
        await harness.settle();
        expect(makes(harness), 0);
        expect(
          harness.coordinator.received,
          isNot(contains(ScriptedMakerRequest.make)),
        );
        expect(await harness.allTrades(), isEmpty);
        expect(
          cubit.state.progress,
          isA<MakeIdle>().having((idle) => idle.problem, 'problem', isNull),
        );
        await _makeVia(cubit, request);
        await harness.settle();
        expect(cubit.state.progress, isA<MakeMade>());
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
        await _makeVia(cubit, MakeHarness.request(currency: usd));
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
        await _makeVia(cubit, requestOf(cubit.state));
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
        await _makeVia(cubit, requestOf(cubit.state));
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
        await _makeVia(cubit, request);
        await harness.settle();
        expect(cubit.state.progress, isA<MakeUncertain>());
        expect(cubit.state.locked, isTrue);
        expect(await harness.pendingMakes(), hasLength(1));
        await _makeVia(cubit, request);
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
        // Nothing read until an amount is typed.
        expect(asked, isEmpty);
        await cubit.wantPrice(true);
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
    group(
      'the price seen at the press, checked again by the make (security review of #181, C1)',
      () {
        /// The cubit over [harness], the Bull wallet's price being [wallet], an amount typed.
        Future<MakeOrderCubit> shown(
          MakeHarness harness,
          P2pWalletBitcoinRate wallet,
        ) async {
          final cubit = cubitOver(
            harness,
            checkPrice: (network, currency, price) async => MakePriceCheck.of(
              currency: currency,
              coordinatorPrice: price,
              wallet: wallet,
            ),
          );
          addTearDown(cubit.close);
          await cubit.start();
          await harness.settle();
          await cubit.wantPrice(true);
          await harness.settle();
          return cubit;
        }

        test(
          'the reviewer\'s scenario: a fair price shown, ten times too low at the make: refused before any robot, the red check shown, then a second press makes the order',
          () async {
            final harness = await MakeHarness.start();
            final cubit = await shown(harness, P2pWalletRateRead(91711.15));
            expect(cubit.seen()?.verdict, MakePriceVerdict.within);
            final request = requestOf(cubit.state);
            harness.coordinator.prices[2] = 9171.115;
            await _makeVia(cubit, request);
            await harness.settle();
            expect(
              cubit.state.progress,
              isA<MakeIdle>().having(
                (idle) => idle.problem,
                'problem',
                isA<MakeWasRefused>().having(
                  (refused) => refused.refusal,
                  'refusal',
                  isA<MakePriceCheckChanged>(),
                ),
              ),
            );
            expect(makes(harness), 0);
            expect(await harness.allTrades(), isEmpty);
            expect(await harness.pendingMakes(), isEmpty);
            expect(cubit.seen()?.verdict, MakePriceVerdict.below);
            // Pressed again, the red seen: made, at the price shown.
            await _makeVia(cubit, requestOf(cubit.state));
            await harness.settle();
            expect(cubit.state.progress, isA<MakeMade>());
            expect(makes(harness), 1);
          },
        );

        test('a price that moves within the threshold: made', () async {
          final harness = await MakeHarness.start();
          final cubit = await shown(harness, P2pWalletRateRead(91711.15));
          final request = requestOf(cubit.state);
          harness.coordinator.prices[2] = 93000;
          await _makeVia(cubit, request);
          await harness.settle();
          expect(cubit.state.progress, isA<MakeMade>());
        });

        test('a red check seen and still red: made', () async {
          final harness = await MakeHarness.start();
          final cubit = await shown(harness, P2pWalletRateRead(110000));
          expect(cubit.seen()?.verdict, MakePriceVerdict.below);
          final request = requestOf(cubit.state);
          harness.coordinator.prices[2] = 91000;
          await _makeVia(cubit, request);
          await harness.settle();
          expect(cubit.state.progress, isA<MakeMade>());
        });

        for (final (side, verdict, seenAt, worse) in [
          ('below', MakePriceVerdict.below, 0.88, 0.10),
          ('above', MakePriceVerdict.above, 1.12, 1.90),
        ]) {
          test(
            'a red check seen $side (12 %): refused before any robot at a price far beyond it, made a little further (second security review of #181, C3)',
            () async {
              final wallet = 91711.15 / seenAt;
              final harness = await MakeHarness.start();
              final cubit = await shown(harness, P2pWalletRateRead(wallet));
              expect(cubit.seen()?.verdict, verdict);
              harness.coordinator.prices[2] = wallet * worse;
              await _makeVia(cubit, requestOf(cubit.state));
              await harness.settle();
              expect(
                cubit.state.progress,
                isA<MakeIdle>().having(
                  (idle) => idle.problem,
                  'problem',
                  isA<MakeWasRefused>().having(
                    (refused) => refused.refusal,
                    'refusal',
                    isA<MakePriceCheckChanged>(),
                  ),
                ),
              );
              expect(makes(harness), 0);
              expect(await harness.allTrades(), isEmpty);
              expect(await harness.pendingMakes(), isEmpty);
              expect(cubit.seen()?.verdict, verdict);
              expect(cubit.seen()?.coordinatorPrice, wallet * worse);
              // Shown at 12 %, read again at 13 %: the same line, made.
              final again = await MakeHarness.start();
              final other = await shown(again, P2pWalletRateRead(wallet));
              again.coordinator.prices[2] = wallet * (seenAt < 1 ? 0.87 : 1.13);
              await _makeVia(other, requestOf(other.state));
              await again.settle();
              expect(other.state.progress, isA<MakeMade>());
              expect(makes(again), 1);
            },
          );
        }

        for (final (name, wallet, verdict) in [
          (
            'a currency the Bull wallet does not price',
            const P2pWalletRateNotPriced(),
            MakePriceVerdict.notPriced,
          ),
          (
            'a Bull wallet\'s price that could not be read',
            const P2pWalletRateUnavailable(),
            MakePriceVerdict.unverified,
          ),
        ]) {
          test(
            '$name: made within 10 % of the price shown, refused beyond',
            () async {
              final harness = await MakeHarness.start();
              final cubit = await shown(harness, wallet);
              expect(cubit.seen()?.verdict, verdict);
              harness.coordinator.prices[2] = 91711.15 * 0.85;
              await _makeVia(cubit, requestOf(cubit.state));
              await harness.settle();
              expect(makes(harness), 0);
              expect(await harness.allTrades(), isEmpty);
              expect(
                (cubit.state.limits as MakerFormLimitsRead).limits[eur]?.price,
                91711.15 * 0.85,
              );
              harness.coordinator.prices[2] = 91711.15 * 0.85 * 1.05;
              await _makeVia(cubit, requestOf(cubit.state));
              await harness.settle();
              expect(cubit.state.progress, isA<MakeMade>());
            },
          );
        }
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
          make:
              (
                request, {
                required coordinator,
                required network,
                required seen,
              }) => throw StateError('no make here'),
          hasGarageKey: (_) async => const Ok(true),
          lottery: CoordinatorLottery(() => 0.5),
          now: () => calls.now,
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
        await cubit.wantPrice(true);
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
        // Compared again from the Bull wallet's price read less than 3 minutes ago: no other request (security review of #181).
        expect(calls.priceAsked.length, 1);
        expect(cubit.state.price, isA<MakeFormPriceChecked>());
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
        expect(calls.priceAsked, isEmpty);
        await cubit.wantPrice(true);
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
        await cubit.wantPrice(true);
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
      await cubit.wantPrice(true);
      await pumpEventQueue();
      expect(
        (cubit.state.price as MakeFormPriceChecked).check,
        isA<MakePriceNotPriced>(),
      );
      await cubit.retryPrice();
      expect(calls.priceAsked, hasLength(1));
    });

    test(
      'the Bull wallet\'s price outside Tor: only once an amount is typed, never for « Clear form », not again within 3 minutes for the currency whatever the host, again after',
      () async {
        final calls = _Calls();
        final cubit = cubitOf(calls);
        addTearDown(cubit.close);
        await cubit.start();
        await pumpEventQueue();
        expect(calls.priceAsked, isEmpty);
        expect(cubit.state.price, isA<MakeFormPriceNone>());
        await cubit.wantPrice(true);
        expect(calls.priceAsked, hasLength(1));
        // The amount taken away, then typed again: nothing read anew.
        await cubit.wantPrice(false);
        await cubit.wantPrice(true);
        expect(calls.priceAsked, hasLength(1));
        // « Clear form »: the amount emptied, USD shown, nothing asked.
        await cubit.wantPrice(false);
        await cubit.showCurrency(usd);
        expect(calls.priceAsked, hasLength(1));
        expect(cubit.state.price, isA<MakeFormPriceNone>());
        await cubit.showCurrency(eur);
        await cubit.wantPrice(true);
        expect(calls.priceAsked, hasLength(1));
        // Another host, or the same, within 3 minutes: compared from the price already read.
        await cubit.choose(coordinatorOf('lake'));
        await cubit.choose(coordinatorOf('lake'));
        expect(calls.priceAsked, hasLength(1));
        expect(cubit.state.price, isA<MakeFormPriceChecked>());
        // After 3 minutes, the next host's limits bring a new read.
        calls.now = calls.now.add(const Duration(minutes: 4));
        await cubit.choose(coordinatorOf('temple'));
        expect(calls.priceAsked, hasLength(2));
      },
    );

    test(
      'the last read kept for each currency: USD, EUR, then USD again within 3 minutes reads nothing anew, a read 3 minutes old is read again (second security review of #181, R10)',
      () async {
        final calls = _Calls();
        final cubit = cubitOf(calls);
        addTearDown(cubit.close);
        await cubit.start();
        await cubit.showCurrency(usd);
        await cubit.wantPrice(true);
        expect(calls.priceAsked, [(usd, 100000.0)]);
        calls.now = calls.now.add(const Duration(minutes: 1));
        await cubit.showCurrency(eur);
        expect(calls.priceAsked, hasLength(2));
        calls.now = calls.now.add(const Duration(minutes: 1));
        await cubit.showCurrency(usd);
        expect(calls.priceAsked, hasLength(2));
        expect(cubit.state.price, isA<MakeFormPriceChecked>());
        await cubit.showCurrency(eur);
        expect(calls.priceAsked, hasLength(2));
        // USD read 3 minutes ago, EUR 2: USD is read again, EUR not yet.
        calls.now = calls.now.add(const Duration(minutes: 1));
        await cubit.showCurrency(usd);
        expect(calls.priceAsked, hasLength(3));
        expect(calls.priceAsked.last, (usd, 100000.0));
        await cubit.showCurrency(eur);
        expect(calls.priceAsked, hasLength(3));
        calls.now = calls.now.add(const Duration(minutes: 1));
        await cubit.showCurrency(usd);
        await cubit.showCurrency(eur);
        expect(calls.priceAsked, hasLength(4));
        expect(calls.priceAsked.last, (eur, 91711.15));
      },
    );

    test(
      'the end of a running read of the Bull wallet\'s price awaited, at once when none runs (second security review of #181, R8)',
      () async {
        final calls = _Calls()..holdPrices = true;
        final cubit = cubitOf(calls);
        addTearDown(cubit.close);
        await cubit.start();
        await cubit.priceSettled();
        unawaited(cubit.wantPrice(true));
        await pumpEventQueue();
        expect(cubit.state.price, isA<MakeFormPriceReading>());
        expect(cubit.seen()?.verdict, MakePriceVerdict.notRead);
        var settled = false;
        unawaited(cubit.priceSettled().then((_) => settled = true));
        await pumpEventQueue();
        expect(settled, isFalse);
        calls.heldPrices.single.complete(
          MakePriceCheck.of(
            currency: eur,
            coordinatorPrice: 91711.15,
            wallet: P2pWalletRateRead(110000),
          ),
        );
        await pumpEventQueue();
        expect(settled, isTrue);
        expect(cubit.seen()?.verdict, MakePriceVerdict.below);
      },
    );

    test(
      'refreshed at the press only when the limits are more than 3 minutes old',
      () async {
        final calls = _Calls();
        final cubit = cubitOf(calls);
        addTearDown(cubit.close);
        await cubit.start();
        await cubit.wantPrice(true);
        calls.now = calls.now.add(const Duration(minutes: 2));
        expect(await cubit.refreshIfStale(), isFalse);
        expect(calls.limitsAsked, hasLength(1));
        calls.now = calls.now.add(const Duration(minutes: 2));
        expect(await cubit.refreshIfStale(), isTrue);
        expect(calls.limitsAsked, hasLength(2));
        expect(calls.priceAsked, hasLength(2));
      },
    );

    test(
      'what the form shows at the press: the verdict of its line, and its change when the price service goes silent (security review of #181, C2)',
      () async {
        final calls = _Calls();
        final cubit = cubitOf(calls);
        addTearDown(cubit.close);
        await cubit.start();
        expect(cubit.seen()?.verdict, MakePriceVerdict.notRead);
        await cubit.wantPrice(true);
        final before = cubit.seen();
        expect(before?.verdict, MakePriceVerdict.within);
        calls
          ..now = calls.now.add(const Duration(minutes: 4))
          ..rate = const P2pWalletRateUnavailable();
        expect(await cubit.refreshIfStale(), isTrue);
        final after = cubit.seen();
        expect(after?.verdict, MakePriceVerdict.unverified);
        expect(
          before != null && after != null && after.sameLineAs(before),
          isFalse,
        );
      },
    );

    test(
      'a make refused because the price changed: the new limits and the check at their price shown, nothing read anew, the form free',
      () async {
        final calls = _Calls();
        final lower = await limitsAt({2: 9171.115});
        MakePriceSeen? sent;
        final cubit = MakeOrderCubit(
          RobosatsNetwork.mainnet,
          currency: eur,
          listHosts: (network) => RobotHosts(network, [
            RobotHost(coordinatorOf('temple'), refusesFirstContacts: false),
          ]),
          fetchInfo: (_, _) async => const Err(CoordinatorUnreachable()),
          fetchLimits: (_, _) async => Ok(limits),
          make:
              (
                request, {
                required coordinator,
                required network,
                required seen,
              }) async {
                sent = seen;
                return Err(
                  MakePriceCheckChanged(
                    lower,
                    MakePriceSeen.of(
                      currency: eur,
                      coordinatorPrice: 9171.115,
                      check: seen.checkAt(9171.115),
                    ),
                  ),
                );
              },
          hasGarageKey: (_) async => const Ok(true),
          lottery: CoordinatorLottery(() => 0.5),
          now: () => calls.now,
          checkPrice: (network, currency, price) async {
            calls.priceAsked.add((currency, price));
            return MakePriceCheck.of(
              currency: currency,
              coordinatorPrice: price,
              wallet: P2pWalletRateRead(91711.15),
            );
          },
        );
        addTearDown(cubit.close);
        await cubit.start();
        await cubit.wantPrice(true);
        final request = MakerFormCheck.of(
          MakerFormInput(
            type: OrderType.buy,
            currency: eur,
            amount: '100',
            paymentMethods: const ['Revolut'],
            premium: '',
          ),
          coordinatorsLoaded: true,
          market: cubit.state.limits,
          sizeLimitSats: cubit.state.sizeLimitSats,
        ).request;
        await _makeVia(cubit, request ?? (throw StateError('no request')));
        expect(sent?.verdict, MakePriceVerdict.within);
        expect(
          cubit.state.progress,
          isA<MakeIdle>().having(
            (idle) => idle.problem,
            'problem',
            isA<MakeWasRefused>(),
          ),
        );
        expect(
          (cubit.state.limits as MakerFormLimitsRead).limits[eur]?.price,
          9171.115,
        );
        final shown = (cubit.state.price as MakeFormPriceChecked).check;
        expect(shown, isA<MakePriceCompared>());
        expect((shown as MakePriceCompared).side, MakePriceSide.below);
        expect(calls.priceAsked, hasLength(1));
        expect(cubit.seen()?.verdict, MakePriceVerdict.below);
      },
    );

    test('without the wallet\'s port, no price is read', () async {
      final calls = _Calls();
      final cubit = cubitOf(calls, wallet: false);
      addTearDown(cubit.close);
      await cubit.start();
      await cubit.wantPrice(true);
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
        make:
            (
              request, {
              required coordinator,
              required network,
              required seen,
            }) => throw StateError('none'),
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

  /// The cubit's clock.
  DateTime now = DateTime.utc(2026, 11, 17);
}
