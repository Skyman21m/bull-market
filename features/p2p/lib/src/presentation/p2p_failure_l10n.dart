import 'package:flutter/widgets.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';

/// What the book says about a coordinator whose book could not be read.
extension CoordinatorFailureL10n on CoordinatorFailure {
  /// « Coordinator offline » when it could not be reached, a generic error when it answered something unusable.
  String toTranslated(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      CoordinatorTransportFailure() ||
      CoordinatorNotOnNetwork() => l10n.p2pCoordinatorOffline,
      CoordinatorUnexpectedStatus() ||
      CoordinatorNotJson() ||
      CoordinatorResponseMalformed() ||
      CoordinatorIdentityFailure() => l10n.p2pBookError,
    };
  }
}
