import 'dart:convert';
import 'dart:math';

import 'package:meta/meta.dart';
import 'package:robosats/src/coordinator/coordinator.dart';
import 'package:robosats/src/coordinator/federation.dart';
import 'package:robosats/src/coordinator/nostr_chat.dart';
import 'package:robosats/src/coordinator/robosats_network.dart';
import 'package:robosats/src/coordinator/robot_session_key.dart';

/// Signed events ready to publish on a relay: the two gift wraps of an [OutgoingNostrChatMessage] (#94), or the one event of an `OutgoingHostRating`.
abstract interface class NostrRelayPublication {
  /// The `["EVENT", <event>]` messages to send to a relay, in order.
  List<String> get relayMessages;

  /// The ids of the events, in the order of [relayMessages]: what a relay's `OK` names.
  List<String> get eventIds;
}

/// The port to the coordinators' Nostr relays, which the app implements over Tor in `features/p2p`: publishes the events of one [NostrRelayPublication] on one relay.
///
/// Contract of an implementation:
/// - [publish] always completes, never throws, within a bound of its own;
/// - it connects to the relay, sends [NostrRelayPublication.relayMessages] in order, waits for the relay's `OK` to each event ([NostrRelayOk]) and closes, the wait only serving to close cleanly and to report;
/// - it goes through a Tor session of [robot] to the relay's onion service, apart from every other robot;
/// - it logs nothing of the events, of the relay or of the robot.
abstract interface class NostrRelayTransport {
  Future<NostrRelayOutcome> publish(
    Uri relay,
    NostrRelayPublication message, {
    required RobotSessionKey robot,
  });
}

/// What one relay did with the events of a publication: a value for a log line, nothing else, since the official client neither waits nor tells anything (`RoboPool.sendEvent`, `frontend/src/services/RoboPool/index.ts:622-626`, commit babf62e).
sealed class NostrRelayOutcome {
  const NostrRelayOutcome();

  /// A fixed word for a log line: never a relay, an event id or a relay's text.
  String get label;
}

/// The relay accepted every event (`["OK", id, true, …]`), or already had it.
final class NostrRelayAccepted extends NostrRelayOutcome {
  const NostrRelayAccepted();
  @override
  String get label => 'accepted';
}

/// The relay refused at least one event (`["OK", id, false, …]`); its reason is not kept.
final class NostrRelayRefused extends NostrRelayOutcome {
  const NostrRelayRefused();
  @override
  String get label => 'refused';
}

/// The relay could not be reached, or did not take the websocket.
final class NostrRelayUnreachable extends NostrRelayOutcome {
  const NostrRelayUnreachable();
  @override
  String get label => 'unreachable';
}

/// Not every event was answered within the bound: they may have been published all the same.
final class NostrRelayTimedOut extends NostrRelayOutcome {
  const NostrRelayTimedOut();
  @override
  String get label => 'timedOut';
}

/// No Tor session could be had for the robot at that moment: nothing was sent.
final class NostrRelayBusy extends NostrRelayOutcome {
  const NostrRelayBusy();
  @override
  String get label => 'busy';
}

/// Anything else: an address the transport does not accept, sessions closed meanwhile, a relay speaking something else.
final class NostrRelayFailed extends NostrRelayOutcome {
  const NostrRelayFailed();
  @override
  String get label => 'failed';
}

/// A relay's answer to an event, `["OK", <event id>, <true|false>, <message>]` (NIP-01).
@immutable
final class NostrRelayOk {
  final String eventId;
  final bool accepted;

  const NostrRelayOk(this.eventId, this.accepted);

  /// The `OK` [frame] carries, or `null` for any other message of the relay (`NOTICE`, `CLOSED`, …) and for anything malformed.
  static NostrRelayOk? parse(String frame) {
    final Object? message;
    try {
      message = jsonDecode(frame);
    } on FormatException {
      return null;
    }
    if (message is! List<Object?> ||
        message.length < 3 ||
        message[0] != 'OK' ||
        message[1] is! String ||
        message[2] is! bool) {
      return null;
    }
    return NostrRelayOk(message[1] as String, message[2] as bool);
  }
}

/// The relays a message is published to, as the official client builds its pool (`RoboPool.updateRelays`, `frontend/src/services/RoboPool/index.ts:116-137`, commit babf62e; its later replacement of a relay down for 10 minutes does not apply to a publication, which is not kept open): the relay of the order's coordinator first, in the place the reference gives to the relay of the coordinator that serves its page, then relays drawn at random among the federation's until there are `min(3, n)`, `n` being the number of coordinators with a relay on [network].
///
/// Empty when the order's coordinator has no relay on [network].
List<Uri> nostrRelaysFor(
  Coordinator orderCoordinator,
  Federation federation,
  RobosatsNetwork network,
  Random random,
) {
  final first = OutgoingNostrChatMessage.relayUrl(orderCoordinator, network);
  if (first == null) return const [];
  final federationRelays = [
    for (final coordinator in federation.coordinators)
      ?OutgoingNostrChatMessage.relayUrl(coordinator, network),
  ];
  final relays = [first];
  final target = min(3, federationRelays.length);
  final others = federationRelays.where((relay) => relay != first).toList();
  while (relays.length < target && others.isNotEmpty) {
    relays.add(others.removeAt(random.nextInt(others.length)));
  }
  return List.unmodifiable(relays);
}
