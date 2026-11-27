/// The public relays the design note chose for a copy of the recovery notes (#81, design note `docs/design/garage-key-from-the-words.md` § 4), embedded as the coordinators' list is: a setting, changed by a pull request, never read from the network.
///
/// **Not called.** They must be reached through Tor only, and the embedded Tor of `bull_tor` refuses every destination that is not an onion service (`SocksPolicy.onionOnly`, for the client and for each session, `onion_tor_backend.dart`): reaching them needs a session that accepts the clearnet in `bull_tor`, which a pull request of its own decides. Until then the notes are written and read on the coordinators' relays only, and this list waits; nothing may reach these relays outside Tor.
const List<String> publicNoteRelays = [
  'wss://nos.lol',
  'wss://nostr.bitcoiner.social',
  'wss://relay.primal.net',
  'wss://nostr.mom',
  'wss://nostr.oxtr.dev',
];
