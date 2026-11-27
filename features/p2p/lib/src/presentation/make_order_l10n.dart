import 'package:flutter/widgets.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/p2p_failure.dart';
import '../domain/trade/maker_form.dart';
import '../domain/trade/maker_terms.dart';
import '../domain/trade/trade_make.dart';
import '../domain/trade/trade_renewal.dart';
import 'make_order_cubit.dart';
import 'p2p_failure_l10n.dart';

/// Why the form refuses the range typed, with the bound it takes (#225): the app's own words, [amountOf] writing an amount with its currency.
extension MakerRangeProblemL10n on MakerRangeProblem {
  String toText(
    BuildContext context, {
    required String coordinator,
    required String Function(double amount) amountOf,
  }) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      MakerRangeNoRoom() => l10n.p2pMakeRangeNoRoom(coordinator),
      MakerRangeNotPositive() => l10n.p2pMakeRangeNotPositive,
      MakerRangeMinTooBig(:final atMost) => l10n.p2pMakeRangeMinAtMost(
        amountOf(atMost),
        coordinator,
      ),
      MakerRangeMaxBelowMin() => l10n.p2pMakeRangeMaxBelowMin,
      MakerRangeMinTooSmall(:final atLeast) => l10n.p2pMakeRangeMinAtLeast(
        amountOf(atLeast),
        coordinator,
      ),
      MakerRangeMaxTooBig(:final atMost) => l10n.p2pMakeRangeMaxAtMost(
        amountOf(atMost),
        coordinator,
      ),
      MakerRangeTooNarrow(:final min, :final atLeast) =>
        l10n.p2pMakeRangeMaxAtLeastFor(amountOf(min), amountOf(atLeast)),
      MakerRangeTooWide(:final min, :final atMost) =>
        l10n.p2pMakeRangeMaxAtMostFor(amountOf(min), amountOf(atMost)),
    };
  }
}

/// Why « Create order » is disabled, in the reference's words (`MakerForm.tsx:517-565`), or the app's for « Sell ».
extension MakerFormBlockL10n on MakerFormBlock {
  String toText(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      MakerFormBlock.loadingCoordinators => l10n.p2pMakeWhyLoadingCoordinators,
      MakerFormBlock.priceNotSynchronized =>
        l10n.p2pMakeWhyPriceNotSynchronized,
      MakerFormBlock.limitsUnavailable => l10n.p2pMakeWhyLimitsUnavailable,
      MakerFormBlock.noSide => l10n.p2pMakeWhyNoSide,
      MakerFormBlock.amountOutsideLimits => l10n.p2pMakeWhyOutsideLimits,
      MakerFormBlock.badPaymentMethod => l10n.p2pMakeWhyBadPaymentMethod,
      MakerFormBlock.noAmount => l10n.p2pMakeWhyNoAmount,
      MakerFormBlock.amountRangeInvalid => l10n.p2pMakeWhyRangeInvalid,
      MakerFormBlock.amountNotPositive => l10n.p2pMakeWhyAmountNotPositive,
      MakerFormBlock.premiumInvalid => l10n.p2pMakeWhyPremiumInvalid,
      MakerFormBlock.premiumNotANumber => l10n.p2pMakeWhyPremiumNotANumber,
      MakerFormBlock.noPaymentMethod => l10n.p2pMakeWhyNoPaymentMethod,
      MakerFormBlock.descriptionInvalid => l10n.p2pMakeWhyDescriptionInvalid,
      MakerFormBlock.formIncorrect => l10n.p2pMakeWhyFormIncorrect,
    };
  }
}

/// Why an order cannot be renewed from this device (#185): a text of the app for each type.
extension RenewalRefusalL10n on RenewalRefusal {
  String toText(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      RenewalNotMadeHere() ||
      RenewalTermsUnreadable() => l10n.p2pRenewTermsUnreadable,
      RenewalNotEnded() => l10n.p2pRenewNotEnded,
      RenewalCoordinatorGone() => l10n.p2pRenewCoordinatorGone,
    };
  }
}

