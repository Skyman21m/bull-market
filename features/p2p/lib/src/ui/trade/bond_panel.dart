import 'dart:async';
import 'dart:math' as math;

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/trade/trade_status.dart';
import '../../domain/trade/trade_watch.dart';
import '../../domain/trade_record.dart';
import '../../presentation/coordinator_text.dart';
import '../../presentation/p2p_formats.dart';
import '../../presentation/trade_panel.dart';
import '../widgets/coordinator_link_sheet.dart';
import '../widgets/order_detail_row.dart';
import '../widgets/trade_button.dart';
import 'wallet_payment_section.dart';

/// The prompt of status 3, the taker's bond to lock: the official client's `Prompts/LockInvoice.tsx` (concept `bond`, commit ff1998c) in the wallet's look, with the owner's layout (#88).
///
/// From the top: « You are BUYING BTC », or « You are SELLING BTC » for a taker who sells (#96); the slot of « Pay with this wallet » ([WalletPaymentSection], empty today); « Pay with another wallet », which holds what the reference shows: « See Compatible Wallets » (the link shown for copy, never opened), the QR code of the invoice in capitals and « Copy to clipboard », with the facts read from the invoice under the QR code (amount, expiry, network, description: design note § 4.4); then « This is a hold invoice… ».
/// « Pay with another wallet » is open at first while the wallet's slot offers nothing, as today.
/// The QR code and the copy show only as [invoiceDisplayOf] allows: never for an `UnusableInvoice` nor once the screen's clock passed the invoice's `payableUntil`, behind « Show anyway » for the amount checks, not at all for the others; the warnings themselves are shown by the contract above.
/// Tapping the QR code opens nothing (the reference opens `lightning:`; the feature cannot open a link).
class BondPanel extends StatelessWidget {
  final TradeRecord record;
  final WaitingForTakerBond status;

  /// [status] as the screen shows it, which the wallet's slot is given.
  final TradeSeen seen;
  final WalletPaymentBuilder? walletPayment;

  /// Whether the order is in bitcoin, a swap into Lightning (or out of it, for a seller), as the order read says.
  final bool swap;

  /// Whether this robot sells: « You are SELLING BTC » (`LockInvoice.tsx:78-79`, `order.is_buyer`).
  final bool seller;

  /// Whether the status came with its trail stored: otherwise neither the wallet's slot nor the QR code and the copy are offered (`AGENTS.md`, « Rules for #88 »).
  final bool payable;

  /// The screen's clock, which moves every second: once it passes the invoice's `payableUntil`, the QR code and the copy are gone, as for an invoice read expired ([invoiceExpiredAt]).
  final DateTime now;

  const BondPanel({
    super.key,
    required this.record,
    required this.status,
    required this.seen,
    required this.walletPayment,
    required this.now,
    this.swap = false,
    this.seller = false,
    this.payable = true,
  });

  /// The page of compatible wallets the official client's « See Compatible Wallets » opens (`TradeBox/WalletsButton.tsx`).
  static const compatibleWallets = 'https://learn.robosats.org/docs/wallets/';

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final request = WalletPaymentRequest(
      record: record,
      status: status,
      seen: seen,
      amount: status.bond.orderAmount,
      invoiceExpired: invoiceExpiredAt(status.bond, now),
    );
    final invoice = status.bond;
    // Past the invoice's end the wallet offers nothing more, but a payment it made or is making is still said (the slot decides).
    final slot = payable
        ? WalletPaymentSection.offer(context, walletPayment, request)
        : null;
    final wallet = slot?.child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          // An order in bitcoin is a swap into Lightning, or out of it for a seller (`LockInvoice.tsx:76-80`).
          switch ((swap, seller)) {
            (true, false) => l10n.p2pTradeYouAreSwappingIn,
            (true, true) => l10n.p2pTradeYouAreSwappingOut,
            (false, false) => l10n.p2pTradeYouAreBuying,
            (false, true) => l10n.p2pTradeYouAreSelling,
          },
          textAlign: TextAlign.center,
          style: text.headlineLarge?.copyWith(color: colors.secondary),
        ),
        if (wallet != null) ...[const Gap(BullSpacing.md), wallet],
        const Gap(BullSpacing.md),
        _OtherWallet(
          // A new invoice is a new section: « Show anyway » never carries over to another invoice.
          key: ValueKey(switch (invoice) {
            CheckedInvoice(:final paymentHash) => paymentHash,
            UnusableInvoice() => '',
          }),
          invoice: invoice,
          initiallyOpen: wallet == null || slot?.othersOpen == true,
          opensNow: slot?.othersOpen ?? false,
          // This wallet holds a payment of the invoice: the other way offers it no more.
          heldByWallet: slot?.othersHidden ?? false,
          payable: payable,
          now: now,
        ),
      ],
    );
  }
}

