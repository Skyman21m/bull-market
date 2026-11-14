import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_answer.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart';
import 'package:p2p/src/domain/trade/trade_storable.dart';
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

/// When the trades of the tests were taken.
final takenAt = tradeNow.subtract(const Duration(seconds: 5));

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

  /// The status after [answer]; with no [previous], the first read after the take.
  TradeStatus next(
    TradeStatus? previous,
    TradeAnswer answer, {
    TradeTerms? terms,
    DateTime? now,
  }) => TradeStatus.from(
    previous:
        previous ??
        TradeStatus.beforeFirstRead(
          TradeTrail.forPendingTake(terms ?? buyer, takenAt),
        ),
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
    decoder.add(invoice);
    // The first status of a trade comes from the take's own answer.
    return TradeStatus.afterTake(
      await takeStarted(
        orderJson(3, bond: invoice, role: (terms ?? buyer).role),
      ),
      terms: terms ?? buyer,
      now: now ?? tradeNow,
      reader: reader,
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
          status: status,
          step: InvoiceStep.bond,
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

      // Error 1044 during the pre-take is not an end until the pre-take is certainly gone: the maker may have paused the order.
      final onHold = next(bond, const TradeOrderNotAvailable());
      expect(onHold, isA<PreTakeUnavailable>());
      expect(onHold.isTerminal, isFalse);
      final gone = tradeNow
          .add(const Duration(seconds: 190))
          .add(TradeTolerances.coordinatorLoops);
      expect((onHold as PreTakeUnavailable).finalFrom, gone);
      final stillOnHold = next(
        onHold,
        const TradeOrderNotAvailable(),
        now: gone.subtract(const Duration(seconds: 1)),
      );
      expect(stillOnHold, isA<PreTakeUnavailable>());
      final lost = next(stillOnHold, const TradeOrderNotAvailable(), now: gone);
      expect(lost, isA<TakenByAnother>());
      expect((lost as TakenByAnother).bondMayHaveBeenLost, isFalse);
      expect(
        next(bond, const TradeOrderNotAvailable(), now: gone),
        isA<TakenByAnother>(),
      );

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
      final cancelledLate = next(bond, const TradeOrderCancelled(), now: late);
      expect((cancelledLate as Cancelled).bondMayHaveBeenLost, isTrue);
      final justBefore = late.subtract(const Duration(seconds: 1));
      final endedBefore = next(
        bond,
        await answer(orderJson(1)),
        now: justBefore,
      );
      expect((endedBefore as PreTakeEnded).bondMayHaveBeenLost, isFalse);
      final cancelledBefore = next(
        bond,
        const TradeOrderCancelled(),
        now: justBefore,
      );
      expect((cancelledBefore as Cancelled).bondMayHaveBeenLost, isFalse);

      // Right after the take, nothing can have been locked; after recovery, nothing can be said.
      expect(
        (next(null, await answer(orderJson(1))) as PreTakeEnded)
            .bondMayHaveBeenLost,
        isFalse,
      );
      expect(
        (next(null, const TradeOrderCancelled()) as Cancelled)
            .bondMayHaveBeenLost,
        isFalse,
      );
      final recovered = TradeStatus.beforeFirstRead(
        TradeTrail.recovered(buyer, tradeNow),
      );
      final foundPublic = next(recovered, await answer(orderJson(1)));
      expect((foundPublic as PreTakeEnded).bondMayHaveBeenLost, isTrue);
      expect(foundPublic.has<TradeHistoryUnknown>(), isTrue);
      final afterTake = next(null, const TradeOrderNotAvailable());
      expect(afterTake, isA<PreTakeUnavailable>());
      // Before any pre-take was read, the latest a pre-take can live.
      expect(
        (afterTake as PreTakeUnavailable).finalFrom,
        takenAt
            .add(TradeTolerances.longestPreTake)
            .add(TradeTolerances.coordinatorLoops),
      );

      // After the bond locked, every way back to the book settles it.
      final both = next(bond, await answer(orderJson(6)));
      final forfeited = next(both, await answer(orderJson(1)));
      expect(forfeited, isA<BondForfeited>());
      expect(forfeited.position, TradePosition.publicAgain);
      expect(forfeited.warnings, isEmpty);
      final outOfReach = next(both, const TradeOrderNotAvailable());
      expect(outOfReach, isA<BondForfeited>());
      expect(outOfReach.position, TradePosition.notAvailable);
      // A cancel after 6, 7 or 8 may follow a bond settled in between.
      final cancelledAfterBond = next(both, const TradeOrderCancelled());
      expect((cancelledAfterBond as Cancelled).bondMayHaveBeenLost, isTrue);
      final chat = next(both, await answer(orderJson(9)));
      final cancelledInChat = next(chat, const TradeOrderCancelled());
      expect((cancelledInChat as Cancelled).bondMayHaveBeenLost, isFalse);
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
        final gone = tradeNow.add(const Duration(minutes: 10));
        final taken = next(bond, const TradeOrderNotAvailable(), now: gone);
        expect(taken, isA<TakenByAnother>());
        expect(
          identical(
            next(taken, const TradeOrderNotAvailable(), now: gone),
            taken,
          ),
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
        TradePosition.notAvailable ||
        TradePosition.preTakeUnavailable => const TradeOrderNotAvailable(),
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
      if (position == TradePosition.start) {
        return TradeStatus.beforeFirstRead(
          TradeTrail.forPendingTake(terms, takenAt),
        );
      }
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
              // Error 1044 at the pre-take is final once the pre-take is certainly gone.
              final to = next(
                from,
                await answerAt(target, terms),
                terms: terms,
                now: target == TradePosition.notAvailable
                    ? tradeNow.add(const Duration(minutes: 10))
                    : tradeNow,
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

    test(
      'the steps are exactly those of the reference, as written out here apart from the table',
      () {
        const b = TradeRole.buyer;
        const s = TradeRole.seller;
        TradePosition at(String name) => TradePosition.values.byName(name);
        // (from, to, roles), written out from the reference (see `trade_edges.dart` for the lines of each).
        const listed = <(String, String, Set<TradeRole>)>[
          ('start', 'bondStep', {b, s}),
          ('start', 'publicAgain', {b, s}),
          ('start', 'preTakeUnavailable', {b, s}),
          ('start', 'cancelled', {b, s}),
          ('bondStep', 'waitingForBoth', {b, s}),
          ('bondStep', 'publicAgain', {b, s}),
          ('bondStep', 'preTakeUnavailable', {b, s}),
          ('bondStep', 'notAvailable', {b, s}),
          ('bondStep', 'cancelled', {b, s}),
          ('preTakeUnavailable', 'bondStep', {b, s}),
          ('preTakeUnavailable', 'waitingForBoth', {b, s}),
          ('preTakeUnavailable', 'publicAgain', {b, s}),
          ('preTakeUnavailable', 'notAvailable', {b, s}),
          ('preTakeUnavailable', 'cancelled', {b, s}),
          ('waitingForBoth', 'waitingForEscrow', {b, s}),
          ('waitingForBoth', 'waitingForPayout', {b, s}),
          ('waitingForBoth', 'chatting', {b, s}),
          ('waitingForBoth', 'expired', {b, s}),
          ('waitingForBoth', 'publicAgain', {b, s}),
          ('waitingForBoth', 'cancelled', {b, s}),
          ('waitingForEscrow', 'chatting', {b, s}),
          ('waitingForEscrow', 'expired', {b, s}),
          ('waitingForEscrow', 'publicAgain', {b, s}),
          ('waitingForEscrow', 'cancelled', {b, s}),
          ('waitingForPayout', 'chatting', {b, s}),
          ('waitingForPayout', 'expired', {b, s}),
          ('waitingForPayout', 'publicAgain', {b}),
          ('waitingForPayout', 'cancelled', {b, s}),
          ('chatting', 'fiatSent', {b, s}),
          ('chatting', 'inDispute', {b, s}),
          ('chatting', 'cancelled', {b, s}),
          ('chatting', 'expired', {b, s}),
          ('fiatSent', 'chatting', {b, s}),
          ('fiatSent', 'inDispute', {b, s}),
          ('fiatSent', 'sendingSats', {b, s}),
          ('fiatSent', 'succeeded', {b, s}),
          ('fiatSent', 'expired', {b, s}),
          ('inDispute', 'waitingDisputeResolution', {b, s}),
          ('inDispute', 'takerLostDispute', {b, s}),
          ('inDispute', 'makerLostDispute', {b, s}),
          ('inDispute', 'cancelled', {b, s}),
          ('inDispute', 'sendingSats', {b, s}),
          ('waitingDisputeResolution', 'takerLostDispute', {b, s}),
          ('waitingDisputeResolution', 'makerLostDispute', {b, s}),
          ('waitingDisputeResolution', 'cancelled', {b, s}),
          ('waitingDisputeResolution', 'sendingSats', {b, s}),
          ('publicAgain', 'notAvailable', {b, s}),
          ('publicAgain', 'cancelled', {b, s}),
          ('sendingSats', 'succeeded', {b, s}),
          ('sendingSats', 'routingFailed', {b, s}),
          ('routingFailed', 'sendingSats', {b, s}),
          ('routingFailed', 'succeeded', {b, s}),
        ];
        final table = {
          for (final MapEntry(key: from, value: targets)
              in TradeEdges.steps.entries)
            for (final MapEntry(key: to, value: roles) in targets.entries)
              (from, to): roles,
        };
        expect(table.length, listed.length);
        for (final (from, to, roles) in listed) {
          expect(table[(at(from), at(to))], roles, reason: '$from → $to');
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
        (TradeRole.buyer, TradePosition.start, TradePosition.waitingForBoth),
        (TradeRole.buyer, TradePosition.start, TradePosition.succeeded),
        (TradeRole.seller, TradePosition.start, TradePosition.notAvailable),
        (
          TradeRole.seller,
          TradePosition.waitingForPayout,
          TradePosition.publicAgain,
        ),
        (TradeRole.buyer, TradePosition.chatting, TradePosition.bondStep),
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
      expect(first, isA<StatusUnknown>());
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
        // On testnet, only `lntb` belongs: a signet invoice is another network (#113).
        final testnet = await tradeTerms(network: RobosatsNetwork.testnet);
        for (final (network, belongs) in [
          (Bolt11Network.testnet, true),
          (Bolt11Network.signet, false),
          (Bolt11Network.mainnet, false),
        ]) {
          final invoice = bondInvoice(network: network);
          decoder.add(invoice);
          final status = TradeStatus.from(
            previous: TradeStatus.beforeFirstRead(
              TradeTrail.forPendingTake(testnet, takenAt),
            ),
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
      // The first invoice again may be shown, but a coordinator that swapped an invoice is never trusted again: the wallet never pays on this trade.
      final back = next(
        again,
        await answer(orderJson(3), invoices: [bondInvoice()]),
      );
      expect(back.warnings.map((warning) => warning.runtimeType), [
        CoordinatorInconsistent,
      ]);
      expect(checkedOf(back).mayShow, isTrue);
      expect(
        walletPaymentFor(
          accepted: Sats.fromInt(bookBond),
          status: back,
          step: InvoiceStep.bond,
          now: tradeNow,
        ),
        isA<WalletPaymentRefused>(),
      );
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
          status: stranger,
          step: checkedOf(stranger).step,
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
        final bond = await preTake();
        expect(
          walletPaymentFor(
            accepted: Sats.fromInt(bookBond),
            status: bond,
            step: InvoiceStep.bond,
            now: tradeNow,
          ),
          isA<WalletPaymentOffered>(),
        );
        expect(
          walletPaymentFor(
            accepted: Sats.fromInt(bookBond - 1),
            status: bond,
            step: InvoiceStep.bond,
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
            status: bond,
            step: InvoiceStep.bond,
            now: lastMoment,
          ),
          isA<WalletPaymentOffered>(),
        );
        expect(
          walletPaymentFor(
            accepted: Sats.fromInt(bookBond),
            status: bond,
            step: InvoiceStep.bond,
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
            status: shortStep,
            step: checkedOf(shortStep).step,
            now: tradeNow,
          ),
          isA<WalletPaymentRefused>().having(
            (r) => r.reason,
            'reason',
            WalletPaymentRefusal.tooLate,
          ),
        );
        final stale = await preTake(bond: bondInvoice(sats: bookBond * 2));
        expect(
          walletPaymentFor(
            accepted: Sats.fromInt(bookBond * 3),
            status: stale,
            step: InvoiceStep.bond,
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

    test(
      'an offer carries the wallet\'s invoice: the exact text, amount, network, hash and deadline',
      () async {
        final bond = await preTake();
        final offer = walletPaymentFor(
          accepted: Sats.fromInt(bookBond),
          status: bond,
          step: InvoiceStep.bond,
          now: tradeNow,
        );
        if (offer is! WalletPaymentOffered) fail('not offered: $offer');
        final checked = checkedOf(bond);
        final wallet = offer.walletInvoice;
        expect(wallet.bolt11, checked.bolt11);
        expect(wallet.bolt11, bondInvoice().text);
        expect(wallet.amount, checked.amount);
        expect(wallet.network, RobosatsNetwork.mainnet);
        expect(wallet.paymentHash, checked.paymentHash);
        expect(wallet.paymentHash, bondInvoice().facts.paymentHash);
        expect(wallet.expiresAt, checked.expiresAt);
        expect(wallet.payableUntil, checked.payableUntil);
        // The step ends before the invoice here: the earlier of the two.
        final shortStep = next(
          null,
          await answer(
            orderJson(3, expiresAt: tradeNow.add(const Duration(seconds: 90))),
            invoices: [bondInvoice()],
          ),
        );
        final short = walletPaymentFor(
          accepted: Sats.fromInt(bookBond),
          status: shortStep,
          step: InvoiceStep.bond,
          now: tradeNow,
        );
        if (short is! WalletPaymentOffered) fail('not offered: $short');
        expect(
          short.walletInvoice.payableUntil,
          tradeNow.add(const Duration(seconds: 90)),
        );
        expect(
          short.walletInvoice.payableUntil.isBefore(
            short.walletInvoice.expiresAt,
          ),
          isTrue,
        );
      },
    );

    test(
      'the wallet invoice\'s own strict reading is a second check: an amount written with a leading zero is never offered',
      () async {
        // The decoder of the test reads it as the bond's amount, as a lenient decoder would; the wallet's type refuses its text.
        final lenient = Bolt11TestInvoice(
          network: Bolt11Network.mainnet,
          sats: bookBond,
          seed: 1,
          createdAt: tradeNow.subtract(const Duration(seconds: 10)),
          expiry: const Duration(seconds: 200),
          amountText: '0${bookBond * 10}n',
        );
        final status = await preTake(bond: lenient);
        expect(checkedOf(status).passedEveryCheck, isTrue);
        expect(
          walletPaymentFor(
            accepted: Sats.fromInt(bookBond),
            status: status,
            step: InvoiceStep.bond,
            now: tradeNow,
          ),
          isA<WalletPaymentRefused>().having(
            (r) => r.reason,
            'reason',
            WalletPaymentRefusal.walletRefused,
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
          status: refused,
          step: checkedOf(refused).step,
          now: tradeNow,
        ),
        isA<WalletPaymentRefused>(),
      );
      expect(checkedOf(refused).mayShow, isFalse);
    });
  });

  group('properties, over seeded random answers', () {
    /// One random answer, as generated, with what the generator knows of it: whether it lies about the role, shows a status a taker is never shown, or changes the order's terms.
    Future<
      ({
        TradeAnswer answer,
        bool lies,
        int? wire,
        bool termsChanged,
        int? bondSats,
        int? escrowSats,
      })
    >
    randomAnswer(Random random, TradeTerms terms, DateTime now) async {
      final flipped = random.nextInt(10) == 0;
      final role = flipped
          ? (terms.role == TradeRole.buyer ? TradeRole.seller : TradeRole.buyer)
          : terms.role;
      final pick = random.nextInt(22);
      if (pick == 19) {
        return (
          answer: const TradeOrderCancelled() as TradeAnswer,
          lies: false,
          wire: null,
          termsChanged: false,
          bondSats: null,
          escrowSats: null,
        );
      }
      if (pick == 20) {
        return (
          answer: const TradeOrderNotAvailable() as TradeAnswer,
          lies: false,
          wire: null,
          termsChanged: false,
          bondSats: null,
          escrowSats: null,
        );
      }
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
        6,
        7,
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
        age: tradeNow.difference(now) + Duration(seconds: random.nextInt(260)),
        payee: random.nextInt(8) == 0
            ? strangerNode
            : (random.nextBool() ? templeNode : null),
      );
      final escrowSats = escrowOf(last) + random.nextInt(5) - 2;
      final escrow = Bolt11TestInvoice(
        network: Bolt11Network.mainnet,
        sats: escrowSats,
        seed: 2 + random.nextInt(2),
        createdAt: now.subtract(Duration(seconds: random.nextInt(3600))),
        expiry: const Duration(seconds: 10800),
      );
      if (random.nextInt(10) != 0) {
        decoder
          ..add(bond)
          ..add(escrow);
      }
      final termsChanged = random.nextInt(15) == 0;
      final changes = <String, Object?>{
        if (wire == 0 || wire == 2 || wire == 4) ...withTaker,
        if (termsChanged) 'premium': '3.00',
        if (wire == 3 && random.nextInt(8) == 0) 'bond_satoshis': bondSats + 7,
        if (wire != 1 && random.nextInt(15) == 0) 'trade_satoshis': last,
        if (random.nextInt(20) == 0) 'satoshis_now': null,
        if (role == TradeRole.seller &&
            (wire == 6 || wire == 7) &&
            random.nextInt(8) == 0)
          'escrow_satoshis': escrowSats + 1,
      };
      final answer = TradeOrderRead(
        await readOrder(
          orderJson(
            wire,
            role: role,
            last: last,
            bond: bond,
            escrow: escrow,
            expiresAt: now.add(Duration(seconds: 30 + random.nextInt(400))),
            changes: changes,
          ),
        ),
      );
      return (
        answer: answer as TradeAnswer,
        lies: flipped && wire != 1,
        wire: wire,
        termsChanged: termsChanged,
        bondSats: bondSats,
        escrowSats: escrowSats,
      );
    }

    /// The oracle: whether an invoice the wallet was offered passes every check, computed apart from the code under test, from what the generator made, the trade's terms, what the run saw before and the clock.
    bool payable({
      required TradeAnswer answer,
      required TradeTerms terms,
      required CheckedInvoice invoice,
      required String? firstHash,
      required DateTime? lastDeadlineHere,
      required int accepted,
      required DateTime now,
    }) {
      if (answer is! TradeOrderRead) return false;
      final order = answer.order;
      final hold = switch (invoice.step) {
        InvoiceStep.bond => order.bondInvoice,
        InvoiceStep.escrow => order.escrowInvoice,
      };
      if (hold == null || hold.invoice != invoice.bolt11) return false;
      final amount = invoice.amount.value.toInt();
      if (amount != hold.satoshis.value.toInt() || amount > accepted) {
        return false;
      }
      if (!invoice.facts.network.belongsTo(terms.network)) return false;
      final margin = TradeTolerances.walletPaymentMargin;
      if (invoice.expiresAt.difference(now) < margin) return false;
      if (order.expiresAt.difference(now) < margin) return false;
      if (lastDeadlineHere != null &&
          order.expiresAt.isBefore(lastDeadlineHere)) {
        return false;
      }
      if (firstHash != null && firstHash != invoice.paymentHash) return false;
      final payee = invoice.facts.payeeNodeKey;
      if (payee != null && !terms.nodeKeys.contains(payee)) return false;
      if (order.isMaker || order.isBuyer != (terms.role == TradeRole.buyer)) {
        return false;
      }
      if (order.currency != terms.currency ||
          (order.premium?.percent ?? terms.premium.percent) !=
              terms.premium.percent ||
          order.bondSize.percent != terms.bondSize.percent ||
          order.escrowDuration != terms.escrowDuration) {
        return false;
      }
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

    /// A step of the clock: seconds, minutes or hours.
    Duration tick(Random random) => switch (random.nextInt(4)) {
      0 => Duration(seconds: random.nextInt(10)),
      1 => Duration(seconds: random.nextInt(120)),
      2 => Duration(minutes: random.nextInt(60)),
      _ => Duration(hours: random.nextInt(4)),
    };

    for (final role in TradeRole.values) {
      test(
        'as $role: never leaves an end, never an unlisted edge without a warning, never pays after a failed check, and a restored trail decides as the original',
        () async {
          final terms = role == TradeRole.buyer ? buyer : seller;
          var offered = 0;
          var restarts = 0;
          for (var seed = 0; seed < 150; seed++) {
            final random = Random(seed);
            // A quarter of the runs is of a trade found by recovery, on which the wallet never pays.
            final recoveredRun = seed % 4 == 3;
            TradeStatus status = TradeStatus.beforeFirstRead(
              recoveredRun
                  ? TradeTrail.recovered(terms, takenAt)
                  : TradeTrail.forPendingTake(terms, takenAt),
            );
            final records = <TradeTrailRecord>[status.trail.record];
            var now = tradeNow;
            final hashes = <InvoiceStep, String>{};
            final deadlines = <TradePosition, DateTime>{};
            // The oracle's own memory of a breach: what the generator knows it sent.
            var breached = false;
            var lastFrom = TradePosition.start;
            for (var step = 0; step < 12; step++) {
              now = now.add(tick(random));
              final made = await randomAnswer(random, terms, now);
              final answer = made.answer;
              final before = status;
              final after = next(before, answer, terms: terms, now: now);
              // Pure: the same input gives the same status.
              expect(
                next(before, answer, terms: terms, now: now).toString(),
                after.toString(),
              );
              final from = before.position;
              if (before.isTerminal) {
                expect(
                  after.position,
                  from,
                  reason: 'seed $seed: left $before',
                );
              }
              if (after.position != from &&
                  !(before.trail.historyUnknown &&
                      from == TradePosition.start) &&
                  !TradeEdges.allows(terms.role, from, after.position)) {
                expect(
                  after.has<TradeStatusUnexpected>(),
                  isTrue,
                  reason: 'seed $seed: $from → ${after.position}',
                );
              }
              // A restored trail is the trail, and decides the next read as the original does.
              final restored = switch (TradeTrail.restore(
                after.trail.record,
                terms: terms,
                now: now,
              )) {
                Ok(:final value) => value,
                Err(:final failure) => fail('seed $seed: $failure'),
              };
              expect(restored, after.trail);
              // Every trail a run writes may replace the one before it; a trail of an earlier read never replaces a later one.
              final record = after.trail.record;
              expect(
                record.whyNotReplace(records.last),
                isNull,
                reason: 'seed $seed step $step',
              );
              for (final earlier in records) {
                if (earlier.readAtMicros < record.readAtMicros) {
                  expect(earlier.mayReplace(record), isFalse);
                }
              }
              records.add(record);
              var restartedHere = false;
              if (!after.isTerminal && step < 11 && random.nextInt(3) == 0) {
                restarts++;
                restartedHere = true;
                final probe = await randomAnswer(
                  Random(seed * 100 + step),
                  terms,
                  now,
                );
                final viaOriginal = next(
                  after,
                  probe.answer,
                  terms: terms,
                  now: now,
                );
                final viaRestored = next(
                  TradeStatus.beforeFirstRead(restored),
                  probe.answer,
                  terms: terms,
                  now: now,
                );
                expect(
                  viaRestored.trail,
                  viaOriginal.trail,
                  reason: 'seed $seed',
                );
                expect(viaRestored.position, viaOriginal.position);
                WalletPaymentRefusal? decided(TradeStatus s) {
                  final step = s.invoice?.step;
                  if (step == null) return WalletPaymentRefusal.noInvoice;
                  return switch (walletPaymentFor(
                    accepted: Sats.fromInt(1 << 40),
                    status: s,
                    step: step,
                    now: now,
                  )) {
                    WalletPaymentRefused(:final reason) => reason,
                    WalletPaymentOffered() => null,
                  };
                }

                // Offered after a restart exactly when offered without one.
                expect(
                  decided(viaRestored) == null,
                  decided(viaOriginal) == null,
                  reason: 'seed $seed',
                );
              }

              // The oracle's breach: a lie about the role, a status never shown, an unlisted edge, back to the bond step, another invoice in a step.
              final wire = made.wire;
              if (made.lies ||
                  (wire != null && const [0, 2, 4, 12].contains(wire)) ||
                  (wire == 3 &&
                      !const [
                        TradePosition.start,
                        TradePosition.bondStep,
                        TradePosition.preTakeUnavailable,
                      ].contains(lastFrom))) {
                breached = true;
              }
              // Where the answer meant to go, worked out from what was generated.
              final TradePosition? meant = switch (answer) {
                TradeOrderCancelled() => TradePosition.cancelled,
                TradeOrderNotAvailable() =>
                  const [
                        TradePosition.start,
                        TradePosition.bondStep,
                        TradePosition.preTakeUnavailable,
                      ].contains(lastFrom)
                      ? null
                      : TradePosition.notAvailable,
                TradeOrderRead() => switch (wire) {
                  1 => TradePosition.publicAgain,
                  0 || 2 || 4 || 12 || null => null,
                  final shown => TradePosition.values.firstWhere(
                    (position) => _wireOrNull(position) == shown,
                  ),
                },
              };
              if (meant != null &&
                  meant != lastFrom &&
                  !TradeEdges.allows(terms.role, lastFrom, meant)) {
                breached = true;
              }
              final invoice = after.invoice;
              if (!identical(after, before) && invoice is CheckedInvoice) {
                final first = hashes[invoice.step];
                if (first != null && first != invoice.paymentHash) {
                  breached = true;
                }
                final amount = invoice.amount.value.toInt();
                // Accepted near the real amounts, so that the cap is exercised both ways.
                final accepted = amount + random.nextInt(7) - 3;
                final decision = walletPaymentFor(
                  accepted: Sats.fromInt(accepted),
                  status: after,
                  step: invoice.step,
                  now: now,
                );
                if (decision is WalletPaymentOffered) {
                  offered++;
                  expect(recoveredRun, isFalse, reason: 'seed $seed');
                  expect(breached, isFalse, reason: 'seed $seed step $step');
                  expect(made.termsChanged, isFalse, reason: 'seed $seed');
                  expect(
                    payable(
                      answer: answer,
                      terms: terms,
                      invoice: invoice,
                      firstHash: first,
                      lastDeadlineHere: deadlines[after.position],
                      accepted: accepted,
                      now: now,
                    ),
                    isTrue,
                    reason: 'seed $seed step $step',
                  );
                }
                hashes.putIfAbsent(invoice.step, () => invoice.paymentHash);
              }
              if (answer case TradeOrderRead(
                :final order,
              ) when !identical(after, before)) {
                deadlines[after.position] = order.expiresAt;
              }
              lastFrom = after.position;
              // After a restart, the run goes on from the restored trail.
              status = restartedHere
                  ? TradeStatus.beforeFirstRead(restored)
                  : after;
            }
          }
          // The properties are not empty: some invoices passed every check, and some trails were restored mid-run.
          expect(offered, greaterThan(0));
          expect(restarts, greaterThan(0));
        },
      );
    }

    test(
      'terms round-trip exactly, and a record that is not one is refused',
      () async {
        final range = await tradeTerms(range: true);
        final testnet = await tradeTerms(network: RobosatsNetwork.testnet);
        for (final terms in [buyer, seller, range, testnet]) {
          expect(switch (TradeTerms.restore(terms.record)) {
            Ok(:final value) => value,
            Err(:final failure) => failure,
          }, terms);
        }
        final r = buyer.record;
        TradeTermsRecord changed({
          int? version,
          String? network,
          String? alias,
          String? role,
          int? type,
          double? takerFee,
          int? escrowSeconds,
          double? bookPrice,
        }) => TradeTermsRecord(
          version: version ?? r.version,
          network: network ?? r.network,
          coordinatorAlias: alias ?? r.coordinatorAlias,
          orderId: r.orderId,
          role: role ?? r.role,
          type: type ?? r.type,
          currencyId: r.currencyId,
          amount: r.amount,
          isRange: r.isRange,
          premiumPercent: r.premiumPercent,
          explicitSatoshis: r.explicitSatoshis,
          bondSizePercent: r.bondSizePercent,
          escrowSeconds: escrowSeconds ?? r.escrowSeconds,
          bookPrice: bookPrice ?? r.bookPrice,
          takerFee: takerFee ?? r.takerFee,
        );
        for (final bad in [
          changed(version: 2),
          changed(network: 'regtest'),
          changed(alias: 'nobody'),
          changed(role: 'seller'),
          changed(type: 0),
          changed(takerFee: 0.0101),
          changed(takerFee: double.nan),
          changed(escrowSeconds: 60),
          changed(bookPrice: 0),
        ]) {
          expect(
            TradeTerms.restore(bad),
            isA<Err<TradeTerms, TradeRecordRefusal>>(),
            reason: '$bad',
          );
        }
      },
    );

    test(
      'a trail record that is not one, or not this trade\'s, is refused',
      () async {
        final r = (await preTake()).trail.record;
        TradeTrailRecord changed({
          int? version,
          String? position,
          String? bondHash,
          int? readAtMicros,
          int? orderId,
          int? bondStepSeenAtMicros,
          int? deadlineMicros,
        }) => TradeTrailRecord(
          version: version ?? r.version,
          network: r.network,
          coordinatorAlias: r.coordinatorAlias,
          orderId: orderId ?? r.orderId,
          role: r.role,
          position: position ?? r.position,
          readAtMicros: readAtMicros ?? r.readAtMicros,
          bondHash: bondHash ?? r.bondHash,
          escrowHash: r.escrowHash,
          deadlineMicros: deadlineMicros ?? r.deadlineMicros,
          bondStepSeenAtMicros: bondStepSeenAtMicros ?? r.bondStepSeenAtMicros,
          bondStepDeadlineMicros: r.bondStepDeadlineMicros,
          breached: r.breached,
          historyUnknown: r.historyUnknown,
        );
        Result<TradeTrail, TradeRecordRefusal> restore(
          TradeTrailRecord record,
        ) => TradeTrail.restore(record, terms: buyer, now: tradeNow);
        expect(restore(r), isA<Ok<TradeTrail, TradeRecordRefusal>>());
        for (final bad in [
          changed(version: 0),
          changed(position: 'somewhere'),
          changed(bondHash: 'F' * 64),
          changed(bondHash: 'f' * 63),
          changed(readAtMicros: -1),
          // A read after the resume, beyond a clock step; a pre-take seen after the last read.
          changed(
            readAtMicros: tradeNow
                .add(TradeTolerances.clockStep)
                .add(const Duration(seconds: 1))
                .microsecondsSinceEpoch,
          ),
          changed(bondStepSeenAtMicros: r.readAtMicros + 1),
          // A time out of range, which only the range check sees (mutant Q33).
          changed(deadlineMicros: -1),
          changed(deadlineMicros: 253402300800000000),
        ]) {
          expect(
            switch (restore(bad)) {
              Err(:final failure) => failure,
              Ok() => null,
            },
            isA<TradeRecordMalformed>(),
            reason: '$bad',
          );
        }
        // Within a clock step ahead, the record is taken.
        expect(
          restore(
            changed(
              readAtMicros: tradeNow
                  .add(TradeTolerances.clockStep)
                  .microsecondsSinceEpoch,
            ),
          ),
          isA<Ok<TradeTrail, TradeRecordRefusal>>(),
        );
        // Another trade's record, or this record with another trade's terms.
        expect(switch (restore(changed(orderId: 43))) {
          Err(:final failure) => failure,
          Ok() => null,
        }, isA<TradeRecordOfAnotherTrade>());
        expect(switch (TradeTrail.restore(r, terms: seller, now: tradeNow)) {
          Err(:final failure) => failure,
          Ok() => null,
        }, isA<TradeRecordOfAnotherTrade>());
      },
    );
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
          '${status.trail.record}',
          if (status.invoice case final CheckedInvoice checked) ...[
            '${checked.facts}',
            '$checked',
          ],
        ],
        '$buyer',
        '${buyer.record}',
        '${walletPaymentFor(accepted: Sats.fromInt(bookBond), status: statuses.first, step: checkedOf(statuses.first).step, now: tradeNow)}',
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

int? _wireOrNull(TradePosition position) => switch (position) {
  TradePosition.start ||
  TradePosition.cancelled ||
  TradePosition.notAvailable ||
  TradePosition.preTakeUnavailable ||
  TradePosition.publicAgain => null,
  _ => _wireOf(position),
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
  TradePosition.notAvailable ||
  TradePosition.preTakeUnavailable => throw StateError('$position'),
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
