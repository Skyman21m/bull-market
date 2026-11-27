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

/// A filter of a relay request (`["REQ", <subscription id>, <filter>]`, NIP-01), as an [OwnSessionNostrRelayTransport] sends it.
abstract interface class NostrRelayFilter {
  /// The filter's JSON object, as it is sent.
  String toJson();

  /// The start of the subscription id the request is sent under, to which the transport adds `_` and a few random characters, as the official client names its subscriptions (`accountRecovery_<random>`, `RoboPool/index.ts:634`, commit babf62e): a fixed word of the client, never a value of the filter.
  String get subscriptionLabel;
}

/// The port to the coordinators' Nostr relays for what belongs to no robot, such as the recovery note of a Garage Key (#81): a publication or a read, each on a Tor session of its own, which the app implements over Tor in `features/p2p`.
///
/// Contract of an implementation:
/// - each call goes through a Tor session of its own, opened for that call and closed after it, shared with no robot, with no anonymous read of the books and with no other call: a relay, or anyone watching one, can tie one call to another only by what the calls themselves carry, and by their times;
/// - [publishOnOwnSession] sends [NostrRelayPublication.relayMessages] in order, waits for the relay's `OK` to each event and closes, as [NostrRelayTransport.publish] does;
/// - [readOnOwnSession] sends one `REQ` per filter on one websocket, each under its own subscription id, keeps the events the relay sends for those subscriptions until each has its `EOSE`, or its `CLOSED`, or a bound is reached, then sends a `CLOSE` for each and closes;
/// - both always complete, never throw, within a bound of time of their own; a read is also bounded in events, in bytes and in the length of one message, so that a relay that sends without end, slowly, or never sends `EOSE` costs a bounded time and memory;
/// - they log nothing of the events, the filters or the relay: at most a fixed word.
abstract interface class OwnSessionNostrRelayTransport {
  Future<NostrRelayOutcome> publishOnOwnSession(
    Uri relay,
    NostrRelayPublication message,
  );

  Future<NostrRelayRead> readOnOwnSession(
    Uri relay,
    List<NostrRelayFilter> filters,
  );
}

/// What one relay answered to the filters of a read ([OwnSessionNostrRelayTransport.readOnOwnSession]).
@immutable
final class NostrRelayRead {
  /// The JSON texts of the events the relay sent for the read's subscriptions, in the order received, duplicates included, as many as the transport's bound at most: data from the relay, never trusted.
  final List<String> events;

  /// Whether every subscription ended with the relay's `EOSE` within the bounds: the relay's whole answer. A relay that closed a subscription (`CLOSED`), stopped, or went past a bound gave part of it at most.
  final bool complete;

  /// A fixed word for a log line: never a relay, an event or a filter.
  final String label;

  NostrRelayRead({
    required Iterable<String> events,
    required this.complete,
    required this.label,
  }) : events = List.unmodifiable(events);

  /// No answer: the relay could not be reached, or the read failed before any event.
  const NostrRelayRead.none(this.label) : events = const [], complete = false;

  @override
  String toString() =>
      'NostrRelayRead(${events.length} events, complete: $complete, $label)';
}

/// What one relay did with the events of a publication: a value for a log line, nothing else, since the official client awaits no `OK` and tells nothing (`RoboPool.sendEvent`, `frontend/src/services/RoboPool/index.ts:622-626`, commit babf62e; it only tries a socket not yet connected again every 500 ms, `sendMessage`, `:387-403`).
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

/// Every coordinator relay of [federation] on [network], in the federation's order: where the recovery note of a Garage Key is written and read (#81, design note `docs/design/garage-key-from-the-words.md` § 3, « This design »: on every coordinator relay of the network, where the official client draws `min(3, n)` of them, `nostrRelaysFor`).
///
/// A coordinator without a relay on [network] gives none.
List<Uri> nostrRelaysOfNetwork(
  Federation federation,
  RobosatsNetwork network,
) => List.unmodifiable([
  for (final coordinator in federation.coordinators)
    ?OutgoingNostrChatMessage.relayUrl(coordinator, network),
]);
