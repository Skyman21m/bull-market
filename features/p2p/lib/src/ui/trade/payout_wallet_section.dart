import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:primitives/primitives.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../../public/p2p_wallet_port.dart';
import '../../presentation/p2p_formats.dart';
import '../../presentation/payout_cubit.dart';
import '../../presentation/payout_wallet_cubit.dart';
import '../widgets/moved_tap_guard.dart';
import '../widgets/trade_button.dart';
import 'payout_panel.dart';

/// The wallet's slot of the payout panel (#90): on the Lightning tab « Generate Invoice », an invoice of this wallet's Instant payments for exactly the amount the panel shows; on the Onchain tab « Generate New Address », a new address of its Bitcoin wallet.
///
/// The wallet's own words for the same acts (its Receive screen); the reference has no wallet, and with a WebLN one it makes the invoice and submits it by itself on the status change (`TradeBox/index.tsx:336-345`). Here each request is the user's tap, and what the wallet gives goes into the panel's field through [PayoutWalletRequest.use], where the panel checks it as a pasted text and shows what « Submit » gives (for an invoice its amount, its expiry and its network, with the warning when it may expire before the coordinator pays); the user then taps « Submit ». Nothing is submitted by this section.
/// While the field holds the invoice it put there, what the Instant payments wallet receives once the swap service's fee is taken is said by the panel's breakdown ([receiptOf], #228). At status 15 the panel shows the Lightning tab alone: the same button gives a new invoice once the wallet's earlier one for the trade has ended, and while that one is still open it says so, since the coordinator takes only a new invoice, and an invoice from another wallet can be pasted.
/// An answer that comes once the user changed the field meanwhile is dropped: what the user pasted stays.
/// Each wait says what it waits for, with the bar, and after 30 s that it still waits; a refusal is said in the wallet's words.
class PayoutWalletSection extends StatelessWidget {
  final PayoutWalletRequest request;

  const PayoutWalletSection({super.key, required this.request});

  /// The slot for [request], as the payout panel's `PayoutWalletBuilder`.
  static Widget? slotFor(BuildContext context, PayoutWalletRequest request) =>
      PayoutWalletSection(request: request);

  /// What the invoice this wallet made brings, while the Lightning field of [request] holds it, as the payout panel's `PayoutWalletReceiptOf` (#228): its amount and what arrives in Instant payments, the swap service's fee taken out; `null` otherwise (no invoice made, another text in the field, the Onchain tab).
  static ({Sats amount, Sats received})? receiptOf(
    BuildContext context,
    PayoutWalletRequest request,
  ) => switch (context.watch<PayoutWalletCubit>().state) {
    PayoutWalletMadeInvoice(:final invoice)
        when request.kind == PayoutKind.lightning &&
            request.field == invoice.bolt11 =>
      (amount: invoice.amount, received: invoice.received),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final state = context.watch<PayoutWalletCubit>().state;
    final kind = request.kind;
    final making = state is PayoutWalletMaking;
    final makingHere = state is PayoutWalletMaking && state.kind == kind;
    final amount = request.invoiceSats;
    VoidCallback? onPressed;
    if (request.editable && !making) {
      switch (kind) {
        case PayoutKind.lightning:
          if (amount != null) onPressed = () => _invoice(context, amount);
        case PayoutKind.onchain:
          onPressed = () => _address(context);
      }
    }
    final waiting = switch (kind) {
      PayoutKind.lightning => l10n.p2pPayoutWalletMakingInvoice,
      PayoutKind.onchain => l10n.p2pPayoutWalletMakingAddress,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Under the payout's breakdown, moved by the rule's lines as « Submit » is: a tap aimed at what stood here before is ignored for a moment (#283), so that no request reaches the wallet unasked; the button stays enabled.
        MovedTapGuard(
          builder: (context, guard) => TradeButton(
            label: switch (kind) {
              PayoutKind.lightning => l10n.p2pPayoutWalletGenerateInvoice,
              PayoutKind.onchain => l10n.p2pPayoutWalletGenerateAddress,
            },
            icon: Icons.account_balance_wallet_outlined,
            outlined: true,
            busy: makingHere,
            onPressed: guard(onPressed),
          ),
        ),
        if (makingHere) ...[
          const Gap(BullSpacing.xs),
          _Line(waiting, live: true),
          const Gap(BullSpacing.xs),
          LinearProgressIndicator(
            color: colors.primary,
            semanticsLabel: waiting,
          ),
          if (state case PayoutWalletMaking(waitedLong: true)) ...[
            const Gap(BullSpacing.xs),
            _Line(l10n.p2pPayoutWalletStillWaiting, muted: true, live: true),
          ],
        ],
        ...switch (state) {
          // What the invoice in the field brings is the breakdown's last two lines (#228, [receiptOf]).
          PayoutWalletEarlierStillOpen() when kind == PayoutKind.lightning => [
            const Gap(BullSpacing.xs),
            _Line(
              l10n.p2pPayoutWalletEarlierStillOpen,
              color: colors.error,
              live: true,
            ),
          ],
          PayoutWalletRefused(kind: final refused, :final refusal)
              when refused == kind =>
            [
              const Gap(BullSpacing.xs),
              _Line(
                _refusalText(context, refusal, kind),
                color: colors.error,
                live: true,
              ),
            ],
          _ => const <Widget>[],
        },
        const Gap(BullSpacing.md),
      ],
    );
  }

