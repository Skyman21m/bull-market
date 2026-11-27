import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/p2p_failure.dart';
import '../domain/trade/trade_payout.dart';
import '../domain/trade/trade_payout_outcome.dart';
import 'p2p_failure_l10n.dart';
import 'p2p_formats.dart';
import 'payout_cubit.dart';

/// The date of an invoice's expiry, local, as the panel's table and its warning write it.
String payoutExpiryDate(BuildContext context, DateTime expiresAt) =>
    DateFormat.yMd(
      P2pLocalizations.of(context).localeName,
    ).format(expiresAt.toLocal());

/// The time of an invoice's expiry, local, to the second, as the panel's table and its warning write it.
String payoutExpiryTime(BuildContext context, DateTime expiresAt) =>
    DateFormat.Hms(
      P2pLocalizations.of(context).localeName,
    ).format(expiresAt.toLocal());

/// Why a payout cannot be given, in words of the app or of the reference (#91): never the pasted text, never a coordinator's text.
extension PayoutCheckRefusalL10n on PayoutCheckRefusal {
  /// The text, naming [coordinator], the long alias of the trade's coordinator.
  String toText(BuildContext context, {required String coordinator}) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      PayoutNeedsARead() => l10n.p2pPayoutNeedsARead,
      PayoutNotAsked() => l10n.p2pPayoutNotAsked(coordinator),
      PayoutOnchainNotOffered() => l10n.p2pPayoutSwapUnavailable(coordinator),
      PayoutAmountUnknown() => l10n.p2pPayoutAmountUnknown(coordinator),
      PayoutInvoiceUnreadable() => l10n.p2pPayoutInvoiceUnreadable,
      PayoutInvoiceOfAnotherNetwork() => l10n.p2pPayoutInvoiceOtherNetwork,
      // The reference's own words for it (`Forms/LightningPayout.tsx:120`).
      PayoutInvoiceAmountNotAsked() => l10n.p2pPayoutInvalidInvoiceAmount,
      PayoutInvoiceAmountNotWholeSats() => l10n.p2pPayoutInvoiceWholeSats,
      PayoutInvoiceExpired() => l10n.p2pTradeWarnExpired,
      PayoutAddressUnusable(:final reason) => switch (reason) {
        PayoutDestinationMalformed() ||
        PayoutDestinationNoAmount() => l10n.p2pPayoutAddressMalformed,
        PayoutDestinationBadChecksum() => l10n.p2pPayoutAddressBadChecksum,
        PayoutDestinationWrongNetwork() => l10n.p2pPayoutAddressOtherNetwork,
        PayoutDestinationUnsupported() => l10n.p2pPayoutAddressUnsupported(
          coordinator,
        ),
      },
    };
  }
}

/// What a payout warning says (#91): information, never a refusal.
extension PayoutWarningL10n on PayoutWarning {
  String toText(
    BuildContext context, {
    required String coordinator,
    required CheckedPayout payout,
  }) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      PayoutWarning.invoiceMayExpireFirst => switch (payout) {
        CheckedPayoutInvoice(:final expiresAt) =>
          l10n.p2pPayoutWarnExpiresFirst(
            payoutExpiryDate(context, expiresAt),
            payoutExpiryTime(context, expiresAt),
            coordinator,
          ),
        CheckedPayoutAddress() => '',
      },
      PayoutWarning.sentBelowMinimum => l10n.p2pPayoutWarnBelowMinimum(
        coordinator,
      ),
    };
  }
}

/// Why the coordinator offers no on-chain payout, as its `swap_failure_reason` gives it, read as a kind ([SwapRefusal]): the reference disables its tab without saying why (`Prompts/Payout.tsx:98`).
extension SwapRefusalL10n on SwapRefusal? {
  String toText(BuildContext context, {required String coordinator}) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      SwapRefusal.belowMinimum => l10n.p2pPayoutSwapBelowMinimum(coordinator),
      SwapRefusal.aboveMaximum => l10n.p2pPayoutSwapAboveMaximum(coordinator),
      SwapRefusal.disabled => l10n.p2pPayoutSwapDisabled(coordinator),
      SwapRefusal.noLiquidity => l10n.p2pPayoutSwapNoLiquidity(coordinator),
      SwapRefusal.unspecified ||
      null => l10n.p2pPayoutSwapUnavailable(coordinator),
    };
  }
}

