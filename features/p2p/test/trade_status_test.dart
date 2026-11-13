import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/checked_invoice.dart';
import 'package:p2p/src/domain/trade/trade_answer.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:p2p/src/domain/trade/trade_tolerances.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/trade/wallet_payment.dart';
import 'package:p2p/src/testing/bolt11_test_invoice.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart';
import 'support/key_output.dart';
import 'support/trade_orders.dart';

/// temple's mainnet Lightning node, from the federation list.
final String templeNode = coordinator(
  'temple',
).nodesPubkeys(RobosatsNetwork.mainnet).first;

/// A node key no coordinator has: a fixed test value.
const strangerNode =
    '02aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  late TradeTerms buyer;
  late TradeTerms seller;
  late Bolt11TestDecoder decoder;
  late Bolt11Reader reader;

  setUpAll(() async {
    buyer = await tradeTerms();
    seller = await tradeTerms(role: TradeRole.seller);
  });

  setUp(() {
    decoder = Bolt11TestDecoder();
    reader = Bolt11Reader(decoder);
  });

  /// [json] read through the package's parser, its invoices made readable.
  Future<TradeAnswer> answer(
    Map<String, Object?> json, {
    List<Bolt11TestInvoice> invoices = const [],
  }) async {
    invoices.forEach(decoder.add);
    return readAnswer(json);
  }

  TradeStatus next(
    TradeStatus? previous,
    TradeAnswer answer, {
    TradeTerms? terms,
    DateTime? now,
  }) => TradeStatus.from(
    previous: previous,
    answer: answer,
    terms: terms ?? buyer,
    now: now ?? tradeNow,
    reader: reader,
  );

  /// The status of the pre-take with [bond], first read.
  Future<TradeStatus> preTake({
    Bolt11TestInvoice? bond,
    TradeTerms? terms,
    DateTime? now,
  }) async {
    final invoice = bond ?? bondInvoice();
    return next(
      null,
      await answer(
        orderJson(3, bond: invoice, role: (terms ?? buyer).role),
        invoices: [invoice],
      ),
      terms: terms,
      now: now,
    );
  }

  CheckedInvoice checkedOf(TradeStatus status) => switch (status.invoice) {
    final CheckedInvoice invoice => invoice,
    final other => fail('expected a checked invoice, got $other'),
  };

  group('statuses from the answers of the reference', () {
    test('3: the pre-take with its bond, checked clean and payable', () async {
      final status = await preTake();
      expect(status, isA<WaitingForTakerBond>());
      status as WaitingForTakerBond;
      expect(status.warnings, isEmpty);
      expect(status.deadline, tradeNow.add(const Duration(seconds: 190)));
      expect(status.stepDuration, const Duration(seconds: 190));
      final bond = checkedOf(status);
      expect(bond.step, InvoiceStep.bond);
      expect(bond.amount, Sats.fromInt(bookBond));
      expect(bond.orderAmount, Sats.fromInt(bookBond));
      expect(bond.network, RobosatsNetwork.mainnet);
      expect(bond.bolt11, bondInvoice().text);
      expect(bond.passedEveryCheck, isTrue);
      expect(bond.mayShow, isTrue);
      expect(
        walletPaymentFor(
          accepted: Sats.fromInt(bookBond),
          invoice: bond,
          now: tradeNow,
        ),
        isA<WalletPaymentOffered>(),
      );
    });

    test('6, 7 and 8 for a buyer and a seller', () async {
      final bond = await preTake();
      final both = next(bond, await answer(orderJson(6)));
      expect(both, isA<WaitingForBoth>());
      both as WaitingForBoth;
      expect(both.warnings, isEmpty);
      expect(both.role, TradeRole.buyer);
      expect(both.escrow, isNull);
      expect(both.payoutAmount, Sats.fromInt(payoutOf(bookSats)));
      expect(both.tradeSatoshis, Sats.fromInt(payoutOf(bookSats)));
      expect(next(both, await answer(orderJson(7))), isA<WaitingForEscrow>());
      final payout = next(both, await answer(orderJson(8)));
      expect(payout, isA<WaitingForPayout>());
      expect((payout as WaitingForPayout).payoutAmount, both.payoutAmount);
      expect(payout.warnings, isEmpty);

      final sellerBond = await preTake(terms: seller);
      final escrow = escrowInvoice();
      final sellerBoth = next(
        sellerBond,
        await answer(
          orderJson(6, role: TradeRole.seller, escrow: escrow),
          invoices: [escrow],
        ),
        terms: seller,
      );
      expect(sellerBoth, isA<WaitingForBoth>());
      expect(sellerBoth.warnings, isEmpty);
      final checked = checkedOf(sellerBoth);
      expect(checked.step, InvoiceStep.escrow);
      expect(checked.amount, Sats.fromInt(escrowOf(bookSats)));
      final sellerEscrow = next(
        sellerBoth,
        await answer(
          orderJson(7, role: TradeRole.seller, escrow: escrow),
          invoices: [escrow],
        ),
        terms: seller,
      );
      expect(sellerEscrow, isA<WaitingForEscrow>());
      expect(checkedOf(sellerEscrow).passedEveryCheck, isTrue);
      final sellerWaits = next(
        sellerEscrow,
        await answer(orderJson(8, role: TradeRole.seller)),
        terms: seller,
      );
      expect(sellerWaits, isA<WaitingForPayout>());
      expect(sellerWaits.invoice, isNull);
    });

    test('9 to 18 and 5, along the edges of the reference', () async {
      final both = next(await preTake(), await answer(orderJson(6)));
      final chat = next(both, await answer(orderJson(9)));
      expect(chat, isA<Chatting>());
      expect((chat as Chatting).fiatSent, isFalse);
      expect(chat.chatLastIndex, 3);
      final sent = next(chat, await answer(orderJson(10)));
      expect((sent as Chatting).fiatSent, isTrue);
      expect(sent.position, TradePosition.fiatSent);
      final dispute = next(sent, await answer(orderJson(11)));
      expect(dispute, isA<InDispute>());
      expect((dispute as InDispute).statementSubmitted, isFalse);
      final resolution = next(dispute, await answer(orderJson(16)));
      expect(resolution, isA<WaitingDisputeResolution>());
      expect(next(resolution, await answer(orderJson(17))), isA<DisputeWon>());
      expect(next(resolution, await answer(orderJson(18))), isA<DisputeLost>());
      final paying = next(sent, await answer(orderJson(13)));
      expect(paying, isA<SendingSats>());
      final failed = next(paying, await answer(orderJson(15)));
      expect(failed, isA<RoutingFailed>());
      failed as RoutingFailed;
      expect(failed.retries, 2);
      expect(failed.invoiceExpired, isTrue);
      expect(failed.reason, PayoutFailureReason.nonRecoverable);
      final done = next(failed, await answer(orderJson(14)));
      expect(done, isA<Succeeded>());
      expect(done.isTerminal, isTrue);
      final expired = next(both, await answer(orderJson(5)));
      expect(expired, isA<Expired>());
      expect(
        (expired as Expired).reason,
        OrderExpiryReason.invoiceNotSubmitted,
      );
      for (final status in [chat, sent, dispute, resolution, paying, failed]) {
        expect(status.warnings, isEmpty, reason: '$status');
      }
    });

    test('1043 and 1044, and the order public again', () async {
      final bond = await preTake();
      expect(next(bond, const TradeOrderCancelled()), isA<Cancelled>());

      final lost = next(bond, const TradeOrderNotAvailable());
      expect(lost, isA<TakenByAnother>());
      expect((lost as TakenByAnother).bondMayHaveBeenLost, isFalse);

      final ended = next(bond, await answer(orderJson(1)));
      expect(ended, isA<PreTakeEnded>());
      expect((ended as PreTakeEnded).bondMayHaveBeenLost, isFalse);
      expect(ended.warnings, isEmpty);

      // Past the escrow duration since the last read of the pre-take, the bond may have locked, been left at 8 and lost.
      final late = tradeNow.add(const Duration(hours: 2, minutes: 59));
      final endedLate = next(bond, await answer(orderJson(1)), now: late);
      expect((endedLate as PreTakeEnded).bondMayHaveBeenLost, isTrue);
      final takenLate = next(bond, const TradeOrderNotAvailable(), now: late);
      expect((takenLate as TakenByAnother).bondMayHaveBeenLost, isTrue);
      final justBefore = late.subtract(const Duration(seconds: 1));
      final endedBefore = next(
        bond,
        await answer(orderJson(1)),
        now: justBefore,
      );
      expect((endedBefore as PreTakeEnded).bondMayHaveBeenLost, isFalse);

      // With no history, nothing can be said.
      expect(
        (next(null, await answer(orderJson(1))) as PreTakeEnded)
            .bondMayHaveBeenLost,
        isTrue,
      );
      expect(
        (next(null, const TradeOrderNotAvailable()) as TakenByAnother)
            .bondMayHaveBeenLost,
        isTrue,
      );

      // After the bond locked, every way back to the book settles it.
      final both = next(bond, await answer(orderJson(6)));
      final forfeited = next(both, await answer(orderJson(1)));
      expect(forfeited, isA<BondForfeited>());
      expect(forfeited.position, TradePosition.publicAgain);
      expect(forfeited.warnings, isEmpty);
      final gone = next(both, const TradeOrderNotAvailable());
      expect(gone, isA<BondForfeited>());
      expect(gone.position, TradePosition.notAvailable);
    });

    test(
      'a terminal status is never left, but refreshed at its position',
      () async {
        final both = next(await preTake(), await answer(orderJson(6)));
        final cancelled = next(both, const TradeOrderCancelled());
        expect(
          identical(next(cancelled, await answer(orderJson(9))), cancelled),
          isTrue,
        );
        final done = next(
          next(
            next(both, await answer(orderJson(9))),
            await answer(orderJson(10)),
          ),
          await answer(orderJson(14)),
        );
        final again = next(
          done,
          await answer(orderJson(14)),
          now: tradeNow.add(const Duration(minutes: 1)),
        );
        expect(again, isA<Succeeded>());
        expect(again.seenAt, tradeNow.add(const Duration(minutes: 1)));
        expect(
          identical(next(done, const TradeOrderCancelled()), done),
          isTrue,
        );
        // Out of the order again says nothing new: the end stays as it was.
        final bond = await preTake();
        final ended = next(bond, await answer(orderJson(1)));
        expect(
          identical(next(ended, await answer(orderJson(1))), ended),
          isTrue,
        );
        final taken = next(bond, const TradeOrderNotAvailable());
        expect(
          identical(next(taken, const TradeOrderNotAvailable()), taken),
          isTrue,
        );
      },
    );
  });

  group('edges', () {
    /// An answer that shows [position] to a taker of [terms], with its invoices readable.
    Future<TradeAnswer> answerAt(
      TradePosition position,
      TradeTerms terms,
    ) async {
      final role = terms.role;
      return switch (position) {
        TradePosition.cancelled => const TradeOrderCancelled(),
        TradePosition.notAvailable => const TradeOrderNotAvailable(),
        TradePosition.publicAgain => answer(orderJson(1, role: role)),
        TradePosition.bondStep => answer(
          orderJson(3, role: role),
          invoices: [bondInvoice()],
        ),
        TradePosition.start => throw StateError('no answer at start'),
        _ => answer(
          orderJson(_wireOf(position), role: role),
          invoices: [escrowInvoice()],
        ),
      };
    }

    /// The status at [position], reached from the pre-take along listed edges.
    Future<TradeStatus> statusAt(
      TradePosition position,
      TradeTerms terms,
    ) async {
      final bond = await preTake(terms: terms);
      if (position == TradePosition.bondStep) return bond;
      return next(bond, await answerAt(position, terms), terms: terms);
    }

    test(
      'every single step of the reference is allowed, for the roles it lists',
      () async {
        for (final MapEntry(key: origin, value: targets)
            in TradeEdges.steps.entries) {
          for (final MapEntry(key: target, value: roles) in targets.entries) {
            for (final role in roles) {
              expect(TradeEdges.allows(role, origin, target), isTrue);
              // From an end, a step only extends the paths that lead through it: [TradeStatus.from] never leaves the end itself.
              if (origin.isTerminal) continue;
              final terms = role == TradeRole.buyer ? buyer : seller;
              final from = await statusAt(origin, terms);
              expect(from.position, origin, reason: '$origin as $role');
              final to = next(
                from,
                await answerAt(target, terms),
                terms: terms,
              );
              expect(to.position, target, reason: '$origin → $target as $role');
              expect(
                to.has<TradeStatusUnexpected>(),
                isFalse,
                reason: '$origin → $target as $role',
              );
              expect(to.has<TradeStatusRegressed>(), isFalse);
              expect(TradeEdges.allows(role, origin, target), isTrue);
            }
          }
        }
      },
    );

    test('several moves between two reads are allowed', () {
      expect(
        TradeEdges.allows(
          TradeRole.buyer,
          TradePosition.bondStep,
          TradePosition.chatting,
        ),
        isTrue,
      );
      expect(
        TradeEdges.allows(
          TradeRole.buyer,
          TradePosition.waitingForBoth,
          TradePosition.succeeded,
        ),
        isTrue,
      );
      expect(
        TradeEdges.allows(
          TradeRole.seller,
          TradePosition.bondStep,
          TradePosition.waitingForEscrow,
        ),
        isTrue,
      );
      expect(
        TradeEdges.allows(
          TradeRole.buyer,
          TradePosition.routingFailed,
          TradePosition.routingFailed,
        ),
        isTrue,
      );
    });

    test('a sample of forbidden edges', () {
      final forbidden = [
        (TradeRole.buyer, TradePosition.chatting, TradePosition.waitingForBoth),
        (TradeRole.buyer, TradePosition.chatting, TradePosition.publicAgain),
        (TradeRole.buyer, TradePosition.sendingSats, TradePosition.cancelled),
        (TradeRole.buyer, TradePosition.waitingForBoth, TradePosition.bondStep),
        (TradeRole.buyer, TradePosition.sendingSats, TradePosition.inDispute),
        (TradeRole.buyer, TradePosition.inDispute, TradePosition.chatting),
        (
          TradeRole.buyer,
          TradePosition.waitingForPayout,
          TradePosition.expired,
        ),
        (
          TradeRole.seller,
          TradePosition.waitingForPayout,
          TradePosition.publicAgain,
        ),
        (
          TradeRole.seller,
          TradePosition.waitingForEscrow,
          TradePosition.expired,
        ),
        (TradeRole.buyer, TradePosition.chatting, TradePosition.notAvailable),
        (TradeRole.buyer, TradePosition.routingFailed, TradePosition.chatting),
      ];
      for (final (role, from, to) in forbidden) {
        expect(
          TradeEdges.allows(role, from, to),
          isFalse,
          reason: '$from → $to as $role',
        );
      }
    });

    test(
      'an unlisted edge to a status that goes on gives it with a warning',
      () async {
        final chat = await statusAt(TradePosition.chatting, buyer);
        final back = next(chat, await answer(orderJson(6)));
        expect(back, isA<WaitingForBoth>());
        expect(back.has<TradeStatusUnexpected>(), isTrue);
        // And every later status remembers it: the wallet never pays on this trade.
        final later = next(back, await answer(orderJson(9)));
        expect(later.has<CoordinatorInconsistent>(), isTrue);
      },
    );

    test('an unlisted edge to an end is refused, the status stays', () async {
      final chat = await statusAt(TradePosition.chatting, buyer);
      final refused = next(chat, await answer(orderJson(1)));
      expect(refused, isA<Chatting>());
      expect(refused.has<TradeStatusUnexpected>(), isTrue);
      expect(refused.seenAt, chat.seenAt);
      expect(next(chat, const TradeOrderNotAvailable()), isA<Chatting>());
    });

    test('back to the bond step after it is refused as an answer', () async {
      final both = await statusAt(TradePosition.waitingForBoth, buyer);
      final regressed = next(
        both,
        await answer(orderJson(3), invoices: [bondInvoice()]),
      );
      expect(regressed, isA<WaitingForBoth>());
      expect(regressed.has<TradeStatusRegressed>(), isTrue);
      // Refused twice, said once.
      final twice = next(regressed, await answer(orderJson(3)));
      expect(twice.warnings.whereType<TradeStatusRegressed>(), hasLength(1));
    });

    test('a status a taker is never shown is refused', () async {
      final both = await statusAt(TradePosition.waitingForBoth, buyer);
      for (final wire in [0, 2, 4, 12]) {
        final refused = next(
          both,
          await answer(orderJson(wire, changes: withTaker)),
        );
        expect(refused, isA<WaitingForBoth>(), reason: '$wire');
        expect(refused.has<TradeStatusRegressed>(), isTrue, reason: '$wire');
      }
      final first = next(null, await answer(orderJson(2, changes: withTaker)));
      expect(first, isA<StatusNotUnderstood>());
      expect(first.has<TradeStatusRegressed>(), isTrue);
      // After a first answer refused, any next one may come, with the breach remembered.
      final then = next(first, await answer(orderJson(6)));
      expect(then, isA<WaitingForBoth>());
      expect(then.has<CoordinatorInconsistent>(), isTrue);
    });
  });

  group('role and order', () {
    test('the maker\'s or the other side\'s view is refused', () async {
      final bond = await preTake();
      // The coordinator says this robot is the buyer of a buy order it took as seller…
      final asSeller = next(
        await preTake(terms: seller),
        await answer(orderJson(6, role: TradeRole.buyer)),
        terms: seller,
      );
      expect(asSeller, isA<WaitingForTakerBond>());
      expect(asSeller.has<TradeRoleMismatch>(), isTrue);
      expect(checkedOf(asSeller).passedEveryCheck, isFalse);
      expect(checkedOf(asSeller).mayShow, isFalse);
      expect(checkedOf(asSeller).mayShowAnyway, isFalse);
      // …or the maker.
      final asMaker = next(
        bond,
        await answer(
          orderJson(
            6,
            changes: {
              'is_maker': true,
              'is_taker': false,
              'maker_hash_id': us.hashId.hex,
              'maker_nick': us.nickname,
              'taker_hash_id': peer.hashId.hex,
              'taker_nick': peer.nickname,
              'is_buyer': false,
              'is_seller': true,
              'invoice_amount': null,
            },
          ),
        ),
      );
      expect(asMaker, isA<WaitingForTakerBond>());
      expect(asMaker.has<TradeRoleMismatch>(), isTrue);
    });

    test('an answer about another order or coordinator is refused', () async {
      final bond = await preTake();
      final other = TradeOrderRead(
        await readOrder(orderJson(6, changes: {'id': 43}), orderId: 43),
      );
      expect(next(bond, other).has<TradeOrderMismatch>(), isTrue);
      final lake = TradeOrderRead(await readOrder(orderJson(6), alias: 'lake'));
      expect(next(bond, lake).has<TradeOrderMismatch>(), isTrue);
    });

    test('changed terms hide the invoice until « Show anyway »', () async {
      final changes = <Map<String, Object?>>[
        {'currency': 1},
        {'premium': '2.50'},
        {'bond_size': '4.00'},
        {'escrow_duration': 7200},
        {'amount': '101.00000000'},
      ];
      for (final change in changes) {
        final invoice = bondInvoice();
        final status = next(
          null,
          await answer(
            orderJson(3, bond: invoice, changes: change),
            invoices: [invoice],
          ),
        );
        expect(status.has<TradeTermsChanged>(), isTrue, reason: '$change');
        final checked = checkedOf(status);
        expect(checked.mayShow, isFalse);
        expect(checked.mayShowAnyway, isTrue);
        expect(checked.passedEveryCheck, isFalse);
      }
      // Within the coordinator's precision, the same terms.
      final same = bondInvoice();
      final within = next(
        null,
        await answer(
          orderJson(
            3,
            bond: same,
            changes: {'premium': '2.0', 'bond_size': '3.0'},
          ),
          invoices: [same],
        ),
      );
      expect(within.has<TradeTermsChanged>(), isFalse);
    });

    test('a range order: the amount taken and its sats', () async {
      final terms = await tradeTerms(range: true);
      expect(terms.amount.value, 120);
      expect(terms.expectedSatoshis, closeTo(bookSats * 1.2, 1e-6));
      final last = (bookSats * 1.2).round();
      final bond = bondInvoice(sats: last * 3 ~/ 100);
      final status = next(
        null,
        await answer(orderJson(3, range: true, bond: bond), invoices: [bond]),
        terms: terms,
      );
      expect(status.warnings, isEmpty);
      final both = next(
        status,
        await answer(orderJson(6, range: true, last: last)),
        terms: terms,
      );
      expect(both.warnings, isEmpty);
      final other = next(
        status,
        await answer(
          orderJson(
            6,
            range: true,
            last: last,
            changes: {'amount': '130.00000000'},
          ),
        ),
        terms: terms,
      );
      expect(other.has<TradeTermsChanged>(), isTrue);
    });
  });

  group('amounts around each tolerance', () {
    test(
      'the bond: within 2 % of the order\'s, and one sat for the truncation, both ways',
      () async {
        final expected = buyer.expectedBond;
        final high =
            (expected * (1 + TradeTolerances.price) +
                    TradeTolerances.roundingSats)
                .floor();
        final low =
            (expected * (1 - TradeTolerances.price) -
                    TradeTolerances.roundingSats)
                .ceil();
        for (final (sats, outside) in [
          (high, false),
          (high + 1, true),
          (low, false),
          (low - 1, true),
          (bookBond, false),
        ]) {
          final status = await preTake(
            bond: bondInvoice(sats: sats, seed: sats),
          );
          expect(
            status.has<BondAmountOutsideOrder>(),
            outside,
            reason: '$sats',
          );
          expect(checkedOf(status).passedEveryCheck, !outside, reason: '$sats');
          if (outside) expect(checkedOf(status).mayShowAnyway, isTrue);
        }
      },
    );

    test('the bond invoice\'s own amount equals bond_satoshis', () async {
      final invoice = bondInvoice(sats: bookBond + 1);
      final status = next(
        null,
        await answer(
          orderJson(3, bond: invoice, changes: {'bond_satoshis': bookBond}),
          invoices: [invoice],
        ),
      );
      expect(status.has<InvoiceAmountMismatch>(), isTrue);
      expect(status.has<BondAmountOutsideOrder>(), isFalse);
      final checked = checkedOf(status);
      expect(checked.mayShow, isFalse);
      expect(checked.mayShowAnyway, isTrue);
    });

    test(
      'the trade\'s sats: within 2 % of the book\'s price, both ways',
      () async {
        final high =
            (bookSats * (1 + TradeTolerances.price) +
                    TradeTolerances.roundingSats)
                .floor();
        final low =
            (bookSats * (1 - TradeTolerances.price) -
                    TradeTolerances.roundingSats)
                .ceil();
        final bond = await preTake();
        for (final (last, outside) in [
          (high, false),
          (high + 1, true),
          (low, false),
          (low - 1, true),
        ]) {
          final status = next(bond, await answer(orderJson(6, last: last)));
          expect(
            status.has<TradePriceOutsideOrder>(),
            outside,
            reason: '$last',
          );
          expect(
            status.has<TakerFeeAboveAnnounced>(),
            isFalse,
            reason: '$last',
          );
        }
        final missing = next(
          bond,
          await answer(orderJson(6, changes: {'satoshis_now': null})),
        );
        expect(missing.has<TradePriceOutsideOrder>(), isTrue);
      },
    );

    test(
      'the seller\'s escrow: escrow_satoshis = trade_satoshis = the invoice, fee at most the announced one and a sat',
      () async {
        final bond = await preTake(terms: seller);
        Future<TradeStatus> withEscrow(int sats, {int? trade}) async {
          final invoice = escrowInvoice(sats: sats, seed: sats);
          return next(
            bond,
            await answer(
              orderJson(
                6,
                role: TradeRole.seller,
                escrow: invoice,
                changes: {'trade_satoshis': ?trade},
              ),
              invoices: [invoice],
            ),
            terms: seller,
          );
        }

        final ceiling =
            (bookSats + bookSats * takerFee + TradeTolerances.feeSats).floor();
        final atCeiling = await withEscrow(ceiling, trade: ceiling);
        expect(atCeiling.warnings, isEmpty);
        final above = await withEscrow(ceiling + 1, trade: ceiling + 1);
        expect(above.has<TakerFeeAboveAnnounced>(), isTrue);
        expect(checkedOf(above).mayShowAnyway, isTrue);
        final negative = await withEscrow(bookSats - 1, trade: bookSats - 1);
        expect(negative.has<TakerFeeAboveAnnounced>(), isTrue);
        final mismatch = await withEscrow(
          escrowOf(bookSats),
          trade: escrowOf(bookSats) - 1,
        );
        expect(mismatch.has<EscrowAmountMismatch>(), isTrue);
        final unknown = await withEscrow(escrowOf(bookSats));
        expect(unknown.warnings, isEmpty);
        final noTrade = next(
          bond,
          await answer(
            orderJson(
              6,
              role: TradeRole.seller,
              changes: {'trade_satoshis': null},
            ),
            invoices: [escrowInvoice()],
          ),
          terms: seller,
        );
        expect(noTrade.has<EscrowAmountMismatch>(), isTrue);
      },
    );

    test(
      'the buyer\'s payout: invoice_amount = trade_satoshis, fee at most the announced one and a sat',
      () async {
        final bond = await preTake();
        final floor = (bookSats - bookSats * takerFee - TradeTolerances.feeSats)
            .ceil();
        Future<TradeStatus> withPayout(int payout, {int? trade}) async => next(
          bond,
          await answer(
            orderJson(
              6,
              changes: {
                'invoice_amount': payout,
                'trade_satoshis': trade ?? payout,
              },
            ),
          ),
        );
        expect((await withPayout(floor)).warnings, isEmpty);
        expect(
          (await withPayout(floor - 1)).has<TakerFeeAboveAnnounced>(),
          isTrue,
        );
        expect(
          (await withPayout(bookSats + 1)).has<TakerFeeAboveAnnounced>(),
          isTrue,
        );
        expect(
          (await withPayout(
            payoutOf(bookSats),
            trade: payoutOf(bookSats) + 1,
          )).has<PayoutAmountMismatch>(),
          isTrue,
        );
        final chat = next(
          bond,
          await answer(orderJson(10, changes: {'trade_satoshis': floor - 1})),
        );
        expect(chat.has<TakerFeeAboveAnnounced>(), isTrue);
      },
    );
  });

  group('the invoice of a step (design note § 4.4)', () {
    test(
      'another network: never shown, never decoded into a checked invoice',
      () async {
        for (final network in [
          Bolt11Network.testnet,
          Bolt11Network.signet,
          Bolt11Network.regtest,
        ]) {
          final invoice = bondInvoice(network: network);
          final status = next(
            null,
            await answer(orderJson(3, bond: invoice), invoices: [invoice]),
          );
          expect(status.invoice, isA<UnusableInvoice>(), reason: '$network');
          expect(
            (status.invoice as UnusableInvoice).reason,
            isA<InvoiceWrongNetwork>(),
          );
          expect(status.has<InvoiceWrongNetwork>(), isTrue);
        }
        // On testnet, `lntb` and `lntbs` belong; `lnbc` does not.
        final testnet = await tradeTerms(network: RobosatsNetwork.testnet);
        for (final (network, belongs) in [
          (Bolt11Network.testnet, true),
          (Bolt11Network.signet, true),
          (Bolt11Network.mainnet, false),
        ]) {
          final invoice = bondInvoice(network: network);
          decoder.add(invoice);
          final status = TradeStatus.from(
            previous: null,
            answer: TradeOrderRead(
              await readOrder(
                orderJson(3, bond: invoice),
                network: RobosatsNetwork.testnet,
              ),
            ),
            terms: testnet,
            now: tradeNow,
            reader: reader,
          );
          expect(status.invoice is CheckedInvoice, belongs, reason: '$network');
        }
      },
    );

    test(
      'garbage, too long or not ASCII: unusable, and the decoder never sees what is out of bounds',
      () async {
        final garbage = next(
          null,
          await answer(orderJson(3, bond: bondInvoice()), invoices: []),
        );
        expect(
          (garbage.invoice as UnusableInvoice).reason,
          isA<InvoiceUnreadable>(),
        );
        expect(
          ((garbage.invoice as UnusableInvoice).reason as InvoiceUnreadable)
              .reason,
          isA<Bolt11Malformed>(),
        );
        decoder.decoded.clear();
        expect(
          reader.read('l' * 2001),
          isA<Err<Bolt11Invoice, Bolt11Refusal>>(),
        );
        expect(switch (reader.read('l' * 2001)) {
          Err(:final failure) => failure,
          Ok() => null,
        }, isA<Bolt11TooLong>());
        for (final text in ['', 'lnbc1é', 'lnbc 1', 'lnbc\n1', 'lnbc1\u0000']) {
          expect(
            switch (reader.read(text)) {
              Err(:final failure) => failure,
              Ok() => null,
            },
            isA<Bolt11NotVisibleAscii>(),
            reason: text,
          );
        }
        expect(decoder.decoded, isEmpty);
        final longest = 'l' * 2000;
        reader.read(longest);
        expect(decoder.decoded, [longest]);
      },
    );

    test('a decoder that throws or breaks its contract gives a refusal', () {
      final valid = bondInvoice();
      Bolt11Invoice withFacts({
        String? hash,
        String? payee,
        int sats = 10,
        Duration? expiry,
      }) => Bolt11Invoice(
        network: Bolt11Network.mainnet,
        amount: Sats.fromInt(sats),
        paymentHash: hash ?? valid.facts.paymentHash,
        createdAt: tradeNow,
        expiry: expiry ?? const Duration(seconds: 1),
        description: null,
        payeeNodeKey: payee,
      );
      for (final facts in [
        withFacts(hash: 'F' * 64),
        withFacts(hash: 'f' * 63),
        withFacts(payee: '04${'a' * 64}'),
        withFacts(sats: 0),
        withFacts(expiry: const Duration(seconds: -1)),
      ]) {
        expect(
          Bolt11Reader(_Answering(Ok(facts))).read(valid.text),
          isA<Err<Bolt11Invoice, Bolt11Refusal>>(),
        );
      }
      expect(
        Bolt11Reader(
          _Answering(Ok(withFacts(payee: templeNode))),
        ).read(valid.text),
        isA<Ok<Bolt11Invoice, Bolt11Refusal>>(),
      );
      expect(
        Bolt11Reader(const _Throwing()).read(valid.text),
        isA<Err<Bolt11Invoice, Bolt11Refusal>>(),
      );
    });

    test(
      'expired: hidden; expiring within the margin: shown, not paid from this wallet',
      () async {
        final expired = await preTake(
          bond: bondInvoice(age: const Duration(seconds: 200)),
        );
        expect(expired.has<InvoiceExpired>(), isTrue);
        expect(checkedOf(expired).mayShow, isFalse);
        expect(checkedOf(expired).mayShowAnyway, isFalse);

        final margin = TradeTolerances.walletPaymentMargin;
        final soon = await preTake(
          bond: bondInvoice(
            age:
                const Duration(seconds: 200) -
                margin +
                const Duration(seconds: 1),
          ),
        );
        expect(soon.has<InvoiceExpiringSoon>(), isTrue);
        expect(checkedOf(soon).mayShow, isTrue);
        expect(checkedOf(soon).passedEveryCheck, isFalse);
        final inTime = await preTake(
          bond: bondInvoice(age: const Duration(seconds: 200) - margin),
        );
        expect(inTime.warnings, isEmpty);
      },
    );

    test('a changed payment hash in the same step: hidden, for good', () async {
      final first = await preTake();
      final other = bondInvoice(seed: 99);
      final changed = next(
        first,
        await answer(orderJson(3, bond: other), invoices: [other]),
      );
      expect(changed.has<InvoiceHashChanged>(), isTrue);
      expect(checkedOf(changed).mayShow, isFalse);
      expect(checkedOf(changed).mayShowAnyway, isFalse);
      // The hash of the step stays the first one: the new invoice is never clean.
      final again = next(
        changed,
        await answer(orderJson(3, bond: other), invoices: [other]),
      );
      expect(again.has<InvoiceHashChanged>(), isTrue);
      // The first invoice again is fine.
      final back = next(
        again,
        await answer(orderJson(3), invoices: [bondInvoice()]),
      );
      expect(back.warnings, isEmpty);
      // The escrow has its own hash.
      final sellerBond = await preTake(terms: seller);
      final escrow = escrowInvoice();
      final sixth = next(
        sellerBond,
        await answer(
          orderJson(6, role: TradeRole.seller, escrow: escrow),
          invoices: [escrow],
        ),
        terms: seller,
      );
      expect(sixth.warnings, isEmpty);
      final swapped = escrowInvoice(seed: 77);
      final seventh = next(
        sixth,
        await answer(
          orderJson(7, role: TradeRole.seller, escrow: swapped),
          invoices: [swapped],
        ),
        terms: seller,
      );
      expect(seventh.has<InvoiceHashChanged>(), isTrue);
    });

    test('a payee it states must be one of the coordinator\'s nodes', () async {
      final ours = await preTake(bond: bondInvoice(payee: templeNode));
      expect(ours.warnings, isEmpty);
      final stranger = await preTake(bond: bondInvoice(payee: strangerNode));
      expect(stranger.has<InvoicePayeeNotCoordinator>(), isTrue);
      expect(checkedOf(stranger).mayShow, isTrue);
      expect(
        walletPaymentFor(
          accepted: Sats.fromInt(bookBond),
          invoice: checkedOf(stranger),
          now: tradeNow,
        ),
        isA<WalletPaymentRefused>(),
      );
    });

    test('a deadline moved back is shown', () async {
      final first = await preTake();
      final earlier = next(
        first,
        await answer(
          orderJson(3, expiresAt: tradeNow.add(const Duration(seconds: 100))),
          invoices: [bondInvoice()],
        ),
      );
      expect(earlier.has<DeadlineMovedBack>(), isTrue);
      expect(checkedOf(earlier).mayShow, isTrue);
      expect(checkedOf(earlier).passedEveryCheck, isFalse);
      final later = next(
        first,
        await answer(
          orderJson(3, expiresAt: tradeNow.add(const Duration(seconds: 300))),
          invoices: [bondInvoice()],
        ),
      );
      expect(later.warnings, isEmpty);
    });
  });

  group('« Pay with this wallet »', () {
    test(
      'at most the amount accepted, never too late, never after a failed check',
      () async {
        final bond = checkedOf(await preTake());
        expect(
          walletPaymentFor(
            accepted: Sats.fromInt(bookBond),
            invoice: bond,
            now: tradeNow,
          ),
          isA<WalletPaymentOffered>(),
        );
        expect(
          walletPaymentFor(
            accepted: Sats.fromInt(bookBond - 1),
            invoice: bond,
            now: tradeNow,
          ),
          isA<WalletPaymentRefused>().having(
            (r) => r.reason,
            'reason',
            WalletPaymentRefusal.aboveAccepted,
          ),
        );
        // The invoice lives until 190 s after the clock, the step as long: refused once less than the margin is left.
        final lastMoment = tradeNow
            .add(const Duration(seconds: 190))
            .subtract(TradeTolerances.walletPaymentMargin);
        expect(
          walletPaymentFor(
            accepted: Sats.fromInt(bookBond),
            invoice: bond,
            now: lastMoment,
          ),
          isA<WalletPaymentOffered>(),
        );
        expect(
          walletPaymentFor(
            accepted: Sats.fromInt(bookBond),
            invoice: bond,
            now: lastMoment.add(const Duration(seconds: 1)),
          ),
          isA<WalletPaymentRefused>().having(
            (r) => r.reason,
            'reason',
            WalletPaymentRefusal.tooLate,
          ),
        );
        // The step's own deadline counts too.
        final shortStep = next(
          null,
          await answer(
            orderJson(3, expiresAt: tradeNow.add(const Duration(seconds: 59))),
            invoices: [bondInvoice()],
          ),
        );
        expect(
          walletPaymentFor(
            accepted: Sats.fromInt(bookBond),
            invoice: checkedOf(shortStep),
            now: tradeNow,
          ),
          isA<WalletPaymentRefused>().having(
            (r) => r.reason,
            'reason',
            WalletPaymentRefusal.tooLate,
          ),
        );
        final stale = checkedOf(
          await preTake(bond: bondInvoice(sats: bookBond * 2)),
        );
        expect(
          walletPaymentFor(
            accepted: Sats.fromInt(bookBond * 3),
            invoice: stale,
            now: tradeNow,
          ),
          isA<WalletPaymentRefused>().having(
            (r) => r.reason,
            'reason',
            WalletPaymentRefusal.checkFailed,
          ),
        );
      },
    );

    test('a refused answer forbids it on the status left in place', () async {
      final bond = await preTake();
      final refused = next(
        bond,
        await answer(orderJson(2, changes: withTaker)),
      );
      expect(refused, isA<WaitingForTakerBond>());
      expect(
        walletPaymentFor(
          accepted: Sats.fromInt(bookBond),
          invoice: checkedOf(refused),
          now: tradeNow,
        ),
        isA<WalletPaymentRefused>(),
      );
      expect(checkedOf(refused).mayShow, isFalse);
    });
  });

  group('properties, over seeded random answers', () {
    /// One random answer for a taker of [terms], from the reference's statuses and from what a lying coordinator could send.
    Future<TradeAnswer> randomAnswer(Random random, TradeTerms terms) async {
      final role = random.nextInt(10) == 0
          ? (terms.role == TradeRole.buyer ? TradeRole.seller : TradeRole.buyer)
          : terms.role;
      final pick = random.nextInt(22);
      if (pick == 19) return const TradeOrderCancelled();
      if (pick == 20) return const TradeOrderNotAvailable();
      const wires = [
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        16,
        17,
        18,
        3,
      ];
      final wire = wires[pick % wires.length];
      final last = bookSats + random.nextInt(6001) - 3000;
      final bondSats = bookBond + random.nextInt(201) - 100;
      final bond = bondInvoice(
        sats: random.nextInt(8) == 0 ? bondSats + 1 : bondSats,
        seed: random.nextInt(3),
        network: random.nextInt(12) == 0
            ? Bolt11Network.testnet
            : Bolt11Network.mainnet,
        age: Duration(seconds: random.nextInt(260)),
        payee: random.nextInt(8) == 0
            ? strangerNode
            : (random.nextBool() ? templeNode : null),
      );
      final escrowSats = escrowOf(last) + random.nextInt(5) - 2;
      final escrow = escrowInvoice(
        sats: escrowSats,
        seed: 2 + random.nextInt(2),
      );
      final unreadable = random.nextInt(10) == 0;
      if (!unreadable) {
        decoder
          ..add(bond)
          ..add(escrow);
      }
      final changes = <String, Object?>{
        if (wire == 0 || wire == 2 || wire == 4) ...withTaker,
        if (random.nextInt(15) == 0) 'premium': '3.00',
        if (wire == 3 && random.nextInt(8) == 0) 'bond_satoshis': bondSats + 7,
        if (wire != 1 && random.nextInt(15) == 0) 'trade_satoshis': last,
        if (random.nextInt(20) == 0) 'satoshis_now': null,
        if (role == TradeRole.seller &&
            (wire == 6 || wire == 7) &&
            random.nextInt(8) == 0)
          'escrow_satoshis': escrowSats + 1,
      };
      return TradeOrderRead(
        await readOrder(
          orderJson(
            wire,
            role: role,
            last: last,
            bond: bond,
            escrow: escrow,
            expiresAt: tradeNow.add(
              Duration(seconds: 30 + random.nextInt(400)),
            ),
            changes: changes,
          ),
        ),
      );
    }

    /// An independent oracle of the checks a payable invoice must have passed: what the coordinator said in [answer] against [terms], the first hash of the step in the run, and the clock.
    bool everyCheckPasses(
      TradeAnswer answer,
      TradeTerms terms,
      CheckedInvoice invoice,
      String? firstHash,
      DateTime now,
    ) {
      if (answer is! TradeOrderRead) return false;
      final order = answer.order;
      final hold = switch (invoice.step) {
        InvoiceStep.bond => order.bondInvoice,
        InvoiceStep.escrow => order.escrowInvoice,
      };
      if (hold == null || hold.invoice != invoice.bolt11) return false;
      final amount = invoice.amount.value.toInt();
      if (amount != hold.satoshis.value.toInt()) return false;
      if (!invoice.facts.network.belongsTo(terms.network)) return false;
      if (now.isAfter(
        invoice.expiresAt.subtract(TradeTolerances.walletPaymentMargin),
      )) {
        return false;
      }
      if (firstHash != null && firstHash != invoice.paymentHash) return false;
      final payee = invoice.facts.payeeNodeKey;
      if (payee != null && !terms.nodeKeys.contains(payee)) return false;
      if (order.isBuyer != (terms.role == TradeRole.buyer)) return false;
      switch (invoice.step) {
        case InvoiceStep.bond:
          if ((amount - terms.expectedBond).abs() >
              terms.expectedBond * 0.02 + 1) {
            return false;
          }
        case InvoiceStep.escrow:
          final last = order.satoshisNow?.value.toInt();
          if (last == null ||
              (last - terms.expectedSatoshis).abs() >
                  terms.expectedSatoshis * 0.02 + 1) {
            return false;
          }
          if (order.tradeSatoshis?.value.toInt() != amount) return false;
          final fee = amount - last;
          if (fee < 0 || fee > last * terms.takerFee + 1) return false;
      }
      return true;
    }

    for (final role in TradeRole.values) {
      test(
        'as $role: never leaves an end, never an unlisted edge without a warning, never pays after a failed check',
        () async {
          final terms = role == TradeRole.buyer ? buyer : seller;
          var offered = 0;
          for (var seed = 0; seed < 150; seed++) {
            final random = Random(seed);
            TradeStatus? status;
            final hashes = <InvoiceStep, String>{};
            var breached = false;
            for (var step = 0; step < 12; step++) {
              final answer = await randomAnswer(random, terms);
              final now = tradeNow.add(
                Duration(seconds: step * random.nextInt(4)),
              );
              final before = status;
              final after = next(before, answer, terms: terms, now: now);
              // Pure: the same input gives the same status.
              expect(
                next(before, answer, terms: terms, now: now).toString(),
                after.toString(),
              );
              final from = before?.position ?? TradePosition.start;
              if (before != null && before.isTerminal) {
                expect(
                  after.position,
                  from,
                  reason: 'seed $seed: left $before',
                );
              }
              if (after.position != from &&
                  !TradeEdges.allows(terms.role, from, after.position)) {
                expect(
                  after.has<TradeStatusUnexpected>(),
                  isTrue,
                  reason: 'seed $seed: $from → ${after.position}',
                );
              }
              if (after.warnings.any((warning) => warning.isBreachOfTrust)) {
                breached = true;
              }
              if (breached &&
                  !identical(after, before) &&
                  after.position != TradePosition.start) {
                expect(
                  after.warnings,
                  isNotEmpty,
                  reason: 'seed $seed: breach forgotten',
                );
              }
              if (after.invoice case final CheckedInvoice invoice) {
                final decision = walletPaymentFor(
                  accepted: Sats.fromInt(1 << 40),
                  invoice: invoice,
                  now: now,
                );
                if (decision is WalletPaymentOffered) {
                  offered++;
                  expect(after.warnings, isEmpty, reason: 'seed $seed');
                  expect(breached, isFalse, reason: 'seed $seed');
                  expect(
                    everyCheckPasses(
                      answer,
                      terms,
                      invoice,
                      hashes[invoice.step],
                      now,
                    ),
                    isTrue,
                    reason: 'seed $seed step $step',
                  );
                }
                hashes.putIfAbsent(invoice.step, () => invoice.paymentHash);
              }
              status = after;
            }
          }
          // The property is not empty: some invoices passed every check.
          expect(offered, greaterThan(0));
        },
      );
    }
  });

  test(
    'nothing printed or logged, and no invoice, hash or key in any text of a status',
    () async {
      final invoices = [bondInvoice(payee: templeNode), escrowInvoice()];
      final statuses = <TradeStatus>[];
      final output = await captureKeyOutput(() async {
        final bond = await preTake(bond: invoices.first);
        statuses
          ..add(bond)
          ..add(next(bond, await answer(orderJson(6))))
          ..add(next(bond, await answer(orderJson(2, changes: withTaker))))
          ..add(
            next(
              await preTake(terms: seller),
              await answer(
                orderJson(6, role: TradeRole.seller, escrow: invoices.last),
                invoices: [invoices.last],
              ),
              terms: seller,
            ),
          );
      });
      final texts = [
        output,
        for (final status in statuses) ...[
          '$status',
          '${status.invoice}',
          '${status.trail}',
          if (status.invoice case final CheckedInvoice checked) ...[
            '${checked.facts}',
            '$checked',
          ],
        ],
        '$buyer',
        '${walletPaymentFor(accepted: Sats.fromInt(bookBond), invoice: checkedOf(statuses.first), now: tradeNow)}',
      ].join('\n');
      for (final invoice in invoices) {
        // Booleans, so that a failure never prints what it found.
        expect(texts.contains(invoice.text), isFalse);
        expect(texts.contains(invoice.text.substring(10, 40)), isFalse);
        expect(texts.contains(invoice.facts.paymentHash), isFalse);
        expect(
          texts.contains(invoice.facts.paymentHash.substring(0, 16)),
          isFalse,
        );
      }
      expect(texts.contains(templeNode), isFalse);
    },
  );
}