/// The seller's escrow to lock at 6 and 7 (#96): the official client's `Prompts/LockInvoice.tsx` with the concept `escrow` (commit ff1998c), paid from another wallet in this version (« Pay with this wallet » for the escrow is #97).
///
/// From the top, as the reference: « You risk losing your bond if you do not lock the collateral. Total time available is {{deposit_timer_hours}}h {{deposit_timer_minutes}}m. » (the escrow's time of the trade's terms, split as the reference splits `escrow_duration`), the QR code of the invoice in capitals, the facts read from it (amount, expiry, network, description: design note § 4.4), « Copy to clipboard », then « This is a hold invoice, it will freeze in your wallet. It will be released to the buyer once you confirm to have received the {{currencyCode}}. »; no « See Compatible Wallets » and no « You are SELLING BTC », which the reference shows for the bond only.
/// The QR code and the copy show only as [invoiceDisplayOf] allows, as for the bond: never for an `UnusableInvoice`, nor once the screen's clock passed the invoice's `payableUntil`, nor for a status not marked stored ([payable]); behind « Show anyway » for the amount checks (the escrow not the trade's sats, the implied fee above the announced one, the invoice not `escrow_satoshis`), not at all for the others. While the coordinator has not given the invoice yet, the two lines are shown without the QR code.
/// Tapping the QR code opens nothing (the reference opens `lightning:`).
class EscrowPanel extends StatefulWidget {
  /// The escrow invoice of the status shown, `null` until the coordinator gives it.
  final StepInvoice? invoice;

  /// The trade's currency, which the hold invoice's line names, and the escrow's time: both from the trade's terms.
  final RobosatsCurrency currency;
  final Duration escrowDuration;
  final bool payable;
  final DateTime now;

  const EscrowPanel({
    super.key,
    required this.invoice,
    required this.currency,
    required this.escrowDuration,
    required this.now,
    this.payable = true,
  });

  @override
  State<EscrowPanel> createState() => _EscrowPanelState();
}

class _EscrowPanelState extends State<EscrowPanel> {
  bool _shownAnyway = false;
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void didUpdateWidget(EscrowPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // « Show anyway » holds for one payment hash.
    if (_hashOf(widget.invoice) != _hashOf(oldWidget.invoice)) {
      _shownAnyway = false;
    }
  }

