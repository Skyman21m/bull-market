import 'dart:async';

import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/trade/make_price_check.dart';
import 'package:p2p/src/domain/trade/taken_price_check.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart' show TradeRole;
import 'package:p2p/src/presentation/take_order_cubit.dart';
import 'package:test/test.dart';

import 'support/fakes.dart' show bookOrder, parseOrders;
import 'support/prepared_takes.dart';
import 'support/trade_screens.dart';

/// The comparison of the read shown with the Bull wallet's price in `TakeOrderCubit` (#249, slice 4; design note `docs/design/phase-3-taken-order-price-check.md` § 8, point 4): read once the read is shown and never before, at most once per 3 minutes per currency, again at « Retry », awaited by « Continue », never checked again at the confirmation.
///
/// The read of the tests is the book's order 42 on temple, 100 EUR for 106,900 sats at +2 %: the coordinator's price without the premium is 1e10 / 106,900 / 1.02 = 91,711.15… EUR/BTC.
void main() {
  late PreparedTake read;
  late PreparedTake readUsd;
  late PreparedTake readFree;
  late PublicOrder order;

  setUpAll(() async {
    read = await preparedTake();
    readUsd = await preparedTake(changes: {'currency': 1});
    readFree = await preparedTake(changes: {'premium': '-100.00'});
    order = (await parseOrders([bookOrder(id: 42, type: 1)])).single;
  });

  test('the price of the read of the tests', () {
    expect(
      TakenPriceCheck.coordinatorPrice(read.terms),
      closeTo(1e10 / 106900 / 1.02, 1e-6),
    );
  });

  group('TakeOrderCubit and the Bull wallet\'s price', () {
    late _Prices prices;
    late _Take take;
    late DateTime clock;
    late TakeOrderCubit cubit;

    TakeOrderCubit build({bool wallet = true}) {
      final built = TakeOrderCubit(
        order,
        RobosatsNetwork.mainnet,
        take.calls,
        (_) async => const Ok(true),
        checkPrice: wallet ? prices.check : null,
        now: () => clock,
      );
      addTearDown(built.close);
      return built;
    }

    setUp(() {
      prices = _Prices();
      take = _Take([Ok(read)]);
      clock = DateTime.utc(2026, 11, 25, 9);
      cubit = build();
    });

    test(
      'nothing is read when the page opens, nor before a read is shown',
      () async {
        await pumpEventQueue();
        expect(prices.asked, isEmpty);
        expect(cubit.state.price, isA<TakePriceNone>());
        final preparing = take.preparing = Completer();
        unawaited(cubit.take());
        await pumpEventQueue();
        expect(cubit.state, isA<TakePreparing>());
        expect(prices.asked, isEmpty);
        preparing.complete(Ok(read));
        await pumpEventQueue();
        expect(prices.asked, hasLength(1));
      },
    );

    test(
      'once the read is shown: the coordinator\'s price without the premium, of the terms, in their currency',
      () async {
        await cubit.take();
        final (currency, price) = prices.asked.single;
        expect(currency, read.terms.currency);
        expect(price, TakenPriceCheck.coordinatorPrice(read.terms));
        final state = cubit.state as TakeReady;
        expect(identical(state.prepared, read), isTrue);
        expect(state.price, isA<TakePriceChecked>());
        expect(cubit.priceShown, TakenPriceShown.nothing);
      },
    );

    test(
      'a price 20 % below for a buyer: the red alert « far below »',
      () async {
        prices.rate = P2pWalletRateRead(91711.15 * 1.25);
        await cubit.take();
        expect(read.terms.role, TradeRole.buyer);
        expect(cubit.priceShown, TakenPriceShown.farBelow);
      },
    );

    test(
      'compared on the terms the take is sent on, never on the read\'s `price_now`',
      () async {
        final odd = await preparedTake(changes: {'price_now': 50000.0});
        take = _Take([Ok(odd)]);
        cubit = build();
        await cubit.take();
        expect(prices.asked.single.$2, closeTo(1e10 / 106900 / 1.02, 1e-6));
        expect(cubit.priceShown, TakenPriceShown.nothing);
      },
    );

    test('no wallet\'s port lent: nothing compared, nothing read', () async {
      cubit = build(wallet: false);
      await cubit.take();
      expect(cubit.state, isA<TakeReady>());
      expect(cubit.state.price, isA<TakePriceNone>());
      expect(cubit.priceShown, TakenPriceShown.nothing);
    });

    test(
      'a premium of −100 %: « Price not checked », nothing read, « Retry » reads nothing either',
      () async {
        take = _Take([Ok(readFree)]);
        cubit = build();
        await cubit.take();
        expect(prices.asked, isEmpty);
        expect(cubit.priceShown, TakenPriceShown.unverified);
        await cubit.retryPrice();
        expect(prices.asked, isEmpty);
        expect(cubit.priceShown, TakenPriceShown.unverified);
      },
    );

    test(
      'at most one read per 3 minutes per currency: taken again within them, compared from the last read',
      () async {
        await cubit.take();
        cubit.back();
        clock = clock.add(const Duration(minutes: 2, seconds: 59));
        await cubit.take();
        expect(prices.asked, hasLength(1));
        expect(cubit.state.price, isA<TakePriceChecked>());
        cubit.back();
        clock = clock.add(const Duration(seconds: 1));
        await cubit.take();
        expect(prices.asked, hasLength(2));
      },
    );

    test(
      'the last read kept is the price, compared again with a new read\'s price',
      () async {
        await cubit.take();
        cubit.back();
        // The same Bull wallet's price, a coordinator's price now 20 % higher: red for a buyer, nothing read.
        final dearer = await preparedTake(changes: {'satoshis_now': 89083});
        take.prepared = [Ok(dearer)];
        await cubit.take();
        expect(prices.asked, hasLength(1));
        expect(cubit.priceShown, TakenPriceShown.against);
      },
    );

    test('another currency is read anew', () async {
      take.prepared = [Ok(read), Ok(readUsd)];
      await cubit.take();
      cubit.back();
      await cubit.take();
      expect(prices.asked.map((asked) => asked.$1.code), ['EUR', 'USD']);
    });

    test(
      '« Retry » reads again at once, « Price not checked » still drawn meanwhile',
      () async {
        prices.rate = const P2pWalletRateUnavailable();
        await cubit.take();
        expect(cubit.priceShown, TakenPriceShown.unverified);
        prices.rate = P2pWalletRateRead(91711);
        prices.held = Completer();
        unawaited(cubit.retryPrice());
        await pumpEventQueue();
        expect(prices.asked, hasLength(2));
        expect(cubit.state.price, isA<TakePriceReading>());
        expect(cubit.priceShown, TakenPriceShown.unverified);
        // A second « Retry » meanwhile reads nothing more.
        await Future.wait([cubit.retryPrice(), pumpEventQueue()]);
        expect(prices.asked, hasLength(2));
        prices.held?.complete();
        await pumpEventQueue();
        expect(cubit.priceShown, TakenPriceShown.nothing);
      },
    );

    test(
      'a read that ends in an error (a bug, not a failure the service answers) is « Price not checked »: « Continue » no longer waits on it, « Retry » reads again (#270)',
      () async {
        prices
          ..error = StateError('a bug of the read')
          ..held = Completer();
        unawaited(cubit.take());
        await pumpEventQueue();
        expect(cubit.state.price, isA<TakePriceReading>());
        var settled = false;
        unawaited(cubit.priceSettled().then((_) => settled = true));
        prices.held?.complete();
        await pumpEventQueue();
        expect(settled, isTrue);
        expect(cubit.state.price, isA<TakePriceChecked>());
        expect(cubit.state.price.shownCheck, isA<MakePriceUnverified>());
        expect(cubit.priceShown, TakenPriceShown.unverified);
        // Nothing runs any more: at once.
        await cubit.priceSettled();
        prices
          ..error = null
          ..held = null;
        await cubit.retryPrice();
        expect(prices.asked, hasLength(2));
        expect(cubit.priceShown, TakenPriceShown.nothing);
      },
    );

    test(
      '« Retry » of a comparison that is not « Price not checked » reads nothing',
      () async {
        await cubit.take();
        await cubit.retryPrice();
        expect(prices.asked, hasLength(1));
      },
    );

    test(
      '« Continue » waits for the read that runs ([priceSettled])',
      () async {
        prices.held = Completer();
        unawaited(cubit.take());
        await pumpEventQueue();
        expect(cubit.state.price, isA<TakePriceReading>());
        var settled = false;
        unawaited(cubit.priceSettled().then((_) => settled = true));
        await pumpEventQueue();
        expect(settled, isFalse);
        prices.held?.complete();
        await pumpEventQueue();
        expect(settled, isTrue);
        expect(cubit.state.price, isA<TakePriceChecked>());
        // Nothing runs: at once.
        await cubit.priceSettled();
      },
    );

    test(
      'an answer for a read no longer shown is dropped, and kept for the next comparison',
      () async {
        prices.held = Completer();
        unawaited(cubit.take());
        await pumpEventQueue();
        cubit.back();
        prices.rate = P2pWalletRateRead(91711.15 * 1.25);
        prices.held?.complete();
        await pumpEventQueue();
        expect(cubit.state, isA<TakeIdle>());
        expect(cubit.state.price, isA<TakePriceNone>());
        prices.held = null;
        await cubit.take();
        expect(prices.asked, hasLength(1));
        expect(cubit.priceShown, TakenPriceShown.farBelow);
      },
    );

    test(
      'the take is sent on the very terms compared, the verdict not checked again at the confirmation',
      () async {
        prices.rate = P2pWalletRateRead(91711.15 * 1.25);
        await cubit.take();
        await cubit.confirm();
        expect(identical(take.confirmed.single, read), isTrue);
        expect(prices.asked, hasLength(1));
        final sent = cubit.state as TakeSent;
        expect(identical(sent.prepared, read), isTrue);
        expect(cubit.priceShown, TakenPriceShown.farBelow);
      },
    );

    test(
      'the order changed at the confirmation: the new read compared anew, from the price already read',
      () async {
        final dearer = await preparedTake(changes: {'satoshis_now': 89083});
        take
          ..prepared = [Ok(read), Ok(dearer)]
          ..answer = () => const Err(TakeOrderChanged());
        await cubit.take();
        expect(cubit.priceShown, TakenPriceShown.nothing);
        await cubit.confirm();
        final state = cubit.state as TakeReady;
        expect(identical(state.prepared, dearer), isTrue);
        expect(state.changed, isTrue);
        expect(cubit.priceShown, TakenPriceShown.against);
        expect(prices.asked, hasLength(1));
      },
    );

    test(
      'the preparation gone at the confirmation: the new read compared anew, from the price already read',
      () async {
        final dearer = await preparedTake(changes: {'satoshis_now': 89083});
        take
          ..prepared = [Ok(read), Ok(dearer)]
          ..answer = () => const Err(TakePreparationGone());
        await cubit.take();
        expect(cubit.priceShown, TakenPriceShown.nothing);
        await cubit.confirm();
        final state = cubit.state as TakeReady;
        expect(identical(state.prepared, dearer), isTrue);
        expect(state.price, isA<TakePriceChecked>());
        expect(cubit.priceShown, TakenPriceShown.against);
        expect(prices.asked, hasLength(1));
      },
    );

    test(
      'a comparison never stops the take: « Continue » and « Done » send it, red or not checked',
      () async {
        prices.rate = const P2pWalletRateUnavailable();
        await cubit.take();
        expect(cubit.priceShown, TakenPriceShown.unverified);
        await cubit.confirm();
        expect(take.confirmed, hasLength(1));
      },
    );
  });
}

