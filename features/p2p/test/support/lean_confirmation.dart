import 'package:bull_ui/bull_ui.dart' show BullTheme;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/presentation/p2p_formats.dart';
import 'package:p2p/src/ui/trade/pay_confirmation_card.dart';
import 'package:p2p/src/ui/widgets/price_check_lines.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';

/// The checks of the lean confirmation of « Pay with this wallet » (#250; layout and words validated by the owner on 2026-11-24), shared by the route tests of the four payments: a maker's bond and a maker seller's collateral (`maker_escrow_route_test.dart`, `maker_sell_route_test.dart`), a taker's bond and a taker seller's collateral (`taken_price_route_test.dart`).
final class LeanConfirmation {
  final WidgetTester tester;
  final Locale locale;

  LeanConfirmation(this.tester, this.locale);

  P2pLocalizations get l10n => lookupP2pLocalizations(locale);

  P2pFormats get formats => P2pFormats(l10n);

  Finder get card => find.byType(PayConfirmationCard);

  Finder inCard(Finder finder) => find.descendant(of: card, matching: finder);

  Finder get goBack => find.byKey(PayConfirmationCard.goBack);

  /// « Pay {total} sats » for [quote].
  Finder payOf(P2pWalletQuote quote) => inCard(
    find.widgetWithText(
      TradeButton,
      l10n.p2pPayConfirm(formats.sats(quote.total.value.toInt())),
    ),
  );

  String sats(Sats amount) =>
      l10n.p2pPayAmountSats(formats.bigSats(amount.value));

  /// The texts of the row of [key], joined.
  String row(Key key) => [
    for (final text in tester.widgetList<Text>(
      find.descendant(of: find.byKey(key), matching: find.byType(Text)),
    ))
      text.data ?? '',
  ].join(' | ');

  /// The card on arrival for [quote]: « Bond » or « Collateral » and the invoice's sats; « Swap and network fees », the swap fee and the network fee added; « Total to pay », what « Pay » takes; « Go back », « Pay {total} sats » and « Show details » under them, the detail closed, no title of the card's own; the rows add up to the sat.
  void expectArrival(P2pWalletQuote quote, {required bool escrow}) {
    expect(card, findsOneWidget);
    expect(
      row(PayConfirmationCard.amountRow),
      '${escrow ? l10n.p2pPayRowCollateral : l10n.p2pPayRowBond} | ${sats(quote.amount)}',
    );
    final fees = Sats(quote.serviceFee.value + quote.networkFee.value);
    expect(
      row(PayConfirmationCard.feesRow),
      '${l10n.p2pPayRowFees} | ${sats(fees)}',
    );
    expect(
      row(PayConfirmationCard.totalRow),
      '${l10n.p2pPayRowTotal} | ${sats(quote.total)}',
    );
    expect(quote.amount.value + fees.value, quote.total.value);
    expect(payOf(quote), findsOneWidget);
    expect(inCard(find.text(l10n.p2pCommonGoBack)), findsOneWidget);
    expect(inCard(find.text(l10n.p2pDetailShow)), findsOneWidget);
    expect(find.byKey(PayConfirmationCard.detail), findsNothing);
    // « sats » in lower case in the card (the owner's vocabulary).
    expect(inCard(find.textContaining('Sats')), findsNothing);
    // From the top: the amounts, the rule's lines, the alerts, the buttons, the link.
    final total = tester.getBottomLeft(
      find.byKey(PayConfirmationCard.totalRow),
    );
    final back = tester.getTopLeft(goBack);
    final pay = tester.getTopLeft(payOf(quote));
    final toggle = tester.getTopLeft(
      find.byKey(PayConfirmationCard.detailToggle),
    );
    expect(total.dy, lessThan(back.dy));
    expect(back.dy, lessThan(pay.dy));
    expect(pay.dy, lessThan(toggle.dy));
  }

  /// Every alert of the card above « Go back », visible without a tap.
  void expectAboveButtons(Finder finder) {
    expect(finder, findsWidgets);
    for (final element in finder.evaluate()) {
      final box = element.renderObject as RenderBox?;
      if (box == null) fail('no box');
      expect(
        box.localToGlobal(Offset.zero).dy,
        lessThan(tester.getTopLeft(goBack).dy),
      );
    }
  }