/// The reason a payout failed, as the coordinator labels it (`LNPayment.FailureReason`), which the reference shows untranslated.
extension PayoutFailureReasonL10n on PayoutFailureReason {
  String toText(BuildContext context, {required String coordinator}) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      PayoutFailureReason.notFailedYet => l10n.p2pPayoutFailureNotYet,
      PayoutFailureReason.timedOut => l10n.p2pPayoutFailureTimeout,
      PayoutFailureReason.noRoute => l10n.p2pPayoutFailureNoRoute,
      PayoutFailureReason.nonRecoverable => l10n.p2pPayoutFailureNonRecoverable,
      PayoutFailureReason.incorrectDetails => l10n.p2pPayoutFailureIncorrect,
      PayoutFailureReason.coordinatorBalance => l10n.p2pPayoutFailureBalance,
      PayoutFailureReason.unspecified => l10n.p2pPayoutFailureUnknown(
        coordinator,
      ),
    };
  }
}

/// What a payout being given waits for (#91: each wait says what it waits for).
extension PayoutProgressL10n on PayoutProgress {
  String toText(BuildContext context, {required String coordinator}) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      PayoutProgress.opening => l10n.p2pPayoutStepOpening,
      PayoutProgress.waitingForOrder => l10n.p2pPayoutStepWaitingForOrder,
      PayoutProgress.unlockingKey => l10n.p2pPayoutStepUnlocking(coordinator),
      PayoutProgress.readingOrder => l10n.p2pPayoutStepReading(coordinator),
      PayoutProgress.sending => l10n.p2pPayoutStepSending(coordinator),
      PayoutProgress.readingAfter => l10n.p2pPayoutStepReadingAfter(
        coordinator,
      ),
    };
  }
}