/// `CheckMakePriceUsecase.execute` over a Bull wallet's price set by the test, held while [held] runs.
final class _Prices {
  P2pWalletBitcoinRate rate = P2pWalletRateRead(91711);
  Completer<void>? held;

  /// While set, the read throws it, once [held] is completed: a bug of the price's service.
  Error? error;
  final List<(RobosatsCurrency, double)> asked = [];

  Future<MakePriceCheck> check(
    RobosatsNetwork network,
    RobosatsCurrency currency,
    double coordinatorPrice,
  ) async {
    asked.add((currency, coordinatorPrice));
    final gate = held;
    if (gate != null) await gate.future;
    if (error case final thrown?) throw thrown;
    return MakePriceCheck.of(
      currency: currency,
      coordinatorPrice: coordinatorPrice,
      wallet: rate,
    );
  }
}

/// The take in two steps, played by the test.
final class _Take {
  List<Result<PreparedTake, TakeRefusal>> prepared;
  Completer<Result<PreparedTake, TakeRefusal>>? preparing;
  Result<TakeOutcome, TakeRefusal> Function()? answer;
  final List<PreparedTake> confirmed = [];

  _Take(this.prepared);

  TakeCalls get calls => TakeCalls(
    prepare: (shown, {required network, amount, onStep, garageRobot}) async {
      final waiting = preparing;
      if (waiting != null) {
        preparing = null;
        return waiting.future;
      }
      return prepared.length > 1 ? prepared.removeAt(0) : prepared.single;
    },
    confirm: (prepared, {password, onStep}) async {
      confirmed.add(prepared);
      final result =
          (answer ??
          () => Ok(TakeOutcomeUnknown(TradeScreenStatuses.record)))();
      answer = null;
      return result;
    },
    abandon: (_) {},
    abandonOrder: (shown, {required network}) {},
  );
}
