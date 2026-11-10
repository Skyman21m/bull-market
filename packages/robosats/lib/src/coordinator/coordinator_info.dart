import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/src/coordinator/json_fields.dart';
import 'package:robosats/src/coordinator/read_bounds.dart';
import 'package:robosats/src/coordinator/robosats_network.dart';
import 'package:robosats/src/robosats_failure.dart';

/// The version of the RoboSats backend a coordinator runs.
@immutable
final class CoordinatorVersion implements Comparable<CoordinatorVersion> {
  final int major;
  final int minor;
  final int patch;

  const CoordinatorVersion(this.major, this.minor, this.patch);

  @override
  int compareTo(CoordinatorVersion other) =>
      switch ((major.compareTo(other.major), minor.compareTo(other.minor))) {
        (0, 0) => patch.compareTo(other.patch),
        (0, final minorOrder) => minorOrder,
        (final majorOrder, _) => majorOrder,
      };

  @override
  bool operator ==(Object other) =>
      other is CoordinatorVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// How the coordinator asks the client to show its notice.
enum NoticeSeverity {
  none,
  info,
  success,
  warning,
  error;

  /// Reads `notice_severity` ignoring case: one live coordinator sends `Info`.
  ///
  /// An unknown value is shown as [info], so a notice is never hidden by its severity.
  static NoticeSeverity fromWire(String value) {
    final lower = value.toLowerCase();
    for (final severity in values) {
      if (severity.name == lower) return severity;
    }
    return info;
  }
}

/// What a coordinator says about itself on `GET /api/info/` (`InfoView`, `api/views.py:977-1074`).
///
/// The identity fields, [network] and [nodeId], have been checked against the federation list when this comes from `CoordinatorClient.fetchInfo`.
/// Every string is coordinator text: display it as text, never as markup, and never log it.
@immutable
final class CoordinatorInfo {
  final int numPublicBuyOrders;
  final int numPublicSellOrders;

  /// The sats of all public orders.
  final Sats bookLiquidity;
  final int activeRobotsToday;

  /// The average premium of the last 24 hours, weighted by volume, in percent.
  final double lastDayNonKycBtcPremium;

  /// In BTC.
  final double lastDayVolume;

  /// In BTC.
  final double lifetimeVolume;

  /// The LND version, or a label such as `Not installed`.
  final String? lndVersion;

  /// The Core Lightning version, or a label such as `Not installed`.
  final String? clnVersion;
  final String? robosatsRunningCommitHash;
  final CoordinatorVersion version;

  /// The other instance of the coordinator, usually its onion address for the other network, without scheme.
  final String? alternativeSite;
  final String? alternativeName;
  final String nodeAlias;

  /// The public key of the coordinator's Lightning node, 66 lowercase hexadecimal characters.
  final String nodeId;

  /// The network the coordinator announces, or `null` for a value this package does not know.
  final RobosatsNetwork? network;

  /// The fee of the maker, as a fraction of the trade amount: 0.00025 is 0.025 %.
  final double makerFee;

  /// The fee of the taker, as a fraction of the trade amount.
  final double takerFee;

  /// The share of its proceeds the coordinator gives to the development fund, in percent.
  final double? devfund;

  /// The default bond, in percent.
  final double bondSize;

  /// The smallest order the coordinator accepts.
  final Sats minOrderSize;

  /// The largest order the coordinator accepts, at least [minOrderSize].
  final Sats maxOrderSize;

  /// Whether a buyer can be paid on-chain.
  final bool swapEnabled;
  final Sats maxSwap;

  /// The fee of an on-chain payout, in percent.
  final double? currentSwapFeeRate;
  final bool? blossomEnabled;
  final NoticeSeverity noticeSeverity;

  /// The notice of the coordinator, empty when it has none: it may contain HTML, which must be shown as plain text.
  final String noticeMessage;