/// What makes an answer at 0 or 2 name this robot as the taker, so that the package's parser lets it through to the state machine.
final Map<String, Object?> withTaker = {
  'taker': 8,
  'taker_hash_id': us.hashId.hex,
  'taker_nick': us.nickname,
};

int _wireOf(TradePosition position) => switch (position) {
  TradePosition.bondStep => 3,
  TradePosition.waitingForBoth => 6,
  TradePosition.waitingForEscrow => 7,
  TradePosition.waitingForPayout => 8,
  TradePosition.chatting => 9,
  TradePosition.fiatSent => 10,
  TradePosition.inDispute => 11,
  TradePosition.sendingSats => 13,
  TradePosition.succeeded => 14,
  TradePosition.routingFailed => 15,
  TradePosition.waitingDisputeResolution => 16,
  TradePosition.makerLostDispute => 17,
  TradePosition.takerLostDispute => 18,
  TradePosition.expired => 5,
  TradePosition.publicAgain => 1,
  TradePosition.start ||
  TradePosition.cancelled ||
  TradePosition.notAvailable => throw StateError('$position'),
};

final class _Answering implements Bolt11Decoder {
  final Result<Bolt11Invoice, Bolt11Refusal> answer;

  const _Answering(this.answer);

  @override
  Result<Bolt11Invoice, Bolt11Refusal> decode(String invoice) => answer;
}

final class _Throwing implements Bolt11Decoder {
  const _Throwing();

  @override
  Result<Bolt11Invoice, Bolt11Refusal> decode(String invoice) =>
      throw const FormatException('broken');
}
