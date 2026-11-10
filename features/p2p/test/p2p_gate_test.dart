import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';

// The pure gate of the P2P tab, as the router of the app calls it: no widget tree, so this is the shipped decision.
void main() {
  const home = '/wallet';
  const flags = [
    (superuser: false, devMode: false),
    (superuser: true, devMode: false),
    (superuser: false, devMode: true),
    (superuser: true, devMode: true),
  ];

  String? redirect(String path, ({bool superuser, bool devMode}) flag) =>
      P2pFeature.redirect(
        path,
        isSuperuser: flag.superuser,
        isDevModeEnabled: flag.devMode,
        gateClosedRedirectPath: home,
      );

  test('only a superuser in developer mode may see P2P', () {
    for (final flag in flags) {
      expect(
        P2pFeature.isVisibleTo(
          isSuperuser: flag.superuser,
          isDevModeEnabled: flag.devMode,
        ),
        flag.superuser && flag.devMode,
        reason: '$flag',
      );
    }
  });

  for (final path in ['/p2p', '/p2p/order']) {
    group(path, () {
      for (final flag in flags) {
        final open = flag.superuser && flag.devMode;
        test('$flag: ${open ? 'let through' : 'sent to the wallet'}', () {
          expect(redirect(path, flag), open ? isNull : home);
        });
      }
    });
  }

  for (final path in ['/p2px', '/wallet']) {
    group(path, () {
      for (final flag in flags) {
        test('$flag: never redirected', () {
          expect(redirect(path, flag), isNull);
        });
      }
    });
  }

  test('the pages of the tab are /p2p and below only', () {
    expect(P2pFeature.isP2pPath('/p2p'), isTrue);
    expect(P2pFeature.isP2pPath('/p2p/order'), isTrue);
    expect(P2pFeature.isP2pPath('/p2px'), isFalse);
    expect(P2pFeature.isP2pPath('/wallet'), isFalse);
  });
}