  /// The price sources, as a comma-separated list of URLs.
  final String? marketPriceApis;

  /// The SHA-256, in hexadecimal, of the federation list the coordinator serves, which the official client uses to vote on the list.
  final String? federationHash;

  const CoordinatorInfo._({
    required this.numPublicBuyOrders,
    required this.numPublicSellOrders,
    required this.bookLiquidity,
    required this.activeRobotsToday,
    required this.lastDayNonKycBtcPremium,
    required this.lastDayVolume,
    required this.lifetimeVolume,
    required this.lndVersion,
    required this.clnVersion,
    required this.robosatsRunningCommitHash,
    required this.version,
    required this.alternativeSite,
    required this.alternativeName,
    required this.nodeAlias,
    required this.nodeId,
    required this.network,
    required this.makerFee,
    required this.takerFee,
    required this.devfund,
    required this.bondSize,
    required this.minOrderSize,
    required this.maxOrderSize,
    required this.swapEnabled,
    required this.maxSwap,
    required this.currentSwapFeeRate,
    required this.blossomEnabled,
    required this.noticeSeverity,
    required this.noticeMessage,
    required this.marketPriceApis,
    required this.federationHash,
  });

  static final RegExp _nodeId = RegExp(r'^0[23][0-9a-f]{64}$');
  static final RegExp _sha256Hex = RegExp(r'^[0-9a-f]{64}$');
  static const _counts = 1000000000;
  static const _btc = 21000000.0;
  static const _text = 1024;

