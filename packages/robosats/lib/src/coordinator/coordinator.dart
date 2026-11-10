import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/src/coordinator/robosats_network.dart';
import 'package:robosats/src/robosats_failure.dart';

/// The addresses of one instance of a coordinator: an empty or missing address in the federation list is `null` here.
@immutable
final class CoordinatorOrigins {
  /// `http://<56 characters>.onion`, without a trailing slash.
  final String? onion;
  final String? clearnet;
  final String? i2p;

  const CoordinatorOrigins({this.onion, this.clearnet, this.i2p});

  @override
  bool operator ==(Object other) =>
      other is CoordinatorOrigins &&
      other.onion == onion &&
      other.clearnet == clearnet &&
      other.i2p == i2p;

  @override
  int get hashCode => Object.hash(onion, clearnet, i2p);

  @override
  String toString() => 'CoordinatorOrigins($onion)';
}

/// How to reach the operator of a coordinator: an empty or missing entry in the federation list is `null` here.
@immutable
final class CoordinatorContact {
  final String? email;
  final String? telegram;
  final String? simplex;
  final String? matrix;
  final String? website;
  final String? nostr;

  /// The path of the operator's OpenPGP key on the coordinator's web app, such as `/static/federation/pgp/<fingerprint>.asc`.
  final String? pgp;
  final String? fingerprint;
  final String? reddit;
  final String? twitter;

  const CoordinatorContact({
    this.email,
    this.telegram,
    this.simplex,
    this.matrix,
    this.website,
    this.nostr,
    this.pgp,
    this.fingerprint,
    this.reddit,
    this.twitter,
  });

  @override
  bool operator ==(Object other) =>
      other is CoordinatorContact &&
      other.email == email &&
      other.telegram == telegram &&
      other.simplex == simplex &&
      other.matrix == matrix &&
      other.website == website &&
      other.nostr == nostr &&
      other.pgp == pgp &&
      other.fingerprint == fingerprint &&
      other.reddit == reddit &&
      other.twitter == twitter;

  @override
  int get hashCode => Object.hash(
    email,
    telegram,
    simplex,
    matrix,
    website,
    nostr,
    pgp,
    fingerprint,
    reddit,
    twitter,
  );

  @override
  String toString() => 'CoordinatorContact(…)';
}

/// The badges the coordinator dialog shows, greyed out or not.
@immutable
final class CoordinatorBadges {
  final bool isFounder;

  /// The share of its proceeds the coordinator gives to the development fund, in percent: the badge is lit from 20.
  final int donatesToDevFund;
  final bool hasGoodOpSec;
  final bool hasLargeLimits;

  const CoordinatorBadges({
    required this.isFounder,
    required this.donatesToDevFund,
    required this.hasGoodOpSec,
    required this.hasLargeLimits,
  });

  @override
  bool operator ==(Object other) =>
      other is CoordinatorBadges &&
      other.isFounder == isFounder &&
      other.donatesToDevFund == donatesToDevFund &&
      other.hasGoodOpSec == hasGoodOpSec &&
      other.hasLargeLimits == hasLargeLimits;

  @override
  int get hashCode =>
      Object.hash(isFounder, donatesToDevFund, hasGoodOpSec, hasLargeLimits);

  @override
  String toString() =>
      'CoordinatorBadges(founder: $isFounder, devFund: $donatesToDevFund, opSec: $hasGoodOpSec, largeLimits: $hasLargeLimits)';
}

/// A coordinator of the RoboSats federation, as the federation list describes it.
///
/// Every field comes from `frontend/static/federation.json` of RoboSats, embedded in this package: see [Federation.robosats].
@immutable
final class Coordinator {
  /// The key of the coordinator in the federation list, such as `temple`: lowercase letters and digits.
  final String shortAlias;

  /// The display name, such as `Temple of Sats`.
  final String longAlias;
  final String identifier;
  final String description;
  final String motto;

  /// The brand colour of the coordinator as a CSS hexadecimal colour, such as `#000` or `#ff6b35`.
  final String color;

  /// The date the coordinator joined the federation, as `YYYY-MM-DD`: see [establishedOn].
  final String established;

  /// The Nostr public key of the coordinator, 64 hexadecimal characters.
  final String nostrHexPubkey;
  final CoordinatorContact contact;
  final CoordinatorBadges badges;

  /// The policies of the coordinator, title to text, in the order of the federation list.
  final Map<String, String> policies;
  final CoordinatorOrigins mainnet;
  final CoordinatorOrigins testnet;

  /// The public keys of the Lightning nodes of the mainnet instance, 66 hexadecimal characters each.
  final List<String> mainnetNodesPubkeys;

  /// The public keys of the Lightning nodes of the testnet instance, 66 hexadecimal characters each.
  final List<String> testnetNodesPubkeys;
  final bool federated;

  const Coordinator({
    required this.shortAlias,
    required this.longAlias,
    required this.identifier,
    required this.description,
    required this.motto,
    required this.color,
    required this.established,
    required this.nostrHexPubkey,
    required this.contact,
    required this.badges,
    required this.policies,
    required this.mainnet,
    required this.testnet,
    required this.mainnetNodesPubkeys,
    required this.testnetNodesPubkeys,
    required this.federated,
  });

  /// The date the coordinator joined the federation, at midnight UTC.
  DateTime get establishedOn => DateTime.parse('${established}T00:00:00Z');

  /// The addresses of the instance on [network].
  CoordinatorOrigins origins(RobosatsNetwork network) => switch (network) {
    RobosatsNetwork.mainnet => mainnet,
    RobosatsNetwork.testnet => testnet,
  };

  /// The Lightning node public keys of the instance on [network].
  List<String> nodesPubkeys(RobosatsNetwork network) => switch (network) {
    RobosatsNetwork.mainnet => mainnetNodesPubkeys,
    RobosatsNetwork.testnet => testnetNodesPubkeys,
  };

  /// Whether the coordinator has an onion address on [network], the only kind of address this package sends requests to.
  bool isOn(RobosatsNetwork network) => origins(network).onion != null;

  /// Checks the `network` and `node_id` a coordinator announced against this federation entry.
  ///
  /// The onion address already authenticates the server: this check catches a coordinator that runs another Lightning node, or the instance of the other network, than the federation list says.
  /// Fails with [CoordinatorNetworkMismatch] when [announcedNetwork] is not [expected], or is `null` for a value this package does not know, and with [CoordinatorNodeIdMismatch] when [announcedNodeId] is not one of [nodesPubkeys] on [expected].
  Result<void, CoordinatorIdentityFailure> verifyIdentity({
    required RobosatsNetwork expected,
    required RobosatsNetwork? announcedNetwork,
    required String announcedNodeId,
  }) {
    if (announcedNetwork != expected) {
      return const Err(CoordinatorNetworkMismatch());
    }
    if (!nodesPubkeys(expected).contains(announcedNodeId)) {
      return const Err(CoordinatorNodeIdMismatch());
    }
    return const Ok(null);
  }

  /// Coordinators are identified by their short alias.
  @override
  bool operator ==(Object other) =>
      other is Coordinator && other.shortAlias == shortAlias;

  @override
  int get hashCode => shortAlias.hashCode;

  @override
  String toString() => 'Coordinator($shortAlias)';
}
