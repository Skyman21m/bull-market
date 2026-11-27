/// The texts a robot clear-signs for the requests that change a state on a coordinator: since the fix of GHSA-22q8-9ghc-jg3h (RoboSats pull request 2955, head `0943c9748ac35f13319628aac5054f6dd50512ca`, not yet merged upstream on 2026-11-27), the bearer header is a read credential only, and every such request also carries, in its `signature` field, a cleartext signature by the robot's key of one of these texts.
///
/// Byte for byte the reference's `frontend/src/utils/actionSignature.ts` and what `api/utils.py` rebuilds (`validate_action_signature`, `validate_signed_action_timestamp`), at that head:
///
/// | Request | Signed text | Window |
/// | --- | --- | --- |
/// | `POST /api/order/` (every action) | `{action}:{order_id}:{shortAlias}` | none |
/// | `POST /api/make/` | `make:{shortAlias}:{unix_ts}` | ± 300 s |
/// | `POST /api/stealth/` | `stealth:{shortAlias}:{unix_ts}` | ± 300 s |
/// | `PUT /api/robot/` | `robot:{shortAlias}:{unix_ts}` | ± 300 s |
/// | `POST /api/review/` | `review:{pubkey}` | none |
///
/// `shortAlias` is the coordinator's alias in the federation list this client embeds ([Coordinator.shortAlias]), never a value a coordinator sends: the coordinator compares it with its own (`get_federation_short_alias`), so that a signature captured by one coordinator cannot be replayed at another.
/// This client sends neither `stealth` nor `PUT /api/robot/`; their text is here for completeness.
library;

import 'package:robosats/src/coordinator/coordinator.dart';

/// How far from the coordinator's clock the time of a timed text may be: `ACTION_SIGNATURE_WINDOW` of `api/utils.py`, 300 seconds either way.
const actionSignatureWindow = Duration(seconds: 300);

/// The text signed for [action] on the order [orderId] of the coordinator [shortAlias]: `{action}:{order_id}:{shortAlias}` (`orderActionContent`).
String orderActionContent(String action, int orderId, String shortAlias) =>
    '$action:$orderId:$shortAlias';

/// The text signed for [action] outside an order (`make`, `stealth`, `robot`) to the coordinator [shortAlias] at [now]: `{action}:{shortAlias}:{unix_ts}`, the time in whole seconds since the Unix epoch, rounded down as `Math.floor(Date.now() / 1000)` (`timedActionContent`).
String timedActionContent(String action, String shortAlias, DateTime now) =>
    '$action:$shortAlias:${unixSeconds(now)}';

/// The text signed for the token to rate a coordinator with the robot's Nostr public key [pubkeyHex]: `review:{pubkey}`, with no time (`reviewActionContent`).
String reviewActionContent(String pubkeyHex) => 'review:$pubkeyHex';

/// [now] in whole seconds since the Unix epoch, rounded down, never in milliseconds.
int unixSeconds(DateTime now) {
  final milliseconds = now.millisecondsSinceEpoch;
  return milliseconds >= 0
      ? milliseconds ~/ 1000
      : -((-milliseconds + 999) ~/ 1000);
}
