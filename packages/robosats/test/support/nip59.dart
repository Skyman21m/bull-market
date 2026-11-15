import 'dart:convert';

import 'package:convert/convert.dart';
import 'package:robosats/src/nostr/nip44.dart';
import 'package:robosats/src/nostr/nostr_event.dart';
import 'package:robosats/src/nostr/schnorr.dart';
import 'package:robosats/src/nostr_key_pair.dart';

/// An event read back from its JSON, with every check `verifyEvent` of `nostr-tools` makes when [signed]: the id recomputed from the fields, the BIP-340 signature of the id by `pubkey`.
Map<String, dynamic> readEvent(String json, {required bool signed}) {
  final event = jsonDecode(json) as Map<String, dynamic>;
  final tags = [
    for (final tag in event['tags'] as List<dynamic>)
      (tag as List<dynamic>).cast<String>(),
  ];
  final id = NostrEvent.idOf(
    event['pubkey'] as String,
    event['created_at'] as int,
    event['kind'] as int,
    tags,
    event['content'] as String,
  );
  if (id != event['id']) throw StateError('event id does not match its fields');
  if (signed &&
      !Bip340.verify(
        hex.decode(event['pubkey'] as String),
        hex.decode(id),
        hex.decode(event['sig'] as String),
      )) {
    throw StateError('event signature is invalid');
  }
  return event;
}

/// The seal and rumor of a gift wrap, read with [recipient]'s key as `unwrapEvent` of `nip59.ts` (`nostr-tools` 2.25.2) reads them: wrap of kind 1059, seal of kind 13 with a valid signature, rumor of the seal's author.
({
  Map<String, dynamic> wrap,
  Map<String, dynamic> seal,
  Map<String, dynamic> rumor,
})
unwrap(String wrapJson, NostrKeyPair recipient) {
  final wrap = readEvent(wrapJson, signed: true);
  if (wrap['kind'] != 1059) throw StateError('not a gift wrap');
  final seal = readEvent(
    Nip44.decrypt(
      wrap['content'] as String,
      recipient.conversationKeyWith(wrap['pubkey'] as String),
    ),
    signed: true,
  );
  if (seal['kind'] != 13) throw StateError('not a seal');
  final rumor = readEvent(
    Nip44.decrypt(
      seal['content'] as String,
      recipient.conversationKeyWith(seal['pubkey'] as String),
    ),
    signed: false,
  );
  if (rumor['pubkey'] != seal['pubkey']) {
    throw StateError('rumor pubkey does not match seal pubkey');
  }
  return (wrap: wrap, seal: seal, rumor: rumor);
}