  /// « Show details » opens the detail under the link, in the card, and « Hide details » closes it: « Go back » and « Pay » stay where they were throughout (a tap meant for the link never lands on « Pay »). [whileOpen] checks the detail while it is open.
  Future<void> toggleDetail(
    P2pWalletQuote quote, {
    void Function()? whileOpen,
  }) async {
    final pay = payOf(quote);
    final before = (tester.getRect(goBack), tester.getRect(pay));
    await tester.tap(inCard(find.text(l10n.p2pDetailShow)));
    await tester.pump();
    final detail = find.byKey(PayConfirmationCard.detail);
    expect(inCard(detail), findsOneWidget);
    expect((tester.getRect(goBack), tester.getRect(pay)), before);
    expect(
      tester.getTopLeft(detail).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byKey(PayConfirmationCard.detailToggle)).dy,
      ),
    );
    expect(
      tester.getTopLeft(detail).dy,
      greaterThan(tester.getBottomLeft(pay).dy),
    );
    whileOpen?.call();
    await tester.tap(inCard(find.text(l10n.p2pDetailHide)));
    await tester.pump();
    expect(detail, findsNothing);
    expect((tester.getRect(goBack), tester.getRect(pay)), before);
  }

  /// The detail's rows for [quote]: the swap fee, the network fee, the balance after payment.
  void expectDetailRows(P2pWalletQuote quote) {
    expect(
      row(PayConfirmationCard.swapFeeRow),
      '${l10n.p2pPayRowSwapFees} | ${sats(quote.serviceFee)}',
    );
    expect(
      row(PayConfirmationCard.networkFeeRow),
      '${l10n.p2pPayRowNetworkFee} | ${sats(quote.networkFee)}',
    );
    expect(
      row(PayConfirmationCard.balanceRow),
      '${l10n.p2pPayRowLeft} | ${sats(quote.remaining)}',
    );
  }

  /// The red alert in two lines in the card: « ⚠ Gap against you » and [gap] in the alert colour, bold, then the figures; never « (indicative) », never the comparison's sentence nor « A small gap is normal ».
  void expectRed(String gap, String figures) {
    final line = inCard(find.byKey(PriceCheckLines.alertRow));
    expect(line, findsOneWidget);
    expect(
      row(PriceCheckLines.alertRow),
      '${l10n.p2pPayoutBreakdownAgainst} | $gap',
    );
    expect(inCard(find.text(figures)), findsOneWidget);
    expect(inCard(find.text(l10n.p2pPayoutBreakdownGap)), findsNothing);
    expectAboveButtons(find.text(figures));
    final error = Theme.of(tester.element(card)).extension<BullTheme>()?.error;
    expect(tester.widget<Text>(inCard(find.text(figures))).style?.color, error);
    expect(
      tester
          .widget<Text>(inCard(find.text(l10n.p2pPayoutBreakdownAgainst)))
          .style
          ?.color,
      error,
    );
  }

  /// No text of the card or its detail cut inside a word, nothing overflowing: for the renders at 320 points and a large text.
  void expectNothingCut(String reason) {
    expect(tester.takeException(), isNull, reason: reason);
    for (final paragraph in tester.renderObjectList<RenderParagraph>(
      find.descendant(of: card, matching: find.byType(RichText)),
    )) {
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: '$reason: ${paragraph.text.toPlainText()}',
      );
      final text = paragraph.text.toPlainText();
      // Each line ends at a word's end: a line break never falls between two letters. Laid out again as the paragraph is, for its lines.
      final painter = TextPainter(
        text: paragraph.text,
        textDirection: paragraph.textDirection,
        textAlign: paragraph.textAlign,
        textScaler: paragraph.textScaler,
        maxLines: paragraph.maxLines,
        strutStyle: paragraph.strutStyle,
        textWidthBasis: paragraph.textWidthBasis,
      )..layout(maxWidth: paragraph.size.width);
      var offset = 0;
      while (offset < text.length) {
        final end = painter.getLineBoundary(TextPosition(offset: offset)).end;
        if (end <= offset) break;
        if (end < text.length) {
          expect(
            _letter(text[end - 1]) && _letter(text[end]),
            isFalse,
            reason: '$reason: a word cut in « $text » at $end',
          );
        }
        offset = end;
      }
      painter.dispose();
    }
  }

  static bool _letter(String char) =>
      RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(char);
}