  static String? _hashOf(StepInvoice? invoice) => switch (invoice) {
    CheckedInvoice(:final paymentHash) => paymentHash,
    _ => null,
  };

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy(String bolt11) async {
    await Clipboard.setData(ClipboardData(text: bolt11));
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final invoice = widget.invoice;
    // `LockInvoice.tsx:37-46`: whole hours, then whole minutes of what is left.
    final hours = widget.escrowDuration.inHours;
    final minutes = widget.escrowDuration.inMinutes - hours * 60;
    final display = invoice != null && widget.payable
        ? invoiceDisplayOf(invoice, shownAnyway: _shownAnyway, now: widget.now)
        : InvoiceDisplay.hidden;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.p2pTradeEscrowTimeWarning('$hours', '$minutes'),
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: colors.text),
        ),
        if (invoice case CheckedInvoice(:final bolt11)) ...[
          switch (display) {
            InvoiceDisplay.shown => Padding(
              padding: const EdgeInsets.only(top: BullSpacing.md),
              child: _Qr(bolt11: bolt11, label: l10n.p2pTradeEscrowQr),
            ),
            InvoiceDisplay.hiddenUntilShownAnyway => Padding(
              padding: const EdgeInsets.only(top: BullSpacing.md),
              child: TradeButton(
                label: l10n.p2pTradeShowAnyway,
                outlined: true,
                color: colors.warning,
                onPressed: () => setState(() => _shownAnyway = true),
              ),
            ),
            InvoiceDisplay.hidden => const SizedBox.shrink(),
          },
          const Gap(BullSpacing.md),
          _Facts(invoice: invoice),
          if (display == InvoiceDisplay.shown) ...[
            const Gap(BullSpacing.sm),
            TradeButton(
              label: _copied
                  ? l10n.p2pCommonCopied
                  : l10n.p2pTradeCopyToClipboard,
              icon: Icons.copy,
              outlined: true,
              onPressed: () => unawaited(_copy(bolt11)),
            ),
          ],
        ],
        const Gap(BullSpacing.md),
        Text(
          l10n.p2pTradeHoldInvoiceEscrow(widget.currency.code),
          textAlign: TextAlign.center,
          style: text.labelMedium?.copyWith(color: colors.textMuted),
        ),
      ],
    );
  }
}

/// « Pay with another wallet »: a header that opens and closes it, and the reference's QR code, copy and facts.
class _OtherWallet extends StatefulWidget {
  final StepInvoice invoice;
  final bool initiallyOpen;

  /// Whether the wallet's slot asks it open now: it opens when this turns true, and stays as the user leaves it.
  final bool opensNow;

  /// Whether this wallet is paying the invoice, or paid it: the section closes when this turns true, and offers neither the QR code nor the copy (the facts and « See Compatible Wallets » stay), so that nothing invites a second payment.
  final bool heldByWallet;
  final bool payable;
  final DateTime now;

  const _OtherWallet({
    super.key,
    required this.invoice,
    required this.initiallyOpen,
    this.opensNow = false,
    this.heldByWallet = false,
    required this.payable,
    required this.now,
  });

  @override
  State<_OtherWallet> createState() => _OtherWalletState();
}

class _OtherWalletState extends State<_OtherWallet> {
  late bool _open = widget.initiallyOpen;