  Future<void> _invoice(BuildContext context, Sats amount) async {
    final before = context.read<PayoutCubit>().state.form.invoice;
    final text = await context.read<PayoutWalletCubit>().makeInvoice(
      request.ask,
      amount,
    );
    // Dropped once the user changed the field during the wait.
    if (text != null &&
        context.mounted &&
        context.read<PayoutCubit>().state.form.invoice == before) {
      request.use(text);
    }
  }

  Future<void> _address(BuildContext context) async {
    final before = context.read<PayoutCubit>().state.form.address;
    final text = await context.read<PayoutWalletCubit>().makeAddress(
      request.ask,
    );
    if (text != null &&
        context.mounted &&
        context.read<PayoutCubit>().state.form.address == before) {
      request.use(text);
    }
  }

  /// [refusal] in the wallet's words, as the bond's panel says the same swap refusals (#135).
  static String _refusalText(
    BuildContext context,
    P2pWalletRefusal refusal,
    PayoutKind kind,
  ) {
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    String sats(Sats amount) => formats.sats(amount.value.toInt());
    return switch (refusal) {
      P2pWalletUnderMinimum(minimum: final minimum?) => l10n.p2pPayUnderMinimum(
        sats(minimum),
      ),
      P2pWalletUnderMinimum() => l10n.p2pPayUnderMinimumUnknown,
      P2pWalletOverMaximum(maximum: final maximum?) => l10n.p2pPayOverMaximum(
        sats(maximum),
      ),
      P2pWalletOverMaximum() ||
      P2pWalletOutsideServiceLimits() => l10n.p2pPayOutsideLimits,
      P2pWalletServiceUnreachable() => l10n.p2pPayUnreachable,
      P2pWalletServiceBusy() => l10n.p2pPayBusy,
      P2pWalletAnotherInvoiceWaiting() => l10n.p2pPayoutWalletAnotherWaiting,
      P2pWalletNotEnoughBalance() ||
      P2pWalletNeedsConsolidation() ||
      P2pWalletNoInstantWallet() ||
      P2pWalletNoBitcoinWallet() ||
      P2pWalletUnavailable() ||
      P2pWalletWrongNetwork() ||
      P2pWalletInvoiceUnreadable() ||
      P2pWalletInvoiceExpired() ||
      P2pWalletServiceRefused() ||
      P2pWalletInvoiceExpiresTooSoon() ||
      P2pWalletQuoteStale() ||
      P2pWalletQuoteChanged() ||
      P2pWalletPaymentExists() ||
      P2pWalletBroadcastUnknown() ||
      P2pWalletOrderExpiresTooSoon() ||
      P2pWalletPaymentInterrupted() => switch (kind) {
        PayoutKind.lightning => l10n.p2pPayoutWalletNoInvoice,
        PayoutKind.onchain => l10n.p2pPayoutWalletNoAddress,
      },
    };
  }
}

class _Line extends StatelessWidget {
  final String text;
  final Color? color;
  final bool muted;
  final bool live;

  const _Line(this.text, {this.color, this.muted = false, this.live = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final theme = Theme.of(context).textTheme;
    return Semantics(
      container: live,
      liveRegion: live,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.bodyMedium?.copyWith(
          color: color ?? (muted ? colors.textMuted : colors.onSurface),
        ),
      ),
    );
  }
}
