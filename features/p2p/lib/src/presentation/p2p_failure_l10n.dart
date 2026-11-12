import 'package:flutter/widgets.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/p2p_failure.dart';

/// What the book says about a coordinator whose book could not be read.
extension CoordinatorFailureL10n on CoordinatorFailure {
  /// « Coordinator offline » when it could not be reached, a generic error when it answered something unusable or when the transport was busy.
  String toTranslated(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      // No book read gives it, since only the sessions of the robots are bounded: the text that asks to try again later comes with the Garage screens.
      CoordinatorTransportBusy() => l10n.p2pBookError,
      CoordinatorTransportFailure() ||
      CoordinatorNotOnNetwork() => l10n.p2pCoordinatorOffline,
      CoordinatorUnexpectedStatus() ||
      CoordinatorNotJson() ||
      CoordinatorResponseMalformed() ||
      CoordinatorIdentityFailure() ||
      // No book read gives a robot failure: its own texts come with the Garage screens.
      CoordinatorRobotFailure() => l10n.p2pBookError,
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
      // Today only an import gives it to a screen, when the record of the imported key could not be written and the key was not stored.
      P2pStorageFailure() => l10n.p2pGarageKeyNotSaved,
      // No screen sends a robot to a coordinator yet: their own texts come with the screens that do.
      RobotBoundToAnotherCoordinatorFailure() ||
      RobotCoordinatorChangedFailure() ||
      RobotHistoryUnknownFailure() => l10n.p2pBookError,
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
