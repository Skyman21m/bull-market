import 'dart:io';

import 'package:p2p/src/domain/public_note_relays.dart';
import 'package:test/test.dart';

/// The public relays of the design note (#81, § 4): embedded, secure websockets only, and called by nothing until `bull_tor` can reach them through Tor.
void main() {
  test('the five relays of the design note, secure websockets only', () {
    expect(publicNoteRelays, [
      'wss://nos.lol',
      'wss://nostr.bitcoiner.social',
      'wss://relay.primal.net',
      'wss://nostr.mom',
      'wss://nostr.oxtr.dev',
    ]);
    expect(publicNoteRelays.every((url) => Uri.parse(url).isScheme('wss')), isTrue);
  });

  test('no file of the feature reads the list: no public relay is reached', () {
    final readers = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            !file.path.endsWith('public_note_relays.dart') &&
            file.readAsStringSync().contains('publicNoteRelays'))
          file.path,
    ];
    expect(readers, isEmpty);
  });
}