  @override
  void didUpdateWidget(_OtherWallet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.opensNow && !oldWidget.opensNow) _open = true;
    if (widget.heldByWallet && !oldWidget.heldByWallet) _open = false;
  }

  bool _shownAnyway = false;
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy(String bolt11) async {
    await Clipboard.setData(ClipboardData(text: bolt11));
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final invoice = widget.invoice;
    final display = widget.payable && !widget.heldByWallet
        ? invoiceDisplayOf(invoice, shownAnyway: _shownAnyway, now: widget.now)
        : InvoiceDisplay.hidden;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(BullRadius.xxs),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            button: true,
            expanded: _open,
            child: InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.all(BullSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.p2pTradePayOtherWallet,
                        style: text.headlineLarge?.copyWith(color: colors.text),
                      ),
                    ),
                    ExcludeSemantics(
                      child: Icon(
                        _open ? Icons.expand_less : Icons.expand_more,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                BullSpacing.md,
                0,
                BullSpacing.md,
                BullSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TradeButton(
                    label: l10n.p2pTradeCompatibleWallets,
                    icon: Icons.account_balance_wallet_outlined,
                    outlined: true,
                    onPressed: () => CoordinatorLinkSheet.show(
                      context,
                      title: l10n.p2pTradeCompatibleWallets,
                      value: BondPanel.compatibleWallets,
                    ),
                  ),
                  if (invoice case CheckedInvoice(:final bolt11)) ...[
                    switch (display) {
                      InvoiceDisplay.shown => Padding(
                        padding: const EdgeInsets.only(top: BullSpacing.md),
                        child: _Qr(
                          bolt11: bolt11,
                          label: l10n.p2pTradeInvoiceQr,
                        ),
                      ),
                      InvoiceDisplay.hiddenUntilShownAnyway => Padding(
                        padding: const EdgeInsets.only(top: BullSpacing.md),
                        child: TradeButton(
                          label: l10n.p2pTradeShowAnyway,
                          outlined: true,
                          color: colors.warning,
                          onPressed: () => setState(() => _shownAnyway = true),
                        ),
                      ),
                      InvoiceDisplay.hidden => const SizedBox.shrink(),
                    },
                    const Gap(BullSpacing.md),
                    _Facts(invoice: invoice),
                    if (display == InvoiceDisplay.shown) ...[
                      const Gap(BullSpacing.sm),
                      TradeButton(
                        label: _copied
                            ? l10n.p2pCommonCopied
                            : l10n.p2pTradeCopyToClipboard,
                        icon: Icons.copy,
                        outlined: true,
                        onPressed: () => unawaited(_copy(bolt11)),
                      ),
                    ],
                  ],
                  // The reference's line on a hold invoice, word for word; not while this wallet quotes, confirms, sends or paid (its confirmation shows the same line), so that it is never on screen twice (#135).
                  if (!widget.heldByWallet) ...[
                    const Gap(BullSpacing.md),
                    Text(
                      l10n.p2pTradeHoldInvoiceBond,
                      textAlign: TextAlign.center,
                      style: text.labelMedium?.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The QR code of the invoice in capitals, as the reference encodes it, dark on the light fixed surface as the wallet's receive screen draws its own (`QrDisplayWidget`).
class _Qr extends StatelessWidget {
  final String bolt11;

  /// What a screen reader says of it: the bond's or the escrow's invoice.
  final String label;

  const _Qr({required this.bolt11, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, 300.0);
        return Center(
          child: Semantics(
            container: true,
            label: label,
            image: true,
            child: Container(
              width: size,
              height: size,
              padding: const EdgeInsets.all(BullSpacing.md),
              decoration: BoxDecoration(
                color: colors.surfaceFixed,
                borderRadius: BorderRadius.circular(BullRadius.xxs),
              ),
              // The package's own label (« qr code ») would add to the app's.
              child: ExcludeSemantics(
                child: QrImageView(data: bolt11.toUpperCase()),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// What the invoice says, read here (design note § 4.4): its amount, when it expires, its network and its description, the coordinator's text shown cleaned.
class _Facts extends StatelessWidget {
  final CheckedInvoice invoice;

  const _Facts({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final description = invoice.facts.description;
    return BullDetailsTable(
      items: [
        OrderDetailRow(
          l10n.p2pBookColumnAmount,
          l10n.p2pAmountSats(formats.sats(invoice.amount.value.toInt())),
        ),
        OrderDetailRow(
          l10n.p2pTradeInvoiceExpires,
          DateFormat.Hms(l10n.localeName).format(invoice.expiresAt.toLocal()),
        ),
        OrderDetailRow(l10n.p2pTradeInvoiceNetwork, switch (invoice.network) {
          RobosatsNetwork.mainnet => l10n.p2pTradeNetworkMainnet,
          RobosatsNetwork.testnet => l10n.p2pTradeNetworkTestnet,
        }),
        if (description != null && description.isNotEmpty)
          OrderDetailRow(
            l10n.p2pTradeInvoiceDescription,
            CoordinatorText.of(
              description,
              maxCodePoints: CoordinatorText.line,
            ),
          ),
      ],
    );
  }
}