/// What a payout given told (#91): where the reference shows the coordinator's message under the field (`TradeBox/index.tsx:229-232`), the text is that message, from the feature's translations; the rest in words of the app.
extension PayoutNoticeL10n on PayoutNotice {
  String toText(BuildContext context, {required String coordinator}) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      PayoutNoticeGiven() => l10n.p2pPayoutGiven(coordinator),
      PayoutNoticeUnknown() => l10n.p2pPayoutUnknown(coordinator),
      PayoutNoticeAskedAgain() => l10n.p2pPayoutAskedAgain(coordinator),
      PayoutNoticeNotTaken(:final cause, :final shown) => _notTaken(
        context,
        cause,
        shown,
        coordinator,
      ),
      PayoutNoticeNotSent(:final refusal, :final change) => switch (refusal) {
        PayoutChangedSinceShown() => switch (change) {
          PayoutChange.amount => l10n.p2pPayoutChangedAmount,
          PayoutChange.expiry => l10n.p2pPayoutChangedExpiry,
          PayoutChange.status => l10n.p2pPayoutChangedStatus,
          PayoutChange.other || null => l10n.p2pPayoutChanged,
        },
        PayoutNoLongerValid(:final reason) => reason.toText(
          context,
          coordinator: coordinator,
        ),
        PayoutKeyUnavailable() => l10n.p2pPayoutNotSentKey(coordinator),
        PayoutReadFailed() => l10n.p2pPayoutNotSentRead(coordinator),
        PayoutNotSigned() => l10n.p2pPayoutNotSentSign,
        PayoutRefusedFromRead() => l10n.p2pPayoutNotAsked(coordinator),
        PayoutOfAnotherTrade() ||
        PayoutTradeUnavailable() ||
        PayoutTradeUnrestorable() => l10n.p2pPayoutNotSentTrade,
      },
    };
  }

  static String _notTaken(
    BuildContext context,
    Object cause,
    CheckedPayout shown,
    String coordinator,
  ) {
    final l10n = P2pLocalizations.of(context);
    return switch (cause) {
      PayoutInvoiceRefused(:final reason) && final refused => switch (reason) {
        PayoutInvoiceRefusal.empty => l10n.p2pPayoutRefusedEmptyInvoice,
        PayoutInvoiceRefusal.notAnInvoice => l10n.p2pPayoutRefusedNotInvoice,
        PayoutInvoiceRefusal.routeHintsUnpayable =>
          l10n.p2pPayoutRefusedRouteHints,
        PayoutInvoiceRefusal.noAmount => l10n.p2pPayoutRefusedNoAmount,
        // The amount the coordinator expects, from its own message: it computes it itself (`api/lightning/lnd.py:514-520`), and it is the one that differs from the invoice's.
        PayoutInvoiceRefusal.wrongAmount => switch (refused.expectedSats) {
          final expected? => l10n.p2pPayoutRefusedWrongAmount(
            P2pFormats.of(context).sats(expected),
          ),
          null => l10n.p2pPayoutInvalidInvoiceAmount,
        },
        PayoutInvoiceRefusal.expired => l10n.p2pPayoutRefusedExpired,
        PayoutInvoiceRefusal.alreadySubmitted =>
          l10n.p2pPayoutRefusedNewInvoice,
        PayoutInvoiceRefusal.wrongNetwork => l10n.p2pPayoutInvoiceOtherNetwork,
        PayoutInvoiceRefusal.unspecified => l10n.p2pPayoutRefusedOther(
          coordinator,
        ),
      },
      PayoutAddressRefused(:final reason) => switch (reason) {
        PayoutAddressRefusal.empty => l10n.p2pPayoutRefusedEmptyAddress,
        PayoutAddressRefusal.invalid => l10n.p2pPayoutRefusedInvalidAddress,
        PayoutAddressRefusal.unverifiable => l10n.p2pPayoutRefusedUnverifiable,
        PayoutAddressRefusal.wrongNetwork => l10n.p2pPayoutAddressOtherNetwork,
        PayoutAddressRefusal.unspecified => l10n.p2pPayoutRefusedOther(
          coordinator,
        ),
      },
      PayoutMiningFeeTooLow(:final minimumSatPerVbyte?) =>
        l10n.p2pPayoutRefusedFeeTooLow(
          P2pFormats.of(context).number(minimumSatPerVbyte),
        ),
      PayoutMiningFeeTooLow() => l10n.p2pPayoutRefusedFeeTooLowNoRate,
      PayoutMiningFeeTooHigh() => l10n.p2pPayoutRefusedFeeTooHigh,
      PayoutBelowDustLimit() => l10n.p2pPayoutRefusedDust,
      PayoutSignatureRefused() => l10n.p2pPayoutRefusedSignature,
      PayoutNotBuyer() => l10n.p2pPayoutRefusedNotBuyer,
      PayoutNotNow() => switch (shown) {
        CheckedPayoutInvoice() => l10n.p2pPayoutRefusedNotNow,
        CheckedPayoutAddress() => l10n.p2pPayoutRefusedAddressNotNow,
      },
      OrderNotParticipant() => l10n.p2pPayoutRefusedNotParticipant,
      // The signature of the request refused for a reason of its own (1059, 1060, 1061), or not made here: its words; nothing was recorded.
      ActionSignatureRefused(
            reason: ActionSignatureRefusal.clockSkew ||
                ActionSignatureRefusal.missing ||
                ActionSignatureRefusal.otherCoordinator ||
                ActionSignatureRefusal.notSigned,
          ) &&
          final CoordinatorFailure refused =>
        refused.toRobotText(context, coordinator: coordinator),
      // The request never reached the coordinator: nothing was recorded.
      P2pFailure() => l10n.p2pPayoutNotReached(coordinator),
      _ => l10n.p2pPayoutRefusedOther(coordinator),
    };
  }
}