  /// Reads the decoded body of `/api/info/`: any invalid field rejects the whole response, there being nothing to keep from half of it.
  ///
  /// Fields that older coordinators do not send (`devfund`, `blossom_enabled`, `federation_hash`, `current_swap_fee_rate`, the versions and the alternative site) are `null` when missing, but rejected when present with a wrong type.
  /// An unknown `network` is kept as `null` and fails the identity check; an unknown `notice_severity` is read as [NoticeSeverity.info]; a `federation_hash` that is not 64 hexadecimal characters is read as `null`, as the official client ignores it.
  @internal
  static Result<CoordinatorInfo, CoordinatorFailure> parse(Object? body) {
    if (body is! Map<String, Object?>) {
      return const Err(CoordinatorResponseMalformed('info'));
    }
    final fields = JsonFields(body);
    final buy = fields.requiredInt(
      'num_public_buy_orders',
      min: 0,
      max: _counts,
    );
    final sell = fields.requiredInt(
      'num_public_sell_orders',
      min: 0,
      max: _counts,
    );
    final liquidity = fields.requiredInt(
      'book_liquidity',
      min: 0,
      max: CoordinatorReadBounds.maxSats,
    );
    final robots = fields.requiredInt(
      'active_robots_today',
      min: 0,
      max: _counts,
    );
    final premium = fields.requiredDouble(
      'last_day_nonkyc_btc_premium',
      min: -100,
      max: 1e6,
    );
    final lastDayVolume = fields.requiredDouble(
      'last_day_volume',
      min: 0,
      max: _btc,
    );
    final lifetimeVolume = fields.requiredDouble(
      'lifetime_volume',
      min: 0,
      max: _btc,
    );
    final lnd = fields.optionalString('lnd_version', maxLength: _text);
    final cln = fields.optionalString('cln_version', maxLength: _text);
    final commit = fields.optionalString(
      'robosats_running_commit_hash',
      maxLength: _text,
    );
    final versionObject = fields.requiredObject('version');
    final alternativeSite = fields.optionalString(
      'alternative_site',
      maxLength: _text,
    );
    final alternativeName = fields.optionalString(
      'alternative_name',
      maxLength: _text,
    );
    final nodeAlias = fields.requiredString('node_alias', maxLength: _text);
    final nodeId = fields.requiredString('node_id', maxLength: 66);
    final network = fields.requiredString('network', maxLength: _text);
    final makerFee = fields.requiredDouble('maker_fee', min: 0, max: 1);
    final takerFee = fields.requiredDouble('taker_fee', min: 0, max: 1);
    final devfund = fields.optionalDouble('devfund', min: 0, max: 100);
    final bondSize = fields.requiredDouble('bond_size', min: 0, max: 100);
    final minOrder = fields.requiredInt(
      'min_order_size',
      min: 1,
      max: CoordinatorReadBounds.maxSats,
    );
    final maxOrder = fields.requiredInt(
      'max_order_size',
      min: 1,
      max: CoordinatorReadBounds.maxSats,
    );
    final swapEnabled = fields.requiredBool('swap_enabled');
    final maxSwap = fields.requiredInt(
      'max_swap',
      min: 0,
      max: CoordinatorReadBounds.maxSats,
    );
    final swapFee = fields.optionalDouble(
      'current_swap_fee_rate',
      min: 0,
      max: 100,
    );
    final blossom = fields.optionalBool('blossom_enabled');
    final severity = fields.optionalString('notice_severity', maxLength: 64);
    final notice = fields.optionalString('notice_message', maxLength: 16384);
    final priceApis = fields.optionalString(
      'market_price_apis',
      maxLength: 4096,
    );
    final federationHash = fields.optionalString(
      'federation_hash',
      maxLength: 128,
    );
    if (fields.rejected case final field?) {
      return Err(CoordinatorResponseMalformed(field));
    }
    if (!_nodeId.hasMatch(nodeId)) {
      return const Err(CoordinatorResponseMalformed('node_id'));
    }
    if (minOrder > maxOrder) {
      return const Err(CoordinatorResponseMalformed('max_order_size'));
    }
    if (versionObject == null) {
      return const Err(CoordinatorResponseMalformed('version'));
    }
    final versionFields = JsonFields(versionObject);
    final version = CoordinatorVersion(
      versionFields.requiredInt('major', min: 0, max: _counts),
      versionFields.requiredInt('minor', min: 0, max: _counts),
      versionFields.requiredInt('patch', min: 0, max: _counts),
    );
    if (versionFields.rejected != null) {
      return const Err(CoordinatorResponseMalformed('version'));
    }

    return Ok(
      CoordinatorInfo._(
        numPublicBuyOrders: buy,
        numPublicSellOrders: sell,
        bookLiquidity: Sats.fromInt(liquidity),
        activeRobotsToday: robots,
        lastDayNonKycBtcPremium: premium,
        lastDayVolume: lastDayVolume,
        lifetimeVolume: lifetimeVolume,
        lndVersion: lnd,
        clnVersion: cln,
        robosatsRunningCommitHash: commit,
        version: version,
        alternativeSite: alternativeSite,
        alternativeName: alternativeName,
        nodeAlias: nodeAlias,
        nodeId: nodeId,
        network: RobosatsNetwork.fromWire(network),
        makerFee: makerFee,
        takerFee: takerFee,
        devfund: devfund,
        bondSize: bondSize,
        minOrderSize: Sats.fromInt(minOrder),
        maxOrderSize: Sats.fromInt(maxOrder),
        swapEnabled: swapEnabled,
        maxSwap: Sats.fromInt(maxSwap),
        currentSwapFeeRate: swapFee,
        blossomEnabled: blossom,
        noticeSeverity: severity == null
            ? NoticeSeverity.none
            : NoticeSeverity.fromWire(severity),
        noticeMessage: notice ?? '',
        marketPriceApis: priceApis,
        federationHash:
            federationHash != null && _sha256Hex.hasMatch(federationHash)
            ? federationHash
            : null,
      ),
    );
  }

  /// Public, fixed-format data only: the coordinator's free text is left out.
  @override
  String toString() =>
      'CoordinatorInfo(${network?.name}, $nodeId, v$version, buy: $numPublicBuyOrders, sell: $numPublicSellOrders)';
}
