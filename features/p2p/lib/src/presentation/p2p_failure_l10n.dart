import 'package:flutter/widgets.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/p2p_failure.dart';
import 'robot_coordinator_state.dart';

/// What the screens say about a failure of a coordinator: the book shows such a coordinator offline in its row, with no text of its own (`CoordinatorsRow`).
extension CoordinatorFailureL10n on CoordinatorFailure {
  /// What the robot panel of the Garage says when a request of a robot to [coordinator], the long alias it shows, ended with this failure: the texts of the design note of #29, § 2.3.
  ///
  /// None quotes the coordinator's answer; « Coordinator offline » when it could not be reached.
  String toRobotText(BuildContext context, {required String coordinator}) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      CoordinatorTransportBusy() => l10n.p2pRobotBusy,
      CoordinatorResponseTooLarge() => l10n.p2pRobotBadAnswer(coordinator),
      CoordinatorTransportFailure() ||
      CoordinatorNotOnNetwork() => l10n.p2pCoordinatorOffline,
      CoordinatorUnexpectedStatus() ||
      CoordinatorNotJson() ||
      CoordinatorResponseMalformed() ||
      CoordinatorIdentityFailure() => l10n.p2pRobotBadAnswer(coordinator),
      RobotUnknown() => l10n.p2pRobotNotCreated(coordinator),
      RobotKeysRefused(reason: RobotKeysRefusal.keyTooRecent) =>
        l10n.p2pRobotKeyTooRecent(coordinator),
      RobotKeysRefused() ||
      RobotCredentialsRejected() => l10n.p2pRobotRefused(coordinator),
      RobotNicknameTaken() => l10n.p2pRobotNicknameTaken(coordinator),
      RobotMismatchFailure() => l10n.p2pRobotMismatch(coordinator),
    };
  }
}

