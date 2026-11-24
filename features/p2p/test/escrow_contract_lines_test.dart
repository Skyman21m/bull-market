import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/trade/escrow_contract.dart';
import 'package:p2p/src/ui/trade/escrow_contract_lines.dart';

import 'support/harness.dart';

/// The alerts of the confirmation of a maker seller's escrow about the order's earlier escrows (#187, the owner's decision of 2026-11-19: no lock, an alert), composed in English and French: no screen shows them before #188, so they are tested here.
void main() {
  EarlierEscrow escrow(int take, EarlierEscrowCase state, int? sats) =>
      EarlierEscrow(
        take: take,
        state: state,
        sats: sats == null ? null : Sats.fromInt(sats),
        progress: null,
      );

  Future<List<EarlierEscrowAlert>> alertsOf(
    WidgetTester tester,
    EscrowContract contract, {
    Locale locale = const Locale('en'),
  }) async {
    late List<EarlierEscrowAlert> lines;
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) {
            lines = earlierEscrowAlerts(
              context,
              contract,
              coordinator: 'Temple of Sats',
            );
            return const SizedBox.shrink();
          },
        ),
        locale: locale,
      ),
    );
    return lines;
  }

  /// The alerts' lines, each with its bold line before it when it has one (#250).
  Future<List<String>> linesOf(
    WidgetTester tester,
    EscrowContract contract, {
    Locale locale = const Locale('en'),
  }) async => [
    for (final alert in await alertsOf(tester, contract, locale: locale))
      [?alert.title, alert.line].join(' / '),
  ];

  testWidgets(
    'earlier escrows not back: their sats and what will be out with this one; one kept: said apart, with the coordinator; one back: nothing',
    (tester) async {
      final contract = EscrowContract(
        take: 3,
        escrow: Sats.fromInt(196127),
        earlier: [
          escrow(0, EarlierEscrowCase.notBack, 196127),
          escrow(1, EarlierEscrowCase.back, 196127),
          escrow(2, EarlierEscrowCase.kept, 196000),
        ],
      );
      expect(contract.notBackSats, Sats.fromInt(196127));
      expect(contract.outIfPaid, Sats.fromInt(392254));
      // One earlier collateral not back, of a known amount: the two lines the owner validated on 2026-11-24, its explanation for the detail (#250).
      expect(await alertsOf(tester, contract), [
        const EarlierEscrowAlert(
          'With this one, 392,254 sats will be out of this wallet.',
          title: 'A previous collateral has not come back',
          detail:
              'You already paid, or tried to pay, a collateral of 196,127 sats for this order with this wallet. It has not come back to it yet.',
        ),
        const EarlierEscrowAlert(
          'The collateral of an earlier take (196,000 sats) was kept by Temple of Sats: check this order in the official RoboSats app before paying another one.',
        ),
      ]);
      final french = await alertsOf(
        tester,
        contract,
        locale: const Locale('fr'),
      );
      expect(french, hasLength(2));
      expect(french.first.title, 'Une garantie précédente n’est pas revenue');
      expect(french.first.line, startsWith('Avec celle-ci, 392'));
      expect(
        french.first.line,
        endsWith('sats seront hors de ce portefeuille.'),
      );
      expect(
        french.first.detail,
        allOf(
          startsWith(
            'Vous avez déjà payé, ou tenté de payer, une garantie de 196',
          ),
          endsWith(
            'sats pour cet ordre avec ce portefeuille. Elle n’y est pas encore revenue.',
          ),
        ),
      );
      expect(french.last.title, isNull);
      expect(french.last.line, contains('a été encaissée par Temple of Sats'));
      for (final alert in [...french, ...await alertsOf(tester, contract)]) {
        for (final line in [?alert.title, alert.line, ?alert.detail]) {
          expect(line, isNot(contains('Troc')));
          expect(line, isNot(contains('Boltz')));
          expect(line, isNot(contains('another wallet')));
        }
      }
    },
  );

  testWidgets(
    'sats not known after the app started again: said as such, « at least », never as 0; a kept one without its sats',
    (tester) async {
      final contract = EscrowContract(
        take: 2,
        escrow: Sats.fromInt(1000),
        earlier: [
          escrow(0, EarlierEscrowCase.notBack, null),
          escrow(1, EarlierEscrowCase.kept, null),
        ],
      );
      expect(await linesOf(tester, contract), [
        'An earlier collateral of this order, paid or attempted with this wallet, has not come back yet; this device no longer knows its amount. With this one, at least 1,000 sats will be out of this wallet for the collaterals of this order, bond not included.',
        'The collateral of an earlier take was kept by Temple of Sats: check this order in the official RoboSats app before paying another one.',
      ]);
    },
  );

  testWidgets(
    'some sats known, some not: the known ones, how many are not, « at least »',
    (tester) async {
      final contract = EscrowContract(
        take: 3,
        escrow: Sats.fromInt(1000),
        earlier: [
          escrow(0, EarlierEscrowCase.notBack, null),
          escrow(1, EarlierEscrowCase.notBack, null),
          escrow(2, EarlierEscrowCase.notBack, 2000),
        ],
      );
      expect(await linesOf(tester, contract), [
        'An earlier collateral of this order, paid or attempted with this wallet, has not come back yet: 2,000 sats, and 2 more whose amounts this device no longer knows. With this one, at least 3,000 sats will be out of this wallet for the collaterals of this order, bond not included.',
      ]);
    },
  );

  testWidgets(
    'two earlier escrows not back, known: the plural, in English and French',
    (tester) async {
      final contract = EscrowContract(
        take: 2,
        escrow: Sats.fromInt(196654),
        earlier: [
          escrow(0, EarlierEscrowCase.notBack, 196654),
          escrow(1, EarlierEscrowCase.notBack, 196654),
        ],
      );
      expect(await linesOf(tester, contract), [
        '2 earlier collaterals of this order, paid or attempted with this wallet, have not come back yet: 393,308 sats. With this one, 589,962 sats will be out of this wallet for the collaterals of this order, bond not included.',
      ]);
      expect(
        (await linesOf(tester, contract, locale: const Locale('fr'))).single,
        startsWith(
          '2 garanties précédentes de cet ordre, payées ou tentées avec ce portefeuille, ne sont pas encore revenues',
        ),
      );
    },
  );

  testWidgets('nothing earlier, or all back: no alert', (tester) async {
    expect(
      await linesOf(
        tester,
        EscrowContract(
          take: 1,
          escrow: Sats.fromInt(1000),
          earlier: [escrow(0, EarlierEscrowCase.back, 1000)],
        ),
      ),
      isEmpty,
    );
  });
}
