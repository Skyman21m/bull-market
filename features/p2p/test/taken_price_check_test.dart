import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/trade/exact_ratio.dart';
import 'package:p2p/src/domain/trade/sats_at_price.dart';
import 'package:p2p/src/domain/trade/trade_storable.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade/wallet_rate_check.dart';
import 'package:p2p/src/domain/usecases/trade/check_payout_rate_usecase.dart';
import 'package:test/test.dart';

import 'support/trade_orders.dart';
import 'support/trade_screens.dart';

/// The owner's payment rule for an order taken here (#249, decided on 2026-11-20; design note `docs/design/phase-3-taken-order-price-check.md` § 3, § 4, § 7, § 8 slices 1 and 3): the taker bond, a taker seller's escrow and a taker buyer's payout against the amount taken at the Bull wallet's price with the premium kept in the taker's terms, one threshold of 10 % on the side that costs, never a refusal.
///
/// The terms are restored from the record a take stores (`TradeTermsRecord` version 1, the format of phase 2, unchanged since), so that a trade taken before this version is compared as a new one. Every figure is computed by hand, exactly (Python's `fractions`, written out in the comments).
void main() {
  T some<T>(T? value) => value ?? (throw StateError('missing'));

  final usd = some(RobosatsCurrency.fromCode('USD'));

  /// The terms of a take of [amount] USD at [premium] %, a bond of [bond] %, the taker fee [fee], as the take stores them (version 1); a seller takes a buy order, a buyer a sell order.
  TradeTerms<TakenSide> taken({
    TradeRole role = TradeRole.seller,
    double amount = 100,
    bool range = false,
    double premium = 3.5,
    int? explicitSatoshis,
    double bond = 3,
    double bookPrice = 74164.995,
    double fee = 0.00175,
    int currencyId = 0,
  }) => switch (TradeTerms.restore(
    TradeTermsRecord(
      version: 1,
      network: 'mainnet',
      coordinatorAlias: 'temple',
      orderId: 42,
      role: role.name,
      type: role == TradeRole.seller ? 0 : 1,
      currencyId: currencyId == 0 ? usd.id : currencyId,
      amount: amount,
      isRange: range,
      premiumPercent: premium,
      explicitSatoshis: explicitSatoshis,
      bondSizePercent: bond,
      escrowSeconds: 10800,
      bookPrice: bookPrice,
      takerFee: fee,
    ),
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  final wallet = P2pWalletRateRead(71657);

  WalletRateCompared compared(WalletRateCheck check) => switch (check) {
    final WalletRateCompared rate => rate,
    final other => throw StateError('not compared: $other'),
  };

  WalletRateCompared bond(
    int sats, {
    TradeTerms<TakenSide>? of,
    P2pWalletBitcoinRate? at,
  }) => compared(
    WalletRateCheck.ofTakerBond(
      of ?? taken(),
      asked: Sats.fromInt(sats),
      wallet: at ?? wallet,
    ),
  );

  WalletRateCompared escrow(
    int sats, {
    TradeTerms<TakenSide>? of,
    P2pWalletBitcoinRate? at,
  }) => compared(
    WalletRateCheck.ofTakerEscrow(
      of ?? taken(),
      asked: Sats.fromInt(sats),
      wallet: at ?? wallet,
    ),
  );

  WalletRateCompared payout(
    int sats, {
    TradeTerms<TakenSide>? of,
    P2pWalletBitcoinRate? at,
  }) => compared(
    WalletRateCheck.ofTakerPayout(
      of ?? taken(role: TradeRole.buyer),
      received: Sats.fromInt(sats),
      wallet: at ?? wallet,
    ),
  );

  group('the sats of an amount at a price, shared by both sides', () {
    test(
      'the owner\'s example: 100 USD at 71,657 USD/BTC with +3.5 % = 2,000,000,000,000 / 14,832,999 sats exactly (134,834.4997…)',
      () {
        expect(
          amountSatsAtPrice(
            amount: some(FiatAmount.tryCreate(100)),
            premium: some(Premium.tryCreate(3.5)),
            price: 71657,
          ),
          ExactRatio.integer(2000000000000) / ExactRatio.integer(14832999),
        );
      },
    );

    test(
      'a premium of −100 %, which `Premium.tryCreate` accepts: a price of zero, no figure, never a division',
      () {
        expect(
          amountSatsAtPrice(
            amount: some(FiatAmount.tryCreate(100)),
            premium: some(Premium.tryCreate(-100)),
            price: 71657,
          ),
          isNull,
        );
      },
    );

    test('a price outside the bounds of a price: no figure', () {
      for (final price in [
        0.0,
        0.00009,
        1e15,
        double.infinity,
        double.nan,
        -71657.0,
      ]) {
        expect(
          amountSatsAtPrice(
            amount: some(FiatAmount.tryCreate(100)),
            premium: some(Premium.tryCreate(3.5)),
            price: price,
          ),
          isNull,
          reason: '$price',
        );
      }
      expect(TradePriceBounds.lowest, MakerTerms.minCreatedPrice);
      expect(TradePriceBounds.highest, MakerTerms.maxCreatedPrice);
    });

    test(
      'a taker buyer\'s payout at 9 takes the taker fee off, never the maker fee: 134,834 → 134,598 (0.175 %), where the maker fee (0.025 %) would give 134,800',
      () {
        expect(
          taken(role: TradeRole.buyer).payoutAt(Sats.fromInt(134834)),
          Sats.fromInt(134598),
        );
        // A half goes to the even one, as Python's `round`: 999.5 → 1,000, 2,998.5 → 2,998.
        final half = taken(role: TradeRole.buyer, fee: 0.0005);
        expect(half.payoutAt(Sats.fromInt(1000)), Sats.fromInt(1000));
        expect(half.payoutAt(Sats.fromInt(3000)), Sats.fromInt(2998));
      },
    );
  });

  group(
    'the taker bond: the bond size of the amount taken at the Bull wallet\'s price with the premium kept, more than 10 % above it warns',
    () {
      test(
        '4,045 sats expected (4,045.0349…), this wallet the one that pays',
        () {
          final rate = bond(4045);
          expect(rate, isA<WalletRateAtWallet>());
          expect(rate.expected, Sats.fromInt(4045));
          expect(rate.price, 71657);
          expect(rate.side, WalletRateSide.pays);
          expect(rate.warns, isFalse);
          expect(rate.amount, some(FiatAmount.tryCreate(100)));
        },
      );

      test('4,449 sats: shown, no warning (+9.99 %)', () {
        final rate = bond(4449);
        expect(rate.warns, isFalse);
        expect(rate.gapHundredths, BigInt.from(999));
      });

      test('4,450 sats: the warning (+10.02 %), the first sat above 10 %', () {
        final rate = bond(4450);
        expect(rate.warns, isTrue);
        expect(rate.gapHundredths, BigInt.from(1002));
      });

      test(
        'the bond size counts: at 6 % the same bond is half the expected one',
        () {
          final rate = bond(4045, of: taken(bond: 6));
          // 6 % of 134,834.4997… = 8,090.0699…
          expect(rate.expected, Sats.fromInt(8090));
          expect(rate.warns, isFalse);
        },
      );
    },
  );

  group(
    'a taker seller\'s escrow: the amount taken at the Bull wallet\'s price with the premium kept, the taker fee in the gap, more than 10 % above it warns',
    () {
      test(
        '134,834 sats expected; the honest escrow of 135,070 reads +0.18 %',
        () {
          final rate = escrow(135070);
          expect(rate.expected, Sats.fromInt(134834));
          expect(rate.side, WalletRateSide.pays);
          expect(rate.warns, isFalse);
          expect(rate.gapHundredths, BigInt.from(18));
        },
      );

      test('148,317 sats: shown, no warning (+10.00 %)', () {
        final rate = escrow(148317);
        expect(rate.warns, isFalse);
        expect(rate.gapHundredths, BigInt.from(1000));
      });

      test('148,318 sats: the warning (+10.01 %)', () {
        final rate = escrow(148318);
        expect(rate.warns, isTrue);
        expect(rate.gapHundredths, BigInt.from(1001));
      });

      test('the bond size is not applied to the escrow', () {
        expect(
          escrow(135070, of: taken(bond: 6)).expected.value.toInt(),
          134834,
        );
      });
    },
  );

  group(
    'a taker buyer\'s payout: the amount taken at the Bull wallet\'s price with the premium kept, more than 10 % below it warns',
    () {
      test(
        '134,834 sats expected, the side the one that receives; the honest payout of 134,598 reads −0.18 %',
        () {
          final rate = payout(134598);
          expect(rate.expected, Sats.fromInt(134834));
          expect(rate.side, WalletRateSide.receives);
          expect(rate.warns, isFalse);
          expect(rate.gapHundredths, BigInt.from(-18));
        },
      );

      test('121,352 sats, just above 90 %: no warning, −10.00 %', () {
        final rate = payout(121352);
        expect(rate.warns, isFalse);
        expect(rate.gapHundredths, BigInt.from(-1000));
      });

      test('121,351 sats, just below 90 %: the warning, −10.01 %', () {
        final rate = payout(121351);
        expect(rate.warns, isTrue);
        expect(rate.gapHundredths, BigInt.from(-1001));
      });

      test(
        'more sats than expected, by any gap, is in the buyer\'s favour',
        () {
          expect(payout(1348344).warns, isFalse);
        },
      );
    },
  );

  group(
    'a coordinator\'s price 20 % too high and ten times too low, for each role (the coordinator\'s own figures, `Logics.calc_sats` truncated, the bond `int(sats × 3 / 100)`, the escrow and payout rounded with the taker fee)',
    () {
      // 20 % too high: 85,988.4 USD/BTC, 112,362 sats; ten times too low: 7,165.7 USD/BTC, 1,348,344 sats.
      test(
        'a seller: 20 % too high is in its favour (bond 3,370, −16.69 %; escrow 112,559, −16.53 %), ten times too low warns at the bond (40,450, +900.00 %) and at the escrow (1,350,704, +901.75 %)',
        () {
          expect(bond(3370).warns, isFalse);
          expect(bond(3370).gapHundredths, BigInt.from(-1669));
          expect(escrow(112559).warns, isFalse);
          expect(escrow(112559).gapHundredths, BigInt.from(-1653));
          expect(bond(40450).warns, isTrue);
          expect(bond(40450).gapHundredths, BigInt.from(90000));
          expect(escrow(1350704).warns, isTrue);
          expect(escrow(1350704).gapHundredths, BigInt.from(90175));
        },
      );

      test(
        'a buyer: 20 % too high gives no warning at the bond (3,370, −16.69 %) and warns at the payout (112,165, −16.82 %); ten times too low warns at the bond (40,450) and is in its favour at the payout (1,345,984)',
        () {
          final buyer = taken(role: TradeRole.buyer);
          expect(bond(3370, of: buyer).warns, isFalse);
          expect(payout(112165).warns, isTrue);
          expect(payout(112165).gapHundredths, BigInt.from(-1682));
          expect(bond(40450, of: buyer).warns, isTrue);
          expect(payout(1345984).warns, isFalse);
        },
      );

      test(
        'the figure expected never comes from the coordinator\'s price kept in the terms: a coordinator whose book said 20 % too high (its read\'s price with the premium, 88,997.7 USD/BTC) still gives a gap of −16.82 % at the payout',
        () {
          final lied = taken(role: TradeRole.buyer, bookPrice: 88997.7);
          expect(payout(112165, of: lied).gapHundredths, BigInt.from(-1682));
          expect(payout(112165, of: lied).warns, isTrue);
        },
      );
    },
  );

  test(
    'the premium kept, as a percentage and with its sign: at −5 % the same 100 USD are worth 146,898 sats (146,898.4…), more than at +3.5 % (134,834)',
    () {
      // 100 / (71,657 × 0.95) × 10^8 = 146,898.41…; a premium read as a fraction (+0.035 %) would expect 139,066 sats.
      expect(
        escrow(146898, of: taken(premium: -5)).expected,
        Sats.fromInt(146898),
      );
      expect(escrow(134834).expected, Sats.fromInt(134834));
    },
  );

  test(
    'a range taken below its maximum: the amount taken, kept in the terms (120 of 50 to 200 USD), never the maximum',
    () {
      final range = taken(amount: 120, range: true);
      // 120 / (71,657 × 1.035) × 10^8 = 161,801.39…
      expect(escrow(161801, of: range).expected, Sats.fromInt(161801));
      expect(escrow(161801, of: range).warns, isFalse);
      expect(bond(4854, of: range).expected, Sats.fromInt(4854));
    },
  );

  group(
    'an order priced in sats (question 3, the note\'s recommendation: compared as the others, with the coordinator\'s premium kept)',
    () {
      // The maker's 134,834 sats for 100 USD; the coordinator's rate 15 % below the Bull wallet's (60,908.45 USD/BTC) gives a premium of +21.76 % (21.7651… truncated, `api/logics.py:277-295`), 15 % above (82,405.55) one of −9.99 %.
      test(
        'the coordinator\'s rate 15 % low: a seller\'s honest escrow of 135,070 sats reads +17.85 % against 114,613 sats expected, red; a buyer\'s payout of 134,598 is in its favour',
        () {
          final seller = taken(premium: 21.76, explicitSatoshis: 134834);
          final rate = escrow(135070, of: seller);
          expect(rate.expected, Sats.fromInt(114613));
          expect(rate.gapHundredths, BigInt.from(1785));
          expect(rate.warns, isTrue);
          final buyer = taken(
            role: TradeRole.buyer,
            premium: 21.76,
            explicitSatoshis: 134834,
          );
          expect(payout(134598, of: buyer).warns, isFalse);
        },
      );

      test(
        'the coordinator\'s rate 15 % high: a buyer\'s payout of 134,598 sats reads −13.19 % against 155,042 sats expected, red',
        () {
          final buyer = taken(
            role: TradeRole.buyer,
            premium: -9.99,
            explicitSatoshis: 134834,
          );
          final rate = payout(134598, of: buyer);
          expect(rate.expected, Sats.fromInt(155042));
          expect(rate.gapHundredths, BigInt.from(-1319));
          expect(rate.warns, isTrue);
        },
      );

      test(
        'with a range taken at its minimum (50 of 50 to 100 USD, the maker\'s 134,834 sats whatever the amount, `api/logics.py:264-265`): the escrow of 135,070 sats reads +100.35 % against the 50 USD expected, red',
        () {
          final range = taken(
            amount: 50,
            range: true,
            premium: 3.5,
            explicitSatoshis: 134834,
          );
          final rate = escrow(135070, of: range);
          expect(rate.expected, Sats.fromInt(67417));
          expect(rate.gapHundredths, BigInt.from(10035));
          expect(rate.warns, isTrue);
        },
      );
    },
  );

  group(
    'nothing compared without the Bull wallet\'s price: never a figure of the coordinator',
    () {
      test(
        'a price that could not be read: « rate not checked », for each step',
        () {
          const unread = P2pWalletRateUnavailable();
          expect(
            WalletRateCheck.ofTakerBond(
              taken(),
              asked: Sats.fromInt(4045),
              wallet: unread,
            ),
            isA<WalletRateUnverified>(),
          );
          expect(
            WalletRateCheck.ofTakerEscrow(
              taken(),
              asked: Sats.fromInt(135070),
              wallet: unread,
            ),
            isA<WalletRateUnverified>(),
          );
          final received = WalletRateCheck.ofTakerPayout(
            taken(role: TradeRole.buyer),
            received: Sats.fromInt(134598),
            wallet: unread,
          );
          expect(received, isA<WalletRateUnverified>());
          expect(received.side, WalletRateSide.receives);
        },
      );

      test(
        'a port\'s price outside the bounds of a price, or a premium of −100 %: « rate not checked »',
        () {
          expect(
            WalletRateCheck.ofTakerEscrow(
              taken(),
              asked: Sats.fromInt(135070),
              wallet: P2pWalletRateRead(1e15),
            ),
            isA<WalletRateUnverified>(),
          );
          expect(
            WalletRateCheck.ofTakerBond(
              taken(premium: -100),
              asked: Sats.fromInt(4045),
              wallet: wallet,
            ),
            isA<WalletRateUnverified>(),
          );
        },
      );
    },
  );

  group('the two points the owner has not decided (design note § 7)', () {
    test(
      'question 2, a currency the Bull wallet does not price: the « not priced » line alone, no figure, no warning, for each step',
      () {
        const notPriced = P2pWalletRateNotPriced();
        final checks = [
          WalletRateCheck.ofTakerBond(
            taken(),
            asked: Sats.fromInt(40450),
            wallet: notPriced,
          ),
          WalletRateCheck.ofTakerEscrow(
            taken(),
            asked: Sats.fromInt(1350704),
            wallet: notPriced,
          ),
          WalletRateCheck.ofTakerPayout(
            taken(role: TradeRole.buyer),
            received: Sats.fromInt(1000),
            wallet: notPriced,
          ),
        ];
        for (final check in checks) {
          expect(check, isA<WalletRateNotPriced>());
          expect(check, isNot(isA<WalletRateCompared>()));
          expect(check.warns, isFalse);
        }
        expect(
          TakenRateRules.notPriced(
            Sats.fromInt(1),
            usd,
            side: WalletRateSide.pays,
            amount: some(FiatAmount.tryCreate(100)),
          ),
          isA<WalletRateNotPriced>(),
        );
      },
    );

    test(
      'question 3, an order priced in sats: compared at the payments as the others',
      () {
        expect(TakenRateRules.comparesOrdersPricedInSats, isTrue);
        expect(
          TakenRateRules.compares(taken(explicitSatoshis: 134834)),
          isTrue,
        );
        expect(TakenRateRules.compares(taken()), isTrue);
      },
    );
  });

  group(
    'a taker buyer\'s payout, what is compared at each step (the state machine\'s statuses of a sell order taken: 100 EUR, +2 %, 106,900 sats)',
    () {
      late TradeScreenStatuses statuses;
      final record = TradeScreenStatuses.record;
      setUpAll(() async {
        statuses = await TradeScreenStatuses.make();
      });
      TradeTerms<TakenSide> terms() => switch (statuses.terms) {
        final TradeTerms<TakenSide> terms => terms,
        _ => throw StateError('not a take'),
      };

      test(
        'at 6 and 8: the invoice the payout panel asks (106,713 sats), the amount taken, kept for 9',
        () async {
          for (final seen in [
            await statuses.waitingForBoth(),
            await statuses.waitingForPayout(),
          ]) {
            final subject = CheckPayoutRateUsecase.subjectOfTake(
              record,
              terms(),
              seen,
            );
            expect(
              subject,
              isA<PayoutRateCompared>()
                  .having((s) => s.received, 'received', Sats.fromInt(106713))
                  .having(
                    (s) => s.amount,
                    'amount',
                    some(FiatAmount.tryCreate(100)),
                  )
                  .having((s) => s.basis, 'basis', const PayoutRateAskedNow())
                  .having((s) => s.keep, 'keep', Sats.fromInt(106713)),
            );
          }
        },
      );

      test(
        'at 9: the trade\'s sats less the taker fee (106,713), the coordinator\'s of now without a kept invoice, said as such; against the invoice kept, the smaller, and a figure that moved said',
        () async {
          final nine = await statuses.chatting();
          final hundred = some(FiatAmount.tryCreate(100));
          expect(
            CheckPayoutRateUsecase.subjectOfTake(record, terms(), nine),
            PayoutRateCompared(
              received: Sats.fromInt(106713),
              amount: hundred,
              basis: const PayoutRateToldNow(),
            ),
          );
          expect(
            CheckPayoutRateUsecase.subjectOfTake(
              record,
              terms(),
              nine,
              asked: Sats.fromInt(106713),
            ),
            PayoutRateCompared(
              received: Sats.fromInt(106713),
              amount: hundred,
              basis: const PayoutRateAsked(),
            ),
          );
          expect(
            CheckPayoutRateUsecase.subjectOfTake(
              record,
              terms(),
              nine,
              asked: Sats.fromInt(106000),
            ),
            PayoutRateCompared(
              received: Sats.fromInt(106000),
              amount: hundred,
              basis: PayoutRateTold(
                told: Sats.fromInt(106713),
                asked: Sats.fromInt(106000),
              ),
            ),
          );
        },
      );

      test(
        'the terms read otherwise than kept (`TradeTermsChanged`): nothing compared, at 6 as at 9, not even the invoice kept',
        () async {
          final six = await statuses.read(
            await statuses.bondStep(),
            orderJson(6, changes: {'premium': '3.00'}),
          );
          expect(six.status.has<TradeTermsChanged>(), isTrue);
          expect(
            CheckPayoutRateUsecase.subjectOfTake(record, terms(), six),
            isNot(isA<PayoutRateCompared>()),
          );
          final nine = await statuses.read(
            await statuses.chatting(),
            orderJson(9, changes: {'premium': '3.00'}),
          );
          expect(nine.status.has<TradeTermsChanged>(), isTrue);
          final subject = CheckPayoutRateUsecase.subjectOfTake(
            record,
            terms(),
            nine,
            asked: Sats.fromInt(106713),
          );
          expect(subject, isA<PayoutRateMismatch>());
        },
      );

      test(
        'the amounts that do not agree: nothing compared, at 6 (`PayoutAmountMismatch`) as at 9 (`TradePriceOutsideOrder`), where a maker buyer\'s kept invoice would be compared alone',
        () async {
          final six = await statuses.read(
            await statuses.bondStep(),
            orderJson(6, changes: {'invoice_amount': 90000}),
          );
          expect(six.status.has<PayoutAmountMismatch>(), isTrue);
          expect(
            CheckPayoutRateUsecase.subjectOfTake(record, terms(), six),
            isA<PayoutRateMismatch>(),
          );
          final nine = await statuses.read(
            await statuses.waitingForPayout(),
            orderJson(9, last: 80000),
          );
          expect(nine.status.has<TradePriceOutsideOrder>(), isTrue);
          expect(
            CheckPayoutRateUsecase.subjectOfTake(
              record,
              terms(),
              nine,
              asked: Sats.fromInt(106713),
            ),
            isA<PayoutRateMismatch>(),
          );
        },
      );

      test(
        'a status not stored, or not a buyer\'s payout step: nothing',
        () async {
          final six = await statuses.waitingForBoth();
          expect(
            CheckPayoutRateUsecase.subjectOfTake(
              record,
              terms(),
              TradeSeen(six.status, order: six.order, stored: false),
            ),
            isNull,
          );
          expect(
            CheckPayoutRateUsecase.subjectOfTake(
              record,
              terms(),
              await statuses.bondStep(),
            ),
            isNull,
          );
        },
      );
    },
  );
}
