import 'package:flutter/material.dart';

/// The app's own re-authentication, which the shell lends the Garage before it shows a stored Garage Key: the screen it builds calls [onAuthenticated] once the user passed it, and leaves through the back button otherwise.
///
/// In the app it is the PIN screen the wallet shows before it reveals its seeds (`AppUnlockFacade.buildReauthenticationGate`), which passes at once when no PIN is set; the feature never imports wallet code for it.
typedef P2pReauthentication = Widget Function(VoidCallback onAuthenticated);

/// Shows the screen of [reauthenticate] above everything, and completes with `true` only when the user passed it.
///
/// Leaving that screen in any other way, with the back button or by leaving the tab, completes with `false`, and so does a second call of `onAuthenticated`.
Future<bool> askReauthentication(
  BuildContext context,
  P2pReauthentication reauthenticate,
) async {
  var done = false;
  final passed = await Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute<bool>(
      builder: (routeContext) => reauthenticate(() {
        if (done) return;
        done = true;
        if (ModalRoute.of(routeContext)?.isCurrent ?? false) {
          Navigator.of(routeContext).pop(true);
        }
      }),
    ),
  );
  return passed ?? false;
}

/// [askReauthentication] from [context], for a cubit that decides itself whether to ask it: `null` without [reauthenticate], so that the cubit refuses what needs it, and `false` once [context] is gone.
Future<bool> Function()? reauthenticationFrom(
  BuildContext context,
  P2pReauthentication? reauthenticate,
) => switch (reauthenticate) {
  null => null,
  final gate =>
    () async => context.mounted && await askReauthentication(context, gate),
};
