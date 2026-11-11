import 'package:flutter/widgets.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';

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
