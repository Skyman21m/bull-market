import 'package:p2p/public/p2p_wallet_port.dart';
import 'package:p2p/src/domain/coordinator_lottery.dart';
import 'package:p2p/src/domain/robot_host.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/make_price_check.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_payout.dart';
import 'package:p2p/src/domain/trade/trade_renewal.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_storable.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_limits_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/check_make_price_usecase.dart';
import 'package:p2p/src/presentation/make_order_cubit.dart';
import 'package:p2p/testing.dart'
    show
        Bolt11TestInvoice,
        FakeP2pWalletPort,
        ScriptedFault,
        ScriptedMakerRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/make_harness.dart';

/// The renewal of an order made here (#185, design note `docs/design/phase-3-making-an-order.md` § 1.8, § 2.2): « Renew Order » at 5 and « Renew » at 14 make a new order from the terms this device kept, never from what the coordinator reads back, with a fresh robot, on the same coordinator, through the make of a creation and its checks.
///
/// Over the real records, use cases and state machine, the coordinator played by `ScriptedMakerCoordinator` as the reference answers (never a real one): nothing here pays, and no real coordinator, relay, price or swap service is reached.
void main() {
  T valueOf<T, F extends Failure>(Result<T, F> result) => switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  /// How many makes reached the coordinator.
  int makes(MakeHarness harness) => harness.coordinator.received
      .where((kind) => kind == ScriptedMakerRequest.make)
      .length;

  /// The status the watch of [record] reads once, stored.
  Future<TradeSeen> read(MakeHarness harness, TradeRecord record) async {
    final run = harness.watchOf(record);
    await harness.settle();
    final seen = run.lastStatus.seen;
    await run.subscription.cancel();
    return seen;
  }

  /// An order made by [harness] (by default its test order), its bond locked, then expired untaken, as the watch reads and stores it.
  Future<TradeRecord> expiredOrder(
    MakeHarness harness, [
    MakeOrderRequest? request,
  ]) async {
    final made = valueOf(await harness.makeOrder(request)) as MakeStarted;
    final record = made.record;
    harness.coordinator.lockMakerBond(record.orderId);
    expect((await read(harness, record)).status, isA<MakerOrderPublic>());
    harness.coordinator.expire(record.orderId);
    final seen = await read(harness, record);
    expect(seen.status, isA<Expired>());
    expect(seen.stored, isTrue);
    return record;
  }

  /// The price check a user would see without the Bull wallet's port, at the coordinator's present price.
  MakePriceSeen seenNow(MakeHarness harness, MakeOrderRequest request) =>
      MakePriceSeen.of(
        currency: request.currency,
        coordinatorPrice: harness.coordinator.prices[request.currency.id] ?? 1,
      );

  group('the terms renewed are the ones kept here', () {
    test(
      'an order expired untaken: its kept request, its coordinator, its number; nothing sent, nothing written',
      () async {
        final harness = await MakeHarness.start();
        final asked = MakeHarness.request(
          description: 'Bank transfer only',
          publicDuration: const Duration(hours: 2),
          escrowDuration: const Duration(hours: 5),
          bondSize: 5.5,
          range: (50, 200),
        );
        final record = await expiredOrder(harness, asked);
        final before = harness.coordinator.requests.length;
        final trades = await harness.allTrades();
        final renewal = valueOf(await harness.make.renewal(record));
        expect(renewal.request, asked);
        expect(renewal.coordinator, harness.host);
        expect(renewal.network, harness.network);
        expect(renewal.orderId, record.orderId);
        // Read from the device only.
        expect(harness.coordinator.requests.length, before);
        expect(await harness.allTrades(), trades);
      },
    );

    test(
      'a coordinator that reads the expired order back with other terms: the renewal still carries the kept ones, and the new make sends exactly them',
      () async {
        final harness = await MakeHarness.start();
        final asked = MakeHarness.request();
        final made = valueOf(await harness.makeOrder(asked)) as MakeStarted;
        final record = made.record;
        harness.coordinator.lockMakerBond(record.orderId);
        await read(harness, record);
        harness.coordinator.expire(record.orderId);
        // What the reference's renewal would send (`TradeBox/index.tsx:162-181` takes every field from the order read): another amount, premium, bond size, public duration, escrow duration, methods and description.
        harness.coordinator.orderChanges[record.orderId] = {
          'amount': '900.00000000',
          'premium': '-20.00',
          'bond_size': '15.00',
          'public_duration': 600,
          'escrow_duration': 36000,
          'payment_method': 'Cash F2F',
          'description': 'Pay me elsewhere',
        };
        final seen = await read(harness, record);
        // The state machine says the terms changed, and keeps the expiry.
        expect(seen.status, isA<Expired>());
        expect(seen.status.has<TradeTermsChanged>(), isTrue);
        expect(
          (await harness.trailOf(record))?.position,
          TradePosition.expired.name,
        );
        final renewal = valueOf(await harness.make.renewal(record));
        expect(renewal.request, asked);
        final renewed = valueOf(
          await harness.make.execute(
            renewal.request,
            coordinator: renewal.coordinator,
            network: renewal.network,
            seen: seenNow(harness, renewal.request),
          ),
        );
        final next = (renewed as MakeStarted).record;
        // The new make's body is the first make's, field for field: none of the terms read back.
        expect(
          harness.coordinator.order(next.orderId).body,
          harness.coordinator.order(record.orderId).body,
        );
        final body = harness.coordinator.order(next.orderId).body;
        expect((body['amount'] as num?)?.toDouble(), 100);
        expect(body['payment_method'], 'Revolut Instant SEPA');
        expect(body['description'], isNull);
      },
    );

    test(
      'records that do not read back as written: refused, nothing sent',
      () async {
        final harness = await MakeHarness.start();
        final record = await expiredOrder(harness);
        final before = harness.coordinator.requests.length;
        harness.trails.readBack = (_) => null;
        expect(
          await harness.make.renewal(record),
          const Err<OrderRenewal, RenewalRefusal>(RenewalTermsUnreadable()),
        );
        // Terms of another coordinator than the trade's: not this order's.
        harness.trails.readBack = (stored) => stored == null
            ? null
            : MakerTermsRecord(
                version: stored.version,
                network: stored.network,
                coordinatorAlias: 'moon',
                role: stored.role,
                type: stored.type,
                currencyId: stored.currencyId,
                amount: stored.amount,
                minAmount: stored.minAmount,
                maxAmount: stored.maxAmount,
                premiumPercent: stored.premiumPercent,
                paymentMethod: stored.paymentMethod,
                bondSizePercent: stored.bondSizePercent,
                publicSeconds: stored.publicSeconds,
                escrowSeconds: stored.escrowSeconds,
                description: stored.description,
                hasPassword: stored.hasPassword,
                latitude: stored.latitude,
                longitude: stored.longitude,
                createdPrice: stored.createdPrice,
                makerFee: stored.makerFee,
              );
        expect(
          await harness.make.renewal(record),
          const Err<OrderRenewal, RenewalRefusal>(RenewalTermsUnreadable()),
        );
        expect(harness.coordinator.requests.length, before);
      },
    );
  });

  group('only an order made here, at an end where the reference offers it', () {
    test(
      'at 0 and at 1 (public), not offered: the trail is not at an end',
      () async {
        final harness = await MakeHarness.start();
        final made = valueOf(await harness.makeOrder()) as MakeStarted;
        final record = made.record;
        expect(
          await harness.make.renewal(record),
          const Err<OrderRenewal, RenewalRefusal>(RenewalNotEnded()),
        );
        harness.coordinator.lockMakerBond(record.orderId);
        await read(harness, record);
        expect(
          await harness.make.renewal(record),
          const Err<OrderRenewal, RenewalRefusal>(RenewalNotEnded()),
        );
      },
    );

    test('a trade not made here: refused', () async {
      final harness = await MakeHarness.start();
      final record = await expiredOrder(harness);
      for (final origin in [TradeOrigin.takenHere, TradeOrigin.recovered]) {
        final other = TradeRecord(
          robot: record.robot,
          coordinatorAlias: record.coordinatorAlias,
          coordinatorOnion: record.coordinatorOnion,
          orderId: record.orderId,
          role: record.role,
          origin: origin,
          takenAt: record.takenAt,
          confirmedAt: record.confirmedAt,
          closedAt: record.closedAt,
        );
        expect(
          await harness.make.renewal(other),
          const Err<OrderRenewal, RenewalRefusal>(RenewalNotMadeHere()),
        );
      }
    });

    test(
      'a coordinator at another address than the order was made on: refused',
      () async {
        final harness = await MakeHarness.start();
        final record = await expiredOrder(harness);
        final moved = TradeRecord(
          robot: record.robot,
          coordinatorAlias: record.coordinatorAlias,
          coordinatorOnion:
              'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcd.onion',
          orderId: record.orderId,
          role: record.role,
          origin: record.origin,
          takenAt: record.takenAt,
          confirmedAt: record.confirmedAt,
          closedAt: record.closedAt,
        );
        expect(
          await harness.make.renewal(moved),
          const Err<OrderRenewal, RenewalRefusal>(RenewalCoordinatorGone()),
        );
      },
    );

    test(
      'the positions of the reference: 5 and 14 for both sides, 13 and 15 for a seller only, nowhere else (`TradeBox/index.tsx:602-690`, `Prompts/Expired.tsx:40`, `Prompts/Successful.tsx:276`)',
      () {
        for (final position in TradePosition.values) {
          for (final role in TradeRole.values) {
            final expected = switch (position) {
              TradePosition.expired || TradePosition.succeeded => true,
              TradePosition.sendingSats ||
              TradePosition.routingFailed => role == TradeRole.seller,
              _ => false,
            };
            expect(
              OrderRenewal.offeredAt(position, role: role),
              expected,
              reason: '${position.name} ${role.name}',
            );
          }
        }
      },
    );
  });

  group('the renewal is a new order', () {
    test(
      'a fresh robot, the same coordinator, a new number and record; the order renewed left as it was, its kept terms unchanged; one make sent',
      () async {
        final harness = await MakeHarness.start();
        final record = await expiredOrder(harness);
        final keptBefore = valueOf(
          await harness.trails.makerTermsOf(record.robot),
        );
        final trailBefore = await harness.trailOf(record);
        final makesBefore = makes(harness);
        final renewal = valueOf(await harness.make.renewal(record));
        final renewed = valueOf(
          await harness.make.execute(
            renewal.request,
            coordinator: renewal.coordinator,
            network: renewal.network,
            seen: seenNow(harness, renewal.request),
          ),
        );
        expect(makes(harness), makesBefore + 1);
        final next = (renewed as MakeStarted).record;
        expect(renewed.status, isA<WaitingForMakerBond>());
        expect(next.origin, TradeOrigin.madeHere);
        expect(next.orderId, isNot(record.orderId));
        expect(next.robot, isNot(record.robot));
        expect(next.robot.accountIndex, greaterThan(record.robot.accountIndex));
        expect(next.coordinatorAlias, record.coordinatorAlias);
        expect(next.coordinatorOnion, record.coordinatorOnion);
        // Another robot made it, on the same coordinator.
        expect(
          harness.coordinator.order(next.orderId).maker.sessionKey,
          isNot(harness.coordinator.order(record.orderId).maker.sessionKey),
        );
        // Its own terms, the same request.
        final keptNext = valueOf(await harness.trails.makerTermsOf(next.robot));
        expect(keptNext?.paymentMethod, keptBefore?.paymentMethod);
        expect(keptNext?.amount, keptBefore?.amount);
        // The order renewed: its terms and its trail as they were, its record closed.
        expect(
          valueOf(await harness.trails.makerTermsOf(record.robot)),
          keptBefore,
        );
        expect(await harness.trailOf(record), trailBefore);
        final rows = await harness.allTrades();
        final old = rows.singleWhere(
          (row) => row['order_id'] == record.orderId,
        );
        expect(old['closed_at'], isNotNull);
        // The new order active, the old one not.
        expect(
          [for (final active in await harness.activeRecords()) active.orderId],
          [next.orderId],
        );
      },
    );

    test(
      'after a successful trade (14): renewed too, where the reference in Garage Key mode refuses (`TradeBox/index.tsx:150-157`), since the robot changes anyway',
      () async {
        final harness = await MakeHarness.start();
        final made = valueOf(await harness.makeOrder()) as MakeStarted;
        final record = made.record;
        harness.coordinator.lockMakerBond(record.orderId);
        await read(harness, record);
        harness.coordinator.take(record.orderId, harness.robot(4));
        var seen = await read(harness, record);
        expect(seen.status, isA<WaitingForBoth>());
        // The payout invoice given from another wallet, the escrow locked, « fiat sent », the seller's confirmation, the payment.
        final ask = valueOf(harness.payout.ask(record, seen));
        final budget = RoutingBudgetPpm.referenceDefault;
        final amount = ask.invoiceSatsFor(budget) ?? (throw StateError('none'));
        final invoice = Bolt11TestInvoice(
          network: Bolt11Network.testnet,
          sats: amount.value.toInt(),
          seed: 77,
          createdAt: harness.now,
          expiry: const Duration(hours: 24),
          description: 'payout',
        );
        harness.coordinator.decoder.add(invoice);
        final checked = valueOf(
          harness.payout.check(
            record,
            seen,
            PayoutInvoiceText(invoice.text, budget: budget),
          ),
        );
        valueOf(await harness.payout.execute(record, checked));
        await read(harness, record);
        harness.coordinator.lockEscrow(record.orderId);
        seen = await read(harness, record);
        expect(seen.status, isA<Chatting>());
        valueOf(await harness.chat.confirmFiatSent(record, seen));
        await read(harness, record);
        harness.coordinator.sellerConfirms(record.orderId);
        seen = await read(harness, record);
        expect(seen.status, isA<SendingSats>());
        // At 13 a maker buyer is shown the payment's progress, no « Renew » (`TradeBox/index.tsx:603-608`).
        expect(
          await harness.make.renewal(record),
          const Err<OrderRenewal, RenewalRefusal>(RenewalNotEnded()),
        );
        harness.coordinator.buyerPaid(record.orderId);
        seen = await read(harness, record);
        expect(seen.status, isA<Succeeded>());
        final renewal = valueOf(await harness.make.renewal(record));
        expect(renewal.request, MakeHarness.request());
        final renewed = valueOf(
          await harness.make.execute(
            renewal.request,
            coordinator: renewal.coordinator,
            network: renewal.network,
            seen: seenNow(harness, renewal.request),
          ),
        );
        expect(renewed, isA<MakeStarted>());
        expect((renewed as MakeStarted).record.robot, isNot(record.robot));
      },
    );

    test(
      'a renewal whose answer is lost stays pending, as a creation: never sent again by itself, resolved by its robot',
      () async {
        final harness = await MakeHarness.start();
        final record = await expiredOrder(harness);
        final renewal = valueOf(await harness.make.renewal(record));
        final before = makes(harness);
        harness.coordinator.failNext(
          ScriptedMakerRequest.make,
          ScriptedFault.answerLost,
        );
        final outcome = valueOf(
          await harness.make.execute(
            renewal.request,
            coordinator: renewal.coordinator,
            network: renewal.network,
            seen: seenNow(harness, renewal.request),
          ),
        );
        expect(outcome, isA<MakePending>());
        expect(makes(harness), before + 1);
        final pending = (await harness.pendingMakes()).single;
        final resolved = await harness.make.resolve(pending);
        expect(resolved, isA<MakeStarted>());
        expect(makes(harness), before + 1);
        // The order renewed is still renewable from its own records, and nothing was made twice.
        expect(harness.coordinator.orders, hasLength(2));
      },
    );
  });

  group('the price, through the form\'s cubit over the real use cases', () {
    final eur = RobosatsCurrency.fromId(2) ?? (throw StateError('EUR'));

    MakeOrderCubit renewalForm(
      MakeHarness harness,
      TradeRecord record,
      FakeP2pWalletPort wallet,
    ) {
      final client = CoordinatorClient(harness.coordinator);
      final form = MakeOrderCubit.renewal(
        record,
        placeholder: RobosatsCurrency.fromCode('USD') ?? eur,
        readRenewal: harness.make.renewal,
        listHosts: (network) => RobotHosts(network, [
          for (final coordinator in Federation.robosats.on(network))
            RobotHost(coordinator, refusesFirstContacts: false),
        ]),
        fetchInfo: FetchCoordinatorInfoUsecase(client).execute,
        fetchLimits: FetchCoordinatorLimitsUsecase(client).execute,
        make: harness.make.execute,
        hasGarageKey: (_) async => const Ok(true),
        lottery: CoordinatorLottery(() => 0.5),
        now: () => harness.now,
        checkPrice: CheckMakePriceUsecase(wallet).execute,
      );
      addTearDown(form.close);
      return form;
    }

    test(
      'the coordinator\'s price 20 % higher than at the creation, the Bull wallet\'s too: the comparison within, the new order kept at the new price, its bond estimated at it',
      () async {
        final harness = await MakeHarness.start();
        final record = await expiredOrder(harness);
        final created = valueOf(
          await harness.trails.makerTermsOf(record.robot),
        )?.createdPrice;
        expect(created, 91711.15);
        harness.coordinator.prices[2] = 110053.38;
        final wallet = FakeP2pWalletPort(Ok(Sats.fromInt(0)))
          ..rate = P2pWalletRateRead(110000);
        final form = renewalForm(harness, record, wallet);
        await form.start();
        expect(form.state.renewal, isA<MakeRenewalReady>());
        expect(form.state.currency, eur);
        expect(form.state.coordinator, harness.host);
        // Only the order's coordinator's limits read, the Bull wallet's price read for its currency, as at a creation.
        expect(wallet.ratesAsked, [(harness.network, eur)]);
        final check = (form.state.price as MakeFormPriceChecked).check;
        expect((check as MakePriceCompared).side, MakePriceSide.within);
        final seen = form.seen() ?? (throw StateError('no price'));
        final renewal = (form.state.renewal as MakeRenewalReady).renewal;
        await form.make(renewal.request, coordinator: harness.host, seen: seen);
        final next = switch (form.state.progress) {
          MakeMade(:final record) => record,
          final other => throw StateError('$other'),
        };
        expect(
          valueOf(await harness.trails.makerTermsOf(next.robot))?.createdPrice,
          110053.38,
        );
      },
    );

    test(
      'the coordinator\'s price 20 % above the Bull wallet\'s: the red comparison shown, never blocking; the order made as shown',
      () async {
        final harness = await MakeHarness.start();
        final record = await expiredOrder(harness);
        harness.coordinator.prices[2] = 110053.38;
        final wallet = FakeP2pWalletPort(Ok(Sats.fromInt(0)))
          ..rate = P2pWalletRateRead(91711.15);
        final form = renewalForm(harness, record, wallet);
        await form.start();
        final check = (form.state.price as MakeFormPriceChecked).check;
        expect((check as MakePriceCompared).side, MakePriceSide.above);
        expect(check.warns, isTrue);
        final renewal = (form.state.renewal as MakeRenewalReady).renewal;
        await form.make(
          renewal.request,
          coordinator: harness.host,
          seen: form.seen() ?? (throw StateError('no price')),
        );
        expect(form.state.progress, isA<MakeMade>());
      },
    );

    test(
      'the coordinator\'s price moved more than 10 % between what the page shows and the press: refused before any robot (`MakePriceCheckChanged`), the new line shown; a second press makes it',
      () async {
        final harness = await MakeHarness.start();
        final record = await expiredOrder(harness);
        final wallet = FakeP2pWalletPort(Ok(Sats.fromInt(0)))
          ..rate = P2pWalletRateRead(91711.15);
        final form = renewalForm(harness, record, wallet);
        await form.start();
        final shown = form.seen() ?? (throw StateError('no price'));
        expect(shown.verdict, MakePriceVerdict.within);
        harness.coordinator.prices[2] = 110053.38;
        final robotsBefore = harness.coordinator.received
            .where((kind) => kind == ScriptedMakerRequest.robot)
            .length;
        final makesBefore = makes(harness);
        final renewal = (form.state.renewal as MakeRenewalReady).renewal;
        await form.make(
          renewal.request,
          coordinator: harness.host,
          seen: shown,
        );
        expect(
          form.state.progress,
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
        expect(makes(harness), makesBefore);
        expect(
          harness.coordinator.received
              .where((kind) => kind == ScriptedMakerRequest.robot)
              .length,
          robotsBefore,
        );
        final now = form.seen() ?? (throw StateError('no price'));
        expect(now.verdict, MakePriceVerdict.above);
        await form.make(renewal.request, coordinator: harness.host, seen: now);
        expect(form.state.progress, isA<MakeMade>());
        expect(makes(harness), makesBefore + 1);
      },
    );

    test(
      'the cubit sends nothing but the kept request to the order\'s coordinator: another request or coordinator is ignored, another currency and another host are not chosen',
      () async {
        final harness = await MakeHarness.start();
        final record = await expiredOrder(harness);
        final wallet = FakeP2pWalletPort(Ok(Sats.fromInt(0)))
          ..rate = P2pWalletRateRead(91711.15);
        final form = renewalForm(harness, record, wallet);
        await form.start();
        final renewal = (form.state.renewal as MakeRenewalReady).renewal;
        final seen = form.seen() ?? (throw StateError('no price'));
        final before = makes(harness);
        await form.make(
          MakeHarness.request(amount: 150),
          coordinator: harness.host,
          seen: seen,
        );
        expect(form.state.progress, isA<MakeIdle>());
        expect(makes(harness), before);
        final other = Federation.robosats
            .on(harness.network)
            .firstWhere((c) => c != harness.host);
        await form.choose(other);
        expect(form.state.coordinator, harness.host);
        await form.showCurrency(RobosatsCurrency.fromCode('USD') ?? eur);
        expect(form.state.currency, eur);
        await form.make(renewal.request, coordinator: other, seen: seen);
        expect(makes(harness), before);
        await form.make(renewal.request, coordinator: harness.host, seen: seen);
        expect(makes(harness), before + 1);
        // Never a second make after an order made.
        await form.make(renewal.request, coordinator: harness.host, seen: seen);
        expect(makes(harness), before + 1);
      },
    );

    test(
      'records that cannot be read: the form says why, reads no coordinator and sends nothing',
      () async {
        final harness = await MakeHarness.start();
        final record = await expiredOrder(harness);
        harness.trails.readBack = (_) => null;
        final before = harness.coordinator.requests.length;
        final wallet = FakeP2pWalletPort(Ok(Sats.fromInt(0)));
        final form = renewalForm(harness, record, wallet);
        await form.start();
        expect(
          form.state.renewal,
          isA<MakeRenewalRefused>().having(
            (refused) => refused.refusal,
            'refusal',
            isA<RenewalTermsUnreadable>(),
          ),
        );
        expect(harness.coordinator.requests.length, before);
        expect(wallet.ratesAsked, isEmpty);
      },
    );
  });
}
