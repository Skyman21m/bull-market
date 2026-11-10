import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';

// The P2P texts must load in every language of the app: the shell reads the label of the P2P tab with `P2pLocalizations.of`, which throws for a language the feature does not support.
void main() {
  test('P2P supports every language of the app', () {
    for (final locale in AppLocalizations.supportedLocales) {
      expect(
        P2pLocalizations.delegate.isSupported(locale),
        isTrue,
        reason: 'add features/p2p/lib/l10n/p2p_${locale.toLanguageTag().replaceAll('-', '_')}.arb',
      );
      expect(lookupP2pLocalizations(locale).p2pTabLabel, isNotEmpty);
    }
  });
}