/// Why a make did not happen (#181): a text of the app for each type, never the coordinator's (`AGENTS.md`, « Rules for #180 to #182 »).
///
/// Where the official client shows the coordinator's own message for an error code (`MakerForm.tsx:284-286`): for 1004, 1005, 1007 and 1008 the text is the start of that message, without the figures the coordinator gives (`api/errors.py:7-8`, `:10-11`), for 1006 and 1009 the message itself (`:9`, `:12`, #183); for 1037 it is the project's own, after that message (`api/errors.py:44`).
extension MakeProblemL10n on MakeProblem {
  /// The text, naming [coordinator], the long alias of the chosen coordinator.
  String toText(BuildContext context, {required String coordinator}) {
    final l10n = P2pLocalizations.of(context);
    String after(String reason) => l10n.p2pMakeNotMadeAfter(reason);
    return switch (this) {
      MakeWasRefused(:final refusal) => switch (refusal) {
        MakeCoordinatorNotOnNetwork() => l10n.p2pMakeNotMade,
        MakeCoordinatorUnreadable() => l10n.p2pMakeCoordinatorUnreadable(
          coordinator,
        ),
        MakePriceUnknown() => after(l10n.p2pMakeWhyPriceNotSynchronized),
        MakeTermsRefused(reason: MakerFeeTooHigh()) => l10n.p2pMakeFeeTooHigh(
          coordinator,
        ),
        MakeTermsRefused() => l10n.p2pMakeTermsUnusable,
        MakeAmountOutsideLimits() => after(l10n.p2pMakeWhyOutsideLimits),
        MakeRobotRefused(:final failure) => _robotRefused(
          context,
          failure,
          coordinator,
        ),
        MakeRobotNotPut(:final cause) => after(
          cause.toRobotText(context, coordinator: coordinator),
        ),
        MakeNotRecorded() => l10n.p2pMakeNotRecorded,
        MakePriceCheckChanged() => l10n.p2pMakePriceCheckChanged(coordinator),
      },
      MakeWasNotMade(:final refusal) => switch (refusal) {
        null => l10n.p2pMakeNotMade,
        RobotAlreadyMaker() => after(l10n.p2pTakeAlreadyMaker),
        RobotAlreadyTaker() => after(l10n.p2pTakeAlreadyTaker),
        RobotAlreadyTaking() => after(l10n.p2pTakeAlreadyTaking),
        RobotPayoutPending() => after(l10n.p2pTakePaymentPending),
        OrderSizeRefused(reason: OrderSizeRefusal.tooBig) => after(
          l10n.p2pMakeTooBig,
        ),
        OrderSizeRefused(reason: OrderSizeRefusal.tooSmall) => after(
          l10n.p2pMakeTooSmall,
        ),
        OrderSizeRefused(reason: OrderSizeRefusal.rangeTooNarrow) => after(
          l10n.p2pMakeRangeTooNarrow,
        ),
        OrderSizeRefused(reason: OrderSizeRefusal.rangeMaximumTooBig) => after(
          l10n.p2pMakeRangeMaxTooBig,
        ),
        OrderSizeRefused(reason: OrderSizeRefusal.rangeMinimumTooSmall) =>
          after(l10n.p2pMakeRangeMinTooSmall),
        OrderSizeRefused(reason: OrderSizeRefusal.rangeTooWide) => after(
          l10n.p2pMakeRangeTooWide,
        ),
        OrderBookFull() => after(l10n.p2pMakeBookFull(coordinator)),
        final CoordinatorFailure failure => after(
          failure.toRobotText(context, coordinator: coordinator),
        ),
        final P2pFailure failure => after(failure.toTranslated(context)),
        _ => l10n.p2pMakeNotMade,
      },
    };
  }

  static String _robotRefused(
    BuildContext context,
    P2pFailure failure,
    String coordinator,
  ) {
    final l10n = P2pLocalizations.of(context);
    return switch (failure) {
      RobotNotForNewTradeFailure() => l10n.p2pMakeRobotNotNew(coordinator),
      P2pStorageFailure() => l10n.p2pMakeNotRecorded,
      GarageKeyMissingFailure() ||
      TradeKeyMissingFailure() => l10n.p2pNoRobotTitle,
      _ => l10n.p2pMakeNotMadeAfter(
        failure.toRobotText(context, coordinator: coordinator),
      ),
    };
  }
}
