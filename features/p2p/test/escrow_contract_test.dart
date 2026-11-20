import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/trade/escrow_contract.dart';
import 'package:test/test.dart';

/// When the contract of a maker seller's escrow, read again under the payment's lock with the quote about to be paid, asks a new confirmation ([EscrowContract.needsNewConfirmation], #187, the owner's decision of 2026-11-19): more out than confirmed, never less.
void main() {
  EarlierEscrow earlier(EarlierEscrowCase state, {int? sats, int take = 0}) =>
      EarlierEscrow(
        take: take,
        state: state,
        sats: sats == null ? null : Sats.fromInt(sats),
        progress: null,
      );

  EscrowContract contract(int escrow, List<EarlierEscrow> earlier) =>
      EscrowContract(take: 1, escrow: Sats.fromInt(escrow), earlier: earlier);

  test(
    'a dearer quote while an earlier escrow came back meanwhile, so a smaller total out: the confirmation is asked again (security review of #187, R11)',
    () {
      final confirmed = contract(196654, [
        earlier(EarlierEscrowCase.notBack, sats: 196654),
      ]);
      final now = contract(197000, [
        earlier(EarlierEscrowCase.back, sats: 196654),
      ]);
      // Less out in all, nothing more not back, nothing kept: only this escrow's quote costs more.
      expect(now.outIfPaid.value < confirmed.outIfPaid.value, isTrue);
      expect(now.notBackSats.value, BigInt.zero);
      expect(confirmed.needsNewConfirmation(now), isTrue);
    },
  );

  test('the same quote, an earlier escrow back meanwhile: it pays', () {
    final confirmed = contract(196654, [
      earlier(EarlierEscrowCase.notBack, sats: 196654),
    ]);
    final now = contract(196654, [
      earlier(EarlierEscrowCase.back, sats: 196654),
    ]);
    expect(confirmed.needsNewConfirmation(now), isFalse);
  });

  test('a cheaper quote, nothing else changed: it pays', () {
    final confirmed = contract(196654, const []);
    expect(confirmed.needsNewConfirmation(contract(196600, const [])), isFalse);
    expect(confirmed.needsNewConfirmation(contract(196655, const [])), isTrue);
  });

  test('an earlier escrow kept since the confirmation: asked again', () {
    final confirmed = contract(196654, [
      earlier(EarlierEscrowCase.notBack, sats: 196654),
    ]);
    final now = contract(196654, [
      earlier(EarlierEscrowCase.kept, sats: 196654),
    ]);
    expect(confirmed.needsNewConfirmation(now), isTrue);
  });
}