/// What the Garage says about a failed action on the Garage Key of its network.
extension P2pFailureL10n on P2pFailure {
  /// A text of the app for each failure; none quotes the vault or what the user typed.
  String toTranslated(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      GarageKeyMissingFailure() => l10n.p2pNoRobotTitle,
      GarageKeyAlreadyStoredFailure() => l10n.p2pGarageKeyAlreadyStored,
      GarageKeyLockedFailure() => l10n.p2pGarageKeyLocked,
      GarageKeyUnreadableFailure() => l10n.p2pGarageKeyUnreadable,
      GarageKeyUnusableFailure() => l10n.p2pGarageKeyUnusable,
      GarageKeyNotSavedFailure() => l10n.p2pGarageKeyNotSaved,
      GarageKeyNotDeletedFailure() => l10n.p2pGarageKeyNotDeleted,
      GarageKeyInvalidFailure(:final reason) => garageKeyFailureText(
        reason,
        l10n,
      ),
      GarageRobotUnavailableFailure() => l10n.p2pGarageRobotUnavailable,
      // An action on the Garage Key gives it when the record of an imported key could not be written and the key was not stored; the robot panel has its own text ([toRobotText]).
      P2pStorageFailure() => l10n.p2pGarageKeyNotSaved,
      // Only the robot panel shows a robot failure, with [toRobotText], which names the coordinator; here, the texts that need no name.
      RobotBoundToAnotherCoordinatorFailure() => l10n.p2pRobotBoundElsewhere,
      RobotHistoryUnknownFailure() ||
      RobotNotBoundFailure() => l10n.p2pRobotNoCoordinator,
      RobotKeyComputeFailure() => l10n.p2pRobotKeyComputeFailed,
      RobotCoordinatorBusyFailure() ||
      RobotReleasedFailure() => l10n.p2pRobotBusy,
      RobotCoordinatorTooManyRefusalsFailure() =>
        l10n.p2pRobotCoordinatorTooManyRefusals,
      // Its text names the coordinator, which only the robot panel knows: there, [toRobotText].
      RobotCoordinatorChangedFailure() => l10n.p2pBookError,
      // The failures of the trade records and of the robot of a new trade (#85): no screen shows them yet, and the trade screens give them their texts (#88).
      GarageKeyNotForTradesFailure() ||
      TradeCoordinatorNotOnNetworkFailure() ||
      TradeKeyMissingFailure() ||
      TradeAlreadyRecordedFailure() ||
      RobotNotForNewTradeFailure() ||
      TradeClosedFailure() => l10n.p2pBookError,
    };
  }

  /// What the robot panel of the Garage says when a request of a robot to [coordinator], the long alias it shows, was refused with this failure: the texts of the design note of #29, § 2.3, and two the design left out.
  ///
  /// A failure that does not come from a robot request, which the panel never gets, has the text of [toTranslated].
  String toRobotText(BuildContext context, {required String coordinator}) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      P2pStorageFailure() => l10n.p2pRobotStorage,
      RobotCoordinatorChangedFailure() => l10n.p2pRobotCoordinatorChanged(
        coordinator,
      ),
      // A history unknown or no binding: the panel shows the robot without a coordinator, as it is.
      RobotHistoryUnknownFailure() ||
      RobotNotBoundFailure() ||
      // The robot was bound elsewhere: the panel shows where it lives.
      RobotBoundToAnotherCoordinatorFailure() ||
      // The pair of the robot could not be made or proven on this device: no row of the design's table, a text of its own.
      RobotKeyComputeFailure() ||
      RobotCoordinatorBusyFailure() ||
      // The panel is gone when its robot is released: never shown.
      RobotReleasedFailure() ||
      RobotCoordinatorTooManyRefusalsFailure() ||
      GarageKeyMissingFailure() ||
      GarageKeyAlreadyStoredFailure() ||
      GarageKeyLockedFailure() ||
      GarageKeyUnreadableFailure() ||
      GarageKeyUnusableFailure() ||
      GarageKeyNotSavedFailure() ||
      GarageKeyNotDeletedFailure() ||
      GarageKeyInvalidFailure() ||
      GarageRobotUnavailableFailure() ||
      // Not a robot request: the panel never gets them.
      GarageKeyNotForTradesFailure() ||
      TradeCoordinatorNotOnNetworkFailure() ||
      TradeKeyMissingFailure() ||
      TradeAlreadyRecordedFailure() ||
      RobotNotForNewTradeFailure() ||
      TradeClosedFailure() => toTranslated(context),
    };
  }
}

/// Why [text], the cleaned text of a Garage Key field, is not a Garage Key, in the words of the official client's validator, or `null` when it is one or is empty.
String? garageKeyTextError(String text, P2pLocalizations l10n) {
  if (text.isEmpty) return null;
  return switch (GarageKey.parse(text)) {
    Ok() => null,
    Err(:final failure) => garageKeyFailureText(failure, l10n),
  };
}

/// The validator of the official client says why a text is not a Garage Key (`validateGarageKey` at commit ff1998c); where it would show the message of its bech32 decoder, which quotes the text, Troc says « Invalid garage key ».
String garageKeyFailureText(GarageKeyFailure failure, P2pLocalizations l10n) =>
    switch (failure) {
      GarageKeyWrongPrefix() => l10n.p2pGarageKeyMustStartWith,
      GarageKeyWrongLength() => l10n.p2pGarageKeyInvalidLength,
      GarageKeyWrongByteLength() => l10n.p2pGarageKeyInvalidData,
      GarageKeyEmpty() ||
      GarageKeyMalformed() ||
      GarageKeyBadChecksum() => l10n.p2pGarageKeyInvalid,
    };

/// What the robot panel of the Garage says about a failed robot request to [coordinator], the long alias it shows.
extension RobotRequestProblemL10n on RobotRequestProblem {
  String toRobotText(BuildContext context, {required String coordinator}) =>
      switch (this) {
        RobotRequestRefused(:final failure) => failure.toRobotText(
          context,
          coordinator: coordinator,
        ),
        RobotRequestAnswered(:final failure) => failure.toRobotText(
          context,
          coordinator: coordinator,
        ),
      };
}
