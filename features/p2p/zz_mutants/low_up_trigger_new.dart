// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'p2p_database.dart';

// ignore_for_file: type=lint
class $RobotBindingsTable extends RobotBindings
    with TableInfo<$RobotBindingsTable, RobotBindingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RobotBindingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _networkMeta = const VerificationMeta(
    'network',
  );
  @override
  late final GeneratedColumn<String> network = GeneratedColumn<String>(
    'network',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyFingerprintMeta = const VerificationMeta(
    'keyFingerprint',
  );
  @override
  late final GeneratedColumn<String> keyFingerprint = GeneratedColumn<String>(
    'key_fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _robotIndexMeta = const VerificationMeta(
    'robotIndex',
  );
  @override
  late final GeneratedColumn<int> robotIndex = GeneratedColumn<int>(
    'robot_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coordinatorAliasMeta = const VerificationMeta(
    'coordinatorAlias',
  );
  @override
  late final GeneratedColumn<String> coordinatorAlias = GeneratedColumn<String>(
    'coordinator_alias',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coordinatorOnionMeta = const VerificationMeta(
    'coordinatorOnion',
  );
  @override
  late final GeneratedColumn<String> coordinatorOnion = GeneratedColumn<String>(
    'coordinator_onion',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coordinatorNodeKeysMeta =
      const VerificationMeta('coordinatorNodeKeys');
  @override
  late final GeneratedColumn<String> coordinatorNodeKeys =
      GeneratedColumn<String>(
        'coordinator_node_keys',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _coordinatorNostrKeyMeta =
      const VerificationMeta('coordinatorNostrKey');
  @override
  late final GeneratedColumn<String> coordinatorNostrKey =
      GeneratedColumn<String>(
        'coordinator_nostr_key',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _boundAtMeta = const VerificationMeta(
    'boundAt',
  );
  @override
  late final GeneratedColumn<int> boundAt = GeneratedColumn<int>(
    'bound_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _provenanceMeta = const VerificationMeta(
    'provenance',
  );
  @override
  late final GeneratedColumn<String> provenance = GeneratedColumn<String>(
    'provenance',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints:
        'NOT NULL DEFAULT \'generated\' CHECK (provenance IN (\'generated\', \'acknowledged\'))',
    defaultValue: const CustomExpression('\'generated\''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    network,
    keyFingerprint,
    robotIndex,
    coordinatorAlias,
    coordinatorOnion,
    coordinatorNodeKeys,
    coordinatorNostrKey,
    boundAt,
    provenance,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'robot_bindings';
  @override
  VerificationContext validateIntegrity(
    Insertable<RobotBindingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('network')) {
      context.handle(
        _networkMeta,
        network.isAcceptableOrUnknown(data['network']!, _networkMeta),
      );
    } else if (isInserting) {
      context.missing(_networkMeta);
    }
    if (data.containsKey('key_fingerprint')) {
      context.handle(
        _keyFingerprintMeta,
        keyFingerprint.isAcceptableOrUnknown(
          data['key_fingerprint']!,
          _keyFingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_keyFingerprintMeta);
    }
    if (data.containsKey('robot_index')) {
      context.handle(
        _robotIndexMeta,
        robotIndex.isAcceptableOrUnknown(data['robot_index']!, _robotIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_robotIndexMeta);
    }
    if (data.containsKey('coordinator_alias')) {
      context.handle(
        _coordinatorAliasMeta,
        coordinatorAlias.isAcceptableOrUnknown(
          data['coordinator_alias']!,
          _coordinatorAliasMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_coordinatorAliasMeta);
    }
    if (data.containsKey('coordinator_onion')) {
      context.handle(
        _coordinatorOnionMeta,
        coordinatorOnion.isAcceptableOrUnknown(
          data['coordinator_onion']!,
          _coordinatorOnionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_coordinatorOnionMeta);
    }
    if (data.containsKey('coordinator_node_keys')) {
      context.handle(
        _coordinatorNodeKeysMeta,
        coordinatorNodeKeys.isAcceptableOrUnknown(
          data['coordinator_node_keys']!,
          _coordinatorNodeKeysMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_coordinatorNodeKeysMeta);
    }
    if (data.containsKey('coordinator_nostr_key')) {
      context.handle(
        _coordinatorNostrKeyMeta,
        coordinatorNostrKey.isAcceptableOrUnknown(
          data['coordinator_nostr_key']!,
          _coordinatorNostrKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_coordinatorNostrKeyMeta);
    }
    if (data.containsKey('bound_at')) {
      context.handle(
        _boundAtMeta,
        boundAt.isAcceptableOrUnknown(data['bound_at']!, _boundAtMeta),
      );
    } else if (isInserting) {
      context.missing(_boundAtMeta);
    }
    if (data.containsKey('provenance')) {
      context.handle(
        _provenanceMeta,
        provenance.isAcceptableOrUnknown(data['provenance']!, _provenanceMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {keyFingerprint, robotIndex};
  @override
  RobotBindingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RobotBindingRow(
      network: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}network'],
      )!,
      keyFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key_fingerprint'],
      )!,
      robotIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}robot_index'],
      )!,
      coordinatorAlias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coordinator_alias'],
      )!,
      coordinatorOnion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coordinator_onion'],
      )!,
      coordinatorNodeKeys: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coordinator_node_keys'],
      )!,
      coordinatorNostrKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coordinator_nostr_key'],
      )!,
      boundAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bound_at'],
      )!,
      provenance: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provenance'],
      )!,
    );
  }

  @override
  $RobotBindingsTable createAlias(String alias) {
    return $RobotBindingsTable(attachedDatabase, alias);
  }
}

class RobotBindingRow extends DataClass implements Insertable<RobotBindingRow> {
  /// The network of the coordinator, `mainnet` or `testnet`.
  final String network;

  /// The `GarageKeyFingerprint` of the key, 64 hexadecimal characters.
  final String keyFingerprint;

  /// The index of the robot in its key, a hardened BIP32 child number.
  final int robotIndex;

  /// The short alias of the coordinator in the federation list.
  final String coordinatorAlias;

  /// The onion origin of the coordinator's instance on the network.
  final String coordinatorOnion;

  /// The public keys of the Lightning nodes of that instance, sorted and joined with commas.
  final String coordinatorNodeKeys;

  /// The Nostr public key of the coordinator, in hexadecimal.
  final String coordinatorNostrKey;

  /// When the binding was written, in milliseconds since the epoch.
  final int boundAt;

  /// The origin of the key on [network] when the robot was bound, copied from `garage_key_histories` by the statement that binds: `generated` or `acknowledged` (since schema 2).
  ///
  /// Its constraints are the column's own, so that schema 2 adds it to the table without rebuilding it; its default is for the bindings of schema 1, all made under a key drawn here.
  final String provenance;
  const RobotBindingRow({
    required this.network,
    required this.keyFingerprint,
    required this.robotIndex,
    required this.coordinatorAlias,
    required this.coordinatorOnion,
    required this.coordinatorNodeKeys,
    required this.coordinatorNostrKey,
    required this.boundAt,
    required this.provenance,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['network'] = Variable<String>(network);
    map['key_fingerprint'] = Variable<String>(keyFingerprint);
    map['robot_index'] = Variable<int>(robotIndex);
    map['coordinator_alias'] = Variable<String>(coordinatorAlias);
    map['coordinator_onion'] = Variable<String>(coordinatorOnion);
    map['coordinator_node_keys'] = Variable<String>(coordinatorNodeKeys);
    map['coordinator_nostr_key'] = Variable<String>(coordinatorNostrKey);
    map['bound_at'] = Variable<int>(boundAt);
    map['provenance'] = Variable<String>(provenance);
    return map;
  }

  RobotBindingsCompanion toCompanion(bool nullToAbsent) {
    return RobotBindingsCompanion(
      network: Value(network),
      keyFingerprint: Value(keyFingerprint),
      robotIndex: Value(robotIndex),
      coordinatorAlias: Value(coordinatorAlias),
      coordinatorOnion: Value(coordinatorOnion),
      coordinatorNodeKeys: Value(coordinatorNodeKeys),
      coordinatorNostrKey: Value(coordinatorNostrKey),
      boundAt: Value(boundAt),
      provenance: Value(provenance),
    );
  }

  factory RobotBindingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RobotBindingRow(
      network: serializer.fromJson<String>(json['network']),
      keyFingerprint: serializer.fromJson<String>(json['keyFingerprint']),
      robotIndex: serializer.fromJson<int>(json['robotIndex']),
      coordinatorAlias: serializer.fromJson<String>(json['coordinatorAlias']),
      coordinatorOnion: serializer.fromJson<String>(json['coordinatorOnion']),
      coordinatorNodeKeys: serializer.fromJson<String>(
        json['coordinatorNodeKeys'],
      ),
      coordinatorNostrKey: serializer.fromJson<String>(
        json['coordinatorNostrKey'],
      ),
      boundAt: serializer.fromJson<int>(json['boundAt']),
      provenance: serializer.fromJson<String>(json['provenance']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'network': serializer.toJson<String>(network),
      'keyFingerprint': serializer.toJson<String>(keyFingerprint),
      'robotIndex': serializer.toJson<int>(robotIndex),
      'coordinatorAlias': serializer.toJson<String>(coordinatorAlias),
      'coordinatorOnion': serializer.toJson<String>(coordinatorOnion),
      'coordinatorNodeKeys': serializer.toJson<String>(coordinatorNodeKeys),
      'coordinatorNostrKey': serializer.toJson<String>(coordinatorNostrKey),
      'boundAt': serializer.toJson<int>(boundAt),
      'provenance': serializer.toJson<String>(provenance),
    };
  }

  RobotBindingRow copyWith({
    String? network,
    String? keyFingerprint,
    int? robotIndex,
    String? coordinatorAlias,
    String? coordinatorOnion,
    String? coordinatorNodeKeys,
    String? coordinatorNostrKey,
    int? boundAt,
    String? provenance,
  }) => RobotBindingRow(
    network: network ?? this.network,
    keyFingerprint: keyFingerprint ?? this.keyFingerprint,
    robotIndex: robotIndex ?? this.robotIndex,
    coordinatorAlias: coordinatorAlias ?? this.coordinatorAlias,
    coordinatorOnion: coordinatorOnion ?? this.coordinatorOnion,
    coordinatorNodeKeys: coordinatorNodeKeys ?? this.coordinatorNodeKeys,
    coordinatorNostrKey: coordinatorNostrKey ?? this.coordinatorNostrKey,
    boundAt: boundAt ?? this.boundAt,
    provenance: provenance ?? this.provenance,
  );
  RobotBindingRow copyWithCompanion(RobotBindingsCompanion data) {
    return RobotBindingRow(
      network: data.network.present ? data.network.value : this.network,
      keyFingerprint: data.keyFingerprint.present
          ? data.keyFingerprint.value
          : this.keyFingerprint,
      robotIndex: data.robotIndex.present
          ? data.robotIndex.value
          : this.robotIndex,
      coordinatorAlias: data.coordinatorAlias.present
          ? data.coordinatorAlias.value
          : this.coordinatorAlias,
      coordinatorOnion: data.coordinatorOnion.present
          ? data.coordinatorOnion.value
          : this.coordinatorOnion,
      coordinatorNodeKeys: data.coordinatorNodeKeys.present
          ? data.coordinatorNodeKeys.value
          : this.coordinatorNodeKeys,
      coordinatorNostrKey: data.coordinatorNostrKey.present
          ? data.coordinatorNostrKey.value
          : this.coordinatorNostrKey,
      boundAt: data.boundAt.present ? data.boundAt.value : this.boundAt,
      provenance: data.provenance.present
          ? data.provenance.value
          : this.provenance,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RobotBindingRow(')
          ..write('network: $network, ')
          ..write('keyFingerprint: $keyFingerprint, ')
          ..write('robotIndex: $robotIndex, ')
          ..write('coordinatorAlias: $coordinatorAlias, ')
          ..write('coordinatorOnion: $coordinatorOnion, ')
          ..write('coordinatorNodeKeys: $coordinatorNodeKeys, ')
          ..write('coordinatorNostrKey: $coordinatorNostrKey, ')
          ..write('boundAt: $boundAt, ')
          ..write('provenance: $provenance')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    network,
    keyFingerprint,
    robotIndex,
    coordinatorAlias,
    coordinatorOnion,
    coordinatorNodeKeys,
    coordinatorNostrKey,
    boundAt,
    provenance,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RobotBindingRow &&
          other.network == this.network &&
          other.keyFingerprint == this.keyFingerprint &&
          other.robotIndex == this.robotIndex &&
          other.coordinatorAlias == this.coordinatorAlias &&
          other.coordinatorOnion == this.coordinatorOnion &&
          other.coordinatorNodeKeys == this.coordinatorNodeKeys &&
          other.coordinatorNostrKey == this.coordinatorNostrKey &&
          other.boundAt == this.boundAt &&
          other.provenance == this.provenance);
}

class RobotBindingsCompanion extends UpdateCompanion<RobotBindingRow> {
  final Value<String> network;
  final Value<String> keyFingerprint;
  final Value<int> robotIndex;
  final Value<String> coordinatorAlias;
  final Value<String> coordinatorOnion;
  final Value<String> coordinatorNodeKeys;
  final Value<String> coordinatorNostrKey;
  final Value<int> boundAt;
  final Value<String> provenance;
  final Value<int> rowid;
  const RobotBindingsCompanion({
    this.network = const Value.absent(),
    this.keyFingerprint = const Value.absent(),
    this.robotIndex = const Value.absent(),
    this.coordinatorAlias = const Value.absent(),
    this.coordinatorOnion = const Value.absent(),
    this.coordinatorNodeKeys = const Value.absent(),
    this.coordinatorNostrKey = const Value.absent(),
    this.boundAt = const Value.absent(),
    this.provenance = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RobotBindingsCompanion.insert({
    required String network,
    required String keyFingerprint,
    required int robotIndex,
    required String coordinatorAlias,
    required String coordinatorOnion,
    required String coordinatorNodeKeys,
    required String coordinatorNostrKey,
    required int boundAt,
    this.provenance = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : network = Value(network),
       keyFingerprint = Value(keyFingerprint),
       robotIndex = Value(robotIndex),
       coordinatorAlias = Value(coordinatorAlias),
       coordinatorOnion = Value(coordinatorOnion),
       coordinatorNodeKeys = Value(coordinatorNodeKeys),
       coordinatorNostrKey = Value(coordinatorNostrKey),
       boundAt = Value(boundAt);
  static Insertable<RobotBindingRow> custom({
    Expression<String>? network,
    Expression<String>? keyFingerprint,
    Expression<int>? robotIndex,
    Expression<String>? coordinatorAlias,
    Expression<String>? coordinatorOnion,
    Expression<String>? coordinatorNodeKeys,
    Expression<String>? coordinatorNostrKey,
    Expression<int>? boundAt,
    Expression<String>? provenance,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (network != null) 'network': network,
      if (keyFingerprint != null) 'key_fingerprint': keyFingerprint,
      if (robotIndex != null) 'robot_index': robotIndex,
      if (coordinatorAlias != null) 'coordinator_alias': coordinatorAlias,
      if (coordinatorOnion != null) 'coordinator_onion': coordinatorOnion,
      if (coordinatorNodeKeys != null)
        'coordinator_node_keys': coordinatorNodeKeys,
      if (coordinatorNostrKey != null)
        'coordinator_nostr_key': coordinatorNostrKey,
      if (boundAt != null) 'bound_at': boundAt,
      if (provenance != null) 'provenance': provenance,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RobotBindingsCompanion copyWith({
    Value<String>? network,
    Value<String>? keyFingerprint,
    Value<int>? robotIndex,
    Value<String>? coordinatorAlias,
    Value<String>? coordinatorOnion,
    Value<String>? coordinatorNodeKeys,
    Value<String>? coordinatorNostrKey,
    Value<int>? boundAt,
    Value<String>? provenance,
    Value<int>? rowid,
  }) {
    return RobotBindingsCompanion(
      network: network ?? this.network,
      keyFingerprint: keyFingerprint ?? this.keyFingerprint,
      robotIndex: robotIndex ?? this.robotIndex,
      coordinatorAlias: coordinatorAlias ?? this.coordinatorAlias,
      coordinatorOnion: coordinatorOnion ?? this.coordinatorOnion,
      coordinatorNodeKeys: coordinatorNodeKeys ?? this.coordinatorNodeKeys,
      coordinatorNostrKey: coordinatorNostrKey ?? this.coordinatorNostrKey,
      boundAt: boundAt ?? this.boundAt,
      provenance: provenance ?? this.provenance,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (network.present) {
      map['network'] = Variable<String>(network.value);
    }
    if (keyFingerprint.present) {
      map['key_fingerprint'] = Variable<String>(keyFingerprint.value);
    }
    if (robotIndex.present) {
      map['robot_index'] = Variable<int>(robotIndex.value);
    }
    if (coordinatorAlias.present) {
      map['coordinator_alias'] = Variable<String>(coordinatorAlias.value);
    }
    if (coordinatorOnion.present) {
      map['coordinator_onion'] = Variable<String>(coordinatorOnion.value);
    }
    if (coordinatorNodeKeys.present) {
      map['coordinator_node_keys'] = Variable<String>(
        coordinatorNodeKeys.value,
      );
    }
    if (coordinatorNostrKey.present) {
      map['coordinator_nostr_key'] = Variable<String>(
        coordinatorNostrKey.value,
      );
    }
    if (boundAt.present) {
      map['bound_at'] = Variable<int>(boundAt.value);
    }
    if (provenance.present) {
      map['provenance'] = Variable<String>(provenance.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RobotBindingsCompanion(')
          ..write('network: $network, ')
          ..write('keyFingerprint: $keyFingerprint, ')
          ..write('robotIndex: $robotIndex, ')
          ..write('coordinatorAlias: $coordinatorAlias, ')
          ..write('coordinatorOnion: $coordinatorOnion, ')
          ..write('coordinatorNodeKeys: $coordinatorNodeKeys, ')
          ..write('coordinatorNostrKey: $coordinatorNostrKey, ')
          ..write('boundAt: $boundAt, ')
          ..write('provenance: $provenance, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TradesTable extends Trades with TableInfo<$TradesTable, TradeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TradesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _networkMeta = const VerificationMeta(
    'network',
  );
  @override
  late final GeneratedColumn<String> network = GeneratedColumn<String>(
    'network',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyFingerprintMeta = const VerificationMeta(
    'keyFingerprint',
  );
  @override
  late final GeneratedColumn<String> keyFingerprint = GeneratedColumn<String>(
    'key_fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _robotIndexMeta = const VerificationMeta(
    'robotIndex',
  );
  @override
  late final GeneratedColumn<int> robotIndex = GeneratedColumn<int>(
    'robot_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coordinatorAliasMeta = const VerificationMeta(
    'coordinatorAlias',
  );
  @override
  late final GeneratedColumn<String> coordinatorAlias = GeneratedColumn<String>(
    'coordinator_alias',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coordinatorOnionMeta = const VerificationMeta(
    'coordinatorOnion',
  );
  @override
  late final GeneratedColumn<String> coordinatorOnion = GeneratedColumn<String>(
    'coordinator_onion',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orderIdMeta = const VerificationMeta(
    'orderId',
  );
  @override
  late final GeneratedColumn<int> orderId = GeneratedColumn<int>(
    'order_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
    'origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _takenAtMeta = const VerificationMeta(
    'takenAt',
  );
  @override
  late final GeneratedColumn<int> takenAt = GeneratedColumn<int>(
    'taken_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _confirmedAtMeta = const VerificationMeta(
    'confirmedAt',
  );
  @override
  late final GeneratedColumn<int> confirmedAt = GeneratedColumn<int>(
    'confirmed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _closedAtMeta = const VerificationMeta(
    'closedAt',
  );
  @override
  late final GeneratedColumn<int> closedAt = GeneratedColumn<int>(
    'closed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    network,
    keyFingerprint,
    robotIndex,
    coordinatorAlias,
    coordinatorOnion,
    orderId,
    role,
    origin,
    takenAt,
    confirmedAt,
    closedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'trades';
  @override
  VerificationContext validateIntegrity(
    Insertable<TradeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('network')) {
      context.handle(
        _networkMeta,
        network.isAcceptableOrUnknown(data['network']!, _networkMeta),
      );
    } else if (isInserting) {
      context.missing(_networkMeta);
    }
    if (data.containsKey('key_fingerprint')) {
      context.handle(
        _keyFingerprintMeta,
        keyFingerprint.isAcceptableOrUnknown(
          data['key_fingerprint']!,
          _keyFingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_keyFingerprintMeta);
    }
    if (data.containsKey('robot_index')) {
      context.handle(
        _robotIndexMeta,
        robotIndex.isAcceptableOrUnknown(data['robot_index']!, _robotIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_robotIndexMeta);
    }
    if (data.containsKey('coordinator_alias')) {
      context.handle(
        _coordinatorAliasMeta,
        coordinatorAlias.isAcceptableOrUnknown(
          data['coordinator_alias']!,
          _coordinatorAliasMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_coordinatorAliasMeta);
    }
    if (data.containsKey('coordinator_onion')) {
      context.handle(
        _coordinatorOnionMeta,
        coordinatorOnion.isAcceptableOrUnknown(
          data['coordinator_onion']!,
          _coordinatorOnionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_coordinatorOnionMeta);
    }
    if (data.containsKey('order_id')) {
      context.handle(
        _orderIdMeta,
        orderId.isAcceptableOrUnknown(data['order_id']!, _orderIdMeta),
      );
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['origin']!, _originMeta),
      );
    } else if (isInserting) {
      context.missing(_originMeta);
    }
    if (data.containsKey('taken_at')) {
      context.handle(
        _takenAtMeta,
        takenAt.isAcceptableOrUnknown(data['taken_at']!, _takenAtMeta),
      );
    } else if (isInserting) {
      context.missing(_takenAtMeta);
    }
    if (data.containsKey('confirmed_at')) {
      context.handle(
        _confirmedAtMeta,
        confirmedAt.isAcceptableOrUnknown(
          data['confirmed_at']!,
          _confirmedAtMeta,
        ),
      );
    }
    if (data.containsKey('closed_at')) {
      context.handle(
        _closedAtMeta,
        closedAt.isAcceptableOrUnknown(data['closed_at']!, _closedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {keyFingerprint, robotIndex};
  @override
  TradeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TradeRow(
      network: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}network'],
      )!,
      keyFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key_fingerprint'],
      )!,
      robotIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}robot_index'],
      )!,
      coordinatorAlias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coordinator_alias'],
      )!,
      coordinatorOnion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coordinator_onion'],
      )!,
      orderId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_id'],
      ),
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      origin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin'],
      )!,
      takenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}taken_at'],
      )!,
      confirmedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}confirmed_at'],
      ),
      closedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}closed_at'],
      ),
    );
  }

  @override
  $TradesTable createAlias(String alias) {
    return $TradesTable(attachedDatabase, alias);
  }
}

class TradeRow extends DataClass implements Insertable<TradeRow> {
  /// The network of the robot's binding, `mainnet` or `testnet`.
  final String network;

  /// The `GarageKeyFingerprint` of the robot's key, 64 lowercase hexadecimal characters.
  final String keyFingerprint;

  /// The index of the robot in its key.
  final int robotIndex;

  /// The short alias of the coordinator, as the robot's binding records it.
  final String coordinatorAlias;

  /// The onion origin of the coordinator's instance, as the robot's binding records it.
  final String coordinatorOnion;

  /// The id of the order on that coordinator; absent only for a pending make, whose order the coordinator has not numbered yet (schema 8).
  final int? orderId;

  /// `buyer` or `seller`, fixed at the take, or at the make.
  final String role;

  /// `takenHere` for a take of this device, `madeHere` for an order this device made (schema 8), `recovered` for a trade the user took over after recovery found it.
  final String origin;

  /// When the row was written, in milliseconds since the epoch.
  final int takenAt;

  /// When the coordinator showed this robot as the order's taker, or as its maker, in milliseconds since the epoch; absent while the take or the make is pending.
  final int? confirmedAt;

  /// When the trade ended, or its pending take turned out not to have happened, in milliseconds since the epoch; absent while it is active.
  final int? closedAt;
  const TradeRow({
    required this.network,
    required this.keyFingerprint,
    required this.robotIndex,
    required this.coordinatorAlias,
    required this.coordinatorOnion,
    this.orderId,
    required this.role,
    required this.origin,
    required this.takenAt,
    this.confirmedAt,
    this.closedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['network'] = Variable<String>(network);
    map['key_fingerprint'] = Variable<String>(keyFingerprint);
    map['robot_index'] = Variable<int>(robotIndex);
    map['coordinator_alias'] = Variable<String>(coordinatorAlias);
    map['coordinator_onion'] = Variable<String>(coordinatorOnion);
    if (!nullToAbsent || orderId != null) {
      map['order_id'] = Variable<int>(orderId);
    }
    map['role'] = Variable<String>(role);
    map['origin'] = Variable<String>(origin);
    map['taken_at'] = Variable<int>(takenAt);
    if (!nullToAbsent || confirmedAt != null) {
      map['confirmed_at'] = Variable<int>(confirmedAt);
    }
    if (!nullToAbsent || closedAt != null) {
      map['closed_at'] = Variable<int>(closedAt);
    }
    return map;
  }

  TradesCompanion toCompanion(bool nullToAbsent) {
    return TradesCompanion(
      network: Value(network),
      keyFingerprint: Value(keyFingerprint),
      robotIndex: Value(robotIndex),
      coordinatorAlias: Value(coordinatorAlias),
      coordinatorOnion: Value(coordinatorOnion),
      orderId: orderId == null && nullToAbsent
          ? const Value.absent()
          : Value(orderId),
      role: Value(role),
      origin: Value(origin),
      takenAt: Value(takenAt),
      confirmedAt: confirmedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(confirmedAt),
      closedAt: closedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(closedAt),
    );
  }

  factory TradeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TradeRow(
      network: serializer.fromJson<String>(json['network']),
      keyFingerprint: serializer.fromJson<String>(json['keyFingerprint']),
      robotIndex: serializer.fromJson<int>(json['robotIndex']),
      coordinatorAlias: serializer.fromJson<String>(json['coordinatorAlias']),
      coordinatorOnion: serializer.fromJson<String>(json['coordinatorOnion']),
      orderId: serializer.fromJson<int?>(json['orderId']),
      role: serializer.fromJson<String>(json['role']),
      origin: serializer.fromJson<String>(json['origin']),
      takenAt: serializer.fromJson<int>(json['takenAt']),
      confirmedAt: serializer.fromJson<int?>(json['confirmedAt']),
      closedAt: serializer.fromJson<int?>(json['closedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'network': serializer.toJson<String>(network),
      'keyFingerprint': serializer.toJson<String>(keyFingerprint),
      'robotIndex': serializer.toJson<int>(robotIndex),
      'coordinatorAlias': serializer.toJson<String>(coordinatorAlias),
      'coordinatorOnion': serializer.toJson<String>(coordinatorOnion),
      'orderId': serializer.toJson<int?>(orderId),
      'role': serializer.toJson<String>(role),
      'origin': serializer.toJson<String>(origin),
      'takenAt': serializer.toJson<int>(takenAt),
      'confirmedAt': serializer.toJson<int?>(confirmedAt),
      'closedAt': serializer.toJson<int?>(closedAt),
    };
  }

  TradeRow copyWith({
    String? network,
    String? keyFingerprint,
    int? robotIndex,
    String? coordinatorAlias,
    String? coordinatorOnion,
    Value<int?> orderId = const Value.absent(),
    String? role,
    String? origin,
    int? takenAt,
    Value<int?> confirmedAt = const Value.absent(),
    Value<int?> closedAt = const Value.absent(),
  }) => TradeRow(
    network: network ?? this.network,
    keyFingerprint: keyFingerprint ?? this.keyFingerprint,
    robotIndex: robotIndex ?? this.robotIndex,
    coordinatorAlias: coordinatorAlias ?? this.coordinatorAlias,
    coordinatorOnion: coordinatorOnion ?? this.coordinatorOnion,
    orderId: orderId.present ? orderId.value : this.orderId,
    role: role ?? this.role,
    origin: origin ?? this.origin,
    takenAt: takenAt ?? this.takenAt,
    confirmedAt: confirmedAt.present ? confirmedAt.value : this.confirmedAt,
    closedAt: closedAt.present ? closedAt.value : this.closedAt,
  );
  TradeRow copyWithCompanion(TradesCompanion data) {
    return TradeRow(
      network: data.network.present ? data.network.value : this.network,
      keyFingerprint: data.keyFingerprint.present
          ? data.keyFingerprint.value
          : this.keyFingerprint,
      robotIndex: data.robotIndex.present
          ? data.robotIndex.value
          : this.robotIndex,
      coordinatorAlias: data.coordinatorAlias.present
          ? data.coordinatorAlias.value
          : this.coordinatorAlias,
      coordinatorOnion: data.coordinatorOnion.present
          ? data.coordinatorOnion.value
          : this.coordinatorOnion,
      orderId: data.orderId.present ? data.orderId.value : this.orderId,
      role: data.role.present ? data.role.value : this.role,
      origin: data.origin.present ? data.origin.value : this.origin,
      takenAt: data.takenAt.present ? data.takenAt.value : this.takenAt,
      confirmedAt: data.confirmedAt.present
          ? data.confirmedAt.value
          : this.confirmedAt,
      closedAt: data.closedAt.present ? data.closedAt.value : this.closedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TradeRow(')
          ..write('network: $network, ')
          ..write('keyFingerprint: $keyFingerprint, ')
          ..write('robotIndex: $robotIndex, ')
          ..write('coordinatorAlias: $coordinatorAlias, ')
          ..write('coordinatorOnion: $coordinatorOnion, ')
          ..write('orderId: $orderId, ')
          ..write('role: $role, ')
          ..write('origin: $origin, ')
          ..write('takenAt: $takenAt, ')
          ..write('confirmedAt: $confirmedAt, ')
          ..write('closedAt: $closedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    network,
    keyFingerprint,
    robotIndex,
    coordinatorAlias,
    coordinatorOnion,
    orderId,
    role,
    origin,
    takenAt,
    confirmedAt,
    closedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TradeRow &&
          other.network == this.network &&
          other.keyFingerprint == this.keyFingerprint &&
          other.robotIndex == this.robotIndex &&
          other.coordinatorAlias == this.coordinatorAlias &&
          other.coordinatorOnion == this.coordinatorOnion &&
          other.orderId == this.orderId &&
          other.role == this.role &&
          other.origin == this.origin &&
          other.takenAt == this.takenAt &&
          other.confirmedAt == this.confirmedAt &&
          other.closedAt == this.closedAt);
}

class TradesCompanion extends UpdateCompanion<TradeRow> {
  final Value<String> network;
  final Value<String> keyFingerprint;
  final Value<int> robotIndex;
  final Value<String> coordinatorAlias;
  final Value<String> coordinatorOnion;
  final Value<int?> orderId;
  final Value<String> role;
  final Value<String> origin;
  final Value<int> takenAt;
  final Value<int?> confirmedAt;
  final Value<int?> closedAt;
  final Value<int> rowid;
  const TradesCompanion({
    this.network = const Value.absent(),
    this.keyFingerprint = const Value.absent(),
    this.robotIndex = const Value.absent(),
    this.coordinatorAlias = const Value.absent(),
    this.coordinatorOnion = const Value.absent(),
    this.orderId = const Value.absent(),
    this.role = const Value.absent(),
    this.origin = const Value.absent(),
    this.takenAt = const Value.absent(),
    this.confirmedAt = const Value.absent(),
    this.closedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TradesCompanion.insert({
    required String network,
    required String keyFingerprint,
    required int robotIndex,
    required String coordinatorAlias,
    required String coordinatorOnion,
    this.orderId = const Value.absent(),
    required String role,
    required String origin,
    required int takenAt,
    this.confirmedAt = const Value.absent(),
    this.closedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : network = Value(network),
       keyFingerprint = Value(keyFingerprint),
       robotIndex = Value(robotIndex),
       coordinatorAlias = Value(coordinatorAlias),
       coordinatorOnion = Value(coordinatorOnion),
       role = Value(role),
       origin = Value(origin),
       takenAt = Value(takenAt);
  static Insertable<TradeRow> custom({
    Expression<String>? network,
    Expression<String>? keyFingerprint,
    Expression<int>? robotIndex,
    Expression<String>? coordinatorAlias,
    Expression<String>? coordinatorOnion,
    Expression<int>? orderId,
    Expression<String>? role,
    Expression<String>? origin,
    Expression<int>? takenAt,
    Expression<int>? confirmedAt,
    Expression<int>? closedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (network != null) 'network': network,
      if (keyFingerprint != null) 'key_fingerprint': keyFingerprint,
      if (robotIndex != null) 'robot_index': robotIndex,
      if (coordinatorAlias != null) 'coordinator_alias': coordinatorAlias,
      if (coordinatorOnion != null) 'coordinator_onion': coordinatorOnion,
      if (orderId != null) 'order_id': orderId,
      if (role != null) 'role': role,
      if (origin != null) 'origin': origin,
      if (takenAt != null) 'taken_at': takenAt,
      if (confirmedAt != null) 'confirmed_at': confirmedAt,
      if (closedAt != null) 'closed_at': closedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TradesCompanion copyWith({
    Value<String>? network,
    Value<String>? keyFingerprint,
    Value<int>? robotIndex,
    Value<String>? coordinatorAlias,
    Value<String>? coordinatorOnion,
    Value<int?>? orderId,
    Value<String>? role,
    Value<String>? origin,
    Value<int>? takenAt,
    Value<int?>? confirmedAt,
    Value<int?>? closedAt,
    Value<int>? rowid,
  }) {
    return TradesCompanion(
      network: network ?? this.network,
      keyFingerprint: keyFingerprint ?? this.keyFingerprint,
      robotIndex: robotIndex ?? this.robotIndex,
      coordinatorAlias: coordinatorAlias ?? this.coordinatorAlias,
      coordinatorOnion: coordinatorOnion ?? this.coordinatorOnion,
      orderId: orderId ?? this.orderId,
      role: role ?? this.role,
      origin: origin ?? this.origin,
      takenAt: takenAt ?? this.takenAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      closedAt: closedAt ?? this.closedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (network.present) {
      map['network'] = Variable<String>(network.value);
    }
    if (keyFingerprint.present) {
      map['key_fingerprint'] = Variable<String>(keyFingerprint.value);
    }
    if (robotIndex.present) {
      map['robot_index'] = Variable<int>(robotIndex.value);
    }
    if (coordinatorAlias.present) {
      map['coordinator_alias'] = Variable<String>(coordinatorAlias.value);
    }
    if (coordinatorOnion.present) {
      map['coordinator_onion'] = Variable<String>(coordinatorOnion.value);
    }
    if (orderId.present) {
      map['order_id'] = Variable<int>(orderId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (takenAt.present) {
      map['taken_at'] = Variable<int>(takenAt.value);
    }
    if (confirmedAt.present) {
      map['confirmed_at'] = Variable<int>(confirmedAt.value);
    }
    if (closedAt.present) {
      map['closed_at'] = Variable<int>(closedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TradesCompanion(')
          ..write('network: $network, ')
          ..write('keyFingerprint: $keyFingerprint, ')
          ..write('robotIndex: $robotIndex, ')
          ..write('coordinatorAlias: $coordinatorAlias, ')
          ..write('coordinatorOnion: $coordinatorOnion, ')
          ..write('orderId: $orderId, ')
          ..write('role: $role, ')
          ..write('origin: $origin, ')
          ..write('takenAt: $takenAt, ')
          ..write('confirmedAt: $confirmedAt, ')
          ..write('closedAt: $closedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StoredTradePayoutsTable extends StoredTradePayouts
    with TableInfo<$StoredTradePayoutsTable, TradePayoutRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredTradePayoutsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyFingerprintMeta = const VerificationMeta(
    'keyFingerprint',
  );
  @override
  late final GeneratedColumn<String> keyFingerprint = GeneratedColumn<String>(
    'key_fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _robotIndexMeta = const VerificationMeta(
    'robotIndex',
  );
  @override
  late final GeneratedColumn<int> robotIndex = GeneratedColumn<int>(
    'robot_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _takeMeta = const VerificationMeta('take');
  @override
  late final GeneratedColumn<int> take = GeneratedColumn<int>(
    'take',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _submittedAtMeta = const VerificationMeta(
    'submittedAt',
  );
  @override
  late final GeneratedColumn<int> submittedAt = GeneratedColumn<int>(
    'submitted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    keyFingerprint,
    robotIndex,
    take,
    source,
    kind,
    submittedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'trade_payouts';
  @override
  VerificationContext validateIntegrity(
    Insertable<TradePayoutRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key_fingerprint')) {
      context.handle(
        _keyFingerprintMeta,
        keyFingerprint.isAcceptableOrUnknown(
          data['key_fingerprint']!,
          _keyFingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_keyFingerprintMeta);
    }
    if (data.containsKey('robot_index')) {
      context.handle(
        _robotIndexMeta,
        robotIndex.isAcceptableOrUnknown(data['robot_index']!, _robotIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_robotIndexMeta);
    }
    if (data.containsKey('take')) {
      context.handle(
        _takeMeta,
        take.isAcceptableOrUnknown(data['take']!, _takeMeta),
      );
    } else if (isInserting) {
      context.missing(_takeMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('submitted_at')) {
      context.handle(
        _submittedAtMeta,
        submittedAt.isAcceptableOrUnknown(
          data['submitted_at']!,
          _submittedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {keyFingerprint, robotIndex, take};
  @override
  TradePayoutRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TradePayoutRow(
      keyFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key_fingerprint'],
      )!,
      robotIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}robot_index'],
      )!,
      take: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}take'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      ),
      submittedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}submitted_at'],
      ),
    );
  }

  @override
  $StoredTradePayoutsTable createAlias(String alias) {
    return $StoredTradePayoutsTable(attachedDatabase, alias);
  }
}

class TradePayoutRow extends DataClass implements Insertable<TradePayoutRow> {
  /// The trade's robot, as `trades` keys it.
  final String keyFingerprint;
  final int robotIndex;

  /// The contract the payout was given for, the trail's `take` of the read the payout was signed from: 0 for every taker and for a maker's first contract.
  final int take;

  /// `thisWallet` (an invoice or an address this wallet gave), `pasted` (anything else), or `unrecorded` (a contract under way before schema 9).
  final String source;

  /// `invoice` or `address`; absent for `unrecorded`.
  final String? kind;

  /// When the payout was submitted, in microseconds since the epoch; absent for `unrecorded` only.
  final int? submittedAt;
  const TradePayoutRow({
    required this.keyFingerprint,
    required this.robotIndex,
    required this.take,
    required this.source,
    this.kind,
    this.submittedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key_fingerprint'] = Variable<String>(keyFingerprint);
    map['robot_index'] = Variable<int>(robotIndex);
    map['take'] = Variable<int>(take);
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || kind != null) {
      map['kind'] = Variable<String>(kind);
    }
    if (!nullToAbsent || submittedAt != null) {
      map['submitted_at'] = Variable<int>(submittedAt);
    }
    return map;
  }

  StoredTradePayoutsCompanion toCompanion(bool nullToAbsent) {
    return StoredTradePayoutsCompanion(
      keyFingerprint: Value(keyFingerprint),
      robotIndex: Value(robotIndex),
      take: Value(take),
      source: Value(source),
      kind: kind == null && nullToAbsent ? const Value.absent() : Value(kind),
      submittedAt: submittedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(submittedAt),
    );
  }

  factory TradePayoutRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TradePayoutRow(
      keyFingerprint: serializer.fromJson<String>(json['keyFingerprint']),
      robotIndex: serializer.fromJson<int>(json['robotIndex']),
      take: serializer.fromJson<int>(json['take']),
      source: serializer.fromJson<String>(json['source']),
      kind: serializer.fromJson<String?>(json['kind']),
      submittedAt: serializer.fromJson<int?>(json['submittedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'keyFingerprint': serializer.toJson<String>(keyFingerprint),
      'robotIndex': serializer.toJson<int>(robotIndex),
      'take': serializer.toJson<int>(take),
      'source': serializer.toJson<String>(source),
      'kind': serializer.toJson<String?>(kind),
      'submittedAt': serializer.toJson<int?>(submittedAt),
    };
  }

  TradePayoutRow copyWith({
    String? keyFingerprint,
    int? robotIndex,
    int? take,
    String? source,
    Value<String?> kind = const Value.absent(),
    Value<int?> submittedAt = const Value.absent(),
  }) => TradePayoutRow(
    keyFingerprint: keyFingerprint ?? this.keyFingerprint,
    robotIndex: robotIndex ?? this.robotIndex,
    take: take ?? this.take,
    source: source ?? this.source,
    kind: kind.present ? kind.value : this.kind,
    submittedAt: submittedAt.present ? submittedAt.value : this.submittedAt,
  );
  TradePayoutRow copyWithCompanion(StoredTradePayoutsCompanion data) {
    return TradePayoutRow(
      keyFingerprint: data.keyFingerprint.present
          ? data.keyFingerprint.value
          : this.keyFingerprint,
      robotIndex: data.robotIndex.present
          ? data.robotIndex.value
          : this.robotIndex,
      take: data.take.present ? data.take.value : this.take,
      source: data.source.present ? data.source.value : this.source,
      kind: data.kind.present ? data.kind.value : this.kind,
      submittedAt: data.submittedAt.present
          ? data.submittedAt.value
          : this.submittedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TradePayoutRow(')
          ..write('keyFingerprint: $keyFingerprint, ')
          ..write('robotIndex: $robotIndex, ')
          ..write('take: $take, ')
          ..write('source: $source, ')
          ..write('kind: $kind, ')
          ..write('submittedAt: $submittedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(keyFingerprint, robotIndex, take, source, kind, submittedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TradePayoutRow &&
          other.keyFingerprint == this.keyFingerprint &&
          other.robotIndex == this.robotIndex &&
          other.take == this.take &&
          other.source == this.source &&
          other.kind == this.kind &&
          other.submittedAt == this.submittedAt);
}

class StoredTradePayoutsCompanion extends UpdateCompanion<TradePayoutRow> {
  final Value<String> keyFingerprint;
  final Value<int> robotIndex;
  final Value<int> take;
  final Value<String> source;
  final Value<String?> kind;
  final Value<int?> submittedAt;
  final Value<int> rowid;
  const StoredTradePayoutsCompanion({
    this.keyFingerprint = const Value.absent(),
    this.robotIndex = const Value.absent(),
    this.take = const Value.absent(),
    this.source = const Value.absent(),
    this.kind = const Value.absent(),
    this.submittedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredTradePayoutsCompanion.insert({
    required String keyFingerprint,
    required int robotIndex,
    required int take,
    required String source,
    this.kind = const Value.absent(),
    this.submittedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : keyFingerprint = Value(keyFingerprint),
       robotIndex = Value(robotIndex),
       take = Value(take),
       source = Value(source);
  static Insertable<TradePayoutRow> custom({
    Expression<String>? keyFingerprint,
    Expression<int>? robotIndex,
    Expression<int>? take,
    Expression<String>? source,
    Expression<String>? kind,
    Expression<int>? submittedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (keyFingerprint != null) 'key_fingerprint': keyFingerprint,
      if (robotIndex != null) 'robot_index': robotIndex,
      if (take != null) 'take': take,
      if (source != null) 'source': source,
      if (kind != null) 'kind': kind,
      if (submittedAt != null) 'submitted_at': submittedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredTradePayoutsCompanion copyWith({
    Value<String>? keyFingerprint,
    Value<int>? robotIndex,
    Value<int>? take,
    Value<String>? source,
    Value<String?>? kind,
    Value<int?>? submittedAt,
    Value<int>? rowid,
  }) {
    return StoredTradePayoutsCompanion(
      keyFingerprint: keyFingerprint ?? this.keyFingerprint,
      robotIndex: robotIndex ?? this.robotIndex,
      take: take ?? this.take,
      source: source ?? this.source,
      kind: kind ?? this.kind,
      submittedAt: submittedAt ?? this.submittedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (keyFingerprint.present) {
      map['key_fingerprint'] = Variable<String>(keyFingerprint.value);
    }
    if (robotIndex.present) {
      map['robot_index'] = Variable<int>(robotIndex.value);
    }
    if (take.present) {
      map['take'] = Variable<int>(take.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (submittedAt.present) {
      map['submitted_at'] = Variable<int>(submittedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredTradePayoutsCompanion(')
          ..write('keyFingerprint: $keyFingerprint, ')
          ..write('robotIndex: $robotIndex, ')
          ..write('take: $take, ')
          ..write('source: $source, ')
          ..write('kind: $kind, ')
          ..write('submittedAt: $submittedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StoredTradeTrailsTable extends StoredTradeTrails
    with TableInfo<$StoredTradeTrailsTable, TradeTrailRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredTradeTrailsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyFingerprintMeta = const VerificationMeta(
    'keyFingerprint',
  );
  @override
  late final GeneratedColumn<String> keyFingerprint = GeneratedColumn<String>(
    'key_fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _robotIndexMeta = const VerificationMeta(
    'robotIndex',
  );
  @override
  late final GeneratedColumn<int> robotIndex = GeneratedColumn<int>(
    'robot_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _networkMeta = const VerificationMeta(
    'network',
  );
  @override
  late final GeneratedColumn<String> network = GeneratedColumn<String>(
    'network',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coordinatorAliasMeta = const VerificationMeta(
    'coordinatorAlias',
  );
  @override
  late final GeneratedColumn<String> coordinatorAlias = GeneratedColumn<String>(
    'coordinator_alias',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orderIdMeta = const VerificationMeta(
    'orderId',
  );
  @override
  late final GeneratedColumn<int> orderId = GeneratedColumn<int>(
    'order_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<String> position = GeneratedColumn<String>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _readAtMeta = const VerificationMeta('readAt');
  @override
  late final GeneratedColumn<int> readAt = GeneratedColumn<int>(
    'read_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bondHashMeta = const VerificationMeta(
    'bondHash',
  );
  @override
  late final GeneratedColumn<String> bondHash = GeneratedColumn<String>(
    'bond_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _escrowHashMeta = const VerificationMeta(
    'escrowHash',
  );
  @override
  late final GeneratedColumn<String> escrowHash = GeneratedColumn<String>(
    'escrow_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deadlineMeta = const VerificationMeta(
    'deadline',
  );
  @override
  late final GeneratedColumn<int> deadline = GeneratedColumn<int>(
    'deadline',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bondStepSeenAtMeta = const VerificationMeta(
    'bondStepSeenAt',
  );
  @override
  late final GeneratedColumn<int> bondStepSeenAt = GeneratedColumn<int>(
    'bond_step_seen_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bondStepDeadlineMeta = const VerificationMeta(
    'bondStepDeadline',
  );
  @override
  late final GeneratedColumn<int> bondStepDeadline = GeneratedColumn<int>(
    'bond_step_deadline',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _breachedMeta = const VerificationMeta(
    'breached',
  );
  @override
  late final GeneratedColumn<bool> breached = GeneratedColumn<bool>(
    'breached',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("breached" IN (0, 1))',
    ),
  );
  static const VerificationMeta _historyUnknownMeta = const VerificationMeta(
    'historyUnknown',
  );
  @override
  late final GeneratedColumn<bool> historyUnknown = GeneratedColumn<bool>(
    'history_unknown',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("history_unknown" IN (0, 1))',
    ),
  );
  static const VerificationMeta _takeMeta = const VerificationMeta('take');
  @override
  late final GeneratedColumn<int> take = GeneratedColumn<int>(
    'take',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _takeDeadlineMeta = const VerificationMeta(
    'takeDeadline',
  );
  @override
  late final GeneratedColumn<int> takeDeadline = GeneratedColumn<int>(
    'take_deadline',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _takerHashIdMeta = const VerificationMeta(
    'takerHashId',
  );
  @override
  late final GeneratedColumn<String> takerHashId = GeneratedColumn<String>(
    'taker_hash_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _takenAmountMeta = const VerificationMeta(
    'takenAmount',
  );
  @override
  late final GeneratedColumn<double> takenAmount = GeneratedColumn<double>(
    'taken_amount',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _earlierEscrowsMeta = const VerificationMeta(
    'earlierEscrows',
  );
  @override
  late final GeneratedColumn<String> earlierEscrows = GeneratedColumn<String>(
    'earlier_escrows',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _seenLateMeta = const VerificationMeta(
    'seenLate',
  );
  @override
  late final GeneratedColumn<bool> seenLate = GeneratedColumn<bool>(
    'seen_late',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("seen_late" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _termsChangedAtMeta = const VerificationMeta(
    'termsChangedAt',
  );
  @override
  late final GeneratedColumn<int> termsChangedAt = GeneratedColumn<int>(
    'terms_changed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints:
        'NULL CHECK (terms_changed_at IS NULL OR (typeof(terms_changed_at) = \'integer\' AND terms_changed_at BETWEEN 0 AND read_at))',
  );
  static const VerificationMeta _termsChangedPremiumLowMeta =
      const VerificationMeta('termsChangedPremiumLow');
  @override
  late final GeneratedColumn<double>
  termsChangedPremiumLow = GeneratedColumn<double>(
    'terms_changed_premium_low',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints:
        'NULL CHECK (terms_changed_premium_low IS NULL OR (terms_changed_at IS NOT NULL AND typeof(terms_changed_premium_low) = \'real\' AND terms_changed_premium_low BETWEEN -100 AND 999))',
  );
  static const VerificationMeta _termsChangedPremiumHighMeta =
      const VerificationMeta('termsChangedPremiumHigh');
  @override
  late final GeneratedColumn<double>
  termsChangedPremiumHigh = GeneratedColumn<double>(
    'terms_changed_premium_high',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints:
        'NULL CHECK ((terms_changed_premium_high IS NULL) = (terms_changed_premium_low IS NULL) AND (terms_changed_premium_high IS NULL OR (typeof(terms_changed_premium_high) = \'real\' AND terms_changed_premium_high BETWEEN -100 AND 999 AND terms_changed_premium_high >= terms_changed_premium_low)))',
  );
  @override
  List<GeneratedColumn> get $columns => [
    keyFingerprint,
    robotIndex,
    version,
    network,
    coordinatorAlias,
    orderId,
    role,
    position,
    readAt,
    bondHash,
    escrowHash,
    deadline,
    bondStepSeenAt,
    bondStepDeadline,
    breached,
    historyUnknown,
    take,
    takeDeadline,
    takerHashId,
    takenAmount,
    earlierEscrows,
    seenLate,
    termsChangedAt,
    termsChangedPremiumLow,
    termsChangedPremiumHigh,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'trade_trails';
  @override
  VerificationContext validateIntegrity(
    Insertable<TradeTrailRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key_fingerprint')) {
      context.handle(
        _keyFingerprintMeta,
        keyFingerprint.isAcceptableOrUnknown(
          data['key_fingerprint']!,
          _keyFingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_keyFingerprintMeta);
    }
    if (data.containsKey('robot_index')) {
      context.handle(
        _robotIndexMeta,
        robotIndex.isAcceptableOrUnknown(data['robot_index']!, _robotIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_robotIndexMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('network')) {
      context.handle(
        _networkMeta,
        network.isAcceptableOrUnknown(data['network']!, _networkMeta),
      );
    } else if (isInserting) {
      context.missing(_networkMeta);
    }
    if (data.containsKey('coordinator_alias')) {
      context.handle(
        _coordinatorAliasMeta,
        coordinatorAlias.isAcceptableOrUnknown(
          data['coordinator_alias']!,
          _coordinatorAliasMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_coordinatorAliasMeta);
    }
    if (data.containsKey('order_id')) {
      context.handle(
        _orderIdMeta,
        orderId.isAcceptableOrUnknown(data['order_id']!, _orderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_orderIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('read_at')) {
      context.handle(
        _readAtMeta,
        readAt.isAcceptableOrUnknown(data['read_at']!, _readAtMeta),
      );
    } else if (isInserting) {
      context.missing(_readAtMeta);
    }
    if (data.containsKey('bond_hash')) {
      context.handle(
        _bondHashMeta,
        bondHash.isAcceptableOrUnknown(data['bond_hash']!, _bondHashMeta),
      );
    }
    if (data.containsKey('escrow_hash')) {
      context.handle(
        _escrowHashMeta,
        escrowHash.isAcceptableOrUnknown(data['escrow_hash']!, _escrowHashMeta),
      );
    }
    if (data.containsKey('deadline')) {
      context.handle(
        _deadlineMeta,
        deadline.isAcceptableOrUnknown(data['deadline']!, _deadlineMeta),
      );
    }
    if (data.containsKey('bond_step_seen_at')) {
      context.handle(
        _bondStepSeenAtMeta,
        bondStepSeenAt.isAcceptableOrUnknown(
          data['bond_step_seen_at']!,
          _bondStepSeenAtMeta,
        ),
      );
    }
    if (data.containsKey('bond_step_deadline')) {
      context.handle(
        _bondStepDeadlineMeta,
        bondStepDeadline.isAcceptableOrUnknown(
          data['bond_step_deadline']!,
          _bondStepDeadlineMeta,
        ),
      );
    }
    if (data.containsKey('breached')) {
      context.handle(
        _breachedMeta,
        breached.isAcceptableOrUnknown(data['breached']!, _breachedMeta),
      );
    } else if (isInserting) {
      context.missing(_breachedMeta);
    }
    if (data.containsKey('history_unknown')) {
      context.handle(
        _historyUnknownMeta,
        historyUnknown.isAcceptableOrUnknown(
          data['history_unknown']!,
          _historyUnknownMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_historyUnknownMeta);
    }
    if (data.containsKey('take')) {
      context.handle(
        _takeMeta,
        take.isAcceptableOrUnknown(data['take']!, _takeMeta),
      );
    }
    if (data.containsKey('take_deadline')) {
      context.handle(
        _takeDeadlineMeta,
        takeDeadline.isAcceptableOrUnknown(
          data['take_deadline']!,
          _takeDeadlineMeta,
        ),
      );
    }
    if (data.containsKey('taker_hash_id')) {
      context.handle(
        _takerHashIdMeta,
        takerHashId.isAcceptableOrUnknown(
          data['taker_hash_id']!,
          _takerHashIdMeta,
        ),
      );
    }
    if (data.containsKey('taken_amount')) {
      context.handle(
        _takenAmountMeta,
        takenAmount.isAcceptableOrUnknown(
          data['taken_amount']!,
          _takenAmountMeta,
        ),
      );
    }
    if (data.containsKey('earlier_escrows')) {
      context.handle(
        _earlierEscrowsMeta,
        earlierEscrows.isAcceptableOrUnknown(
          data['earlier_escrows']!,
          _earlierEscrowsMeta,
        ),
      );
    }
    if (data.containsKey('seen_late')) {
      context.handle(
        _seenLateMeta,
        seenLate.isAcceptableOrUnknown(data['seen_late']!, _seenLateMeta),
      );
    }
    if (data.containsKey('terms_changed_at')) {
      context.handle(
        _termsChangedAtMeta,
        termsChangedAt.isAcceptableOrUnknown(
          data['terms_changed_at']!,
          _termsChangedAtMeta,
        ),
      );
    }
    if (data.containsKey('terms_changed_premium_low')) {
      context.handle(
        _termsChangedPremiumLowMeta,
        termsChangedPremiumLow.isAcceptableOrUnknown(
          data['terms_changed_premium_low']!,
          _termsChangedPremiumLowMeta,
        ),
      );
    }
    if (data.containsKey('terms_changed_premium_high')) {
      context.handle(
        _termsChangedPremiumHighMeta,
        termsChangedPremiumHigh.isAcceptableOrUnknown(
          data['terms_changed_premium_high']!,
          _termsChangedPremiumHighMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {keyFingerprint, robotIndex};
  @override
  TradeTrailRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TradeTrailRow(
      keyFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key_fingerprint'],
      )!,
      robotIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}robot_index'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      network: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}network'],
      )!,
      coordinatorAlias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coordinator_alias'],
      )!,
      orderId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}position'],
      )!,
      readAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}read_at'],
      )!,
      bondHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bond_hash'],
      ),
      escrowHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}escrow_hash'],
      ),
      deadline: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deadline'],
      ),
      bondStepSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bond_step_seen_at'],
      ),
      bondStepDeadline: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bond_step_deadline'],
      ),
      breached: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}breached'],
      )!,
      historyUnknown: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}history_unknown'],
      )!,
      take: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}take'],
      )!,
      takeDeadline: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}take_deadline'],
      ),
      takerHashId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}taker_hash_id'],
      ),
      takenAmount: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}taken_amount'],
      ),
      earlierEscrows: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}earlier_escrows'],
      )!,
      seenLate: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}seen_late'],
      )!,
      termsChangedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}terms_changed_at'],
      ),
      termsChangedPremiumLow: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}terms_changed_premium_low'],
      ),
      termsChangedPremiumHigh: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}terms_changed_premium_high'],
      ),
    );
  }

  @override
  $StoredTradeTrailsTable createAlias(String alias) {
    return $StoredTradeTrailsTable(attachedDatabase, alias);
  }
}

class TradeTrailRow extends DataClass implements Insertable<TradeTrailRow> {
  /// The trade's robot, as `trades` keys it.
  final String keyFingerprint;
  final int robotIndex;

  /// `TradeTrailRecord.version`.
  final int version;

  /// The trade the trail belongs to: `RobosatsNetwork.name`, the coordinator's short alias, the order, `TradeRole.name`.
  final String network;
  final String coordinatorAlias;
  final int orderId;
  final String role;

  /// `TradePosition.name` of the last status.
  final String position;

  /// When the last status was read, in microseconds since the epoch.
  final int readAt;

  /// The payment hashes of the first bond and escrow invoices, 64 lowercase hexadecimal characters.
  final String? bondHash;
  final String? escrowHash;

  /// The deadline of the last order read, and the pre-take's last read and deadline, in microseconds since the epoch.
  final int? deadline;
  final int? bondStepSeenAt;
  final int? bondStepDeadline;
  final bool breached;
  final bool historyUnknown;

  /// The index of a maker's current contract (schema 8; design note `docs/design/phase-3-making-an-order.md` § 3.2): 0 for the order's first take, one more for each take after the order went back to the book; always 0 for a trade not made here.
  final int take;

  /// The deadline the coordinator gave the current contract, in microseconds since the epoch; absent until a read of 6, 7 or 8 opens the first contract, and always for a trade not made here.
  final int? takeDeadline;

  /// The hash id of the current contract's taker, 64 lowercase hexadecimal characters; absent until a read names it, and always for a trade not made here.
  final String? takerHashId;

  /// The fiat amount the current contract took of a range, in the order's currency; absent for a fixed amount, until a read gives it, and always for a trade not made here.
  final double? takenAmount;

  /// The escrow hashes a maker's earlier contracts pinned, oldest first, each 64 lowercase hexadecimal characters followed by `;` (schema 8 as amended by #178 before any release): only grown, by the escrow hash held when `take` moves, so that an escrow of an earlier contract is never pinned again; empty at contract 0, and always for a trade not made here.
  final String earlierEscrows;

  /// Whether a maker's current contract was first read from the chat on (a next contract seen late, #178), set only in the write that opens that contract; false at contract 0, and always for a trade not made here.
  final bool seenLate;

  /// When a read kept for this trade first showed it with other terms than its own (`TradeTermsChanged`), in microseconds since the epoch: the read time of that write, set once and kept to the end (schema 9, #231; design note `docs/design/phase-3-making-an-order.md` § 3.5 bis); absent when none did since schema 9, and for every trail of a schema 8 file, whose trace was never recorded.
  ///
  /// Its constraints are the column's own, so that schema 9 adds it to the table without rebuilding it.
  final int? termsChangedAt;

  /// The lowest and the highest premium, in percent, that reads kept showed otherwise than the trade's own (an order not priced in sats, within the package's bounds, -100 to 999); both absent while no read showed another premium (schema 9, #231). Both written as soon as a premium differs, even after another term changed first; then the lowest only goes down and the highest only up, neither is cleared: the trigger `trade_trails_terms_trace` keeps them, so that the trace never says less than was seen, on either side (security reviews of schema 9, C1 and R8).
  final double? termsChangedPremiumLow;
  final double? termsChangedPremiumHigh;
  const TradeTrailRow({
    required this.keyFingerprint,
    required this.robotIndex,
    required this.version,
    required this.network,
    required this.coordinatorAlias,
    required this.orderId,
    required this.role,
    required this.position,
    required this.readAt,
    this.bondHash,
    this.escrowHash,
    this.deadline,
    this.bondStepSeenAt,
    this.bondStepDeadline,
    required this.breached,
    required this.historyUnknown,
    required this.take,
    this.takeDeadline,
    this.takerHashId,
    this.takenAmount,
    required this.earlierEscrows,
    required this.seenLate,
    this.termsChangedAt,
    this.termsChangedPremiumLow,
    this.termsChangedPremiumHigh,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key_fingerprint'] = Variable<String>(keyFingerprint);
    map['robot_index'] = Variable<int>(robotIndex);
    map['version'] = Variable<int>(version);
    map['network'] = Variable<String>(network);
    map['coordinator_alias'] = Variable<String>(coordinatorAlias);
    map['order_id'] = Variable<int>(orderId);
    map['role'] = Variable<String>(role);
    map['position'] = Variable<String>(position);
    map['read_at'] = Variable<int>(readAt);
    if (!nullToAbsent || bondHash != null) {
      map['bond_hash'] = Variable<String>(bondHash);
    }
    if (!nullToAbsent || escrowHash != null) {
      map['escrow_hash'] = Variable<String>(escrowHash);
    }
    if (!nullToAbsent || deadline != null) {
      map['deadline'] = Variable<int>(deadline);
    }
    if (!nullToAbsent || bondStepSeenAt != null) {
      map['bond_step_seen_at'] = Variable<int>(bondStepSeenAt);
    }
    if (!nullToAbsent || bondStepDeadline != null) {
      map['bond_step_deadline'] = Variable<int>(bondStepDeadline);
    }
    map['breached'] = Variable<bool>(breached);
    map['history_unknown'] = Variable<bool>(historyUnknown);
    map['take'] = Variable<int>(take);
    if (!nullToAbsent || takeDeadline != null) {
      map['take_deadline'] = Variable<int>(takeDeadline);
    }
    if (!nullToAbsent || takerHashId != null) {
      map['taker_hash_id'] = Variable<String>(takerHashId);
    }
    if (!nullToAbsent || takenAmount != null) {
      map['taken_amount'] = Variable<double>(takenAmount);
    }
    map['earlier_escrows'] = Variable<String>(earlierEscrows);
    map['seen_late'] = Variable<bool>(seenLate);
    if (!nullToAbsent || termsChangedAt != null) {
      map['terms_changed_at'] = Variable<int>(termsChangedAt);
    }
    if (!nullToAbsent || termsChangedPremiumLow != null) {
      map['terms_changed_premium_low'] = Variable<double>(
        termsChangedPremiumLow,
      );
    }
    if (!nullToAbsent || termsChangedPremiumHigh != null) {
      map['terms_changed_premium_high'] = Variable<double>(
        termsChangedPremiumHigh,
      );
    }
    return map;
  }

  StoredTradeTrailsCompanion toCompanion(bool nullToAbsent) {
    return StoredTradeTrailsCompanion(
      keyFingerprint: Value(keyFingerprint),
      robotIndex: Value(robotIndex),
      version: Value(version),
      network: Value(network),
      coordinatorAlias: Value(coordinatorAlias),
      orderId: Value(orderId),
      role: Value(role),
      position: Value(position),
      readAt: Value(readAt),
      bondHash: bondHash == null && nullToAbsent
          ? const Value.absent()
          : Value(bondHash),
      escrowHash: escrowHash == null && nullToAbsent
          ? const Value.absent()
          : Value(escrowHash),
      deadline: deadline == null && nullToAbsent
          ? const Value.absent()
          : Value(deadline),
      bondStepSeenAt: bondStepSeenAt == null && nullToAbsent
          ? const Value.absent()
          : Value(bondStepSeenAt),
      bondStepDeadline: bondStepDeadline == null && nullToAbsent
          ? const Value.absent()
          : Value(bondStepDeadline),
      breached: Value(breached),
      historyUnknown: Value(historyUnknown),
      take: Value(take),
      takeDeadline: takeDeadline == null && nullToAbsent
          ? const Value.absent()
          : Value(takeDeadline),
      takerHashId: takerHashId == null && nullToAbsent
          ? const Value.absent()
          : Value(takerHashId),
      takenAmount: takenAmount == null && nullToAbsent
          ? const Value.absent()
          : Value(takenAmount),
      earlierEscrows: Value(earlierEscrows),
      seenLate: Value(seenLate),
      termsChangedAt: termsChangedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(termsChangedAt),
      termsChangedPremiumLow: termsChangedPremiumLow == null && nullToAbsent
          ? const Value.absent()
          : Value(termsChangedPremiumLow),
      termsChangedPremiumHigh: termsChangedPremiumHigh == null && nullToAbsent
          ? const Value.absent()
          : Value(termsChangedPremiumHigh),
    );
  }

  factory TradeTrailRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TradeTrailRow(
      keyFingerprint: serializer.fromJson<String>(json['keyFingerprint']),
      robotIndex: serializer.fromJson<int>(json['robotIndex']),
      version: serializer.fromJson<int>(json['version']),
      network: serializer.fromJson<String>(json['network']),
      coordinatorAlias: serializer.fromJson<String>(json['coordinatorAlias']),
      orderId: serializer.fromJson<int>(json['orderId']),
      role: serializer.fromJson<String>(json['role']),
      position: serializer.fromJson<String>(json['position']),
      readAt: serializer.fromJson<int>(json['readAt']),
      bondHash: serializer.fromJson<String?>(json['bondHash']),
      escrowHash: serializer.fromJson<String?>(json['escrowHash']),
      deadline: serializer.fromJson<int?>(json['deadline']),
      bondStepSeenAt: serializer.fromJson<int?>(json['bondStepSeenAt']),
      bondStepDeadline: serializer.fromJson<int?>(json['bondStepDeadline']),
      breached: serializer.fromJson<bool>(json['breached']),
      historyUnknown: serializer.fromJson<bool>(json['historyUnknown']),
      take: serializer.fromJson<int>(json['take']),
      takeDeadline: serializer.fromJson<int?>(json['takeDeadline']),
      takerHashId: serializer.fromJson<String?>(json['takerHashId']),
      takenAmount: serializer.fromJson<double?>(json['takenAmount']),
      earlierEscrows: serializer.fromJson<String>(json['earlierEscrows']),
      seenLate: serializer.fromJson<bool>(json['seenLate']),
      termsChangedAt: serializer.fromJson<int?>(json['termsChangedAt']),
      termsChangedPremiumLow: serializer.fromJson<double?>(
        json['termsChangedPremiumLow'],
      ),
      termsChangedPremiumHigh: serializer.fromJson<double?>(
        json['termsChangedPremiumHigh'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'keyFingerprint': serializer.toJson<String>(keyFingerprint),
      'robotIndex': serializer.toJson<int>(robotIndex),
      'version': serializer.toJson<int>(version),
      'network': serializer.toJson<String>(network),
      'coordinatorAlias': serializer.toJson<String>(coordinatorAlias),
      'orderId': serializer.toJson<int>(orderId),
      'role': serializer.toJson<String>(role),
      'position': serializer.toJson<String>(position),
      'readAt': serializer.toJson<int>(readAt),
      'bondHash': serializer.toJson<String?>(bondHash),
      'escrowHash': serializer.toJson<String?>(escrowHash),
      'deadline': serializer.toJson<int?>(deadline),
      'bondStepSeenAt': serializer.toJson<int?>(bondStepSeenAt),
      'bondStepDeadline': serializer.toJson<int?>(bondStepDeadline),
      'breached': serializer.toJson<bool>(breached),
      'historyUnknown': serializer.toJson<bool>(historyUnknown),
      'take': serializer.toJson<int>(take),
      'takeDeadline': serializer.toJson<int?>(takeDeadline),
      'takerHashId': serializer.toJson<String?>(takerHashId),
      'takenAmount': serializer.toJson<double?>(takenAmount),
      'earlierEscrows': serializer.toJson<String>(earlierEscrows),
      'seenLate': serializer.toJson<bool>(seenLate),
      'termsChangedAt': serializer.toJson<int?>(termsChangedAt),
      'termsChangedPremiumLow': serializer.toJson<double?>(
        termsChangedPremiumLow,
      ),
      'termsChangedPremiumHigh': serializer.toJson<double?>(
        termsChangedPremiumHigh,
      ),
    };
  }

  TradeTrailRow copyWith({
    String? keyFingerprint,
    int? robotIndex,
    int? version,
    String? network,
    String? coordinatorAlias,
    int? orderId,
    String? role,
    String? position,
    int? readAt,
    Value<String?> bondHash = const Value.absent(),
    Value<String?> escrowHash = const Value.absent(),
    Value<int?> deadline = const Value.absent(),
    Value<int?> bondStepSeenAt = const Value.absent(),
    Value<int?> bondStepDeadline = const Value.absent(),
    bool? breached,
    bool? historyUnknown,
    int? take,
    Value<int?> takeDeadline = const Value.absent(),
    Value<String?> takerHashId = const Value.absent(),
    Value<double?> takenAmount = const Value.absent(),
    String? earlierEscrows,
    bool? seenLate,
    Value<int?> termsChangedAt = const Value.absent(),
    Value<double?> termsChangedPremiumLow = const Value.absent(),
    Value<double?> termsChangedPremiumHigh = const Value.absent(),
  }) => TradeTrailRow(
    keyFingerprint: keyFingerprint ?? this.keyFingerprint,
    robotIndex: robotIndex ?? this.robotIndex,
    version: version ?? this.version,
    network: network ?? this.network,
    coordinatorAlias: coordinatorAlias ?? this.coordinatorAlias,
    orderId: orderId ?? this.orderId,
    role: role ?? this.role,
    position: position ?? this.position,
    readAt: readAt ?? this.readAt,
    bondHash: bondHash.present ? bondHash.value : this.bondHash,
    escrowHash: escrowHash.present ? escrowHash.value : this.escrowHash,
    deadline: deadline.present ? deadline.value : this.deadline,
    bondStepSeenAt: bondStepSeenAt.present
        ? bondStepSeenAt.value
        : this.bondStepSeenAt,
    bondStepDeadline: bondStepDeadline.present
        ? bondStepDeadline.value
        : this.bondStepDeadline,
    breached: breached ?? this.breached,
    historyUnknown: historyUnknown ?? this.historyUnknown,
    take: take ?? this.take,
    takeDeadline: takeDeadline.present ? takeDeadline.value : this.takeDeadline,
    takerHashId: takerHashId.present ? takerHashId.value : this.takerHashId,
    takenAmount: takenAmount.present ? takenAmount.value : this.takenAmount,
    earlierEscrows: earlierEscrows ?? this.earlierEscrows,
    seenLate: seenLate ?? this.seenLate,
    termsChangedAt: termsChangedAt.present
        ? termsChangedAt.value
        : this.termsChangedAt,
    termsChangedPremiumLow: termsChangedPremiumLow.present
        ? termsChangedPremiumLow.value
        : this.termsChangedPremiumLow,
    termsChangedPremiumHigh: termsChangedPremiumHigh.present
        ? termsChangedPremiumHigh.value
        : this.termsChangedPremiumHigh,
  );
  TradeTrailRow copyWithCompanion(StoredTradeTrailsCompanion data) {
    return TradeTrailRow(
      keyFingerprint: data.keyFingerprint.present
          ? data.keyFingerprint.value
          : this.keyFingerprint,
      robotIndex: data.robotIndex.present
          ? data.robotIndex.value
          : this.robotIndex,
      version: data.version.present ? data.version.value : this.version,
      network: data.network.present ? data.network.value : this.network,
      coordinatorAlias: data.coordinatorAlias.present
          ? data.coordinatorAlias.value
          : this.coordinatorAlias,
      orderId: data.orderId.present ? data.orderId.value : this.orderId,
      role: data.role.present ? data.role.value : this.role,
      position: data.position.present ? data.position.value : this.position,
      readAt: data.readAt.present ? data.readAt.value : this.readAt,
      bondHash: data.bondHash.present ? data.bondHash.value : this.bondHash,
      escrowHash: data.escrowHash.present
          ? data.escrowHash.value
          : this.escrowHash,
      deadline: data.deadline.present ? data.deadline.value : this.deadline,
      bondStepSeenAt: data.bondStepSeenAt.present
          ? data.bondStepSeenAt.value
          : this.bondStepSeenAt,
      bondStepDeadline: data.bondStepDeadline.present
          ? data.bondStepDeadline.value
          : this.bondStepDeadline,
      breached: data.breached.present ? data.breached.value : this.breached,
      historyUnknown: data.historyUnknown.present
          ? data.historyUnknown.value
          : this.historyUnknown,
      take: data.take.present ? data.take.value : this.take,
      takeDeadline: data.takeDeadline.present
          ? data.takeDeadline.value
          : this.takeDeadline,
      takerHashId: data.takerHashId.present
          ? data.takerHashId.value
          : this.takerHashId,
      takenAmount: data.takenAmount.present
          ? data.takenAmount.value
          : this.takenAmount,
      earlierEscrows: data.earlierEscrows.present
          ? data.earlierEscrows.value
          : this.earlierEscrows,
      seenLate: data.seenLate.present ? data.seenLate.value : this.seenLate,
      termsChangedAt: data.termsChangedAt.present
          ? data.termsChangedAt.value
          : this.termsChangedAt,
      termsChangedPremiumLow: data.termsChangedPremiumLow.present
          ? data.termsChangedPremiumLow.value
          : this.termsChangedPremiumLow,
      termsChangedPremiumHigh: data.termsChangedPremiumHigh.present
          ? data.termsChangedPremiumHigh.value
          : this.termsChangedPremiumHigh,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TradeTrailRow(')
          ..write('keyFingerprint: $keyFingerprint, ')
          ..write('robotIndex: $robotIndex, ')
          ..write('version: $version, ')
          ..write('network: $network, ')
          ..write('coordinatorAlias: $coordinatorAlias, ')
          ..write('orderId: $orderId, ')
          ..write('role: $role, ')
          ..write('position: $position, ')
          ..write('readAt: $readAt, ')
          ..write('bondHash: $bondHash, ')
          ..write('escrowHash: $escrowHash, ')
          ..write('deadline: $deadline, ')
          ..write('bondStepSeenAt: $bondStepSeenAt, ')
          ..write('bondStepDeadline: $bondStepDeadline, ')
          ..write('breached: $breached, ')
          ..write('historyUnknown: $historyUnknown, ')
          ..write('take: $take, ')
          ..write('takeDeadline: $takeDeadline, ')
          ..write('takerHashId: $takerHashId, ')
          ..write('takenAmount: $takenAmount, ')
          ..write('earlierEscrows: $earlierEscrows, ')
          ..write('seenLate: $seenLate, ')
          ..write('termsChangedAt: $termsChangedAt, ')
          ..write('termsChangedPremiumLow: $termsChangedPremiumLow, ')
          ..write('termsChangedPremiumHigh: $termsChangedPremiumHigh')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    keyFingerprint,
    robotIndex,
    version,
    network,
    coordinatorAlias,
    orderId,
    role,
    position,
    readAt,
    bondHash,
    escrowHash,
    deadline,
    bondStepSeenAt,
    bondStepDeadline,
    breached,
    historyUnknown,
    take,
    takeDeadline,
    takerHashId,
    takenAmount,
    earlierEscrows,
    seenLate,
    termsChangedAt,
    termsChangedPremiumLow,
    termsChangedPremiumHigh,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TradeTrailRow &&
          other.keyFingerprint == this.keyFingerprint &&
          other.robotIndex == this.robotIndex &&
          other.version == this.version &&
          other.network == this.network &&
          other.coordinatorAlias == this.coordinatorAlias &&
          other.orderId == this.orderId &&
          other.role == this.role &&
          other.position == this.position &&
          other.readAt == this.readAt &&
          other.bondHash == this.bondHash &&
          other.escrowHash == this.escrowHash &&
          other.deadline == this.deadline &&
          other.bondStepSeenAt == this.bondStepSeenAt &&
          other.bondStepDeadline == this.bondStepDeadline &&
          other.breached == this.breached &&
          other.historyUnknown == this.historyUnknown &&
          other.take == this.take &&
          other.takeDeadline == this.takeDeadline &&
          other.takerHashId == this.takerHashId &&
          other.takenAmount == this.takenAmount &&
          other.earlierEscrows == this.earlierEscrows &&
          other.seenLate == this.seenLate &&
          other.termsChangedAt == this.termsChangedAt &&
          other.termsChangedPremiumLow == this.termsChangedPremiumLow &&
          other.termsChangedPremiumHigh == this.termsChangedPremiumHigh);
}

class StoredTradeTrailsCompanion extends UpdateCompanion<TradeTrailRow> {
  final Value<String> keyFingerprint;
  final Value<int> robotIndex;
  final Value<int> version;
  final Value<String> network;
  final Value<String> coordinatorAlias;
  final Value<int> orderId;
  final Value<String> role;
  final Value<String> position;
  final Value<int> readAt;
  final Value<String?> bondHash;
  final Value<String?> escrowHash;
  final Value<int?> deadline;
  final Value<int?> bondStepSeenAt;
  final Value<int?> bondStepDeadline;
  final Value<bool> breached;
  final Value<bool> historyUnknown;
  final Value<int> take;
  final Value<int?> takeDeadline;
  final Value<String?> takerHashId;
  final Value<double?> takenAmount;
  final Value<String> earlierEscrows;
  final Value<bool> seenLate;
  final Value<int?> termsChangedAt;
  final Value<double?> termsChangedPremiumLow;
  final Value<double?> termsChangedPremiumHigh;
  final Value<int> rowid;
  const StoredTradeTrailsCompanion({
    this.keyFingerprint = const Value.absent(),
    this.robotIndex = const Value.absent(),
    this.version = const Value.absent(),
    this.network = const Value.absent(),
    this.coordinatorAlias = const Value.absent(),
    this.orderId = const Value.absent(),
    this.role = const Value.absent(),
    this.position = const Value.absent(),
    this.readAt = const Value.absent(),
    this.bondHash = const Value.absent(),
    this.escrowHash = const Value.absent(),
    this.deadline = const Value.absent(),
    this.bondStepSeenAt = const Value.absent(),
    this.bondStepDeadline = const Value.absent(),
    this.breached = const Value.absent(),
    this.historyUnknown = const Value.absent(),
    this.take = const Value.absent(),
    this.takeDeadline = const Value.absent(),
    this.takerHashId = const Value.absent(),
    this.takenAmount = const Value.absent(),
    this.earlierEscrows = const Value.absent(),
    this.seenLate = const Value.absent(),
    this.termsChangedAt = const Value.absent(),
    this.termsChangedPremiumLow = const Value.absent(),
    this.termsChangedPremiumHigh = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredTradeTrailsCompanion.insert({
    required String keyFingerprint,
    required int robotIndex,
    required int version,
    required String network,
    required String coordinatorAlias,
    required int orderId,
    required String role,
    required String position,
    required int readAt,
    this.bondHash = const Value.absent(),
    this.escrowHash = const Value.absent(),
    this.deadline = const Value.absent(),
    this.bondStepSeenAt = const Value.absent(),
    this.bondStepDeadline = const Value.absent(),
    required bool breached,
    required bool historyUnknown,
    this.take = const Value.absent(),
    this.takeDeadline = const Value.absent(),
    this.takerHashId = const Value.absent(),
    this.takenAmount = const Value.absent(),
    this.earlierEscrows = const Value.absent(),
    this.seenLate = const Value.absent(),
    this.termsChangedAt = const Value.absent(),
    this.termsChangedPremiumLow = const Value.absent(),
    this.termsChangedPremiumHigh = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : keyFingerprint = Value(keyFingerprint),
       robotIndex = Value(robotIndex),
       version = Value(version),
       network = Value(network),
       coordinatorAlias = Value(coordinatorAlias),
       orderId = Value(orderId),
       role = Value(role),
       position = Value(position),
       readAt = Value(readAt),
       breached = Value(breached),
       historyUnknown = Value(historyUnknown);
  static Insertable<TradeTrailRow> custom({
    Expression<String>? keyFingerprint,
    Expression<int>? robotIndex,
    Expression<int>? version,
    Expression<String>? network,
    Expression<String>? coordinatorAlias,
    Expression<int>? orderId,
    Expression<String>? role,
    Expression<String>? position,
    Expression<int>? readAt,
    Expression<String>? bondHash,
    Expression<String>? escrowHash,
    Expression<int>? deadline,
    Expression<int>? bondStepSeenAt,
    Expression<int>? bondStepDeadline,
    Expression<bool>? breached,
    Expression<bool>? historyUnknown,
    Expression<int>? take,
    Expression<int>? takeDeadline,
    Expression<String>? takerHashId,
    Expression<double>? takenAmount,
    Expression<String>? earlierEscrows,
    Expression<bool>? seenLate,
    Expression<int>? termsChangedAt,
    Expression<double>? termsChangedPremiumLow,
    Expression<double>? termsChangedPremiumHigh,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (keyFingerprint != null) 'key_fingerprint': keyFingerprint,
      if (robotIndex != null) 'robot_index': robotIndex,
      if (version != null) 'version': version,
      if (network != null) 'network': network,
      if (coordinatorAlias != null) 'coordinator_alias': coordinatorAlias,
      if (orderId != null) 'order_id': orderId,
      if (role != null) 'role': role,
      if (position != null) 'position': position,
      if (readAt != null) 'read_at': readAt,
      if (bondHash != null) 'bond_hash': bondHash,
      if (escrowHash != null) 'escrow_hash': escrowHash,
      if (deadline != null) 'deadline': deadline,
      if (bondStepSeenAt != null) 'bond_step_seen_at': bondStepSeenAt,
      if (bondStepDeadline != null) 'bond_step_deadline': bondStepDeadline,
      if (breached != null) 'breached': breached,
      if (historyUnknown != null) 'history_unknown': historyUnknown,
      if (take != null) 'take': take,
      if (takeDeadline != null) 'take_deadline': takeDeadline,
      if (takerHashId != null) 'taker_hash_id': takerHashId,
      if (takenAmount != null) 'taken_amount': takenAmount,
      if (earlierEscrows != null) 'earlier_escrows': earlierEscrows,
      if (seenLate != null) 'seen_late': seenLate,
      if (termsChangedAt != null) 'terms_changed_at': termsChangedAt,
      if (termsChangedPremiumLow != null)
        'terms_changed_premium_low': termsChangedPremiumLow,
      if (termsChangedPremiumHigh != null)
        'terms_changed_premium_high': termsChangedPremiumHigh,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredTradeTrailsCompanion copyWith({
    Value<String>? keyFingerprint,
    Value<int>? robotIndex,
    Value<int>? version,
    Value<String>? network,
    Value<String>? coordinatorAlias,
    Value<int>? orderId,
    Value<String>? role,
    Value<String>? position,
    Value<int>? readAt,
    Value<String?>? bondHash,
    Value<String?>? escrowHash,
    Value<int?>? deadline,
    Value<int?>? bondStepSeenAt,
    Value<int?>? bondStepDeadline,
    Value<bool>? breached,
    Value<bool>? historyUnknown,
    Value<int>? take,
    Value<int?>? takeDeadline,
    Value<String?>? takerHashId,
    Value<double?>? takenAmount,
    Value<String>? earlierEscrows,
    Value<bool>? seenLate,
    Value<int?>? termsChangedAt,
    Value<double?>? termsChangedPremiumLow,
    Value<double?>? termsChangedPremiumHigh,
    Value<int>? rowid,
  }) {
    return StoredTradeTrailsCompanion(
      keyFingerprint: keyFingerprint ?? this.keyFingerprint,
      robotIndex: robotIndex ?? this.robotIndex,
      version: version ?? this.version,
      network: network ?? this.network,
      coordinatorAlias: coordinatorAlias ?? this.coordinatorAlias,
      orderId: orderId ?? this.orderId,
      role: role ?? this.role,
      position: position ?? this.position,
      readAt: readAt ?? this.readAt,
      bondHash: bondHash ?? this.bondHash,
      escrowHash: escrowHash ?? this.escrowHash,
      deadline: deadline ?? this.deadline,
      bondStepSeenAt: bondStepSeenAt ?? this.bondStepSeenAt,
      bondStepDeadline: bondStepDeadline ?? this.bondStepDeadline,
      breached: breached ?? this.breached,
      historyUnknown: historyUnknown ?? this.historyUnknown,
      take: take ?? this.take,
      takeDeadline: takeDeadline ?? this.takeDeadline,
      takerHashId: takerHashId ?? this.takerHashId,
      takenAmount: takenAmount ?? this.takenAmount,
      earlierEscrows: earlierEscrows ?? this.earlierEscrows,
      seenLate: seenLate ?? this.seenLate,
      termsChangedAt: termsChangedAt ?? this.termsChangedAt,
      termsChangedPremiumLow:
          termsChangedPremiumLow ?? this.termsChangedPremiumLow,
      termsChangedPremiumHigh:
          termsChangedPremiumHigh ?? this.termsChangedPremiumHigh,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (keyFingerprint.present) {
      map['key_fingerprint'] = Variable<String>(keyFingerprint.value);
    }
    if (robotIndex.present) {
      map['robot_index'] = Variable<int>(robotIndex.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (network.present) {
      map['network'] = Variable<String>(network.value);
    }
    if (coordinatorAlias.present) {
      map['coordinator_alias'] = Variable<String>(coordinatorAlias.value);
    }
    if (orderId.present) {
      map['order_id'] = Variable<int>(orderId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (position.present) {
      map['position'] = Variable<String>(position.value);
    }
    if (readAt.present) {
      map['read_at'] = Variable<int>(readAt.value);
    }
    if (bondHash.present) {
      map['bond_hash'] = Variable<String>(bondHash.value);
    }
    if (escrowHash.present) {
      map['escrow_hash'] = Variable<String>(escrowHash.value);
    }
    if (deadline.present) {
      map['deadline'] = Variable<int>(deadline.value);
    }
    if (bondStepSeenAt.present) {
      map['bond_step_seen_at'] = Variable<int>(bondStepSeenAt.value);
    }
    if (bondStepDeadline.present) {
      map['bond_step_deadline'] = Variable<int>(bondStepDeadline.value);
    }
    if (breached.present) {
      map['breached'] = Variable<bool>(breached.value);
    }
    if (historyUnknown.present) {
      map['history_unknown'] = Variable<bool>(historyUnknown.value);
    }
    if (take.present) {
      map['take'] = Variable<int>(take.value);
    }
    if (takeDeadline.present) {
      map['take_deadline'] = Variable<int>(takeDeadline.value);
    }
    if (takerHashId.present) {
      map['taker_hash_id'] = Variable<String>(takerHashId.value);
    }
    if (takenAmount.present) {
      map['taken_amount'] = Variable<double>(takenAmount.value);
    }
    if (earlierEscrows.present) {
      map['earlier_escrows'] = Variable<String>(earlierEscrows.value);
    }
    if (seenLate.present) {
      map['seen_late'] = Variable<bool>(seenLate.value);
    }
    if (termsChangedAt.present) {
      map['terms_changed_at'] = Variable<int>(termsChangedAt.value);
    }
    if (termsChangedPremiumLow.present) {
      map['terms_changed_premium_low'] = Variable<double>(
        termsChangedPremiumLow.value,
      );
    }
    if (termsChangedPremiumHigh.present) {
      map['terms_changed_premium_high'] = Variable<double>(
        termsChangedPremiumHigh.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredTradeTrailsCompanion(')
          ..write('keyFingerprint: $keyFingerprint, ')
          ..write('robotIndex: $robotIndex, ')
          ..write('version: $version, ')
          ..write('network: $network, ')
          ..write('coordinatorAlias: $coordinatorAlias, ')
          ..write('orderId: $orderId, ')
          ..write('role: $role, ')
          ..write('position: $position, ')
          ..write('readAt: $readAt, ')
          ..write('bondHash: $bondHash, ')
          ..write('escrowHash: $escrowHash, ')
          ..write('deadline: $deadline, ')
          ..write('bondStepSeenAt: $bondStepSeenAt, ')
          ..write('bondStepDeadline: $bondStepDeadline, ')
          ..write('breached: $breached, ')
          ..write('historyUnknown: $historyUnknown, ')
          ..write('take: $take, ')
          ..write('takeDeadline: $takeDeadline, ')
          ..write('takerHashId: $takerHashId, ')
          ..write('takenAmount: $takenAmount, ')
          ..write('earlierEscrows: $earlierEscrows, ')
          ..write('seenLate: $seenLate, ')
          ..write('termsChangedAt: $termsChangedAt, ')
          ..write('termsChangedPremiumLow: $termsChangedPremiumLow, ')
          ..write('termsChangedPremiumHigh: $termsChangedPremiumHigh, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GarageKeyHistoriesTable extends GarageKeyHistories
    with TableInfo<$GarageKeyHistoriesTable, GarageKeyHistoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GarageKeyHistoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _networkMeta = const VerificationMeta(
    'network',
  );
  @override
  late final GeneratedColumn<String> network = GeneratedColumn<String>(
    'network',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyFingerprintMeta = const VerificationMeta(
    'keyFingerprint',
  );
  @override
  late final GeneratedColumn<String> keyFingerprint = GeneratedColumn<String>(
    'key_fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
    'origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordedAtMeta = const VerificationMeta(
    'recordedAt',
  );
  @override
  late final GeneratedColumn<int> recordedAt = GeneratedColumn<int>(
    'recorded_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    network,
    keyFingerprint,
    origin,
    recordedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'garage_key_histories';
  @override
  VerificationContext validateIntegrity(
    Insertable<GarageKeyHistoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('network')) {
      context.handle(
        _networkMeta,
        network.isAcceptableOrUnknown(data['network']!, _networkMeta),
      );
    } else if (isInserting) {
      context.missing(_networkMeta);
    }
    if (data.containsKey('key_fingerprint')) {
      context.handle(
        _keyFingerprintMeta,
        keyFingerprint.isAcceptableOrUnknown(
          data['key_fingerprint']!,
          _keyFingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_keyFingerprintMeta);
    }
    if (data.containsKey('origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['origin']!, _originMeta),
      );
    } else if (isInserting) {
      context.missing(_originMeta);
    }
    if (data.containsKey('recorded_at')) {
      context.handle(
        _recordedAtMeta,
        recordedAt.isAcceptableOrUnknown(data['recorded_at']!, _recordedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_recordedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {network, keyFingerprint};
  @override
  GarageKeyHistoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GarageKeyHistoryRow(
      network: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}network'],
      )!,
      keyFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key_fingerprint'],
      )!,
      origin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin'],
      )!,
      recordedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recorded_at'],
      )!,
    );
  }

  @override
  $GarageKeyHistoriesTable createAlias(String alias) {
    return $GarageKeyHistoriesTable(attachedDatabase, alias);
  }
}

class GarageKeyHistoryRow extends DataClass
    implements Insertable<GarageKeyHistoryRow> {
  /// `mainnet` or `testnet`.
  final String network;

  /// The `GarageKeyFingerprint` of the key, 64 hexadecimal characters.
  final String keyFingerprint;

  /// `generated` for a key drawn on this device, `imported` for a key pasted in, `acknowledged` (since schema 2) for a key of unknown history whose robots the user accepted to bind: only `generated` and `acknowledged` let a robot of the key be bound to a coordinator for the first time.
  final String origin;

  /// When the origin was recorded, in milliseconds since the epoch.
  final int recordedAt;
  const GarageKeyHistoryRow({
    required this.network,
    required this.keyFingerprint,
    required this.origin,
    required this.recordedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['network'] = Variable<String>(network);
    map['key_fingerprint'] = Variable<String>(keyFingerprint);
    map['origin'] = Variable<String>(origin);
    map['recorded_at'] = Variable<int>(recordedAt);
    return map;
  }

  GarageKeyHistoriesCompanion toCompanion(bool nullToAbsent) {
    return GarageKeyHistoriesCompanion(
      network: Value(network),
      keyFingerprint: Value(keyFingerprint),
      origin: Value(origin),
      recordedAt: Value(recordedAt),
    );
  }

  factory GarageKeyHistoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GarageKeyHistoryRow(
      network: serializer.fromJson<String>(json['network']),
      keyFingerprint: serializer.fromJson<String>(json['keyFingerprint']),
      origin: serializer.fromJson<String>(json['origin']),
      recordedAt: serializer.fromJson<int>(json['recordedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'network': serializer.toJson<String>(network),
      'keyFingerprint': serializer.toJson<String>(keyFingerprint),
      'origin': serializer.toJson<String>(origin),
      'recordedAt': serializer.toJson<int>(recordedAt),
    };
  }

  GarageKeyHistoryRow copyWith({
    String? network,
    String? keyFingerprint,
    String? origin,
    int? recordedAt,
  }) => GarageKeyHistoryRow(
    network: network ?? this.network,
    keyFingerprint: keyFingerprint ?? this.keyFingerprint,
    origin: origin ?? this.origin,
    recordedAt: recordedAt ?? this.recordedAt,
  );
  GarageKeyHistoryRow copyWithCompanion(GarageKeyHistoriesCompanion data) {
    return GarageKeyHistoryRow(
      network: data.network.present ? data.network.value : this.network,
      keyFingerprint: data.keyFingerprint.present
          ? data.keyFingerprint.value
          : this.keyFingerprint,
      origin: data.origin.present ? data.origin.value : this.origin,
      recordedAt: data.recordedAt.present
          ? data.recordedAt.value
          : this.recordedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GarageKeyHistoryRow(')
          ..write('network: $network, ')
          ..write('keyFingerprint: $keyFingerprint, ')
          ..write('origin: $origin, ')
          ..write('recordedAt: $recordedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(network, keyFingerprint, origin, recordedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GarageKeyHistoryRow &&
          other.network == this.network &&
          other.keyFingerprint == this.keyFingerprint &&
          other.origin == this.origin &&
          other.recordedAt == this.recordedAt);
}

class GarageKeyHistoriesCompanion extends UpdateCompanion<GarageKeyHistoryRow> {
  final Value<String> network;
  final Value<String> keyFingerprint;
  final Value<String> origin;
  final Value<int> recordedAt;
  final Value<int> rowid;
  const GarageKeyHistoriesCompanion({
    this.network = const Value.absent(),
    this.keyFingerprint = const Value.absent(),
    this.origin = const Value.absent(),
    this.recordedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GarageKeyHistoriesCompanion.insert({
    required String network,
    required String keyFingerprint,
    required String origin,
    required int recordedAt,
    this.rowid = const Value.absent(),
  }) : network = Value(network),
       keyFingerprint = Value(keyFingerprint),
       origin = Value(origin),
       recordedAt = Value(recordedAt);
  static Insertable<GarageKeyHistoryRow> custom({
    Expression<String>? network,
    Expression<String>? keyFingerprint,
    Expression<String>? origin,
    Expression<int>? recordedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (network != null) 'network': network,
      if (keyFingerprint != null) 'key_fingerprint': keyFingerprint,
      if (origin != null) 'origin': origin,
      if (recordedAt != null) 'recorded_at': recordedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GarageKeyHistoriesCompanion copyWith({
    Value<String>? network,
    Value<String>? keyFingerprint,
    Value<String>? origin,
    Value<int>? recordedAt,
    Value<int>? rowid,
  }) {
    return GarageKeyHistoriesCompanion(
      network: network ?? this.network,
      keyFingerprint: keyFingerprint ?? this.keyFingerprint,
      origin: origin ?? this.origin,
      recordedAt: recordedAt ?? this.recordedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (network.present) {
      map['network'] = Variable<String>(network.value);
    }
    if (keyFingerprint.present) {
      map['key_fingerprint'] = Variable<String>(keyFingerprint.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (recordedAt.present) {
      map['recorded_at'] = Variable<int>(recordedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GarageKeyHistoriesCompanion(')
          ..write('network: $network, ')
          ..write('keyFingerprint: $keyFingerprint, ')
          ..write('origin: $origin, ')
          ..write('recordedAt: $recordedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StoredTradeTermsTable extends StoredTradeTerms
    with TableInfo<$StoredTradeTermsTable, TradeTermsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredTradeTermsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyFingerprintMeta = const VerificationMeta(
    'keyFingerprint',
  );
  @override
  late final GeneratedColumn<String> keyFingerprint = GeneratedColumn<String>(
    'key_fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _robotIndexMeta = const VerificationMeta(
    'robotIndex',
  );
  @override
  late final GeneratedColumn<int> robotIndex = GeneratedColumn<int>(
    'robot_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _networkMeta = const VerificationMeta(
    'network',
  );
  @override
  late final GeneratedColumn<String> network = GeneratedColumn<String>(
    'network',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coordinatorAliasMeta = const VerificationMeta(
    'coordinatorAlias',
  );
  @override
  late final GeneratedColumn<String> coordinatorAlias = GeneratedColumn<String>(
    'coordinator_alias',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orderIdMeta = const VerificationMeta(
    'orderId',
  );
  @override
  late final GeneratedColumn<int> orderId = GeneratedColumn<int>(
    'order_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orderTypeMeta = const VerificationMeta(
    'orderType',
  );
  @override
  late final GeneratedColumn<int> orderType = GeneratedColumn<int>(
    'order_type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyIdMeta = const VerificationMeta(
    'currencyId',
  );
  @override
  late final GeneratedColumn<int> currencyId = GeneratedColumn<int>(
    'currency_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isRangeMeta = const VerificationMeta(
    'isRange',
  );
  @override
  late final GeneratedColumn<bool> isRange = GeneratedColumn<bool>(
    'is_range',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_range" IN (0, 1))',
    ),
  );
  static const VerificationMeta _premiumPercentMeta = const VerificationMeta(
    'premiumPercent',
  );
  @override
  late final GeneratedColumn<double> premiumPercent = GeneratedColumn<double>(
    'premium_percent',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _explicitSatoshisMeta = const VerificationMeta(
    'explicitSatoshis',
  );
  @override
  late final GeneratedColumn<int> explicitSatoshis = GeneratedColumn<int>(
    'explicit_satoshis',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bondSizePercentMeta = const VerificationMeta(
    'bondSizePercent',
  );
  @override
  late final GeneratedColumn<double> bondSizePercent = GeneratedColumn<double>(
    'bond_size_percent',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _escrowSecondsMeta = const VerificationMeta(
    'escrowSeconds',
  );
  @override
  late final GeneratedColumn<int> escrowSeconds = GeneratedColumn<int>(
    'escrow_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookPriceMeta = const VerificationMeta(
    'bookPrice',
  );
  @override
  late final GeneratedColumn<double> bookPrice = GeneratedColumn<double>(
    'book_price',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _takerFeeMeta = const VerificationMeta(
    'takerFee',
  );
  @override
  late final GeneratedColumn<double> takerFee = GeneratedColumn<double>(
    'taker_fee',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    keyFingerprint,
    robotIndex,
    version,
    network,
    coordinatorAlias,
    orderId,
    role,
    orderType,
    currencyId,
    amount,
    isRange,
    premiumPercent,
    explicitSatoshis,
    bondSizePercent,
    escrowSeconds,
    bookPrice,
    takerFee,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'trade_terms';
  @override
  VerificationContext validateIntegrity(
    Insertable<TradeTermsRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key_fingerprint')) {
      context.handle(
        _keyFingerprintMeta,
        keyFingerprint.isAcceptableOrUnknown(
          data['key_fingerprint']!,
          _keyFingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_keyFingerprintMeta);
    }
    if (data.containsKey('robot_index')) {
      context.handle(
        _robotIndexMeta,
        robotIndex.isAcceptableOrUnknown(data['robot_index']!, _robotIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_robotIndexMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('network')) {
      context.handle(
        _networkMeta,
        network.isAcceptableOrUnknown(data['network']!, _networkMeta),
      );
    } else if (isInserting) {
      context.missing(_networkMeta);
    }
    if (data.containsKey('coordinator_alias')) {
      context.handle(
        _coordinatorAliasMeta,
        coordinatorAlias.isAcceptableOrUnknown(
          data['coordinator_alias']!,
          _coordinatorAliasMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_coordinatorAliasMeta);
    }
    if (data.containsKey('order_id')) {
      context.handle(
        _orderIdMeta,
        orderId.isAcceptableOrUnknown(data['order_id']!, _orderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_orderIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('order_type')) {
      context.handle(
        _orderTypeMeta,
        orderType.isAcceptableOrUnknown(data['order_type']!, _orderTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_orderTypeMeta);
    }
    if (data.containsKey('currency_id')) {
      context.handle(
        _currencyIdMeta,
        currencyId.isAcceptableOrUnknown(data['currency_id']!, _currencyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyIdMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('is_range')) {
      context.handle(
        _isRangeMeta,
        isRange.isAcceptableOrUnknown(data['is_range']!, _isRangeMeta),
      );
    } else if (isInserting) {
      context.missing(_isRangeMeta);
    }
    if (data.containsKey('premium_percent')) {
      context.handle(
        _premiumPercentMeta,
        premiumPercent.isAcceptableOrUnknown(
          data['premium_percent']!,
          _premiumPercentMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_premiumPercentMeta);
    }
    if (data.containsKey('explicit_satoshis')) {
      context.handle(
        _explicitSatoshisMeta,
        explicitSatoshis.isAcceptableOrUnknown(
          data['explicit_satoshis']!,
          _explicitSatoshisMeta,
        ),
      );
    }
    if (data.containsKey('bond_size_percent')) {
      context.handle(
        _bondSizePercentMeta,
        bondSizePercent.isAcceptableOrUnknown(
          data['bond_size_percent']!,
          _bondSizePercentMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_bondSizePercentMeta);
    }
    if (data.containsKey('escrow_seconds')) {
      context.handle(
        _escrowSecondsMeta,
        escrowSeconds.isAcceptableOrUnknown(
          data['escrow_seconds']!,
          _escrowSecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_escrowSecondsMeta);
    }
    if (data.containsKey('book_price')) {
      context.handle(
        _bookPriceMeta,
        bookPrice.isAcceptableOrUnknown(data['book_price']!, _bookPriceMeta),
      );
    } else if (isInserting) {
      context.missing(_bookPriceMeta);
    }
    if (data.containsKey('taker_fee')) {
      context.handle(
        _takerFeeMeta,
        takerFee.isAcceptableOrUnknown(data['taker_fee']!, _takerFeeMeta),
      );
    } else if (isInserting) {
      context.missing(_takerFeeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {keyFingerprint, robotIndex};
  @override
  TradeTermsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TradeTermsRow(
      keyFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key_fingerprint'],
      )!,
      robotIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}robot_index'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      network: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}network'],
      )!,
      coordinatorAlias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coordinator_alias'],
      )!,
      orderId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      orderType: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_type'],
      )!,
      currencyId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}currency_id'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}amount'],
      )!,
      isRange: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_range'],
      )!,
      premiumPercent: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}premium_percent'],
      )!,
      explicitSatoshis: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}explicit_satoshis'],
      ),
      bondSizePercent: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bond_size_percent'],
      )!,
      escrowSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}escrow_seconds'],
      )!,
      bookPrice: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}book_price'],
      )!,
      takerFee: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}taker_fee'],
      )!,
    );
  }

  @override
  $StoredTradeTermsTable createAlias(String alias) {
    return $StoredTradeTermsTable(attachedDatabase, alias);
  }
}

class TradeTermsRow extends DataClass implements Insertable<TradeTermsRow> {
  /// The trade's robot, as `trades` keys it.
  final String keyFingerprint;
  final int robotIndex;

  /// `TradeTermsRecord.version`.
  final int version;

  /// The trade the terms belong to, which must be the trade of the row of `trades` they are keyed by: `RobosatsNetwork.name`, the coordinator's short alias, the order, `TradeRole.name`.
  final String network;
  final String coordinatorAlias;
  final int orderId;
  final String role;

  /// `OrderType.wire`: 0 buy, 1 sell.
  final int orderType;
  final int currencyId;

  /// The fiat amount traded, in the order's currency.
  final double amount;
  final bool isRange;
  final double premiumPercent;

  /// The sats of an order priced in sats, or absent.
  final int? explicitSatoshis;
  final double bondSizePercent;
  final int escrowSeconds;
  final double bookPrice;
  final double takerFee;
  const TradeTermsRow({
    required this.keyFingerprint,
    required this.robotIndex,
    required this.version,
    required this.network,
    required this.coordinatorAlias,
    required this.orderId,
    required this.role,
    required this.orderType,
    required this.currencyId,
    required this.amount,
    required this.isRange,
    required this.premiumPercent,
    this.explicitSatoshis,
    required this.bondSizePercent,
    required this.escrowSeconds,
    required this.bookPrice,
    required this.takerFee,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key_fingerprint'] = Variable<String>(keyFingerprint);
    map['robot_index'] = Variable<int>(robotIndex);
    map['version'] = Variable<int>(version);
    map['network'] = Variable<String>(network);
    map['coordinator_alias'] = Variable<String>(coordinatorAlias);
    map['order_id'] = Variable<int>(orderId);
    map['role'] = Variable<String>(role);
    map['order_type'] = Variable<int>(orderType);
    map['currency_id'] = Variable<int>(currencyId);
    map['amount'] = Variable<double>(amount);
    map['is_range'] = Variable<bool>(isRange);
    map['premium_percent'] = Variable<double>(premiumPercent);
    if (!nullToAbsent || explicitSatoshis != null) {
      map['explicit_satoshis'] = Variable<int>(explicitSatoshis);
    }
    map['bond_size_percent'] = Variable<double>(bondSizePercent);
    map['escrow_seconds'] = Variable<int>(escrowSeconds);
    map['book_price'] = Variable<double>(bookPrice);
    map['taker_fee'] = Variable<double>(takerFee);
    return map;
  }

  StoredTradeTermsCompanion toCompanion(bool nullToAbsent) {
    return StoredTradeTermsCompanion(
      keyFingerprint: Value(keyFingerprint),
      robotIndex: Value(robotIndex),
      version: Value(version),
      network: Value(network),
      coordinatorAlias: Value(coordinatorAlias),
      orderId: Value(orderId),
      role: Value(role),
      orderType: Value(orderType),
      currencyId: Value(currencyId),
      amount: Value(amount),
      isRange: Value(isRange),
      premiumPercent: Value(premiumPercent),
      explicitSatoshis: explicitSatoshis == null && nullToAbsent
          ? const Value.absent()
          : Value(explicitSatoshis),
      bondSizePercent: Value(bondSizePercent),
      escrowSeconds: Value(escrowSeconds),
      bookPrice: Value(bookPrice),
      takerFee: Value(takerFee),
    );
  }

  factory TradeTermsRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TradeTermsRow(
      keyFingerprint: serializer.fromJson<String>(json['keyFingerprint']),
      robotIndex: serializer.fromJson<int>(json['robotIndex']),
      version: serializer.fromJson<int>(json['version']),
      network: serializer.fromJson<String>(json['network']),
      coordinatorAlias: serializer.fromJson<String>(json['coordinatorAlias']),
      orderId: serializer.fromJson<int>(json['orderId']),
      role: serializer.fromJson<String>(json['role']),
      orderType: serializer.fromJson<int>(json['orderType']),
      currencyId: serializer.fromJson<int>(json['currencyId']),
      amount: serializer.fromJson<double>(json['amount']),
      isRange: serializer.fromJson<bool>(json['isRange']),
      premiumPercent: serializer.fromJson<double>(json['premiumPercent']),
      explicitSatoshis: serializer.fromJson<int?>(json['explicitSatoshis']),
      bondSizePercent: serializer.fromJson<double>(json['bondSizePercent']),
      escrowSeconds: serializer.fromJson<int>(json['escrowSeconds']),
      bookPrice: serializer.fromJson<double>(json['bookPrice']),
      takerFee: serializer.fromJson<double>(json['takerFee']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'keyFingerprint': serializer.toJson<String>(keyFingerprint),
      'robotIndex': serializer.toJson<int>(robotIndex),
      'version': serializer.toJson<int>(version),
      'network': serializer.toJson<String>(network),
      'coordinatorAlias': serializer.toJson<String>(coordinatorAlias),
      'orderId': serializer.toJson<int>(orderId),
      'role': serializer.toJson<String>(role),
      'orderType': serializer.toJson<int>(orderType),
      'currencyId': serializer.toJson<int>(currencyId),
      'amount': serializer.toJson<double>(amount),
      'isRange': serializer.toJson<bool>(isRange),
      'premiumPercent': serializer.toJson<double>(premiumPercent),
      'explicitSatoshis': serializer.toJson<int?>(explicitSatoshis),
      'bondSizePercent': serializer.toJson<double>(bondSizePercent),
      'escrowSeconds': serializer.toJson<int>(escrowSeconds),
      'bookPrice': serializer.toJson<double>(bookPrice),
      'takerFee': serializer.toJson<double>(takerFee),
    };
  }

  TradeTermsRow copyWith({
    String? keyFingerprint,
    int? robotIndex,
    int? version,
    String? network,
    String? coordinatorAlias,
    int? orderId,
    String? role,
    int? orderType,
    int? currencyId,
    double? amount,
    bool? isRange,
    double? premiumPercent,
    Value<int?> explicitSatoshis = const Value.absent(),
    double? bondSizePercent,
    int? escrowSeconds,
    double? bookPrice,
    double? takerFee,
  }) => TradeTermsRow(
    keyFingerprint: keyFingerprint ?? this.keyFingerprint,
    robotIndex: robotIndex ?? this.robotIndex,
    version: version ?? this.version,
    network: network ?? this.network,
    coordinatorAlias: coordinatorAlias ?? this.coordinatorAlias,
    orderId: orderId ?? this.orderId,
    role: role ?? this.role,
    orderType: orderType ?? this.orderType,
    currencyId: currencyId ?? this.currencyId,
    amount: amount ?? this.amount,
    isRange: isRange ?? this.isRange,
    premiumPercent: premiumPercent ?? this.premiumPercent,
    explicitSatoshis: explicitSatoshis.present
        ? explicitSatoshis.value
        : this.explicitSatoshis,
    bondSizePercent: bondSizePercent ?? this.bondSizePercent,
    escrowSeconds: escrowSeconds ?? this.escrowSeconds,
    bookPrice: bookPrice ?? this.bookPrice,
    takerFee: takerFee ?? this.takerFee,
  );
  TradeTermsRow copyWithCompanion(StoredTradeTermsCompanion data) {
    return TradeTermsRow(
      keyFingerprint: data.keyFingerprint.present
          ? data.keyFingerprint.value
          : this.keyFingerprint,
      robotIndex: data.robotIndex.present
          ? data.robotIndex.value
          : this.robotIndex,
      version: data.version.present ? data.version.value : this.version,
      network: data.network.present ? data.network.value : this.network,
      coordinatorAlias: data.coordinatorAlias.present
          ? data.coordinatorAlias.value
          : this.coordinatorAlias,
      orderId: data.orderId.present ? data.orderId.value : this.orderId,
      role: data.role.present ? data.role.value : this.role,
      orderType: data.orderType.present ? data.orderType.value : this.orderType,
      currencyId: data.currencyId.present
          ? data.currencyId.value
          : this.currencyId,
      amount: data.amount.present ? data.amount.value : this.amount,
      isRange: data.isRange.present ? data.isRange.value : this.isRange,
      premiumPercent: data.premiumPercent.present
          ? data.premiumPercent.value
          : this.premiumPercent,
      explicitSatoshis: data.explicitSatoshis.present
          ? data.explicitSatoshis.value
          : this.explicitSatoshis,
      bondSizePercent: data.bondSizePercent.present
          ? data.bondSizePercent.value
          : this.bondSizePercent,
      escrowSeconds: data.escrowSeconds.present
          ? data.escrowSeconds.value
          : this.escrowSeconds,
      bookPrice: data.bookPrice.present ? data.bookPrice.value : this.bookPrice,
      takerFee: data.takerFee.present ? data.takerFee.value : this.takerFee,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TradeTermsRow(')
          ..write('keyFingerprint: $keyFingerprint, ')
          ..write('robotIndex: $robotIndex, ')
          ..write('version: $version, ')
          ..write('network: $network, ')
          ..write('coordinatorAlias: $coordinatorAlias, ')
          ..write('orderId: $orderId, ')
          ..write('role: $role, ')
          ..write('orderType: $orderType, ')
          ..write('currencyId: $currencyId, ')
          ..write('amount: $amount, ')
          ..write('isRange: $isRange, ')
          ..write('premiumPercent: $premiumPercent, ')
          ..write('explicitSatoshis: $explicitSatoshis, ')
          ..write('bondSizePercent: $bondSizePercent, ')
          ..write('escrowSeconds: $escrowSeconds, ')
          ..write('bookPrice: $bookPrice, ')
          ..write('takerFee: $takerFee')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    keyFingerprint,
    robotIndex,
    version,
    network,
    coordinatorAlias,
    orderId,
    role,
    orderType,
    currencyId,
    amount,
    isRange,
    premiumPercent,
    explicitSatoshis,
    bondSizePercent,
    escrowSeconds,
    bookPrice,
    takerFee,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TradeTermsRow &&
          other.keyFingerprint == this.keyFingerprint &&
          other.robotIndex == this.robotIndex &&
          other.version == this.version &&
          other.network == this.network &&
          other.coordinatorAlias == this.coordinatorAlias &&
          other.orderId == this.orderId &&
          other.role == this.role &&
          other.orderType == this.orderType &&
          other.currencyId == this.currencyId &&
          other.amount == this.amount &&
          other.isRange == this.isRange &&
          other.premiumPercent == this.premiumPercent &&
          other.explicitSatoshis == this.explicitSatoshis &&
          other.bondSizePercent == this.bondSizePercent &&
          other.escrowSeconds == this.escrowSeconds &&
          other.bookPrice == this.bookPrice &&
          other.takerFee == this.takerFee);
}

class StoredTradeTermsCompanion extends UpdateCompanion<TradeTermsRow> {
  final Value<String> keyFingerprint;
  final Value<int> robotIndex;
  final Value<int> version;
  final Value<String> network;
  final Value<String> coordinatorAlias;
  final Value<int> orderId;
  final Value<String> role;
  final Value<int> orderType;
  final Value<int> currencyId;
  final Value<double> amount;
  final Value<bool> isRange;
  final Value<double> premiumPercent;
  final Value<int?> explicitSatoshis;
  final Value<double> bondSizePercent;
  final Value<int> escrowSeconds;
  final Value<double> bookPrice;
  final Value<double> takerFee;
  final Value<int> rowid;
  const StoredTradeTermsCompanion({
    this.keyFingerprint = const Value.absent(),
    this.robotIndex = const Value.absent(),
    this.version = const Value.absent(),
    this.network = const Value.absent(),
    this.coordinatorAlias = const Value.absent(),
    this.orderId = const Value.absent(),
    this.role = const Value.absent(),
    this.orderType = const Value.absent(),
    this.currencyId = const Value.absent(),
    this.amount = const Value.absent(),
    this.isRange = const Value.absent(),
    this.premiumPercent = const Value.absent(),
    this.explicitSatoshis = const Value.absent(),
    this.bondSizePercent = const Value.absent(),
    this.escrowSeconds = const Value.absent(),
    this.bookPrice = const Value.absent(),
    this.takerFee = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredTradeTermsCompanion.insert({
    required String keyFingerprint,
    required int robotIndex,
    required int version,
    required String network,
    required String coordinatorAlias,
    required int orderId,
    required String role,
    required int orderType,
    required int currencyId,
    required double amount,
    required bool isRange,
    required double premiumPercent,
    this.explicitSatoshis = const Value.absent(),
    required double bondSizePercent,
    required int escrowSeconds,
    required double bookPrice,
    required double takerFee,
    this.rowid = const Value.absent(),
  }) : keyFingerprint = Value(keyFingerprint),
       robotIndex = Value(robotIndex),
       version = Value(version),
       network = Value(network),
       coordinatorAlias = Value(coordinatorAlias),
       orderId = Value(orderId),
       role = Value(role),
       orderType = Value(orderType),
       currencyId = Value(currencyId),
       amount = Value(amount),
       isRange = Value(isRange),
       premiumPercent = Value(premiumPercent),
       bondSizePercent = Value(bondSizePercent),
       escrowSeconds = Value(escrowSeconds),
       bookPrice = Value(bookPrice),
       takerFee = Value(takerFee);
  static Insertable<TradeTermsRow> custom({
    Expression<String>? keyFingerprint,
    Expression<int>? robotIndex,
    Expression<int>? version,
    Expression<String>? network,
    Expression<String>? coordinatorAlias,
    Expression<int>? orderId,
    Expression<String>? role,
    Expression<int>? orderType,
    Expression<int>? currencyId,
    Expression<double>? amount,
    Expression<bool>? isRange,
    Expression<double>? premiumPercent,
    Expression<int>? explicitSatoshis,
    Expression<double>? bondSizePercent,
    Expression<int>? escrowSeconds,
    Expression<double>? bookPrice,
    Expression<double>? takerFee,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (keyFingerprint != null) 'key_fingerprint': keyFingerprint,
      if (robotIndex != null) 'robot_index': robotIndex,
      if (version != null) 'version': version,
      if (network != null) 'network': network,
      if (coordinatorAlias != null) 'coordinator_alias': coordinatorAlias,
      if (orderId != null) 'order_id': orderId,
      if (role != null) 'role': role,
      if (orderType != null) 'order_type': orderType,
      if (currencyId != null) 'currency_id': currencyId,
      if (amount != null) 'amount': amount,
      if (isRange != null) 'is_range': isRange,
      if (premiumPercent != null) 'premium_percent': premiumPercent,
      if (explicitSatoshis != null) 'explicit_satoshis': explicitSatoshis,
      if (bondSizePercent != null) 'bond_size_percent': bondSizePercent,
      if (escrowSeconds != null) 'escrow_seconds': escrowSeconds,
      if (bookPrice != null) 'book_price': bookPrice,
      if (takerFee != null) 'taker_fee': takerFee,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredTradeTermsCompanion copyWith({
    Value<String>? keyFingerprint,
    Value<int>? robotIndex,
    Value<int>? version,
    Value<String>? network,
    Value<String>? coordinatorAlias,
    Value<int>? orderId,
    Value<String>? role,
    Value<int>? orderType,
    Value<int>? currencyId,
    Value<double>? amount,
    Value<bool>? isRange,
    Value<double>? premiumPercent,
    Value<int?>? explicitSatoshis,
    Value<double>? bondSizePercent,
    Value<int>? escrowSeconds,
    Value<double>? bookPrice,
    Value<double>? takerFee,
    Value<int>? rowid,
  }) {
    return StoredTradeTermsCompanion(
      keyFingerprint: keyFingerprint ?? this.keyFingerprint,
      robotIndex: robotIndex ?? this.robotIndex,
      version: version ?? this.version,
      network: network ?? this.network,
      coordinatorAlias: coordinatorAlias ?? this.coordinatorAlias,
      orderId: orderId ?? this.orderId,
      role: role ?? this.role,
      orderType: orderType ?? this.orderType,
      currencyId: currencyId ?? this.currencyId,
      amount: amount ?? this.amount,
      isRange: isRange ?? this.isRange,
      premiumPercent: premiumPercent ?? this.premiumPercent,
      explicitSatoshis: explicitSatoshis ?? this.explicitSatoshis,
      bondSizePercent: bondSizePercent ?? this.bondSizePercent,
      escrowSeconds: escrowSeconds ?? this.escrowSeconds,
      bookPrice: bookPrice ?? this.bookPrice,
      takerFee: takerFee ?? this.takerFee,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (keyFingerprint.present) {
      map['key_fingerprint'] = Variable<String>(keyFingerprint.value);
    }
    if (robotIndex.present) {
      map['robot_index'] = Variable<int>(robotIndex.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (network.present) {
      map['network'] = Variable<String>(network.value);
    }
    if (coordinatorAlias.present) {
      map['coordinator_alias'] = Variable<String>(coordinatorAlias.value);
    }
    if (orderId.present) {
      map['order_id'] = Variable<int>(orderId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (orderType.present) {
      map['order_type'] = Variable<int>(orderType.value);
    }
    if (currencyId.present) {
      map['currency_id'] = Variable<int>(currencyId.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (isRange.present) {
      map['is_range'] = Variable<bool>(isRange.value);
    }
    if (premiumPercent.present) {
      map['premium_percent'] = Variable<double>(premiumPercent.value);
    }
    if (explicitSatoshis.present) {
      map['explicit_satoshis'] = Variable<int>(explicitSatoshis.value);
    }
    if (bondSizePercent.present) {
      map['bond_size_percent'] = Variable<double>(bondSizePercent.value);
    }
    if (escrowSeconds.present) {
      map['escrow_seconds'] = Variable<int>(escrowSeconds.value);
    }
    if (bookPrice.present) {
      map['book_price'] = Variable<double>(bookPrice.value);
    }
    if (takerFee.present) {
      map['taker_fee'] = Variable<double>(takerFee.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredTradeTermsCompanion(')
          ..write('keyFingerprint: $keyFingerprint, ')
          ..write('robotIndex: $robotIndex, ')
          ..write('version: $version, ')
          ..write('network: $network, ')
          ..write('coordinatorAlias: $coordinatorAlias, ')
          ..write('orderId: $orderId, ')
          ..write('role: $role, ')
          ..write('orderType: $orderType, ')
          ..write('currencyId: $currencyId, ')
          ..write('amount: $amount, ')
          ..write('isRange: $isRange, ')
          ..write('premiumPercent: $premiumPercent, ')
          ..write('explicitSatoshis: $explicitSatoshis, ')
          ..write('bondSizePercent: $bondSizePercent, ')
          ..write('escrowSeconds: $escrowSeconds, ')
          ..write('bookPrice: $bookPrice, ')
          ..write('takerFee: $takerFee, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StoredTradePaymentsTable extends StoredTradePayments
    with TableInfo<$StoredTradePaymentsTable, TradePaymentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredTradePaymentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyFingerprintMeta = const VerificationMeta(
    'keyFingerprint',
  );
  @override
  late final GeneratedColumn<String> keyFingerprint = GeneratedColumn<String>(
    'key_fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _robotIndexMeta = const VerificationMeta(
    'robotIndex',
  );
  @override
  late final GeneratedColumn<int> robotIndex = GeneratedColumn<int>(
    'robot_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stepMeta = const VerificationMeta('step');
  @override
  late final GeneratedColumn<String> step = GeneratedColumn<String>(
    'step',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _paymentHashMeta = const VerificationMeta(
    'paymentHash',
  );
  @override
  late final GeneratedColumn<String> paymentHash = GeneratedColumn<String>(
    'payment_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<int> startedAt = GeneratedColumn<int>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _walletPaymentIdMeta = const VerificationMeta(
    'walletPaymentId',
  );
  @override
  late final GeneratedColumn<String> walletPaymentId = GeneratedColumn<String>(
    'wallet_payment_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _takeMeta = const VerificationMeta('take');
  @override
  late final GeneratedColumn<int> take = GeneratedColumn<int>(
    'take',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _confirmedSatsMeta = const VerificationMeta(
    'confirmedSats',
  );
  @override
  late final GeneratedColumn<int> confirmedSats = GeneratedColumn<int>(
    'confirmed_sats',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints:
        'NULL CHECK (confirmed_sats IS NULL OR (typeof(confirmed_sats) = \'integer\' AND confirmed_sats BETWEEN 1 AND 2100000000000000))',
  );
  @override
  List<GeneratedColumn> get $columns => [
    keyFingerprint,
    robotIndex,
    step,
    paymentHash,
    startedAt,
    walletPaymentId,
    take,
    confirmedSats,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'trade_payments';
  @override
  VerificationContext validateIntegrity(
    Insertable<TradePaymentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key_fingerprint')) {
      context.handle(
        _keyFingerprintMeta,
        keyFingerprint.isAcceptableOrUnknown(
          data['key_fingerprint']!,
          _keyFingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_keyFingerprintMeta);
    }
    if (data.containsKey('robot_index')) {
      context.handle(
        _robotIndexMeta,
        robotIndex.isAcceptableOrUnknown(data['robot_index']!, _robotIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_robotIndexMeta);
    }
    if (data.containsKey('step')) {
      context.handle(
        _stepMeta,
        step.isAcceptableOrUnknown(data['step']!, _stepMeta),
      );
    } else if (isInserting) {
      context.missing(_stepMeta);
    }
    if (data.containsKey('payment_hash')) {
      context.handle(
        _paymentHashMeta,
        paymentHash.isAcceptableOrUnknown(
          data['payment_hash']!,
          _paymentHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_paymentHashMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('wallet_payment_id')) {
      context.handle(
        _walletPaymentIdMeta,
        walletPaymentId.isAcceptableOrUnknown(
          data['wallet_payment_id']!,
          _walletPaymentIdMeta,
        ),
      );
    }
    if (data.containsKey('take')) {
      context.handle(
        _takeMeta,
        take.isAcceptableOrUnknown(data['take']!, _takeMeta),
      );
    }
    if (data.containsKey('confirmed_sats')) {
      context.handle(
        _confirmedSatsMeta,
        confirmedSats.isAcceptableOrUnknown(
          data['confirmed_sats']!,
          _confirmedSatsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    keyFingerprint,
    robotIndex,
    step,
    take,
  };
  @override
  TradePaymentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TradePaymentRow(
      keyFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key_fingerprint'],
      )!,
      robotIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}robot_index'],
      )!,
      step: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}step'],
      )!,
      paymentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_hash'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_at'],
      )!,
      walletPaymentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wallet_payment_id'],
      ),
      take: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}take'],
      )!,
      confirmedSats: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}confirmed_sats'],
      ),
    );
  }

  @override
  $StoredTradePaymentsTable createAlias(String alias) {
    return $StoredTradePaymentsTable(attachedDatabase, alias);
  }
}

class TradePaymentRow extends DataClass implements Insertable<TradePaymentRow> {
  /// The trade's robot, as `trades` keys it.
  final String keyFingerprint;
  final int robotIndex;

  /// `InvoiceStep.name` of the invoice paid: `bond` (the taker's bond) or, since schema 7 (#97), `escrow` (the seller's escrow).
  final String step;

  /// The payment hash of the invoice, 64 lowercase hexadecimal characters.
  final String paymentHash;

  /// When the last attempt was about to call the port, in microseconds since the epoch.
  final int startedAt;

  /// `P2pWalletPayment.id`, the wallet's local id of the swap that pays the invoice, once the port gave one.
  ///
  /// Recorded for the record's sake (a support question, a later reading): nothing decides on it, since the payment is found again by its hash (`P2pWalletPort.findPayment`), which the wallet's records key.
  final String? walletPaymentId;

  /// The contract the invoice belongs to, the trail's `take` when the row was written (schema 8): 0 for a bond and for every payment of a trade not made here, one more for a maker seller's escrow of each later contract.
  final int take;

  /// What the payment takes out of the wallet: the total of the quote the user confirmed (the invoice, the swap service's fee and the network fee, `P2pWalletQuote.total`), in sats, written by the statement that records the payment's start, before the wallet is asked (schema 9, #233; design note `docs/design/phase-3-making-an-order.md` § 3.5 bis); a new attempt of the same invoice never lowers it.
  ///
  /// Absent for every payment of a schema 8 file, whose amount was never kept: unknown, never zero. Its constraints are the column's own, so that schema 9 adds it to the table without rebuilding it; the triggers of `trade_payments.drift` refuse a payment recorded without it and an amount that goes down, is cleared, or appears on a payment whose amount was unknown.
  final int? confirmedSats;
  const TradePaymentRow({
    required this.keyFingerprint,
    required this.robotIndex,
    required this.step,
    required this.paymentHash,
    required this.startedAt,
    this.walletPaymentId,
    required this.take,
    this.confirmedSats,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key_fingerprint'] = Variable<String>(keyFingerprint);
    map['robot_index'] = Variable<int>(robotIndex);
    map['step'] = Variable<String>(step);
    map['payment_hash'] = Variable<String>(paymentHash);
    map['started_at'] = Variable<int>(startedAt);
    if (!nullToAbsent || walletPaymentId != null) {
      map['wallet_payment_id'] = Variable<String>(walletPaymentId);
    }
    map['take'] = Variable<int>(take);
    if (!nullToAbsent || confirmedSats != null) {
      map['confirmed_sats'] = Variable<int>(confirmedSats);
    }
    return map;
  }

  StoredTradePaymentsCompanion toCompanion(bool nullToAbsent) {
    return StoredTradePaymentsCompanion(
      keyFingerprint: Value(keyFingerprint),
      robotIndex: Value(robotIndex),
      step: Value(step),
      paymentHash: Value(paymentHash),
      startedAt: Value(startedAt),
      walletPaymentId: walletPaymentId == null && nullToAbsent
          ? const Value.absent()
          : Value(walletPaymentId),
      take: Value(take),
      confirmedSats: confirmedSats == null && nullToAbsent
          ? const Value.absent()
          : Value(confirmedSats),
    );
  }

  factory TradePaymentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TradePaymentRow(
      keyFingerprint: serializer.fromJson<String>(json['keyFingerprint']),
      robotIndex: serializer.fromJson<int>(json['robotIndex']),
      step: serializer.fromJson<String>(json['step']),
      paymentHash: serializer.fromJson<String>(json['paymentHash']),
      startedAt: serializer.fromJson<int>(json['startedAt']),
      walletPaymentId: serializer.fromJson<String?>(json['walletPaymentId']),
      take: serializer.fromJson<int>(json['take']),
      confirmedSats: serializer.fromJson<int?>(json['confirmedSats']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'keyFingerprint': serializer.toJson<String>(keyFingerprint),
      'robotIndex': serializer.toJson<int>(robotIndex),
      'step': serializer.toJson<String>(step),
      'paymentHash': serializer.toJson<String>(paymentHash),
      'startedAt': serializer.toJson<int>(startedAt),
      'walletPaymentId': serializer.toJson<String?>(walletPaymentId),
      'take': serializer.toJson<int>(take),
      'confirmedSats': serializer.toJson<int?>(confirmedSats),
    };
  }

  TradePaymentRow copyWith({
    String? keyFingerprint,
    int? robotIndex,
    String? step,
    String? paymentHash,
    int? startedAt,
    Value<String?> walletPaymentId = const Value.absent(),
    int? take,
    Value<int?> confirmedSats = const Value.absent(),
  }) => TradePaymentRow(
    keyFingerprint: keyFingerprint ?? this.keyFingerprint,
    robotIndex: robotIndex ?? this.robotIndex,
    step: step ?? this.step,
    paymentHash: paymentHash ?? this.paymentHash,
    startedAt: startedAt ?? this.startedAt,
    walletPaymentId: walletPaymentId.present
        ? walletPaymentId.value
        : this.walletPaymentId,
    take: take ?? this.take,
    confirmedSats: confirmedSats.present
        ? confirmedSats.value
        : this.confirmedSats,
  );
  TradePaymentRow copyWithCompanion(StoredTradePaymentsCompanion data) {
    return TradePaymentRow(
      keyFingerprint: data.keyFingerprint.present
          ? data.keyFingerprint.value
          : this.keyFingerprint,
      robotIndex: data.robotIndex.present
          ? data.robotIndex.value
          : this.robotIndex,
      step: data.step.present ? data.step.value : this.step,
      paymentHash: data.paymentHash.present
          ? data.paymentHash.value
          : this.paymentHash,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      walletPaymentId: data.walletPaymentId.present
          ? data.walletPaymentId.value
          : this.walletPaymentId,
      take: data.take.present ? data.take.value : this.take,
      confirmedSats: data.confirmedSats.present
          ? data.confirmedSats.value
          : this.confirmedSats,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TradePaymentRow(')
          ..write('keyFingerprint: $keyFingerprint, ')
          ..write('robotIndex: $robotIndex, ')
          ..write('step: $step, ')
          ..write('paymentHash: $paymentHash, ')
          ..write('startedAt: $startedAt, ')
          ..write('walletPaymentId: $walletPaymentId, ')
          ..write('take: $take, ')
          ..write('confirmedSats: $confirmedSats')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    keyFingerprint,
    robotIndex,
    step,
    paymentHash,
    startedAt,
    walletPaymentId,
    take,
    confirmedSats,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TradePaymentRow &&
          other.keyFingerprint == this.keyFingerprint &&
          other.robotIndex == this.robotIndex &&
          other.step == this.step &&
          other.paymentHash == this.paymentHash &&
          other.startedAt == this.startedAt &&
          other.walletPaymentId == this.walletPaymentId &&
          other.take == this.take &&
          other.confirmedSats == this.confirmedSats);
}

class StoredTradePaymentsCompanion extends UpdateCompanion<TradePaymentRow> {
  final Value<String> keyFingerprint;
  final Value<int> robotIndex;
  final Value<String> step;
  final Value<String> paymentHash;
  final Value<int> startedAt;
  final Value<String?> walletPaymentId;
  final Value<int> take;
  final Value<int?> confirmedSats;
  final Value<int> rowid;
  const StoredTradePaymentsCompanion({
    this.keyFingerprint = const Value.absent(),
    this.robotIndex = const Value.absent(),
    this.step = const Value.absent(),
    this.paymentHash = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.walletPaymentId = const Value.absent(),
    this.take = const Value.absent(),
    this.confirmedSats = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredTradePaymentsCompanion.insert({
    required String keyFingerprint,
    required int robotIndex,
    required String step,
    required String paymentHash,
    required int startedAt,
    this.walletPaymentId = const Value.absent(),
    this.take = const Value.absent(),
    this.confirmedSats = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : keyFingerprint = Value(keyFingerprint),
       robotIndex = Value(robotIndex),
       step = Value(step),
       paymentHash = Value(paymentHash),
       startedAt = Value(startedAt);
  static Insertable<TradePaymentRow> custom({
    Expression<String>? keyFingerprint,
    Expression<int>? robotIndex,
    Expression<String>? step,
    Expression<String>? paymentHash,
    Expression<int>? startedAt,
    Expression<String>? walletPaymentId,
    Expression<int>? take,
    Expression<int>? confirmedSats,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (keyFingerprint != null) 'key_fingerprint': keyFingerprint,
      if (robotIndex != null) 'robot_index': robotIndex,
      if (step != null) 'step': step,
      if (paymentHash != null) 'payment_hash': paymentHash,
      if (startedAt != null) 'started_at': startedAt,
      if (walletPaymentId != null) 'wallet_payment_id': walletPaymentId,
      if (take != null) 'take': take,
      if (confirmedSats != null) 'confirmed_sats': confirmedSats,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredTradePaymentsCompanion copyWith({
    Value<String>? keyFingerprint,
    Value<int>? robotIndex,
    Value<String>? step,
    Value<String>? paymentHash,
    Value<int>? startedAt,
    Value<String?>? walletPaymentId,
    Value<int>? take,
    Value<int?>? confirmedSats,
    Value<int>? rowid,
  }) {
    return StoredTradePaymentsCompanion(
      keyFingerprint: keyFingerprint ?? this.keyFingerprint,
      robotIndex: robotIndex ?? this.robotIndex,
      step: step ?? this.step,
      paymentHash: paymentHash ?? this.paymentHash,
      startedAt: startedAt ?? this.startedAt,
      walletPaymentId: walletPaymentId ?? this.walletPaymentId,
      take: take ?? this.take,
      confirmedSats: confirmedSats ?? this.confirmedSats,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (keyFingerprint.present) {
      map['key_fingerprint'] = Variable<String>(keyFingerprint.value);
    }
    if (robotIndex.present) {
      map['robot_index'] = Variable<int>(robotIndex.value);
    }
    if (step.present) {
      map['step'] = Variable<String>(step.value);
    }
    if (paymentHash.present) {
      map['payment_hash'] = Variable<String>(paymentHash.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<int>(startedAt.value);
    }
    if (walletPaymentId.present) {
      map['wallet_payment_id'] = Variable<String>(walletPaymentId.value);
    }
    if (take.present) {
      map['take'] = Variable<int>(take.value);
    }
    if (confirmedSats.present) {
      map['confirmed_sats'] = Variable<int>(confirmedSats.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredTradePaymentsCompanion(')
          ..write('keyFingerprint: $keyFingerprint, ')
          ..write('robotIndex: $robotIndex, ')
          ..write('step: $step, ')
          ..write('paymentHash: $paymentHash, ')
          ..write('startedAt: $startedAt, ')
          ..write('walletPaymentId: $walletPaymentId, ')
          ..write('take: $take, ')
          ..write('confirmedSats: $confirmedSats, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StoredTradeChatPinsTable extends StoredTradeChatPins
    with TableInfo<$StoredTradeChatPinsTable, TradeChatPinRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredTradeChatPinsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyFingerprintMeta = const VerificationMeta(
    'keyFingerprint',
  );
  @override
  late final GeneratedColumn<String> keyFingerprint = GeneratedColumn<String>(
    'key_fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _robotIndexMeta = const VerificationMeta(
    'robotIndex',
  );
  @override
  late final GeneratedColumn<int> robotIndex = GeneratedColumn<int>(
    'robot_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _primaryFingerprintMeta =
      const VerificationMeta('primaryFingerprint');
  @override
  late final GeneratedColumn<String> primaryFingerprint =
      GeneratedColumn<String>(
        'primary_fingerprint',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _subkeyFingerprintMeta = const VerificationMeta(
    'subkeyFingerprint',
  );
  @override
  late final GeneratedColumn<String> subkeyFingerprint =
      GeneratedColumn<String>(
        'subkey_fingerprint',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _armoredKeyMeta = const VerificationMeta(
    'armoredKey',
  );
  @override
  late final GeneratedColumn<String> armoredKey = GeneratedColumn<String>(
    'armored_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    keyFingerprint,
    robotIndex,
    primaryFingerprint,
    subkeyFingerprint,
    armoredKey,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'trade_chat_pins';
  @override
  VerificationContext validateIntegrity(
    Insertable<TradeChatPinRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key_fingerprint')) {
      context.handle(
        _keyFingerprintMeta,
        keyFingerprint.isAcceptableOrUnknown(
          data['key_fingerprint']!,
          _keyFingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_keyFingerprintMeta);
    }
    if (data.containsKey('robot_index')) {
      context.handle(
        _robotIndexMeta,
        robotIndex.isAcceptableOrUnknown(data['robot_index']!, _robotIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_robotIndexMeta);
    }
    if (data.containsKey('primary_fingerprint')) {
      context.handle(
        _primaryFingerprintMeta,
        primaryFingerprint.isAcceptableOrUnknown(
          data['primary_fingerprint']!,
          _primaryFingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_primaryFingerprintMeta);
    }
    if (data.containsKey('subkey_fingerprint')) {
      context.handle(
        _subkeyFingerprintMeta,
        subkeyFingerprint.isAcceptableOrUnknown(
          data['subkey_fingerprint']!,
          _subkeyFingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_subkeyFingerprintMeta);
    }
    if (data.containsKey('armored_key')) {
      context.handle(
        _armoredKeyMeta,
        armoredKey.isAcceptableOrUnknown(data['armored_key']!, _armoredKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_armoredKeyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {keyFingerprint, robotIndex};
  @override
  TradeChatPinRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TradeChatPinRow(
      keyFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key_fingerprint'],
      )!,
      robotIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}robot_index'],
      )!,
      primaryFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}primary_fingerprint'],
      )!,
      subkeyFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subkey_fingerprint'],
      )!,
      armoredKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}armored_key'],
      )!,
    );
  }

  @override
  $StoredTradeChatPinsTable createAlias(String alias) {
    return $StoredTradeChatPinsTable(attachedDatabase, alias);
  }
}

class TradeChatPinRow extends DataClass implements Insertable<TradeChatPinRow> {
  /// The trade's robot, as `trades` keys it.
  final String keyFingerprint;
  final int robotIndex;

  /// `PgpPublicKey.fingerprint` of the pinned key: 40 uppercase hexadecimal characters.
  final String primaryFingerprint;

  /// `PgpPublicKey.subkeyFingerprint` of the pinned key: 40 uppercase hexadecimal characters.
  final String subkeyFingerprint;

  /// `PgpPublicKey.armored` of the pinned key: an armored public key block of at most `PgpLimits.keyArmorChars` (20,000) characters.
  final String armoredKey;
  const TradeChatPinRow({
    required this.keyFingerprint,
    required this.robotIndex,
    required this.primaryFingerprint,
    required this.subkeyFingerprint,
    required this.armoredKey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key_fingerprint'] = Variable<String>(keyFingerprint);
    map['robot_index'] = Variable<int>(robotIndex);
    map['primary_fingerprint'] = Variable<String>(primaryFingerprint);
    map['subkey_fingerprint'] = Variable<String>(subkeyFingerprint);
    map['armored_key'] = Variable<String>(armoredKey);
    return map;
  }

  StoredTradeChatPinsCompanion toCompanion(bool nullToAbsent) {
    return StoredTradeChatPinsCompanion(
      keyFingerprint: Value(keyFingerprint),
      robotIndex: Value(robotIndex),
      primaryFingerprint: Value(primaryFingerprint),
      subkeyFingerprint: Value(subkeyFingerprint),
      armoredKey: Value(armoredKey),
    );
  }

  factory TradeChatPinRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TradeChatPinRow(
      keyFingerprint: serializer.fromJson<String>(json['keyFingerprint']),
      robotIndex: serializer.fromJson<int>(json['robotIndex']),
      primaryFingerprint: serializer.fromJson<String>(
        json['primaryFingerprint'],
      ),
      subkeyFingerprint: serializer.fromJson<String>(json['subkeyFingerprint']),
      armoredKey: serializer.fromJson<String>(json['armoredKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'keyFingerprint': serializer.toJson<String>(keyFingerprint),
      'robotIndex': serializer.toJson<int>(robotIndex),
      'primaryFingerprint': serializer.toJson<String>(primaryFingerprint),
      'subkeyFingerprint': serializer.toJson<String>(subkeyFingerprint),
      'armoredKey': serializer.toJson<String>(armoredKey),
    };
  }

  TradeChatPinRow copyWith({
    String? keyFingerprint,
    int? robotIndex,
    String? primaryFingerprint,
    String? subkeyFingerprint,
    String? armoredKey,
  }) => TradeChatPinRow(
    keyFingerprint: keyFingerprint ?? this.keyFingerprint,
    robotIndex: robotIndex ?? this.robotIndex,
    primaryFingerprint: primaryFingerprint ?? this.primaryFingerprint,
    subkeyFingerprint: subkeyFingerprint ?? this.subkeyFingerprint,
    armoredKey: armoredKey ?? this.armoredKey,
  );
  TradeChatPinRow copyWithCompanion(StoredTradeChatPinsCompanion data) {
    return TradeChatPinRow(
      keyFingerprint: data.keyFingerprint.present
          ? data.keyFingerprint.value
          : this.keyFingerprint,
      robotIndex: data.robotIndex.present
          ? data.robotIndex.value
          : this.robotIndex,
      primaryFingerprint: data.primaryFingerprint.present
          ? data.primaryFingerprint.value
          : this.primaryFingerprint,
      subkeyFingerprint: data.subkeyFingerprint.present
          ? data.subkeyFingerprint.value
          : this.subkeyFingerprint,
      armoredKey: data.armoredKey.present
          ? data.armoredKey.value
          : this.armoredKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TradeChatPinRow(')
          ..write('keyFingerprint: $keyFingerprint, ')
          ..write('robotIndex: $robotIndex, ')
          ..write('primaryFingerprint: $primaryFingerprint, ')
          ..write('subkeyFingerprint: $subkeyFingerprint, ')
          ..write('armoredKey: $armoredKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    keyFingerprint,
    robotIndex,
    primaryFingerprint,
    subkeyFingerprint,
    armoredKey,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TradeChatPinRow &&
          other.keyFingerprint == this.keyFingerprint &&
          other.robotIndex == this.robotIndex &&
          other.primaryFingerprint == this.primaryFingerprint &&
          other.subkeyFingerprint == this.subkeyFingerprint &&
          other.armoredKey == this.armoredKey);
}

class StoredTradeChatPinsCompanion extends UpdateCompanion<TradeChatPinRow> {
  final Value<String> keyFingerprint;
  final Value<int> robotIndex;
  final Value<String> primaryFingerprint;
  final Value<String> subkeyFingerprint;
  final Value<String> armoredKey;
  final Value<int> rowid;
  const StoredTradeChatPinsCompanion({
    this.keyFingerprint = const Value.absent(),
    this.robotIndex = const Value.absent(),
    this.primaryFingerprint = const Value.absent(),
    this.subkeyFingerprint = const Value.absent(),
    this.armoredKey = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredTradeChatPinsCompanion.insert({
    required String keyFingerprint,
    required int robotIndex,
    required String primaryFingerprint,
    required String subkeyFingerprint,
    required String armoredKey,
    this.rowid = const Value.absent(),
  }) : keyFingerprint = Value(keyFingerprint),
       robotIndex = Value(robotIndex),
       primaryFingerprint = Value(primaryFingerprint),
       subkeyFingerprint = Value(subkeyFingerprint),
       armoredKey = Value(armoredKey);
  static Insertable<TradeChatPinRow> custom({
    Expression<String>? keyFingerprint,
    Expression<int>? robotIndex,
    Expression<String>? primaryFingerprint,
    Expression<String>? subkeyFingerprint,
    Expression<String>? armoredKey,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (keyFingerprint != null) 'key_fingerprint': keyFingerprint,
      if (robotIndex != null) 'robot_index': robotIndex,
      if (primaryFingerprint != null) 'primary_fingerprint': primaryFingerprint,
      if (subkeyFingerprint != null) 'subkey_fingerprint': subkeyFingerprint,
      if (armoredKey != null) 'armored_key': armoredKey,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredTradeChatPinsCompanion copyWith({
    Value<String>? keyFingerprint,
    Value<int>? robotIndex,
    Value<String>? primaryFingerprint,
    Value<String>? subkeyFingerprint,
    Value<String>? armoredKey,
    Value<int>? rowid,
  }) {
    return StoredTradeChatPinsCompanion(
      keyFingerprint: keyFingerprint ?? this.keyFingerprint,
      robotIndex: robotIndex ?? this.robotIndex,
      primaryFingerprint: primaryFingerprint ?? this.primaryFingerprint,
      subkeyFingerprint: subkeyFingerprint ?? this.subkeyFingerprint,
      armoredKey: armoredKey ?? this.armoredKey,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (keyFingerprint.present) {
      map['key_fingerprint'] = Variable<String>(keyFingerprint.value);
    }
    if (robotIndex.present) {
      map['robot_index'] = Variable<int>(robotIndex.value);
    }
    if (primaryFingerprint.present) {
      map['primary_fingerprint'] = Variable<String>(primaryFingerprint.value);
    }
    if (subkeyFingerprint.present) {
      map['subkey_fingerprint'] = Variable<String>(subkeyFingerprint.value);
    }
    if (armoredKey.present) {
      map['armored_key'] = Variable<String>(armoredKey.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredTradeChatPinsCompanion(')
          ..write('keyFingerprint: $keyFingerprint, ')
          ..write('robotIndex: $robotIndex, ')
          ..write('primaryFingerprint: $primaryFingerprint, ')
          ..write('subkeyFingerprint: $subkeyFingerprint, ')
          ..write('armoredKey: $armoredKey, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StoredTradeChatNostrPinsTable extends StoredTradeChatNostrPins
    with TableInfo<$StoredTradeChatNostrPinsTable, TradeChatNostrPinRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredTradeChatNostrPinsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyFingerprintMeta = const VerificationMeta(
    'keyFingerprint',
  );
  @override
  late final GeneratedColumn<String> keyFingerprint = GeneratedColumn<String>(
    'key_fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _robotIndexMeta = const VerificationMeta(
    'robotIndex',
  );
  @override
  late final GeneratedColumn<int> robotIndex = GeneratedColumn<int>(
    'robot_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerKeyMeta = const VerificationMeta(
    'peerKey',
  );
  @override
  late final GeneratedColumn<String> peerKey = GeneratedColumn<String>(
    'peer_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownKeyMeta = const VerificationMeta('ownKey');
  @override
  late final GeneratedColumn<String> ownKey = GeneratedColumn<String>(
    'own_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    keyFingerprint,
    robotIndex,
    peerKey,
    ownKey,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'trade_chat_nostr_pins';
  @override
  VerificationContext validateIntegrity(
    Insertable<TradeChatNostrPinRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key_fingerprint')) {
      context.handle(
        _keyFingerprintMeta,
        keyFingerprint.isAcceptableOrUnknown(
          data['key_fingerprint']!,
          _keyFingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_keyFingerprintMeta);
    }
    if (data.containsKey('robot_index')) {
      context.handle(
        _robotIndexMeta,
        robotIndex.isAcceptableOrUnknown(data['robot_index']!, _robotIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_robotIndexMeta);
    }
    if (data.containsKey('peer_key')) {
      context.handle(
        _peerKeyMeta,
        peerKey.isAcceptableOrUnknown(data['peer_key']!, _peerKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_peerKeyMeta);
    }
    if (data.containsKey('own_key')) {
      context.handle(
        _ownKeyMeta,
        ownKey.isAcceptableOrUnknown(data['own_key']!, _ownKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_ownKeyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {keyFingerprint, robotIndex};
  @override
  TradeChatNostrPinRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TradeChatNostrPinRow(
      keyFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key_fingerprint'],
      )!,
      robotIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}robot_index'],
      )!,
      peerKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_key'],
      )!,
      ownKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}own_key'],
      )!,
    );
  }

  @override
  $StoredTradeChatNostrPinsTable createAlias(String alias) {
    return $StoredTradeChatNostrPinsTable(attachedDatabase, alias);
  }
}

class TradeChatNostrPinRow extends DataClass
    implements Insertable<TradeChatNostrPinRow> {
  /// The trade's robot, as `trades` keys it.
  final String keyFingerprint;
  final int robotIndex;

  /// The peer's Nostr public key: 64 lowercase hexadecimal characters.
  final String peerKey;

  /// This robot's Nostr public key as the order gives it: 64 lowercase hexadecimal characters.
  final String ownKey;
  const TradeChatNostrPinRow({
    required this.keyFingerprint,
    required this.robotIndex,
    required this.peerKey,
    required this.ownKey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key_fingerprint'] = Variable<String>(keyFingerprint);
    map['robot_index'] = Variable<int>(robotIndex);
    map['peer_key'] = Variable<String>(peerKey);
    map['own_key'] = Variable<String>(ownKey);
    return map;
  }

  StoredTradeChatNostrPinsCompanion toCompanion(bool nullToAbsent) {
    return StoredTradeChatNostrPinsCompanion(
      keyFingerprint: Value(keyFingerprint),
      robotIndex: Value(robotIndex),
      peerKey: Value(peerKey),
      ownKey: Value(ownKey),
    );
  }

  factory TradeChatNostrPinRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TradeChatNostrPinRow(
      keyFingerprint: serializer.fromJson<String>(json['keyFingerprint']),
      robotIndex: serializer.fromJson<int>(json['robotIndex']),
      peerKey: serializer.fromJson<String>(json['peerKey']),
      ownKey: serializer.fromJson<String>(json['ownKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'keyFingerprint': serializer.toJson<String>(keyFingerprint),
      'robotIndex': serializer.toJson<int>(robotIndex),
      'peerKey': serializer.toJson<String>(peerKey),
      'ownKey': serializer.toJson<String>(ownKey),
    };
  }

  TradeChatNostrPinRow copyWith({
    String? keyFingerprint,
    int? robotIndex,
    String? peerKey,
    String? ownKey,
  }) => TradeChatNostrPinRow(
    keyFingerprint: keyFingerprint ?? this.keyFingerprint,
    robotIndex: robotIndex ?? this.robotIndex,
    peerKey: peerKey ?? this.peerKey,
    ownKey: ownKey ?? this.ownKey,
  );
  TradeChatNostrPinRow copyWithCompanion(
    StoredTradeChatNostrPinsCompanion data,
  ) {
    return TradeChatNostrPinRow(
      keyFingerprint: data.keyFingerprint.present
          ? data.keyFingerprint.value
          : this.keyFingerprint,
      robotIndex: data.robotIndex.present
          ? data.robotIndex.value
          : this.robotIndex,
      peerKey: data.peerKey.present ? data.peerKey.value : this.peerKey,
      ownKey: data.ownKey.present ? data.ownKey.value : this.ownKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TradeChatNostrPinRow(')
          ..write('keyFingerprint: $keyFingerprint, ')
          ..write('robotIndex: $robotIndex, ')
          ..write('peerKey: $peerKey, ')
          ..write('ownKey: $ownKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(keyFingerprint, robotIndex, peerKey, ownKey);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TradeChatNostrPinRow &&
          other.keyFingerprint == this.keyFingerprint &&
          other.robotIndex == this.robotIndex &&
          other.peerKey == this.peerKey &&
          other.ownKey == this.ownKey);
}

class StoredTradeChatNostrPinsCompanion
    extends UpdateCompanion<TradeChatNostrPinRow> {
  final Value<String> keyFingerprint;
  final Value<int> robotIndex;
  final Value<String> peerKey;
  final Value<String> ownKey;
  final Value<int> rowid;
  const StoredTradeChatNostrPinsCompanion({
    this.keyFingerprint = const Value.absent(),
    this.robotIndex = const Value.absent(),
    this.peerKey = const Value.absent(),
    this.ownKey = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredTradeChatNostrPinsCompanion.insert({
    required String keyFingerprint,
    required int robotIndex,
    required String peerKey,
    required String ownKey,
    this.rowid = const Value.absent(),
  }) : keyFingerprint = Value(keyFingerprint),
       robotIndex = Value(robotIndex),
       peerKey = Value(peerKey),
       ownKey = Value(ownKey);
  static Insertable<TradeChatNostrPinRow> custom({
    Expression<String>? keyFingerprint,
    Expression<int>? robotIndex,
    Expression<String>? peerKey,
    Expression<String>? ownKey,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (keyFingerprint != null) 'key_fingerprint': keyFingerprint,
      if (robotIndex != null) 'robot_index': robotIndex,
      if (peerKey != null) 'peer_key': peerKey,
      if (ownKey != null) 'own_key': ownKey,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredTradeChatNostrPinsCompanion copyWith({
    Value<String>? keyFingerprint,
    Value<int>? robotIndex,
    Value<String>? peerKey,
    Value<String>? ownKey,
    Value<int>? rowid,
  }) {
    return StoredTradeChatNostrPinsCompanion(
      keyFingerprint: keyFingerprint ?? this.keyFingerprint,
      robotIndex: robotIndex ?? this.robotIndex,
      peerKey: peerKey ?? this.peerKey,
      ownKey: ownKey ?? this.ownKey,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (keyFingerprint.present) {
      map['key_fingerprint'] = Variable<String>(keyFingerprint.value);
    }
    if (robotIndex.present) {
      map['robot_index'] = Variable<int>(robotIndex.value);
    }
    if (peerKey.present) {
      map['peer_key'] = Variable<String>(peerKey.value);
    }
    if (ownKey.present) {
      map['own_key'] = Variable<String>(ownKey.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredTradeChatNostrPinsCompanion(')
          ..write('keyFingerprint: $keyFingerprint, ')
          ..write('robotIndex: $robotIndex, ')
          ..write('peerKey: $peerKey, ')
          ..write('ownKey: $ownKey, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StoredMakerTermsTable extends StoredMakerTerms
    with TableInfo<$StoredMakerTermsTable, MakerTermsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredMakerTermsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyFingerprintMeta = const VerificationMeta(
    'keyFingerprint',
  );
  @override
  late final GeneratedColumn<String> keyFingerprint = GeneratedColumn<String>(
    'key_fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _robotIndexMeta = const VerificationMeta(
    'robotIndex',
  );
  @override
  late final GeneratedColumn<int> robotIndex = GeneratedColumn<int>(
    'robot_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _networkMeta = const VerificationMeta(
    'network',
  );
  @override
  late final GeneratedColumn<String> network = GeneratedColumn<String>(
    'network',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coordinatorAliasMeta = const VerificationMeta(
    'coordinatorAlias',
  );
  @override
  late final GeneratedColumn<String> coordinatorAlias = GeneratedColumn<String>(
    'coordinator_alias',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orderTypeMeta = const VerificationMeta(
    'orderType',
  );
  @override
  late final GeneratedColumn<int> orderType = GeneratedColumn<int>(
    'order_type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyIdMeta = const VerificationMeta(
    'currencyId',
  );
  @override
  late final GeneratedColumn<int> currencyId = GeneratedColumn<int>(
    'currency_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
    'amount',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _minAmountMeta = const VerificationMeta(
    'minAmount',
  );
  @override
  late final GeneratedColumn<double> minAmount = GeneratedColumn<double>(
    'min_amount',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maxAmountMeta = const VerificationMeta(
    'maxAmount',
  );
  @override
  late final GeneratedColumn<double> maxAmount = GeneratedColumn<double>(
    'max_amount',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _premiumPercentMeta = const VerificationMeta(
    'premiumPercent',
  );
  @override
  late final GeneratedColumn<double> premiumPercent = GeneratedColumn<double>(
    'premium_percent',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _paymentMethodMeta = const VerificationMeta(
    'paymentMethod',
  );
  @override
  late final GeneratedColumn<String> paymentMethod = GeneratedColumn<String>(
    'payment_method',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bondSizePercentMeta = const VerificationMeta(
    'bondSizePercent',
  );
  @override
  late final GeneratedColumn<double> bondSizePercent = GeneratedColumn<double>(
    'bond_size_percent',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _publicSecondsMeta = const VerificationMeta(
    'publicSeconds',
  );
  @override
  late final GeneratedColumn<int> publicSeconds = GeneratedColumn<int>(
    'public_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _escrowSecondsMeta = const VerificationMeta(
    'escrowSeconds',
  );
  @override
  late final GeneratedColumn<int> escrowSeconds = GeneratedColumn<int>(
    'escrow_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hasPasswordMeta = const VerificationMeta(
    'hasPassword',
  );
  @override
  late final GeneratedColumn<bool> hasPassword = GeneratedColumn<bool>(
    'has_password',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_password" IN (0, 1))',
    ),
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdPriceMeta = const VerificationMeta(
    'createdPrice',
  );
  @override
  late final GeneratedColumn<double> createdPrice = GeneratedColumn<double>(
    'created_price',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _makerFeeMeta = const VerificationMeta(
    'makerFee',
  );
  @override
  late final GeneratedColumn<double> makerFee = GeneratedColumn<double>(
    'maker_fee',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    keyFingerprint,
    robotIndex,
    version,
    network,
    coordinatorAlias,
    role,
    orderType,
    currencyId,
    amount,
    minAmount,
    maxAmount,
    premiumPercent,
    paymentMethod,
    bondSizePercent,
    publicSeconds,
    escrowSeconds,
    description,
    hasPassword,
    latitude,
    longitude,
    createdPrice,
    makerFee,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'maker_terms';
  @override
  VerificationContext validateIntegrity(
    Insertable<MakerTermsRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key_fingerprint')) {
      context.handle(
        _keyFingerprintMeta,
        keyFingerprint.isAcceptableOrUnknown(
          data['key_fingerprint']!,
          _keyFingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_keyFingerprintMeta);
    }
    if (data.containsKey('robot_index')) {
      context.handle(
        _robotIndexMeta,
        robotIndex.isAcceptableOrUnknown(data['robot_index']!, _robotIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_robotIndexMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('network')) {
      context.handle(
        _networkMeta,
        network.isAcceptableOrUnknown(data['network']!, _networkMeta),
      );
    } else if (isInserting) {
      context.missing(_networkMeta);
    }
    if (data.containsKey('coordinator_alias')) {
      context.handle(
        _coordinatorAliasMeta,
        coordinatorAlias.isAcceptableOrUnknown(
          data['coordinator_alias']!,
          _coordinatorAliasMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_coordinatorAliasMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('order_type')) {
      context.handle(
        _orderTypeMeta,
        orderType.isAcceptableOrUnknown(data['order_type']!, _orderTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_orderTypeMeta);
    }
    if (data.containsKey('currency_id')) {
      context.handle(
        _currencyIdMeta,
        currencyId.isAcceptableOrUnknown(data['currency_id']!, _currencyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyIdMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    }
    if (data.containsKey('min_amount')) {
      context.handle(
        _minAmountMeta,
        minAmount.isAcceptableOrUnknown(data['min_amount']!, _minAmountMeta),
      );
    }
    if (data.containsKey('max_amount')) {
      context.handle(
        _maxAmountMeta,
        maxAmount.isAcceptableOrUnknown(data['max_amount']!, _maxAmountMeta),
      );
    }
    if (data.containsKey('premium_percent')) {
      context.handle(
        _premiumPercentMeta,
        premiumPercent.isAcceptableOrUnknown(
          data['premium_percent']!,
          _premiumPercentMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_premiumPercentMeta);
    }
    if (data.containsKey('payment_method')) {
      context.handle(
        _paymentMethodMeta,
        paymentMethod.isAcceptableOrUnknown(
          data['payment_method']!,
          _paymentMethodMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_paymentMethodMeta);
    }
    if (data.containsKey('bond_size_percent')) {
      context.handle(
        _bondSizePercentMeta,
        bondSizePercent.isAcceptableOrUnknown(
          data['bond_size_percent']!,
          _bondSizePercentMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_bondSizePercentMeta);
    }
    if (data.containsKey('public_seconds')) {
      context.handle(
        _publicSecondsMeta,
        publicSeconds.isAcceptableOrUnknown(
          data['public_seconds']!,
          _publicSecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_publicSecondsMeta);
    }
    if (data.containsKey('escrow_seconds')) {
      context.handle(
        _escrowSecondsMeta,
        escrowSeconds.isAcceptableOrUnknown(
          data['escrow_seconds']!,
          _escrowSecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_escrowSecondsMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('has_password')) {
      context.handle(
        _hasPasswordMeta,
        hasPassword.isAcceptableOrUnknown(
          data['has_password']!,
          _hasPasswordMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_hasPasswordMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    }
    if (data.containsKey('created_price')) {
      context.handle(
        _createdPriceMeta,
        createdPrice.isAcceptableOrUnknown(
          data['created_price']!,
          _createdPriceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdPriceMeta);
    }
    if (data.containsKey('maker_fee')) {
      context.handle(
        _makerFeeMeta,
        makerFee.isAcceptableOrUnknown(data['maker_fee']!, _makerFeeMeta),
      );
    } else if (isInserting) {
      context.missing(_makerFeeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {keyFingerprint, robotIndex};
  @override
  MakerTermsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MakerTermsRow(
      keyFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key_fingerprint'],
      )!,
      robotIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}robot_index'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      network: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}network'],
      )!,
      coordinatorAlias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coordinator_alias'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      orderType: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_type'],
      )!,
      currencyId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}currency_id'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}amount'],
      ),
      minAmount: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}min_amount'],
      ),
      maxAmount: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}max_amount'],
      ),
      premiumPercent: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}premium_percent'],
      )!,
      paymentMethod: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_method'],
      )!,
      bondSizePercent: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bond_size_percent'],
      )!,
      publicSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}public_seconds'],
      )!,
      escrowSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}escrow_seconds'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      hasPassword: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_password'],
      )!,
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      ),
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      ),
      createdPrice: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}created_price'],
      )!,
      makerFee: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}maker_fee'],
      )!,
    );
  }

  @override
  $StoredMakerTermsTable createAlias(String alias) {
    return $StoredMakerTermsTable(attachedDatabase, alias);
  }
}

class MakerTermsRow extends DataClass implements Insertable<MakerTermsRow> {
  /// The trade's robot, as `trades` keys it.
  final String keyFingerprint;
  final int robotIndex;

  /// `MakerTermsRecord.version`.
  final int version;

  /// The make the terms belong to, which must be the pending make of the row of `trades` they are keyed by: `RobosatsNetwork.name`, the coordinator's short alias, `TradeRole.name`.
  final String network;
  final String coordinatorAlias;
  final String role;

  /// `OrderType.wire`: 0 buy, 1 sell.
  final int orderType;
  final int currencyId;

  /// The fixed amount, or the bounds of a range, in the order's currency: one or the other.
  final double? amount;
  final double? minAmount;
  final double? maxAmount;
  final double premiumPercent;

  /// The payment methods as sent, one text.
  final String paymentMethod;
  final double bondSizePercent;

  /// The public duration and the escrow duration asked, in seconds.
  final int publicSeconds;
  final int escrowSeconds;

  /// The description sent, or absent.
  final String? description;

  /// Whether the order was sent with a password: never the password nor its hash.
  final bool hasPassword;

  /// The meeting point sent, both coordinates or none.
  final double? latitude;
  final double? longitude;

  /// The coordinator's price of a bitcoin in the order's currency, read from `/api/limits/` just before the make.
  final double createdPrice;

  /// The maker fee of `/api/info/`, read just before the make.
  final double makerFee;
  const MakerTermsRow({
    required this.keyFingerprint,
    required this.robotIndex,
    required this.version,
    required this.network,
    required this.coordinatorAlias,
    required this.role,
    required this.orderType,
    required this.currencyId,
    this.amount,
    this.minAmount,
    this.maxAmount,
    required this.premiumPercent,
    required this.paymentMethod,
    required this.bondSizePercent,
    required this.publicSeconds,
    required this.escrowSeconds,
    this.description,
    required this.hasPassword,
    this.latitude,
    this.longitude,
    required this.createdPrice,
    required this.makerFee,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key_fingerprint'] = Variable<String>(keyFingerprint);
    map['robot_index'] = Variable<int>(robotIndex);
    map['version'] = Variable<int>(version);
    map['network'] = Variable<String>(network);
    map['coordinator_alias'] = Variable<String>(coordinatorAlias);
    map['role'] = Variable<String>(role);
    map['order_type'] = Variable<int>(orderType);
    map['currency_id'] = Variable<int>(currencyId);
    if (!nullToAbsent || amount != null) {
      map['amount'] = Variable<double>(amount);
    }
    if (!nullToAbsent || minAmount != null) {
      map['min_amount'] = Variable<double>(minAmount);
    }
    if (!nullToAbsent || maxAmount != null) {
      map['max_amount'] = Variable<double>(maxAmount);
    }
    map['premium_percent'] = Variable<double>(premiumPercent);
    map['payment_method'] = Variable<String>(paymentMethod);
    map['bond_size_percent'] = Variable<double>(bondSizePercent);
    map['public_seconds'] = Variable<int>(publicSeconds);
    map['escrow_seconds'] = Variable<int>(escrowSeconds);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['has_password'] = Variable<bool>(hasPassword);
    if (!nullToAbsent || latitude != null) {
      map['latitude'] = Variable<double>(latitude);
    }
    if (!nullToAbsent || longitude != null) {
      map['longitude'] = Variable<double>(longitude);
    }
    map['created_price'] = Variable<double>(createdPrice);
    map['maker_fee'] = Variable<double>(makerFee);
    return map;
  }

  StoredMakerTermsCompanion toCompanion(bool nullToAbsent) {
    return StoredMakerTermsCompanion(
      keyFingerprint: Value(keyFingerprint),
      robotIndex: Value(robotIndex),
      version: Value(version),
      network: Value(network),
      coordinatorAlias: Value(coordinatorAlias),
      role: Value(role),
      orderType: Value(orderType),
      currencyId: Value(currencyId),
      amount: amount == null && nullToAbsent
          ? const Value.absent()
          : Value(amount),
      minAmount: minAmount == null && nullToAbsent
          ? const Value.absent()
          : Value(minAmount),
      maxAmount: maxAmount == null && nullToAbsent
          ? const Value.absent()
          : Value(maxAmount),
      premiumPercent: Value(premiumPercent),
      paymentMethod: Value(paymentMethod),
      bondSizePercent: Value(bondSizePercent),
      publicSeconds: Value(publicSeconds),
      escrowSeconds: Value(escrowSeconds),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      hasPassword: Value(hasPassword),
      latitude: latitude == null && nullToAbsent
          ? const Value.absent()
          : Value(latitude),
      longitude: longitude == null && nullToAbsent
          ? const Value.absent()
          : Value(longitude),
      createdPrice: Value(createdPrice),
      makerFee: Value(makerFee),
    );
  }

  factory MakerTermsRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MakerTermsRow(
      keyFingerprint: serializer.fromJson<String>(json['keyFingerprint']),
      robotIndex: serializer.fromJson<int>(json['robotIndex']),
      version: serializer.fromJson<int>(json['version']),
      network: serializer.fromJson<String>(json['network']),
      coordinatorAlias: serializer.fromJson<String>(json['coordinatorAlias']),
      role: serializer.fromJson<String>(json['role']),
      orderType: serializer.fromJson<int>(json['orderType']),
      currencyId: serializer.fromJson<int>(json['currencyId']),
      amount: serializer.fromJson<double?>(json['amount']),
      minAmount: serializer.fromJson<double?>(json['minAmount']),
      maxAmount: serializer.fromJson<double?>(json['maxAmount']),
      premiumPercent: serializer.fromJson<double>(json['premiumPercent']),
      paymentMethod: serializer.fromJson<String>(json['paymentMethod']),
      bondSizePercent: serializer.fromJson<double>(json['bondSizePercent']),
      publicSeconds: serializer.fromJson<int>(json['publicSeconds']),
      escrowSeconds: serializer.fromJson<int>(json['escrowSeconds']),
      description: serializer.fromJson<String?>(json['description']),
      hasPassword: serializer.fromJson<bool>(json['hasPassword']),
      latitude: serializer.fromJson<double?>(json['latitude']),
      longitude: serializer.fromJson<double?>(json['longitude']),
      createdPrice: serializer.fromJson<double>(json['createdPrice']),
      makerFee: serializer.fromJson<double>(json['makerFee']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'keyFingerprint': serializer.toJson<String>(keyFingerprint),
      'robotIndex': serializer.toJson<int>(robotIndex),
      'version': serializer.toJson<int>(version),
      'network': serializer.toJson<String>(network),
      'coordinatorAlias': serializer.toJson<String>(coordinatorAlias),
      'role': serializer.toJson<String>(role),
      'orderType': serializer.toJson<int>(orderType),
      'currencyId': serializer.toJson<int>(currencyId),
      'amount': serializer.toJson<double?>(amount),
      'minAmount': serializer.toJson<double?>(minAmount),
      'maxAmount': serializer.toJson<double?>(maxAmount),
      'premiumPercent': serializer.toJson<double>(premiumPercent),
      'paymentMethod': serializer.toJson<String>(paymentMethod),
      'bondSizePercent': serializer.toJson<double>(bondSizePercent),
      'publicSeconds': serializer.toJson<int>(publicSeconds),
      'escrowSeconds': serializer.toJson<int>(escrowSeconds),
      'description': serializer.toJson<String?>(description),
      'hasPassword': serializer.toJson<bool>(hasPassword),
      'latitude': serializer.toJson<double?>(latitude),
      'longitude': serializer.toJson<double?>(longitude),
      'createdPrice': serializer.toJson<double>(createdPrice),
      'makerFee': serializer.toJson<double>(makerFee),
    };
  }

  MakerTermsRow copyWith({
    String? keyFingerprint,
    int? robotIndex,
    int? version,
    String? network,
    String? coordinatorAlias,
    String? role,
    int? orderType,
    int? currencyId,
    Value<double?> amount = const Value.absent(),
    Value<double?> minAmount = const Value.absent(),
    Value<double?> maxAmount = const Value.absent(),
    double? premiumPercent,
    String? paymentMethod,
    double? bondSizePercent,
    int? publicSeconds,
    int? escrowSeconds,
    Value<String?> description = const Value.absent(),
    bool? hasPassword,
    Value<double?> latitude = const Value.absent(),
    Value<double?> longitude = const Value.absent(),
    double? createdPrice,
    double? makerFee,
  }) => MakerTermsRow(
    keyFingerprint: keyFingerprint ?? this.keyFingerprint,
    robotIndex: robotIndex ?? this.robotIndex,
    version: version ?? this.version,
    network: network ?? this.network,
    coordinatorAlias: coordinatorAlias ?? this.coordinatorAlias,
    role: role ?? this.role,
    orderType: orderType ?? this.orderType,
    currencyId: currencyId ?? this.currencyId,
    amount: amount.present ? amount.value : this.amount,
    minAmount: minAmount.present ? minAmount.value : this.minAmount,
    maxAmount: maxAmount.present ? maxAmount.value : this.maxAmount,
    premiumPercent: premiumPercent ?? this.premiumPercent,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    bondSizePercent: bondSizePercent ?? this.bondSizePercent,
    publicSeconds: publicSeconds ?? this.publicSeconds,
    escrowSeconds: escrowSeconds ?? this.escrowSeconds,
    description: description.present ? description.value : this.description,
    hasPassword: hasPassword ?? this.hasPassword,
    latitude: latitude.present ? latitude.value : this.latitude,
    longitude: longitude.present ? longitude.value : this.longitude,
    createdPrice: createdPrice ?? this.createdPrice,
    makerFee: makerFee ?? this.makerFee,
  );
  MakerTermsRow copyWithCompanion(StoredMakerTermsCompanion data) {
    return MakerTermsRow(
      keyFingerprint: data.keyFingerprint.present
          ? data.keyFingerprint.value
          : this.keyFingerprint,
      robotIndex: data.robotIndex.present
          ? data.robotIndex.value
          : this.robotIndex,
      version: data.version.present ? data.version.value : this.version,
      network: data.network.present ? data.network.value : this.network,
      coordinatorAlias: data.coordinatorAlias.present
          ? data.coordinatorAlias.value
          : this.coordinatorAlias,
      role: data.role.present ? data.role.value : this.role,
      orderType: data.orderType.present ? data.orderType.value : this.orderType,
      currencyId: data.currencyId.present
          ? data.currencyId.value
          : this.currencyId,
      amount: data.amount.present ? data.amount.value : this.amount,
      minAmount: data.minAmount.present ? data.minAmount.value : this.minAmount,
      maxAmount: data.maxAmount.present ? data.maxAmount.value : this.maxAmount,
      premiumPercent: data.premiumPercent.present
          ? data.premiumPercent.value
          : this.premiumPercent,
      paymentMethod: data.paymentMethod.present
          ? data.paymentMethod.value
          : this.paymentMethod,
      bondSizePercent: data.bondSizePercent.present
          ? data.bondSizePercent.value
          : this.bondSizePercent,
      publicSeconds: data.publicSeconds.present
          ? data.publicSeconds.value
          : this.publicSeconds,
      escrowSeconds: data.escrowSeconds.present
          ? data.escrowSeconds.value
          : this.escrowSeconds,
      description: data.description.present
          ? data.description.value
          : this.description,
      hasPassword: data.hasPassword.present
          ? data.hasPassword.value
          : this.hasPassword,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      createdPrice: data.createdPrice.present
          ? data.createdPrice.value
          : this.createdPrice,
      makerFee: data.makerFee.present ? data.makerFee.value : this.makerFee,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MakerTermsRow(')
          ..write('keyFingerprint: $keyFingerprint, ')
          ..write('robotIndex: $robotIndex, ')
          ..write('version: $version, ')
          ..write('network: $network, ')
          ..write('coordinatorAlias: $coordinatorAlias, ')
          ..write('role: $role, ')
          ..write('orderType: $orderType, ')
          ..write('currencyId: $currencyId, ')
          ..write('amount: $amount, ')
          ..write('minAmount: $minAmount, ')
          ..write('maxAmount: $maxAmount, ')
          ..write('premiumPercent: $premiumPercent, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('bondSizePercent: $bondSizePercent, ')
          ..write('publicSeconds: $publicSeconds, ')
          ..write('escrowSeconds: $escrowSeconds, ')
          ..write('description: $description, ')
          ..write('hasPassword: $hasPassword, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('createdPrice: $createdPrice, ')
          ..write('makerFee: $makerFee')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    keyFingerprint,
    robotIndex,
    version,
    network,
    coordinatorAlias,
    role,
    orderType,
    currencyId,
    amount,
    minAmount,
    maxAmount,
    premiumPercent,
    paymentMethod,
    bondSizePercent,
    publicSeconds,
    escrowSeconds,
    description,
    hasPassword,
    latitude,
    longitude,
    createdPrice,
    makerFee,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MakerTermsRow &&
          other.keyFingerprint == this.keyFingerprint &&
          other.robotIndex == this.robotIndex &&
          other.version == this.version &&
          other.network == this.network &&
          other.coordinatorAlias == this.coordinatorAlias &&
          other.role == this.role &&
          other.orderType == this.orderType &&
          other.currencyId == this.currencyId &&
          other.amount == this.amount &&
          other.minAmount == this.minAmount &&
          other.maxAmount == this.maxAmount &&
          other.premiumPercent == this.premiumPercent &&
          other.paymentMethod == this.paymentMethod &&
          other.bondSizePercent == this.bondSizePercent &&
          other.publicSeconds == this.publicSeconds &&
          other.escrowSeconds == this.escrowSeconds &&
          other.description == this.description &&
          other.hasPassword == this.hasPassword &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.createdPrice == this.createdPrice &&
          other.makerFee == this.makerFee);
}

class StoredMakerTermsCompanion extends UpdateCompanion<MakerTermsRow> {
  final Value<String> keyFingerprint;
  final Value<int> robotIndex;
  final Value<int> version;
  final Value<String> network;
  final Value<String> coordinatorAlias;
  final Value<String> role;
  final Value<int> orderType;
  final Value<int> currencyId;
  final Value<double?> amount;
  final Value<double?> minAmount;
  final Value<double?> maxAmount;
  final Value<double> premiumPercent;
  final Value<String> paymentMethod;
  final Value<double> bondSizePercent;
  final Value<int> publicSeconds;
  final Value<int> escrowSeconds;
  final Value<String?> description;
  final Value<bool> hasPassword;
  final Value<double?> latitude;
  final Value<double?> longitude;
  final Value<double> createdPrice;
  final Value<double> makerFee;
  final Value<int> rowid;
  const StoredMakerTermsCompanion({
    this.keyFingerprint = const Value.absent(),
    this.robotIndex = const Value.absent(),
    this.version = const Value.absent(),
    this.network = const Value.absent(),
    this.coordinatorAlias = const Value.absent(),
    this.role = const Value.absent(),
    this.orderType = const Value.absent(),
    this.currencyId = const Value.absent(),
    this.amount = const Value.absent(),
    this.minAmount = const Value.absent(),
    this.maxAmount = const Value.absent(),
    this.premiumPercent = const Value.absent(),
    this.paymentMethod = const Value.absent(),
    this.bondSizePercent = const Value.absent(),
    this.publicSeconds = const Value.absent(),
    this.escrowSeconds = const Value.absent(),
    this.description = const Value.absent(),
    this.hasPassword = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.createdPrice = const Value.absent(),
    this.makerFee = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredMakerTermsCompanion.insert({
    required String keyFingerprint,
    required int robotIndex,
    required int version,
    required String network,
    required String coordinatorAlias,
    required String role,
    required int orderType,
    required int currencyId,
    this.amount = const Value.absent(),
    this.minAmount = const Value.absent(),
    this.maxAmount = const Value.absent(),
    required double premiumPercent,
    required String paymentMethod,
    required double bondSizePercent,
    required int publicSeconds,
    required int escrowSeconds,
    this.description = const Value.absent(),
    required bool hasPassword,
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    required double createdPrice,
    required double makerFee,
    this.rowid = const Value.absent(),
  }) : keyFingerprint = Value(keyFingerprint),
       robotIndex = Value(robotIndex),
       version = Value(version),
       network = Value(network),
       coordinatorAlias = Value(coordinatorAlias),
       role = Value(role),
       orderType = Value(orderType),
       currencyId = Value(currencyId),
       premiumPercent = Value(premiumPercent),
       paymentMethod = Value(paymentMethod),
       bondSizePercent = Value(bondSizePercent),
       publicSeconds = Value(publicSeconds),
       escrowSeconds = Value(escrowSeconds),
       hasPassword = Value(hasPassword),
       createdPrice = Value(createdPrice),
       makerFee = Value(makerFee);
  static Insertable<MakerTermsRow> custom({
    Expression<String>? keyFingerprint,
    Expression<int>? robotIndex,
    Expression<int>? version,
    Expression<String>? network,
    Expression<String>? coordinatorAlias,
    Expression<String>? role,
    Expression<int>? orderType,
    Expression<int>? currencyId,
    Expression<double>? amount,
    Expression<double>? minAmount,
    Expression<double>? maxAmount,
    Expression<double>? premiumPercent,
    Expression<String>? paymentMethod,
    Expression<double>? bondSizePercent,
    Expression<int>? publicSeconds,
    Expression<int>? escrowSeconds,
    Expression<String>? description,
    Expression<bool>? hasPassword,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? createdPrice,
    Expression<double>? makerFee,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (keyFingerprint != null) 'key_fingerprint': keyFingerprint,
      if (robotIndex != null) 'robot_index': robotIndex,
      if (version != null) 'version': version,
      if (network != null) 'network': network,
      if (coordinatorAlias != null) 'coordinator_alias': coordinatorAlias,
      if (role != null) 'role': role,
      if (orderType != null) 'order_type': orderType,
      if (currencyId != null) 'currency_id': currencyId,
      if (amount != null) 'amount': amount,
      if (minAmount != null) 'min_amount': minAmount,
      if (maxAmount != null) 'max_amount': maxAmount,
      if (premiumPercent != null) 'premium_percent': premiumPercent,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (bondSizePercent != null) 'bond_size_percent': bondSizePercent,
      if (publicSeconds != null) 'public_seconds': publicSeconds,
      if (escrowSeconds != null) 'escrow_seconds': escrowSeconds,
      if (description != null) 'description': description,
      if (hasPassword != null) 'has_password': hasPassword,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (createdPrice != null) 'created_price': createdPrice,
      if (makerFee != null) 'maker_fee': makerFee,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredMakerTermsCompanion copyWith({
    Value<String>? keyFingerprint,
    Value<int>? robotIndex,
    Value<int>? version,
    Value<String>? network,
    Value<String>? coordinatorAlias,
    Value<String>? role,
    Value<int>? orderType,
    Value<int>? currencyId,
    Value<double?>? amount,
    Value<double?>? minAmount,
    Value<double?>? maxAmount,
    Value<double>? premiumPercent,
    Value<String>? paymentMethod,
    Value<double>? bondSizePercent,
    Value<int>? publicSeconds,
    Value<int>? escrowSeconds,
    Value<String?>? description,
    Value<bool>? hasPassword,
    Value<double?>? latitude,
    Value<double?>? longitude,
    Value<double>? createdPrice,
    Value<double>? makerFee,
    Value<int>? rowid,
  }) {
    return StoredMakerTermsCompanion(
      keyFingerprint: keyFingerprint ?? this.keyFingerprint,
      robotIndex: robotIndex ?? this.robotIndex,
      version: version ?? this.version,
      network: network ?? this.network,
      coordinatorAlias: coordinatorAlias ?? this.coordinatorAlias,
      role: role ?? this.role,
      orderType: orderType ?? this.orderType,
      currencyId: currencyId ?? this.currencyId,
      amount: amount ?? this.amount,
      minAmount: minAmount ?? this.minAmount,
      maxAmount: maxAmount ?? this.maxAmount,
      premiumPercent: premiumPercent ?? this.premiumPercent,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      bondSizePercent: bondSizePercent ?? this.bondSizePercent,
      publicSeconds: publicSeconds ?? this.publicSeconds,
      escrowSeconds: escrowSeconds ?? this.escrowSeconds,
      description: description ?? this.description,
      hasPassword: hasPassword ?? this.hasPassword,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      createdPrice: createdPrice ?? this.createdPrice,
      makerFee: makerFee ?? this.makerFee,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (keyFingerprint.present) {
      map['key_fingerprint'] = Variable<String>(keyFingerprint.value);
    }
    if (robotIndex.present) {
      map['robot_index'] = Variable<int>(robotIndex.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (network.present) {
      map['network'] = Variable<String>(network.value);
    }
    if (coordinatorAlias.present) {
      map['coordinator_alias'] = Variable<String>(coordinatorAlias.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (orderType.present) {
      map['order_type'] = Variable<int>(orderType.value);
    }
    if (currencyId.present) {
      map['currency_id'] = Variable<int>(currencyId.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (minAmount.present) {
      map['min_amount'] = Variable<double>(minAmount.value);
    }
    if (maxAmount.present) {
      map['max_amount'] = Variable<double>(maxAmount.value);
    }
    if (premiumPercent.present) {
      map['premium_percent'] = Variable<double>(premiumPercent.value);
    }
    if (paymentMethod.present) {
      map['payment_method'] = Variable<String>(paymentMethod.value);
    }
    if (bondSizePercent.present) {
      map['bond_size_percent'] = Variable<double>(bondSizePercent.value);
    }
    if (publicSeconds.present) {
      map['public_seconds'] = Variable<int>(publicSeconds.value);
    }
    if (escrowSeconds.present) {
      map['escrow_seconds'] = Variable<int>(escrowSeconds.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (hasPassword.present) {
      map['has_password'] = Variable<bool>(hasPassword.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (createdPrice.present) {
      map['created_price'] = Variable<double>(createdPrice.value);
    }
    if (makerFee.present) {
      map['maker_fee'] = Variable<double>(makerFee.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredMakerTermsCompanion(')
          ..write('keyFingerprint: $keyFingerprint, ')
          ..write('robotIndex: $robotIndex, ')
          ..write('version: $version, ')
          ..write('network: $network, ')
          ..write('coordinatorAlias: $coordinatorAlias, ')
          ..write('role: $role, ')
          ..write('orderType: $orderType, ')
          ..write('currencyId: $currencyId, ')
          ..write('amount: $amount, ')
          ..write('minAmount: $minAmount, ')
          ..write('maxAmount: $maxAmount, ')
          ..write('premiumPercent: $premiumPercent, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('bondSizePercent: $bondSizePercent, ')
          ..write('publicSeconds: $publicSeconds, ')
          ..write('escrowSeconds: $escrowSeconds, ')
          ..write('description: $description, ')
          ..write('hasPassword: $hasPassword, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('createdPrice: $createdPrice, ')
          ..write('makerFee: $makerFee, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$P2pDatabase extends GeneratedDatabase {
  _$P2pDatabase(QueryExecutor e) : super(e);
  $P2pDatabaseManager get managers => $P2pDatabaseManager(this);
  late final $RobotBindingsTable robotBindings = $RobotBindingsTable(this);
  late final $TradesTable trades = $TradesTable(this);
  late final $StoredTradePayoutsTable storedTradePayouts =
      $StoredTradePayoutsTable(this);
  late final Trigger tradePayoutsNeverDeleted = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_payouts_never_deleted BEFORE DELETE ON trade_payouts BEGIN SELECT RAISE (ABORT, \'the payout of a contract is kept\');END',
    'trade_payouts_never_deleted',
  );
  late final $StoredTradeTrailsTable storedTradeTrails =
      $StoredTradeTrailsTable(this);
  late final Trigger tradePayoutsForward = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_payouts_forward BEFORE UPDATE ON trade_payouts WHEN NEW.key_fingerprint IS NOT OLD.key_fingerprint OR NEW.robot_index IS NOT OLD.robot_index OR NEW.take IS NOT OLD.take OR NEW.source IS \'unrecorded\' OR(OLD.submitted_at IS NOT NULL AND(NEW.submitted_at IS NULL OR NEW.submitted_at < OLD.submitted_at))OR NOT EXISTS (SELECT 1 FROM trades JOIN trade_trails ON trade_trails.key_fingerprint = trades.key_fingerprint AND trade_trails.robot_index = trades.robot_index WHERE trades.key_fingerprint = NEW.key_fingerprint AND trades.robot_index = NEW.robot_index AND trades.closed_at IS NULL AND trades.role = \'buyer\' AND trade_trails.take = NEW.take) BEGIN SELECT RAISE (ABORT, \'a payout only moves forward\');END',
    'trade_payouts_forward',
  );
  late final Trigger tradePayoutsOfTheirTrade = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_payouts_of_their_trade BEFORE INSERT ON trade_payouts WHEN(NEW.source IS NOT \'thisWallet\' AND NEW.source IS NOT \'pasted\')OR NOT EXISTS (SELECT 1 FROM trades JOIN trade_trails ON trade_trails.key_fingerprint = trades.key_fingerprint AND trade_trails.robot_index = trades.robot_index WHERE trades.key_fingerprint = NEW.key_fingerprint AND trades.robot_index = NEW.robot_index AND trades.closed_at IS NULL AND trades.role = \'buyer\' AND trade_trails.take = NEW.take) BEGIN SELECT RAISE (ABORT, \'a payout of no open trade\');END',
    'trade_payouts_of_their_trade',
  );
  late final Trigger tradePayoutsInsertedOnce = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_payouts_inserted_once BEFORE INSERT ON trade_payouts WHEN EXISTS (SELECT 1 FROM trade_payouts WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index AND take = NEW.take) BEGIN SELECT RAISE (IGNORE);END',
    'trade_payouts_inserted_once',
  );
  late final $GarageKeyHistoriesTable garageKeyHistories =
      $GarageKeyHistoriesTable(this);
  late final $StoredTradeTermsTable storedTradeTerms = $StoredTradeTermsTable(
    this,
  );
  late final $StoredTradePaymentsTable storedTradePayments =
      $StoredTradePaymentsTable(this);
  late final $StoredTradeChatPinsTable storedTradeChatPins =
      $StoredTradeChatPinsTable(this);
  late final $StoredTradeChatNostrPinsTable storedTradeChatNostrPins =
      $StoredTradeChatNostrPinsTable(this);
  late final $StoredMakerTermsTable storedMakerTerms = $StoredMakerTermsTable(
    this,
  );
  late final Trigger makerTermsNeverDeleted = Trigger(
    'CREATE TRIGGER IF NOT EXISTS maker_terms_never_deleted BEFORE DELETE ON maker_terms BEGIN SELECT RAISE (ABORT, \'the terms of a make are kept\');END',
    'maker_terms_never_deleted',
  );
  late final Trigger makerTermsSetOnce = Trigger(
    'CREATE TRIGGER IF NOT EXISTS maker_terms_set_once BEFORE UPDATE ON maker_terms BEGIN SELECT RAISE (ABORT, \'the terms of a make are set once\');END',
    'maker_terms_set_once',
  );
  late final Trigger makerTermsInsertedOnce = Trigger(
    'CREATE TRIGGER IF NOT EXISTS maker_terms_inserted_once BEFORE INSERT ON maker_terms WHEN EXISTS (SELECT 1 FROM maker_terms WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index) BEGIN SELECT RAISE (IGNORE);END',
    'maker_terms_inserted_once',
  );
  late final Trigger makerTermsOfTheirMake = Trigger(
    'CREATE TRIGGER IF NOT EXISTS maker_terms_of_their_make BEFORE INSERT ON maker_terms WHEN NOT EXISTS (SELECT 1 FROM trades WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index AND network = NEW.network AND coordinator_alias = NEW.coordinator_alias AND role = NEW.role AND origin = \'madeHere\' AND order_id IS NULL AND closed_at IS NULL) BEGIN SELECT RAISE (ABORT, \'terms of no pending make\');END',
    'maker_terms_of_their_make',
  );
  late final Trigger tradeChatPinsNeverDeleted = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_chat_pins_never_deleted BEFORE DELETE ON trade_chat_pins BEGIN SELECT RAISE (ABORT, \'the pinned key of a trade is kept\');END',
    'trade_chat_pins_never_deleted',
  );
  late final Trigger tradeChatPinsNeverChanged = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_chat_pins_never_changed BEFORE UPDATE ON trade_chat_pins BEGIN SELECT RAISE (ABORT, \'the pinned key of a trade never changes\');END',
    'trade_chat_pins_never_changed',
  );
  late final Trigger tradeChatPinsInsertedOnce = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_chat_pins_inserted_once BEFORE INSERT ON trade_chat_pins WHEN EXISTS (SELECT 1 FROM trade_chat_pins WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index) BEGIN SELECT RAISE (IGNORE);END',
    'trade_chat_pins_inserted_once',
  );
  late final Trigger tradeChatPinsOfTheirTrade = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_chat_pins_of_their_trade BEFORE INSERT ON trade_chat_pins WHEN NOT EXISTS (SELECT 1 FROM trades WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index AND closed_at IS NULL) BEGIN SELECT RAISE (ABORT, \'a pin of no open trade\');END',
    'trade_chat_pins_of_their_trade',
  );
  late final Trigger tradeChatNostrPinsNeverDeleted = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_chat_nostr_pins_never_deleted BEFORE DELETE ON trade_chat_nostr_pins BEGIN SELECT RAISE (ABORT, \'the Nostr keys of a trade are kept\');END',
    'trade_chat_nostr_pins_never_deleted',
  );
  late final Trigger tradeChatNostrPinsNeverChanged = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_chat_nostr_pins_never_changed BEFORE UPDATE ON trade_chat_nostr_pins BEGIN SELECT RAISE (ABORT, \'the Nostr keys of a trade never change\');END',
    'trade_chat_nostr_pins_never_changed',
  );
  late final Trigger tradeChatNostrPinsInsertedOnce = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_chat_nostr_pins_inserted_once BEFORE INSERT ON trade_chat_nostr_pins WHEN EXISTS (SELECT 1 FROM trade_chat_nostr_pins WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index) BEGIN SELECT RAISE (IGNORE);END',
    'trade_chat_nostr_pins_inserted_once',
  );
  late final Trigger tradeChatNostrPinsOfTheirTrade = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_chat_nostr_pins_of_their_trade BEFORE INSERT ON trade_chat_nostr_pins WHEN NOT EXISTS (SELECT 1 FROM trades WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index AND closed_at IS NULL) BEGIN SELECT RAISE (ABORT, \'a Nostr pin of no open trade\');END',
    'trade_chat_nostr_pins_of_their_trade',
  );
  late final Trigger tradePaymentsNeverDeleted = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_payments_never_deleted BEFORE DELETE ON trade_payments BEGIN SELECT RAISE (ABORT, \'the payment of a trade is kept\');END',
    'trade_payments_never_deleted',
  );
  late final Trigger tradePaymentsInsertedOnce = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_payments_inserted_once BEFORE INSERT ON trade_payments WHEN EXISTS (SELECT 1 FROM trade_payments WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index AND step = NEW.step AND take = NEW.take) BEGIN SELECT RAISE (IGNORE);END',
    'trade_payments_inserted_once',
  );
  late final Trigger tradePaymentsOfTheirTrade = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_payments_of_their_trade BEFORE INSERT ON trade_payments WHEN NOT EXISTS (SELECT 1 FROM trades JOIN trade_trails ON trade_trails.key_fingerprint = trades.key_fingerprint AND trade_trails.robot_index = trades.robot_index WHERE trades.key_fingerprint = NEW.key_fingerprint AND trades.robot_index = NEW.robot_index AND trades.closed_at IS NULL AND trade_trails.take = NEW.take AND(NEW.take = 0 OR trades.origin = \'madeHere\')) BEGIN SELECT RAISE (ABORT, \'a payment of no open trade\');END',
    'trade_payments_of_their_trade',
  );
  late final Trigger tradePaymentsForward = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_payments_forward BEFORE UPDATE ON trade_payments WHEN NEW.key_fingerprint IS NOT OLD.key_fingerprint OR NEW.robot_index IS NOT OLD.robot_index OR NEW.step IS NOT OLD.step OR NEW.payment_hash IS NOT OLD.payment_hash OR NEW.started_at < OLD.started_at OR NEW.take IS NOT OLD.take BEGIN SELECT RAISE (ABORT, \'a payment only moves forward\');END',
    'trade_payments_forward',
  );
  late final Trigger tradePaymentsHashOnce = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_payments_hash_once BEFORE INSERT ON trade_payments WHEN EXISTS (SELECT 1 FROM trade_payments WHERE payment_hash = NEW.payment_hash AND NOT(key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index AND step = NEW.step AND take = NEW.take)) BEGIN SELECT RAISE (ABORT, \'an invoice is paid once\');END',
    'trade_payments_hash_once',
  );
  late final Trigger tradePaymentsSatsKnown = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_payments_sats_known BEFORE INSERT ON trade_payments WHEN NEW.confirmed_sats IS NULL BEGIN SELECT RAISE (ABORT, \'a payment is recorded with its amount\');END',
    'trade_payments_sats_known',
  );
  late final Trigger tradePaymentsSatsForward = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_payments_sats_forward BEFORE UPDATE ON trade_payments WHEN(OLD.confirmed_sats IS NULL AND NEW.confirmed_sats IS NOT NULL)OR(OLD.confirmed_sats IS NOT NULL AND(NEW.confirmed_sats IS NULL OR NEW.confirmed_sats < OLD.confirmed_sats))BEGIN SELECT RAISE (ABORT, \'the amount of a payment never goes down\');END',
    'trade_payments_sats_forward',
  );
  late final Trigger tradesOneOpenPerOrder = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trades_one_open_per_order BEFORE INSERT ON trades WHEN EXISTS (SELECT 1 FROM trades WHERE network = NEW.network AND coordinator_alias = NEW.coordinator_alias AND order_id = NEW.order_id AND closed_at IS NULL) BEGIN SELECT RAISE (ABORT, \'an order has one open trade\');END',
    'trades_one_open_per_order',
  );
  late final Trigger tradesOneOpenPerOrderUpdate = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trades_one_open_per_order_update BEFORE UPDATE OF order_id ON trades WHEN EXISTS (SELECT 1 FROM trades WHERE network = NEW.network AND coordinator_alias = NEW.coordinator_alias AND order_id = NEW.order_id AND closed_at IS NULL AND NOT(key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index)) BEGIN SELECT RAISE (ABORT, \'an order has one open trade\');END',
    'trades_one_open_per_order_update',
  );
  late final Trigger tradeTermsNeverDeleted = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_terms_never_deleted BEFORE DELETE ON trade_terms BEGIN SELECT RAISE (ABORT, \'the terms of a trade are kept\');END',
    'trade_terms_never_deleted',
  );
  late final Trigger tradeTermsSetOnce = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_terms_set_once BEFORE UPDATE ON trade_terms BEGIN SELECT RAISE (ABORT, \'the terms of a trade are set once\');END',
    'trade_terms_set_once',
  );
  late final Trigger tradeTermsInsertedOnce = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_terms_inserted_once BEFORE INSERT ON trade_terms WHEN EXISTS (SELECT 1 FROM trade_terms WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index) BEGIN SELECT RAISE (IGNORE);END',
    'trade_terms_inserted_once',
  );
  late final Trigger tradeTermsOfTheirTrade = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_terms_of_their_trade BEFORE INSERT ON trade_terms WHEN NOT EXISTS (SELECT 1 FROM trades WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index AND network = NEW.network AND coordinator_alias = NEW.coordinator_alias AND order_id = NEW.order_id AND role = NEW.role AND origin IN (\'takenHere\', \'recovered\') AND closed_at IS NULL) BEGIN SELECT RAISE (ABORT, \'terms of no open trade\');END',
    'trade_terms_of_their_trade',
  );
  late final Trigger tradeTrailsNeverDeleted = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_trails_never_deleted BEFORE DELETE ON trade_trails BEGIN SELECT RAISE (ABORT, \'the trail of a trade is kept\');END',
    'trade_trails_never_deleted',
  );
  late final Trigger tradeTrailsInsertedOnce = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_trails_inserted_once BEFORE INSERT ON trade_trails WHEN EXISTS (SELECT 1 FROM trade_trails WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index) BEGIN SELECT RAISE (IGNORE);END',
    'trade_trails_inserted_once',
  );
  late final Trigger tradeTrailsOfTheirTrade = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_trails_of_their_trade BEFORE INSERT ON trade_trails WHEN NOT EXISTS (SELECT 1 FROM trades WHERE trades.key_fingerprint = NEW.key_fingerprint AND trades.robot_index = NEW.robot_index AND trades.network = NEW.network AND trades.coordinator_alias = NEW.coordinator_alias AND trades.order_id = NEW.order_id AND trades.role = NEW.role AND trades.closed_at IS NULL AND NEW.take = 0 AND((trades.origin IN (\'takenHere\', \'recovered\') AND NEW.take_deadline IS NULL AND NEW.taker_hash_id IS NULL AND NEW.taken_amount IS NULL AND EXISTS (SELECT 1 FROM trade_terms WHERE trade_terms.key_fingerprint = trades.key_fingerprint AND trade_terms.robot_index = trades.robot_index))OR(trades.origin = \'madeHere\' AND EXISTS (SELECT 1 FROM maker_terms WHERE maker_terms.key_fingerprint = trades.key_fingerprint AND maker_terms.robot_index = trades.robot_index)))) BEGIN SELECT RAISE (ABORT, \'a trail of no open trade\');END',
    'trade_trails_of_their_trade',
  );
  late final Trigger tradeTrailsClosed = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_trails_closed BEFORE UPDATE ON trade_trails WHEN EXISTS (SELECT 1 FROM trades WHERE key_fingerprint = OLD.key_fingerprint AND robot_index = OLD.robot_index AND closed_at IS NOT NULL) BEGIN SELECT RAISE (IGNORE);END',
    'trade_trails_closed',
  );
  late final Trigger tradeTrailsForward = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_trails_forward BEFORE UPDATE ON trade_trails WHEN NEW.key_fingerprint IS NOT OLD.key_fingerprint OR NEW.robot_index IS NOT OLD.robot_index OR NEW.network IS NOT OLD.network OR NEW.coordinator_alias IS NOT OLD.coordinator_alias OR NEW.order_id IS NOT OLD.order_id OR NEW.role IS NOT OLD.role OR NEW.version < OLD.version OR NEW.read_at < OLD.read_at OR NEW.breached < OLD.breached OR NEW.history_unknown IS NOT OLD.history_unknown OR(OLD.bond_hash IS NOT NULL AND NEW.bond_hash IS NOT OLD.bond_hash)OR(OLD.escrow_hash IS NOT NULL AND NEW.escrow_hash IS NOT OLD.escrow_hash AND NEW.take IS OLD.take)OR(OLD.escrow_hash IS NOT NULL AND NEW.escrow_hash IS OLD.escrow_hash AND NEW.take IS NOT OLD.take)OR(OLD.bond_step_seen_at IS NOT NULL AND(NEW.bond_step_seen_at IS NULL OR NEW.bond_step_seen_at < OLD.bond_step_seen_at))OR(OLD.bond_step_deadline IS NOT NULL AND NEW.bond_step_deadline IS NULL)OR(OLD.position IN (\'succeeded\', \'makerLostDispute\', \'takerLostDispute\', \'expired\', \'cancelled\', \'publicAgain\', \'notAvailable\') AND NEW.position IS NOT OLD.position)OR(NEW.take IS NOT OLD.take AND NOT(NEW.take IS OLD.take + 1 AND OLD.position IN (\'public\', \'paused\', \'waitingForBoth\', \'waitingForEscrow\', \'waitingForPayout\') AND NOT(OLD.position = \'waitingForPayout\' AND OLD.role = \'buyer\')AND OLD.take_deadline IS NOT NULL AND((NEW.position IN (\'waitingForBoth\', \'waitingForEscrow\', \'waitingForPayout\') AND NEW.take_deadline IS NOT NULL AND NEW.take_deadline > OLD.take_deadline AND NEW.seen_late = 0)OR(NEW.position IN (\'chatting\', \'fiatSent\', \'inDispute\', \'sendingSats\', \'succeeded\', \'routingFailed\', \'waitingDisputeResolution\', \'makerLostDispute\', \'takerLostDispute\') AND NEW.take_deadline IS OLD.take_deadline AND NEW.taker_hash_id IS NOT NULL AND NEW.escrow_hash IS NULL AND(OLD.position IN (\'public\', \'paused\') OR NEW.taker_hash_id IS NOT OLD.taker_hash_id)AND NEW.seen_late = 1))AND NEW.earlier_escrows IS(OLD.earlier_escrows || coalesce(OLD.escrow_hash || \';\', \'\'))AND EXISTS (SELECT 1 FROM trades WHERE key_fingerprint = OLD.key_fingerprint AND robot_index = OLD.robot_index AND origin = \'madeHere\')))OR(NEW.take IS OLD.take AND(NEW.earlier_escrows IS NOT OLD.earlier_escrows OR NEW.seen_late IS NOT OLD.seen_late))OR(NEW.escrow_hash IS NOT NULL AND instr(\';\' || NEW.earlier_escrows, \';\' || NEW.escrow_hash || \';\') > 0)OR(OLD.take_deadline IS NOT NULL AND NEW.take_deadline IS NULL)OR(OLD.taker_hash_id IS NOT NULL AND NEW.taker_hash_id IS NULL)OR(OLD.taken_amount IS NOT NULL AND NEW.taken_amount IS NULL)OR(NEW.take IS OLD.take AND OLD.take_deadline IS NOT NULL AND NEW.take_deadline IS NOT OLD.take_deadline)OR(NEW.take IS OLD.take AND OLD.taker_hash_id IS NOT NULL AND NEW.taker_hash_id IS NOT OLD.taker_hash_id)OR(NEW.take IS OLD.take AND OLD.taken_amount IS NOT NULL AND NEW.taken_amount IS NOT OLD.taken_amount)OR(NEW.take IS NOT OLD.take AND OLD.taker_hash_id IS NULL AND NEW.taker_hash_id IS NOT NULL)OR(NEW.take IS NOT OLD.take AND OLD.taken_amount IS NULL AND NEW.taken_amount IS NOT NULL)OR((NEW.take_deadline IS NOT NULL OR NEW.taker_hash_id IS NOT NULL OR NEW.taken_amount IS NOT NULL)AND NOT EXISTS (SELECT 1 FROM trades WHERE key_fingerprint = OLD.key_fingerprint AND robot_index = OLD.robot_index AND origin = \'madeHere\'))BEGIN SELECT RAISE (ABORT, \'a trail only moves forward\');END',
    'trade_trails_forward',
  );
  late final Trigger tradeTrailsTermsTrace = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trade_trails_terms_trace BEFORE UPDATE ON trade_trails WHEN(OLD.terms_changed_at IS NOT NULL AND NEW.terms_changed_at IS NOT OLD.terms_changed_at)OR(OLD.terms_changed_at IS NULL AND NEW.terms_changed_at IS NOT NULL AND NEW.terms_changed_at IS NOT NEW.read_at)OR(OLD.terms_changed_premium_low IS NOT NULL AND(NEW.terms_changed_premium_low IS NULL))OR(OLD.terms_changed_premium_high IS NOT NULL AND(NEW.terms_changed_premium_high IS NULL OR NEW.terms_changed_premium_high < OLD.terms_changed_premium_high))BEGIN SELECT RAISE (ABORT, \'the trace of terms shown otherwise is kept\');END',
    'trade_trails_terms_trace',
  );
  late final Index robotBindingsNetwork = Index(
    'robot_bindings_network',
    'CREATE UNIQUE INDEX IF NOT EXISTS robot_bindings_network ON robot_bindings (key_fingerprint, robot_index, network)',
  );
  late final Trigger tradesNeverDeleted = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trades_never_deleted BEFORE DELETE ON trades BEGIN SELECT RAISE (ABORT, \'a trade record is kept\');END',
    'trades_never_deleted',
  );
  late final Trigger tradesSetOnce = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trades_set_once BEFORE UPDATE ON trades WHEN OLD.closed_at IS NOT NULL OR(OLD.confirmed_at IS NOT NULL AND NEW.confirmed_at IS NOT OLD.confirmed_at)OR NEW.network IS NOT OLD.network OR NEW.key_fingerprint IS NOT OLD.key_fingerprint OR NEW.robot_index IS NOT OLD.robot_index OR NEW.coordinator_alias IS NOT OLD.coordinator_alias OR NEW.coordinator_onion IS NOT OLD.coordinator_onion OR(NEW.order_id IS NOT OLD.order_id AND NOT(OLD.origin IS \'madeHere\' AND OLD.order_id IS NULL AND OLD.confirmed_at IS NULL AND NEW.confirmed_at IS NOT NULL AND EXISTS (SELECT 1 FROM maker_terms WHERE key_fingerprint = OLD.key_fingerprint AND robot_index = OLD.robot_index)))OR NEW.role IS NOT OLD.role OR NEW.origin IS NOT OLD.origin OR NEW.taken_at IS NOT OLD.taken_at BEGIN SELECT RAISE (ABORT, \'a trade record only gains its times\');END',
    'trades_set_once',
  );
  late final Trigger tradesMadePending = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trades_made_pending BEFORE INSERT ON trades WHEN NEW.origin IS \'madeHere\' AND(NEW.order_id IS NOT NULL OR NEW.closed_at IS NOT NULL)BEGIN SELECT RAISE (ABORT, \'a make is recorded pending\');END',
    'trades_made_pending',
  );
  late final Trigger tradesInsertedOnce = Trigger(
    'CREATE TRIGGER IF NOT EXISTS trades_inserted_once BEFORE INSERT ON trades WHEN EXISTS (SELECT 1 FROM trades WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index) BEGIN SELECT RAISE (IGNORE);END',
    'trades_inserted_once',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    robotBindings,
    trades,
    storedTradePayouts,
    tradePayoutsNeverDeleted,
    storedTradeTrails,
    tradePayoutsForward,
    tradePayoutsOfTheirTrade,
    tradePayoutsInsertedOnce,
    garageKeyHistories,
    storedTradeTerms,
    storedTradePayments,
    storedTradeChatPins,
    storedTradeChatNostrPins,
    storedMakerTerms,
    makerTermsNeverDeleted,
    makerTermsSetOnce,
    makerTermsInsertedOnce,
    makerTermsOfTheirMake,
    tradeChatPinsNeverDeleted,
    tradeChatPinsNeverChanged,
    tradeChatPinsInsertedOnce,
    tradeChatPinsOfTheirTrade,
    tradeChatNostrPinsNeverDeleted,
    tradeChatNostrPinsNeverChanged,
    tradeChatNostrPinsInsertedOnce,
    tradeChatNostrPinsOfTheirTrade,
    tradePaymentsNeverDeleted,
    tradePaymentsInsertedOnce,
    tradePaymentsOfTheirTrade,
    tradePaymentsForward,
    tradePaymentsHashOnce,
    tradePaymentsSatsKnown,
    tradePaymentsSatsForward,
    tradesOneOpenPerOrder,
    tradesOneOpenPerOrderUpdate,
    tradeTermsNeverDeleted,
    tradeTermsSetOnce,
    tradeTermsInsertedOnce,
    tradeTermsOfTheirTrade,
    tradeTrailsNeverDeleted,
    tradeTrailsInsertedOnce,
    tradeTrailsOfTheirTrade,
    tradeTrailsClosed,
    tradeTrailsForward,
    tradeTrailsTermsTrace,
    robotBindingsNetwork,
    tradesNeverDeleted,
    tradesSetOnce,
    tradesMadePending,
    tradesInsertedOnce,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_payouts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_payouts',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_payouts',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_payouts',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'maker_terms',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'maker_terms',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'maker_terms',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'maker_terms',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_chat_pins',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_chat_pins',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_chat_pins',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_chat_pins',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_chat_nostr_pins',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_chat_nostr_pins',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_chat_nostr_pins',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_chat_nostr_pins',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_payments',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_payments',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_payments',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_payments',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_payments',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_payments',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_payments',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trades',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trades',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_terms',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_terms',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_terms',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_terms',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_trails',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_trails',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_trails',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_trails',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_trails',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trade_trails',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trades',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trades',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trades',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'trades',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
  ]);
}

typedef $$RobotBindingsTableCreateCompanionBuilder =
    RobotBindingsCompanion Function({
      required String network,
      required String keyFingerprint,
      required int robotIndex,
      required String coordinatorAlias,
      required String coordinatorOnion,
      required String coordinatorNodeKeys,
      required String coordinatorNostrKey,
      required int boundAt,
      Value<String> provenance,
      Value<int> rowid,
    });
typedef $$RobotBindingsTableUpdateCompanionBuilder =
    RobotBindingsCompanion Function({
      Value<String> network,
      Value<String> keyFingerprint,
      Value<int> robotIndex,
      Value<String> coordinatorAlias,
      Value<String> coordinatorOnion,
      Value<String> coordinatorNodeKeys,
      Value<String> coordinatorNostrKey,
      Value<int> boundAt,
      Value<String> provenance,
      Value<int> rowid,
    });

class $$RobotBindingsTableFilterComposer
    extends Composer<_$P2pDatabase, $RobotBindingsTable> {
  $$RobotBindingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get network => $composableBuilder(
    column: $table.network,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coordinatorAlias => $composableBuilder(
    column: $table.coordinatorAlias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coordinatorOnion => $composableBuilder(
    column: $table.coordinatorOnion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coordinatorNodeKeys => $composableBuilder(
    column: $table.coordinatorNodeKeys,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coordinatorNostrKey => $composableBuilder(
    column: $table.coordinatorNostrKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get boundAt => $composableBuilder(
    column: $table.boundAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provenance => $composableBuilder(
    column: $table.provenance,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RobotBindingsTableOrderingComposer
    extends Composer<_$P2pDatabase, $RobotBindingsTable> {
  $$RobotBindingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get network => $composableBuilder(
    column: $table.network,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coordinatorAlias => $composableBuilder(
    column: $table.coordinatorAlias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coordinatorOnion => $composableBuilder(
    column: $table.coordinatorOnion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coordinatorNodeKeys => $composableBuilder(
    column: $table.coordinatorNodeKeys,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coordinatorNostrKey => $composableBuilder(
    column: $table.coordinatorNostrKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get boundAt => $composableBuilder(
    column: $table.boundAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provenance => $composableBuilder(
    column: $table.provenance,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RobotBindingsTableAnnotationComposer
    extends Composer<_$P2pDatabase, $RobotBindingsTable> {
  $$RobotBindingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get network =>
      $composableBuilder(column: $table.network, builder: (column) => column);

  GeneratedColumn<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get coordinatorAlias => $composableBuilder(
    column: $table.coordinatorAlias,
    builder: (column) => column,
  );

  GeneratedColumn<String> get coordinatorOnion => $composableBuilder(
    column: $table.coordinatorOnion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get coordinatorNodeKeys => $composableBuilder(
    column: $table.coordinatorNodeKeys,
    builder: (column) => column,
  );

  GeneratedColumn<String> get coordinatorNostrKey => $composableBuilder(
    column: $table.coordinatorNostrKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get boundAt =>
      $composableBuilder(column: $table.boundAt, builder: (column) => column);

  GeneratedColumn<String> get provenance => $composableBuilder(
    column: $table.provenance,
    builder: (column) => column,
  );
}

class $$RobotBindingsTableTableManager
    extends
        RootTableManager<
          _$P2pDatabase,
          $RobotBindingsTable,
          RobotBindingRow,
          $$RobotBindingsTableFilterComposer,
          $$RobotBindingsTableOrderingComposer,
          $$RobotBindingsTableAnnotationComposer,
          $$RobotBindingsTableCreateCompanionBuilder,
          $$RobotBindingsTableUpdateCompanionBuilder,
          (
            RobotBindingRow,
            BaseReferences<_$P2pDatabase, $RobotBindingsTable, RobotBindingRow>,
          ),
          RobotBindingRow,
          PrefetchHooks Function()
        > {
  $$RobotBindingsTableTableManager(_$P2pDatabase db, $RobotBindingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RobotBindingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RobotBindingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RobotBindingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> network = const Value.absent(),
                Value<String> keyFingerprint = const Value.absent(),
                Value<int> robotIndex = const Value.absent(),
                Value<String> coordinatorAlias = const Value.absent(),
                Value<String> coordinatorOnion = const Value.absent(),
                Value<String> coordinatorNodeKeys = const Value.absent(),
                Value<String> coordinatorNostrKey = const Value.absent(),
                Value<int> boundAt = const Value.absent(),
                Value<String> provenance = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RobotBindingsCompanion(
                network: network,
                keyFingerprint: keyFingerprint,
                robotIndex: robotIndex,
                coordinatorAlias: coordinatorAlias,
                coordinatorOnion: coordinatorOnion,
                coordinatorNodeKeys: coordinatorNodeKeys,
                coordinatorNostrKey: coordinatorNostrKey,
                boundAt: boundAt,
                provenance: provenance,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String network,
                required String keyFingerprint,
                required int robotIndex,
                required String coordinatorAlias,
                required String coordinatorOnion,
                required String coordinatorNodeKeys,
                required String coordinatorNostrKey,
                required int boundAt,
                Value<String> provenance = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RobotBindingsCompanion.insert(
                network: network,
                keyFingerprint: keyFingerprint,
                robotIndex: robotIndex,
                coordinatorAlias: coordinatorAlias,
                coordinatorOnion: coordinatorOnion,
                coordinatorNodeKeys: coordinatorNodeKeys,
                coordinatorNostrKey: coordinatorNostrKey,
                boundAt: boundAt,
                provenance: provenance,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RobotBindingsTableProcessedTableManager =
    ProcessedTableManager<
      _$P2pDatabase,
      $RobotBindingsTable,
      RobotBindingRow,
      $$RobotBindingsTableFilterComposer,
      $$RobotBindingsTableOrderingComposer,
      $$RobotBindingsTableAnnotationComposer,
      $$RobotBindingsTableCreateCompanionBuilder,
      $$RobotBindingsTableUpdateCompanionBuilder,
      (
        RobotBindingRow,
        BaseReferences<_$P2pDatabase, $RobotBindingsTable, RobotBindingRow>,
      ),
      RobotBindingRow,
      PrefetchHooks Function()
    >;
typedef $$TradesTableCreateCompanionBuilder =
    TradesCompanion Function({
      required String network,
      required String keyFingerprint,
      required int robotIndex,
      required String coordinatorAlias,
      required String coordinatorOnion,
      Value<int?> orderId,
      required String role,
      required String origin,
      required int takenAt,
      Value<int?> confirmedAt,
      Value<int?> closedAt,
      Value<int> rowid,
    });
typedef $$TradesTableUpdateCompanionBuilder =
    TradesCompanion Function({
      Value<String> network,
      Value<String> keyFingerprint,
      Value<int> robotIndex,
      Value<String> coordinatorAlias,
      Value<String> coordinatorOnion,
      Value<int?> orderId,
      Value<String> role,
      Value<String> origin,
      Value<int> takenAt,
      Value<int?> confirmedAt,
      Value<int?> closedAt,
      Value<int> rowid,
    });

class $$TradesTableFilterComposer
    extends Composer<_$P2pDatabase, $TradesTable> {
  $$TradesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get network => $composableBuilder(
    column: $table.network,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coordinatorAlias => $composableBuilder(
    column: $table.coordinatorAlias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coordinatorOnion => $composableBuilder(
    column: $table.coordinatorOnion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderId => $composableBuilder(
    column: $table.orderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get takenAt => $composableBuilder(
    column: $table.takenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get confirmedAt => $composableBuilder(
    column: $table.confirmedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get closedAt => $composableBuilder(
    column: $table.closedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TradesTableOrderingComposer
    extends Composer<_$P2pDatabase, $TradesTable> {
  $$TradesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get network => $composableBuilder(
    column: $table.network,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coordinatorAlias => $composableBuilder(
    column: $table.coordinatorAlias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coordinatorOnion => $composableBuilder(
    column: $table.coordinatorOnion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderId => $composableBuilder(
    column: $table.orderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get takenAt => $composableBuilder(
    column: $table.takenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get confirmedAt => $composableBuilder(
    column: $table.confirmedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get closedAt => $composableBuilder(
    column: $table.closedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TradesTableAnnotationComposer
    extends Composer<_$P2pDatabase, $TradesTable> {
  $$TradesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get network =>
      $composableBuilder(column: $table.network, builder: (column) => column);

  GeneratedColumn<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get coordinatorAlias => $composableBuilder(
    column: $table.coordinatorAlias,
    builder: (column) => column,
  );

  GeneratedColumn<String> get coordinatorOnion => $composableBuilder(
    column: $table.coordinatorOnion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get orderId =>
      $composableBuilder(column: $table.orderId, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<int> get takenAt =>
      $composableBuilder(column: $table.takenAt, builder: (column) => column);

  GeneratedColumn<int> get confirmedAt => $composableBuilder(
    column: $table.confirmedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get closedAt =>
      $composableBuilder(column: $table.closedAt, builder: (column) => column);
}

class $$TradesTableTableManager
    extends
        RootTableManager<
          _$P2pDatabase,
          $TradesTable,
          TradeRow,
          $$TradesTableFilterComposer,
          $$TradesTableOrderingComposer,
          $$TradesTableAnnotationComposer,
          $$TradesTableCreateCompanionBuilder,
          $$TradesTableUpdateCompanionBuilder,
          (TradeRow, BaseReferences<_$P2pDatabase, $TradesTable, TradeRow>),
          TradeRow,
          PrefetchHooks Function()
        > {
  $$TradesTableTableManager(_$P2pDatabase db, $TradesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TradesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TradesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TradesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> network = const Value.absent(),
                Value<String> keyFingerprint = const Value.absent(),
                Value<int> robotIndex = const Value.absent(),
                Value<String> coordinatorAlias = const Value.absent(),
                Value<String> coordinatorOnion = const Value.absent(),
                Value<int?> orderId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<int> takenAt = const Value.absent(),
                Value<int?> confirmedAt = const Value.absent(),
                Value<int?> closedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TradesCompanion(
                network: network,
                keyFingerprint: keyFingerprint,
                robotIndex: robotIndex,
                coordinatorAlias: coordinatorAlias,
                coordinatorOnion: coordinatorOnion,
                orderId: orderId,
                role: role,
                origin: origin,
                takenAt: takenAt,
                confirmedAt: confirmedAt,
                closedAt: closedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String network,
                required String keyFingerprint,
                required int robotIndex,
                required String coordinatorAlias,
                required String coordinatorOnion,
                Value<int?> orderId = const Value.absent(),
                required String role,
                required String origin,
                required int takenAt,
                Value<int?> confirmedAt = const Value.absent(),
                Value<int?> closedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TradesCompanion.insert(
                network: network,
                keyFingerprint: keyFingerprint,
                robotIndex: robotIndex,
                coordinatorAlias: coordinatorAlias,
                coordinatorOnion: coordinatorOnion,
                orderId: orderId,
                role: role,
                origin: origin,
                takenAt: takenAt,
                confirmedAt: confirmedAt,
                closedAt: closedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TradesTableProcessedTableManager =
    ProcessedTableManager<
      _$P2pDatabase,
      $TradesTable,
      TradeRow,
      $$TradesTableFilterComposer,
      $$TradesTableOrderingComposer,
      $$TradesTableAnnotationComposer,
      $$TradesTableCreateCompanionBuilder,
      $$TradesTableUpdateCompanionBuilder,
      (TradeRow, BaseReferences<_$P2pDatabase, $TradesTable, TradeRow>),
      TradeRow,
      PrefetchHooks Function()
    >;
typedef $$StoredTradePayoutsTableCreateCompanionBuilder =
    StoredTradePayoutsCompanion Function({
      required String keyFingerprint,
      required int robotIndex,
      required int take,
      required String source,
      Value<String?> kind,
      Value<int?> submittedAt,
      Value<int> rowid,
    });
typedef $$StoredTradePayoutsTableUpdateCompanionBuilder =
    StoredTradePayoutsCompanion Function({
      Value<String> keyFingerprint,
      Value<int> robotIndex,
      Value<int> take,
      Value<String> source,
      Value<String?> kind,
      Value<int?> submittedAt,
      Value<int> rowid,
    });

class $$StoredTradePayoutsTableFilterComposer
    extends Composer<_$P2pDatabase, $StoredTradePayoutsTable> {
  $$StoredTradePayoutsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get take => $composableBuilder(
    column: $table.take,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get submittedAt => $composableBuilder(
    column: $table.submittedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StoredTradePayoutsTableOrderingComposer
    extends Composer<_$P2pDatabase, $StoredTradePayoutsTable> {
  $$StoredTradePayoutsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get take => $composableBuilder(
    column: $table.take,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get submittedAt => $composableBuilder(
    column: $table.submittedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StoredTradePayoutsTableAnnotationComposer
    extends Composer<_$P2pDatabase, $StoredTradePayoutsTable> {
  $$StoredTradePayoutsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get take =>
      $composableBuilder(column: $table.take, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get submittedAt => $composableBuilder(
    column: $table.submittedAt,
    builder: (column) => column,
  );
}

class $$StoredTradePayoutsTableTableManager
    extends
        RootTableManager<
          _$P2pDatabase,
          $StoredTradePayoutsTable,
          TradePayoutRow,
          $$StoredTradePayoutsTableFilterComposer,
          $$StoredTradePayoutsTableOrderingComposer,
          $$StoredTradePayoutsTableAnnotationComposer,
          $$StoredTradePayoutsTableCreateCompanionBuilder,
          $$StoredTradePayoutsTableUpdateCompanionBuilder,
          (
            TradePayoutRow,
            BaseReferences<
              _$P2pDatabase,
              $StoredTradePayoutsTable,
              TradePayoutRow
            >,
          ),
          TradePayoutRow,
          PrefetchHooks Function()
        > {
  $$StoredTradePayoutsTableTableManager(
    _$P2pDatabase db,
    $StoredTradePayoutsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredTradePayoutsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoredTradePayoutsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoredTradePayoutsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> keyFingerprint = const Value.absent(),
                Value<int> robotIndex = const Value.absent(),
                Value<int> take = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> kind = const Value.absent(),
                Value<int?> submittedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoredTradePayoutsCompanion(
                keyFingerprint: keyFingerprint,
                robotIndex: robotIndex,
                take: take,
                source: source,
                kind: kind,
                submittedAt: submittedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String keyFingerprint,
                required int robotIndex,
                required int take,
                required String source,
                Value<String?> kind = const Value.absent(),
                Value<int?> submittedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoredTradePayoutsCompanion.insert(
                keyFingerprint: keyFingerprint,
                robotIndex: robotIndex,
                take: take,
                source: source,
                kind: kind,
                submittedAt: submittedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StoredTradePayoutsTableProcessedTableManager =
    ProcessedTableManager<
      _$P2pDatabase,
      $StoredTradePayoutsTable,
      TradePayoutRow,
      $$StoredTradePayoutsTableFilterComposer,
      $$StoredTradePayoutsTableOrderingComposer,
      $$StoredTradePayoutsTableAnnotationComposer,
      $$StoredTradePayoutsTableCreateCompanionBuilder,
      $$StoredTradePayoutsTableUpdateCompanionBuilder,
      (
        TradePayoutRow,
        BaseReferences<_$P2pDatabase, $StoredTradePayoutsTable, TradePayoutRow>,
      ),
      TradePayoutRow,
      PrefetchHooks Function()
    >;
typedef $$StoredTradeTrailsTableCreateCompanionBuilder =
    StoredTradeTrailsCompanion Function({
      required String keyFingerprint,
      required int robotIndex,
      required int version,
      required String network,
      required String coordinatorAlias,
      required int orderId,
      required String role,
      required String position,
      required int readAt,
      Value<String?> bondHash,
      Value<String?> escrowHash,
      Value<int?> deadline,
      Value<int?> bondStepSeenAt,
      Value<int?> bondStepDeadline,
      required bool breached,
      required bool historyUnknown,
      Value<int> take,
      Value<int?> takeDeadline,
      Value<String?> takerHashId,
      Value<double?> takenAmount,
      Value<String> earlierEscrows,
      Value<bool> seenLate,
      Value<int?> termsChangedAt,
      Value<double?> termsChangedPremiumLow,
      Value<double?> termsChangedPremiumHigh,
      Value<int> rowid,
    });
typedef $$StoredTradeTrailsTableUpdateCompanionBuilder =
    StoredTradeTrailsCompanion Function({
      Value<String> keyFingerprint,
      Value<int> robotIndex,
      Value<int> version,
      Value<String> network,
      Value<String> coordinatorAlias,
      Value<int> orderId,
      Value<String> role,
      Value<String> position,
      Value<int> readAt,
      Value<String?> bondHash,
      Value<String?> escrowHash,
      Value<int?> deadline,
      Value<int?> bondStepSeenAt,
      Value<int?> bondStepDeadline,
      Value<bool> breached,
      Value<bool> historyUnknown,
      Value<int> take,
      Value<int?> takeDeadline,
      Value<String?> takerHashId,
      Value<double?> takenAmount,
      Value<String> earlierEscrows,
      Value<bool> seenLate,
      Value<int?> termsChangedAt,
      Value<double?> termsChangedPremiumLow,
      Value<double?> termsChangedPremiumHigh,
      Value<int> rowid,
    });

class $$StoredTradeTrailsTableFilterComposer
    extends Composer<_$P2pDatabase, $StoredTradeTrailsTable> {
  $$StoredTradeTrailsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get network => $composableBuilder(
    column: $table.network,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coordinatorAlias => $composableBuilder(
    column: $table.coordinatorAlias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderId => $composableBuilder(
    column: $table.orderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get readAt => $composableBuilder(
    column: $table.readAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bondHash => $composableBuilder(
    column: $table.bondHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get escrowHash => $composableBuilder(
    column: $table.escrowHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deadline => $composableBuilder(
    column: $table.deadline,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bondStepSeenAt => $composableBuilder(
    column: $table.bondStepSeenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bondStepDeadline => $composableBuilder(
    column: $table.bondStepDeadline,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get breached => $composableBuilder(
    column: $table.breached,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get historyUnknown => $composableBuilder(
    column: $table.historyUnknown,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get take => $composableBuilder(
    column: $table.take,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get takeDeadline => $composableBuilder(
    column: $table.takeDeadline,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get takerHashId => $composableBuilder(
    column: $table.takerHashId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get takenAmount => $composableBuilder(
    column: $table.takenAmount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get earlierEscrows => $composableBuilder(
    column: $table.earlierEscrows,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get seenLate => $composableBuilder(
    column: $table.seenLate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get termsChangedAt => $composableBuilder(
    column: $table.termsChangedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get termsChangedPremiumLow => $composableBuilder(
    column: $table.termsChangedPremiumLow,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get termsChangedPremiumHigh => $composableBuilder(
    column: $table.termsChangedPremiumHigh,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StoredTradeTrailsTableOrderingComposer
    extends Composer<_$P2pDatabase, $StoredTradeTrailsTable> {
  $$StoredTradeTrailsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get network => $composableBuilder(
    column: $table.network,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coordinatorAlias => $composableBuilder(
    column: $table.coordinatorAlias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderId => $composableBuilder(
    column: $table.orderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get readAt => $composableBuilder(
    column: $table.readAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bondHash => $composableBuilder(
    column: $table.bondHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get escrowHash => $composableBuilder(
    column: $table.escrowHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deadline => $composableBuilder(
    column: $table.deadline,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bondStepSeenAt => $composableBuilder(
    column: $table.bondStepSeenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bondStepDeadline => $composableBuilder(
    column: $table.bondStepDeadline,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get breached => $composableBuilder(
    column: $table.breached,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get historyUnknown => $composableBuilder(
    column: $table.historyUnknown,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get take => $composableBuilder(
    column: $table.take,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get takeDeadline => $composableBuilder(
    column: $table.takeDeadline,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get takerHashId => $composableBuilder(
    column: $table.takerHashId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get takenAmount => $composableBuilder(
    column: $table.takenAmount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get earlierEscrows => $composableBuilder(
    column: $table.earlierEscrows,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get seenLate => $composableBuilder(
    column: $table.seenLate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get termsChangedAt => $composableBuilder(
    column: $table.termsChangedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get termsChangedPremiumLow => $composableBuilder(
    column: $table.termsChangedPremiumLow,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get termsChangedPremiumHigh => $composableBuilder(
    column: $table.termsChangedPremiumHigh,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StoredTradeTrailsTableAnnotationComposer
    extends Composer<_$P2pDatabase, $StoredTradeTrailsTable> {
  $$StoredTradeTrailsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get network =>
      $composableBuilder(column: $table.network, builder: (column) => column);

  GeneratedColumn<String> get coordinatorAlias => $composableBuilder(
    column: $table.coordinatorAlias,
    builder: (column) => column,
  );

  GeneratedColumn<int> get orderId =>
      $composableBuilder(column: $table.orderId, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<int> get readAt =>
      $composableBuilder(column: $table.readAt, builder: (column) => column);

  GeneratedColumn<String> get bondHash =>
      $composableBuilder(column: $table.bondHash, builder: (column) => column);

  GeneratedColumn<String> get escrowHash => $composableBuilder(
    column: $table.escrowHash,
    builder: (column) => column,
  );

  GeneratedColumn<int> get deadline =>
      $composableBuilder(column: $table.deadline, builder: (column) => column);

  GeneratedColumn<int> get bondStepSeenAt => $composableBuilder(
    column: $table.bondStepSeenAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get bondStepDeadline => $composableBuilder(
    column: $table.bondStepDeadline,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get breached =>
      $composableBuilder(column: $table.breached, builder: (column) => column);

  GeneratedColumn<bool> get historyUnknown => $composableBuilder(
    column: $table.historyUnknown,
    builder: (column) => column,
  );

  GeneratedColumn<int> get take =>
      $composableBuilder(column: $table.take, builder: (column) => column);

  GeneratedColumn<int> get takeDeadline => $composableBuilder(
    column: $table.takeDeadline,
    builder: (column) => column,
  );

  GeneratedColumn<String> get takerHashId => $composableBuilder(
    column: $table.takerHashId,
    builder: (column) => column,
  );

  GeneratedColumn<double> get takenAmount => $composableBuilder(
    column: $table.takenAmount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get earlierEscrows => $composableBuilder(
    column: $table.earlierEscrows,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get seenLate =>
      $composableBuilder(column: $table.seenLate, builder: (column) => column);

  GeneratedColumn<int> get termsChangedAt => $composableBuilder(
    column: $table.termsChangedAt,
    builder: (column) => column,
  );

  GeneratedColumn<double> get termsChangedPremiumLow => $composableBuilder(
    column: $table.termsChangedPremiumLow,
    builder: (column) => column,
  );

  GeneratedColumn<double> get termsChangedPremiumHigh => $composableBuilder(
    column: $table.termsChangedPremiumHigh,
    builder: (column) => column,
  );
}

class $$StoredTradeTrailsTableTableManager
    extends
        RootTableManager<
          _$P2pDatabase,
          $StoredTradeTrailsTable,
          TradeTrailRow,
          $$StoredTradeTrailsTableFilterComposer,
          $$StoredTradeTrailsTableOrderingComposer,
          $$StoredTradeTrailsTableAnnotationComposer,
          $$StoredTradeTrailsTableCreateCompanionBuilder,
          $$StoredTradeTrailsTableUpdateCompanionBuilder,
          (
            TradeTrailRow,
            BaseReferences<
              _$P2pDatabase,
              $StoredTradeTrailsTable,
              TradeTrailRow
            >,
          ),
          TradeTrailRow,
          PrefetchHooks Function()
        > {
  $$StoredTradeTrailsTableTableManager(
    _$P2pDatabase db,
    $StoredTradeTrailsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredTradeTrailsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoredTradeTrailsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoredTradeTrailsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> keyFingerprint = const Value.absent(),
                Value<int> robotIndex = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String> network = const Value.absent(),
                Value<String> coordinatorAlias = const Value.absent(),
                Value<int> orderId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> position = const Value.absent(),
                Value<int> readAt = const Value.absent(),
                Value<String?> bondHash = const Value.absent(),
                Value<String?> escrowHash = const Value.absent(),
                Value<int?> deadline = const Value.absent(),
                Value<int?> bondStepSeenAt = const Value.absent(),
                Value<int?> bondStepDeadline = const Value.absent(),
                Value<bool> breached = const Value.absent(),
                Value<bool> historyUnknown = const Value.absent(),
                Value<int> take = const Value.absent(),
                Value<int?> takeDeadline = const Value.absent(),
                Value<String?> takerHashId = const Value.absent(),
                Value<double?> takenAmount = const Value.absent(),
                Value<String> earlierEscrows = const Value.absent(),
                Value<bool> seenLate = const Value.absent(),
                Value<int?> termsChangedAt = const Value.absent(),
                Value<double?> termsChangedPremiumLow = const Value.absent(),
                Value<double?> termsChangedPremiumHigh = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoredTradeTrailsCompanion(
                keyFingerprint: keyFingerprint,
                robotIndex: robotIndex,
                version: version,
                network: network,
                coordinatorAlias: coordinatorAlias,
                orderId: orderId,
                role: role,
                position: position,
                readAt: readAt,
                bondHash: bondHash,
                escrowHash: escrowHash,
                deadline: deadline,
                bondStepSeenAt: bondStepSeenAt,
                bondStepDeadline: bondStepDeadline,
                breached: breached,
                historyUnknown: historyUnknown,
                take: take,
                takeDeadline: takeDeadline,
                takerHashId: takerHashId,
                takenAmount: takenAmount,
                earlierEscrows: earlierEscrows,
                seenLate: seenLate,
                termsChangedAt: termsChangedAt,
                termsChangedPremiumLow: termsChangedPremiumLow,
                termsChangedPremiumHigh: termsChangedPremiumHigh,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String keyFingerprint,
                required int robotIndex,
                required int version,
                required String network,
                required String coordinatorAlias,
                required int orderId,
                required String role,
                required String position,
                required int readAt,
                Value<String?> bondHash = const Value.absent(),
                Value<String?> escrowHash = const Value.absent(),
                Value<int?> deadline = const Value.absent(),
                Value<int?> bondStepSeenAt = const Value.absent(),
                Value<int?> bondStepDeadline = const Value.absent(),
                required bool breached,
                required bool historyUnknown,
                Value<int> take = const Value.absent(),
                Value<int?> takeDeadline = const Value.absent(),
                Value<String?> takerHashId = const Value.absent(),
                Value<double?> takenAmount = const Value.absent(),
                Value<String> earlierEscrows = const Value.absent(),
                Value<bool> seenLate = const Value.absent(),
                Value<int?> termsChangedAt = const Value.absent(),
                Value<double?> termsChangedPremiumLow = const Value.absent(),
                Value<double?> termsChangedPremiumHigh = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoredTradeTrailsCompanion.insert(
                keyFingerprint: keyFingerprint,
                robotIndex: robotIndex,
                version: version,
                network: network,
                coordinatorAlias: coordinatorAlias,
                orderId: orderId,
                role: role,
                position: position,
                readAt: readAt,
                bondHash: bondHash,
                escrowHash: escrowHash,
                deadline: deadline,
                bondStepSeenAt: bondStepSeenAt,
                bondStepDeadline: bondStepDeadline,
                breached: breached,
                historyUnknown: historyUnknown,
                take: take,
                takeDeadline: takeDeadline,
                takerHashId: takerHashId,
                takenAmount: takenAmount,
                earlierEscrows: earlierEscrows,
                seenLate: seenLate,
                termsChangedAt: termsChangedAt,
                termsChangedPremiumLow: termsChangedPremiumLow,
                termsChangedPremiumHigh: termsChangedPremiumHigh,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StoredTradeTrailsTableProcessedTableManager =
    ProcessedTableManager<
      _$P2pDatabase,
      $StoredTradeTrailsTable,
      TradeTrailRow,
      $$StoredTradeTrailsTableFilterComposer,
      $$StoredTradeTrailsTableOrderingComposer,
      $$StoredTradeTrailsTableAnnotationComposer,
      $$StoredTradeTrailsTableCreateCompanionBuilder,
      $$StoredTradeTrailsTableUpdateCompanionBuilder,
      (
        TradeTrailRow,
        BaseReferences<_$P2pDatabase, $StoredTradeTrailsTable, TradeTrailRow>,
      ),
      TradeTrailRow,
      PrefetchHooks Function()
    >;
typedef $$GarageKeyHistoriesTableCreateCompanionBuilder =
    GarageKeyHistoriesCompanion Function({
      required String network,
      required String keyFingerprint,
      required String origin,
      required int recordedAt,
      Value<int> rowid,
    });
typedef $$GarageKeyHistoriesTableUpdateCompanionBuilder =
    GarageKeyHistoriesCompanion Function({
      Value<String> network,
      Value<String> keyFingerprint,
      Value<String> origin,
      Value<int> recordedAt,
      Value<int> rowid,
    });

class $$GarageKeyHistoriesTableFilterComposer
    extends Composer<_$P2pDatabase, $GarageKeyHistoriesTable> {
  $$GarageKeyHistoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get network => $composableBuilder(
    column: $table.network,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GarageKeyHistoriesTableOrderingComposer
    extends Composer<_$P2pDatabase, $GarageKeyHistoriesTable> {
  $$GarageKeyHistoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get network => $composableBuilder(
    column: $table.network,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GarageKeyHistoriesTableAnnotationComposer
    extends Composer<_$P2pDatabase, $GarageKeyHistoriesTable> {
  $$GarageKeyHistoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get network =>
      $composableBuilder(column: $table.network, builder: (column) => column);

  GeneratedColumn<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<int> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => column,
  );
}

class $$GarageKeyHistoriesTableTableManager
    extends
        RootTableManager<
          _$P2pDatabase,
          $GarageKeyHistoriesTable,
          GarageKeyHistoryRow,
          $$GarageKeyHistoriesTableFilterComposer,
          $$GarageKeyHistoriesTableOrderingComposer,
          $$GarageKeyHistoriesTableAnnotationComposer,
          $$GarageKeyHistoriesTableCreateCompanionBuilder,
          $$GarageKeyHistoriesTableUpdateCompanionBuilder,
          (
            GarageKeyHistoryRow,
            BaseReferences<
              _$P2pDatabase,
              $GarageKeyHistoriesTable,
              GarageKeyHistoryRow
            >,
          ),
          GarageKeyHistoryRow,
          PrefetchHooks Function()
        > {
  $$GarageKeyHistoriesTableTableManager(
    _$P2pDatabase db,
    $GarageKeyHistoriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GarageKeyHistoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GarageKeyHistoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GarageKeyHistoriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> network = const Value.absent(),
                Value<String> keyFingerprint = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<int> recordedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GarageKeyHistoriesCompanion(
                network: network,
                keyFingerprint: keyFingerprint,
                origin: origin,
                recordedAt: recordedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String network,
                required String keyFingerprint,
                required String origin,
                required int recordedAt,
                Value<int> rowid = const Value.absent(),
              }) => GarageKeyHistoriesCompanion.insert(
                network: network,
                keyFingerprint: keyFingerprint,
                origin: origin,
                recordedAt: recordedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GarageKeyHistoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$P2pDatabase,
      $GarageKeyHistoriesTable,
      GarageKeyHistoryRow,
      $$GarageKeyHistoriesTableFilterComposer,
      $$GarageKeyHistoriesTableOrderingComposer,
      $$GarageKeyHistoriesTableAnnotationComposer,
      $$GarageKeyHistoriesTableCreateCompanionBuilder,
      $$GarageKeyHistoriesTableUpdateCompanionBuilder,
      (
        GarageKeyHistoryRow,
        BaseReferences<
          _$P2pDatabase,
          $GarageKeyHistoriesTable,
          GarageKeyHistoryRow
        >,
      ),
      GarageKeyHistoryRow,
      PrefetchHooks Function()
    >;
typedef $$StoredTradeTermsTableCreateCompanionBuilder =
    StoredTradeTermsCompanion Function({
      required String keyFingerprint,
      required int robotIndex,
      required int version,
      required String network,
      required String coordinatorAlias,
      required int orderId,
      required String role,
      required int orderType,
      required int currencyId,
      required double amount,
      required bool isRange,
      required double premiumPercent,
      Value<int?> explicitSatoshis,
      required double bondSizePercent,
      required int escrowSeconds,
      required double bookPrice,
      required double takerFee,
      Value<int> rowid,
    });
typedef $$StoredTradeTermsTableUpdateCompanionBuilder =
    StoredTradeTermsCompanion Function({
      Value<String> keyFingerprint,
      Value<int> robotIndex,
      Value<int> version,
      Value<String> network,
      Value<String> coordinatorAlias,
      Value<int> orderId,
      Value<String> role,
      Value<int> orderType,
      Value<int> currencyId,
      Value<double> amount,
      Value<bool> isRange,
      Value<double> premiumPercent,
      Value<int?> explicitSatoshis,
      Value<double> bondSizePercent,
      Value<int> escrowSeconds,
      Value<double> bookPrice,
      Value<double> takerFee,
      Value<int> rowid,
    });

class $$StoredTradeTermsTableFilterComposer
    extends Composer<_$P2pDatabase, $StoredTradeTermsTable> {
  $$StoredTradeTermsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get network => $composableBuilder(
    column: $table.network,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coordinatorAlias => $composableBuilder(
    column: $table.coordinatorAlias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderId => $composableBuilder(
    column: $table.orderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderType => $composableBuilder(
    column: $table.orderType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get currencyId => $composableBuilder(
    column: $table.currencyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isRange => $composableBuilder(
    column: $table.isRange,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get premiumPercent => $composableBuilder(
    column: $table.premiumPercent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get explicitSatoshis => $composableBuilder(
    column: $table.explicitSatoshis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bondSizePercent => $composableBuilder(
    column: $table.bondSizePercent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get escrowSeconds => $composableBuilder(
    column: $table.escrowSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bookPrice => $composableBuilder(
    column: $table.bookPrice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get takerFee => $composableBuilder(
    column: $table.takerFee,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StoredTradeTermsTableOrderingComposer
    extends Composer<_$P2pDatabase, $StoredTradeTermsTable> {
  $$StoredTradeTermsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get network => $composableBuilder(
    column: $table.network,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coordinatorAlias => $composableBuilder(
    column: $table.coordinatorAlias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderId => $composableBuilder(
    column: $table.orderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderType => $composableBuilder(
    column: $table.orderType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get currencyId => $composableBuilder(
    column: $table.currencyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isRange => $composableBuilder(
    column: $table.isRange,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get premiumPercent => $composableBuilder(
    column: $table.premiumPercent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get explicitSatoshis => $composableBuilder(
    column: $table.explicitSatoshis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bondSizePercent => $composableBuilder(
    column: $table.bondSizePercent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get escrowSeconds => $composableBuilder(
    column: $table.escrowSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bookPrice => $composableBuilder(
    column: $table.bookPrice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get takerFee => $composableBuilder(
    column: $table.takerFee,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StoredTradeTermsTableAnnotationComposer
    extends Composer<_$P2pDatabase, $StoredTradeTermsTable> {
  $$StoredTradeTermsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get network =>
      $composableBuilder(column: $table.network, builder: (column) => column);

  GeneratedColumn<String> get coordinatorAlias => $composableBuilder(
    column: $table.coordinatorAlias,
    builder: (column) => column,
  );

  GeneratedColumn<int> get orderId =>
      $composableBuilder(column: $table.orderId, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<int> get orderType =>
      $composableBuilder(column: $table.orderType, builder: (column) => column);

  GeneratedColumn<int> get currencyId => $composableBuilder(
    column: $table.currencyId,
    builder: (column) => column,
  );

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<bool> get isRange =>
      $composableBuilder(column: $table.isRange, builder: (column) => column);

  GeneratedColumn<double> get premiumPercent => $composableBuilder(
    column: $table.premiumPercent,
    builder: (column) => column,
  );

  GeneratedColumn<int> get explicitSatoshis => $composableBuilder(
    column: $table.explicitSatoshis,
    builder: (column) => column,
  );

  GeneratedColumn<double> get bondSizePercent => $composableBuilder(
    column: $table.bondSizePercent,
    builder: (column) => column,
  );

  GeneratedColumn<int> get escrowSeconds => $composableBuilder(
    column: $table.escrowSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<double> get bookPrice =>
      $composableBuilder(column: $table.bookPrice, builder: (column) => column);

  GeneratedColumn<double> get takerFee =>
      $composableBuilder(column: $table.takerFee, builder: (column) => column);
}

class $$StoredTradeTermsTableTableManager
    extends
        RootTableManager<
          _$P2pDatabase,
          $StoredTradeTermsTable,
          TradeTermsRow,
          $$StoredTradeTermsTableFilterComposer,
          $$StoredTradeTermsTableOrderingComposer,
          $$StoredTradeTermsTableAnnotationComposer,
          $$StoredTradeTermsTableCreateCompanionBuilder,
          $$StoredTradeTermsTableUpdateCompanionBuilder,
          (
            TradeTermsRow,
            BaseReferences<
              _$P2pDatabase,
              $StoredTradeTermsTable,
              TradeTermsRow
            >,
          ),
          TradeTermsRow,
          PrefetchHooks Function()
        > {
  $$StoredTradeTermsTableTableManager(
    _$P2pDatabase db,
    $StoredTradeTermsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredTradeTermsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoredTradeTermsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoredTradeTermsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> keyFingerprint = const Value.absent(),
                Value<int> robotIndex = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String> network = const Value.absent(),
                Value<String> coordinatorAlias = const Value.absent(),
                Value<int> orderId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<int> orderType = const Value.absent(),
                Value<int> currencyId = const Value.absent(),
                Value<double> amount = const Value.absent(),
                Value<bool> isRange = const Value.absent(),
                Value<double> premiumPercent = const Value.absent(),
                Value<int?> explicitSatoshis = const Value.absent(),
                Value<double> bondSizePercent = const Value.absent(),
                Value<int> escrowSeconds = const Value.absent(),
                Value<double> bookPrice = const Value.absent(),
                Value<double> takerFee = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoredTradeTermsCompanion(
                keyFingerprint: keyFingerprint,
                robotIndex: robotIndex,
                version: version,
                network: network,
                coordinatorAlias: coordinatorAlias,
                orderId: orderId,
                role: role,
                orderType: orderType,
                currencyId: currencyId,
                amount: amount,
                isRange: isRange,
                premiumPercent: premiumPercent,
                explicitSatoshis: explicitSatoshis,
                bondSizePercent: bondSizePercent,
                escrowSeconds: escrowSeconds,
                bookPrice: bookPrice,
                takerFee: takerFee,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String keyFingerprint,
                required int robotIndex,
                required int version,
                required String network,
                required String coordinatorAlias,
                required int orderId,
                required String role,
                required int orderType,
                required int currencyId,
                required double amount,
                required bool isRange,
                required double premiumPercent,
                Value<int?> explicitSatoshis = const Value.absent(),
                required double bondSizePercent,
                required int escrowSeconds,
                required double bookPrice,
                required double takerFee,
                Value<int> rowid = const Value.absent(),
              }) => StoredTradeTermsCompanion.insert(
                keyFingerprint: keyFingerprint,
                robotIndex: robotIndex,
                version: version,
                network: network,
                coordinatorAlias: coordinatorAlias,
                orderId: orderId,
                role: role,
                orderType: orderType,
                currencyId: currencyId,
                amount: amount,
                isRange: isRange,
                premiumPercent: premiumPercent,
                explicitSatoshis: explicitSatoshis,
                bondSizePercent: bondSizePercent,
                escrowSeconds: escrowSeconds,
                bookPrice: bookPrice,
                takerFee: takerFee,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StoredTradeTermsTableProcessedTableManager =
    ProcessedTableManager<
      _$P2pDatabase,
      $StoredTradeTermsTable,
      TradeTermsRow,
      $$StoredTradeTermsTableFilterComposer,
      $$StoredTradeTermsTableOrderingComposer,
      $$StoredTradeTermsTableAnnotationComposer,
      $$StoredTradeTermsTableCreateCompanionBuilder,
      $$StoredTradeTermsTableUpdateCompanionBuilder,
      (
        TradeTermsRow,
        BaseReferences<_$P2pDatabase, $StoredTradeTermsTable, TradeTermsRow>,
      ),
      TradeTermsRow,
      PrefetchHooks Function()
    >;
typedef $$StoredTradePaymentsTableCreateCompanionBuilder =
    StoredTradePaymentsCompanion Function({
      required String keyFingerprint,
      required int robotIndex,
      required String step,
      required String paymentHash,
      required int startedAt,
      Value<String?> walletPaymentId,
      Value<int> take,
      Value<int?> confirmedSats,
      Value<int> rowid,
    });
typedef $$StoredTradePaymentsTableUpdateCompanionBuilder =
    StoredTradePaymentsCompanion Function({
      Value<String> keyFingerprint,
      Value<int> robotIndex,
      Value<String> step,
      Value<String> paymentHash,
      Value<int> startedAt,
      Value<String?> walletPaymentId,
      Value<int> take,
      Value<int?> confirmedSats,
      Value<int> rowid,
    });

class $$StoredTradePaymentsTableFilterComposer
    extends Composer<_$P2pDatabase, $StoredTradePaymentsTable> {
  $$StoredTradePaymentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get step => $composableBuilder(
    column: $table.step,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paymentHash => $composableBuilder(
    column: $table.paymentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get walletPaymentId => $composableBuilder(
    column: $table.walletPaymentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get take => $composableBuilder(
    column: $table.take,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get confirmedSats => $composableBuilder(
    column: $table.confirmedSats,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StoredTradePaymentsTableOrderingComposer
    extends Composer<_$P2pDatabase, $StoredTradePaymentsTable> {
  $$StoredTradePaymentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get step => $composableBuilder(
    column: $table.step,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentHash => $composableBuilder(
    column: $table.paymentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get walletPaymentId => $composableBuilder(
    column: $table.walletPaymentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get take => $composableBuilder(
    column: $table.take,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get confirmedSats => $composableBuilder(
    column: $table.confirmedSats,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StoredTradePaymentsTableAnnotationComposer
    extends Composer<_$P2pDatabase, $StoredTradePaymentsTable> {
  $$StoredTradePaymentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get step =>
      $composableBuilder(column: $table.step, builder: (column) => column);

  GeneratedColumn<String> get paymentHash => $composableBuilder(
    column: $table.paymentHash,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<String> get walletPaymentId => $composableBuilder(
    column: $table.walletPaymentId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get take =>
      $composableBuilder(column: $table.take, builder: (column) => column);

  GeneratedColumn<int> get confirmedSats => $composableBuilder(
    column: $table.confirmedSats,
    builder: (column) => column,
  );
}

class $$StoredTradePaymentsTableTableManager
    extends
        RootTableManager<
          _$P2pDatabase,
          $StoredTradePaymentsTable,
          TradePaymentRow,
          $$StoredTradePaymentsTableFilterComposer,
          $$StoredTradePaymentsTableOrderingComposer,
          $$StoredTradePaymentsTableAnnotationComposer,
          $$StoredTradePaymentsTableCreateCompanionBuilder,
          $$StoredTradePaymentsTableUpdateCompanionBuilder,
          (
            TradePaymentRow,
            BaseReferences<
              _$P2pDatabase,
              $StoredTradePaymentsTable,
              TradePaymentRow
            >,
          ),
          TradePaymentRow,
          PrefetchHooks Function()
        > {
  $$StoredTradePaymentsTableTableManager(
    _$P2pDatabase db,
    $StoredTradePaymentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredTradePaymentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoredTradePaymentsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$StoredTradePaymentsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> keyFingerprint = const Value.absent(),
                Value<int> robotIndex = const Value.absent(),
                Value<String> step = const Value.absent(),
                Value<String> paymentHash = const Value.absent(),
                Value<int> startedAt = const Value.absent(),
                Value<String?> walletPaymentId = const Value.absent(),
                Value<int> take = const Value.absent(),
                Value<int?> confirmedSats = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoredTradePaymentsCompanion(
                keyFingerprint: keyFingerprint,
                robotIndex: robotIndex,
                step: step,
                paymentHash: paymentHash,
                startedAt: startedAt,
                walletPaymentId: walletPaymentId,
                take: take,
                confirmedSats: confirmedSats,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String keyFingerprint,
                required int robotIndex,
                required String step,
                required String paymentHash,
                required int startedAt,
                Value<String?> walletPaymentId = const Value.absent(),
                Value<int> take = const Value.absent(),
                Value<int?> confirmedSats = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoredTradePaymentsCompanion.insert(
                keyFingerprint: keyFingerprint,
                robotIndex: robotIndex,
                step: step,
                paymentHash: paymentHash,
                startedAt: startedAt,
                walletPaymentId: walletPaymentId,
                take: take,
                confirmedSats: confirmedSats,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StoredTradePaymentsTableProcessedTableManager =
    ProcessedTableManager<
      _$P2pDatabase,
      $StoredTradePaymentsTable,
      TradePaymentRow,
      $$StoredTradePaymentsTableFilterComposer,
      $$StoredTradePaymentsTableOrderingComposer,
      $$StoredTradePaymentsTableAnnotationComposer,
      $$StoredTradePaymentsTableCreateCompanionBuilder,
      $$StoredTradePaymentsTableUpdateCompanionBuilder,
      (
        TradePaymentRow,
        BaseReferences<
          _$P2pDatabase,
          $StoredTradePaymentsTable,
          TradePaymentRow
        >,
      ),
      TradePaymentRow,
      PrefetchHooks Function()
    >;
typedef $$StoredTradeChatPinsTableCreateCompanionBuilder =
    StoredTradeChatPinsCompanion Function({
      required String keyFingerprint,
      required int robotIndex,
      required String primaryFingerprint,
      required String subkeyFingerprint,
      required String armoredKey,
      Value<int> rowid,
    });
typedef $$StoredTradeChatPinsTableUpdateCompanionBuilder =
    StoredTradeChatPinsCompanion Function({
      Value<String> keyFingerprint,
      Value<int> robotIndex,
      Value<String> primaryFingerprint,
      Value<String> subkeyFingerprint,
      Value<String> armoredKey,
      Value<int> rowid,
    });

class $$StoredTradeChatPinsTableFilterComposer
    extends Composer<_$P2pDatabase, $StoredTradeChatPinsTable> {
  $$StoredTradeChatPinsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get primaryFingerprint => $composableBuilder(
    column: $table.primaryFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subkeyFingerprint => $composableBuilder(
    column: $table.subkeyFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get armoredKey => $composableBuilder(
    column: $table.armoredKey,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StoredTradeChatPinsTableOrderingComposer
    extends Composer<_$P2pDatabase, $StoredTradeChatPinsTable> {
  $$StoredTradeChatPinsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get primaryFingerprint => $composableBuilder(
    column: $table.primaryFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subkeyFingerprint => $composableBuilder(
    column: $table.subkeyFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get armoredKey => $composableBuilder(
    column: $table.armoredKey,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StoredTradeChatPinsTableAnnotationComposer
    extends Composer<_$P2pDatabase, $StoredTradeChatPinsTable> {
  $$StoredTradeChatPinsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get primaryFingerprint => $composableBuilder(
    column: $table.primaryFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get subkeyFingerprint => $composableBuilder(
    column: $table.subkeyFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get armoredKey => $composableBuilder(
    column: $table.armoredKey,
    builder: (column) => column,
  );
}

class $$StoredTradeChatPinsTableTableManager
    extends
        RootTableManager<
          _$P2pDatabase,
          $StoredTradeChatPinsTable,
          TradeChatPinRow,
          $$StoredTradeChatPinsTableFilterComposer,
          $$StoredTradeChatPinsTableOrderingComposer,
          $$StoredTradeChatPinsTableAnnotationComposer,
          $$StoredTradeChatPinsTableCreateCompanionBuilder,
          $$StoredTradeChatPinsTableUpdateCompanionBuilder,
          (
            TradeChatPinRow,
            BaseReferences<
              _$P2pDatabase,
              $StoredTradeChatPinsTable,
              TradeChatPinRow
            >,
          ),
          TradeChatPinRow,
          PrefetchHooks Function()
        > {
  $$StoredTradeChatPinsTableTableManager(
    _$P2pDatabase db,
    $StoredTradeChatPinsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredTradeChatPinsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoredTradeChatPinsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$StoredTradeChatPinsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> keyFingerprint = const Value.absent(),
                Value<int> robotIndex = const Value.absent(),
                Value<String> primaryFingerprint = const Value.absent(),
                Value<String> subkeyFingerprint = const Value.absent(),
                Value<String> armoredKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoredTradeChatPinsCompanion(
                keyFingerprint: keyFingerprint,
                robotIndex: robotIndex,
                primaryFingerprint: primaryFingerprint,
                subkeyFingerprint: subkeyFingerprint,
                armoredKey: armoredKey,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String keyFingerprint,
                required int robotIndex,
                required String primaryFingerprint,
                required String subkeyFingerprint,
                required String armoredKey,
                Value<int> rowid = const Value.absent(),
              }) => StoredTradeChatPinsCompanion.insert(
                keyFingerprint: keyFingerprint,
                robotIndex: robotIndex,
                primaryFingerprint: primaryFingerprint,
                subkeyFingerprint: subkeyFingerprint,
                armoredKey: armoredKey,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StoredTradeChatPinsTableProcessedTableManager =
    ProcessedTableManager<
      _$P2pDatabase,
      $StoredTradeChatPinsTable,
      TradeChatPinRow,
      $$StoredTradeChatPinsTableFilterComposer,
      $$StoredTradeChatPinsTableOrderingComposer,
      $$StoredTradeChatPinsTableAnnotationComposer,
      $$StoredTradeChatPinsTableCreateCompanionBuilder,
      $$StoredTradeChatPinsTableUpdateCompanionBuilder,
      (
        TradeChatPinRow,
        BaseReferences<
          _$P2pDatabase,
          $StoredTradeChatPinsTable,
          TradeChatPinRow
        >,
      ),
      TradeChatPinRow,
      PrefetchHooks Function()
    >;
typedef $$StoredTradeChatNostrPinsTableCreateCompanionBuilder =
    StoredTradeChatNostrPinsCompanion Function({
      required String keyFingerprint,
      required int robotIndex,
      required String peerKey,
      required String ownKey,
      Value<int> rowid,
    });
typedef $$StoredTradeChatNostrPinsTableUpdateCompanionBuilder =
    StoredTradeChatNostrPinsCompanion Function({
      Value<String> keyFingerprint,
      Value<int> robotIndex,
      Value<String> peerKey,
      Value<String> ownKey,
      Value<int> rowid,
    });

class $$StoredTradeChatNostrPinsTableFilterComposer
    extends Composer<_$P2pDatabase, $StoredTradeChatNostrPinsTable> {
  $$StoredTradeChatNostrPinsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerKey => $composableBuilder(
    column: $table.peerKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownKey => $composableBuilder(
    column: $table.ownKey,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StoredTradeChatNostrPinsTableOrderingComposer
    extends Composer<_$P2pDatabase, $StoredTradeChatNostrPinsTable> {
  $$StoredTradeChatNostrPinsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerKey => $composableBuilder(
    column: $table.peerKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownKey => $composableBuilder(
    column: $table.ownKey,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StoredTradeChatNostrPinsTableAnnotationComposer
    extends Composer<_$P2pDatabase, $StoredTradeChatNostrPinsTable> {
  $$StoredTradeChatNostrPinsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get peerKey =>
      $composableBuilder(column: $table.peerKey, builder: (column) => column);

  GeneratedColumn<String> get ownKey =>
      $composableBuilder(column: $table.ownKey, builder: (column) => column);
}

class $$StoredTradeChatNostrPinsTableTableManager
    extends
        RootTableManager<
          _$P2pDatabase,
          $StoredTradeChatNostrPinsTable,
          TradeChatNostrPinRow,
          $$StoredTradeChatNostrPinsTableFilterComposer,
          $$StoredTradeChatNostrPinsTableOrderingComposer,
          $$StoredTradeChatNostrPinsTableAnnotationComposer,
          $$StoredTradeChatNostrPinsTableCreateCompanionBuilder,
          $$StoredTradeChatNostrPinsTableUpdateCompanionBuilder,
          (
            TradeChatNostrPinRow,
            BaseReferences<
              _$P2pDatabase,
              $StoredTradeChatNostrPinsTable,
              TradeChatNostrPinRow
            >,
          ),
          TradeChatNostrPinRow,
          PrefetchHooks Function()
        > {
  $$StoredTradeChatNostrPinsTableTableManager(
    _$P2pDatabase db,
    $StoredTradeChatNostrPinsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredTradeChatNostrPinsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$StoredTradeChatNostrPinsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$StoredTradeChatNostrPinsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> keyFingerprint = const Value.absent(),
                Value<int> robotIndex = const Value.absent(),
                Value<String> peerKey = const Value.absent(),
                Value<String> ownKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoredTradeChatNostrPinsCompanion(
                keyFingerprint: keyFingerprint,
                robotIndex: robotIndex,
                peerKey: peerKey,
                ownKey: ownKey,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String keyFingerprint,
                required int robotIndex,
                required String peerKey,
                required String ownKey,
                Value<int> rowid = const Value.absent(),
              }) => StoredTradeChatNostrPinsCompanion.insert(
                keyFingerprint: keyFingerprint,
                robotIndex: robotIndex,
                peerKey: peerKey,
                ownKey: ownKey,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StoredTradeChatNostrPinsTableProcessedTableManager =
    ProcessedTableManager<
      _$P2pDatabase,
      $StoredTradeChatNostrPinsTable,
      TradeChatNostrPinRow,
      $$StoredTradeChatNostrPinsTableFilterComposer,
      $$StoredTradeChatNostrPinsTableOrderingComposer,
      $$StoredTradeChatNostrPinsTableAnnotationComposer,
      $$StoredTradeChatNostrPinsTableCreateCompanionBuilder,
      $$StoredTradeChatNostrPinsTableUpdateCompanionBuilder,
      (
        TradeChatNostrPinRow,
        BaseReferences<
          _$P2pDatabase,
          $StoredTradeChatNostrPinsTable,
          TradeChatNostrPinRow
        >,
      ),
      TradeChatNostrPinRow,
      PrefetchHooks Function()
    >;
typedef $$StoredMakerTermsTableCreateCompanionBuilder =
    StoredMakerTermsCompanion Function({
      required String keyFingerprint,
      required int robotIndex,
      required int version,
      required String network,
      required String coordinatorAlias,
      required String role,
      required int orderType,
      required int currencyId,
      Value<double?> amount,
      Value<double?> minAmount,
      Value<double?> maxAmount,
      required double premiumPercent,
      required String paymentMethod,
      required double bondSizePercent,
      required int publicSeconds,
      required int escrowSeconds,
      Value<String?> description,
      required bool hasPassword,
      Value<double?> latitude,
      Value<double?> longitude,
      required double createdPrice,
      required double makerFee,
      Value<int> rowid,
    });
typedef $$StoredMakerTermsTableUpdateCompanionBuilder =
    StoredMakerTermsCompanion Function({
      Value<String> keyFingerprint,
      Value<int> robotIndex,
      Value<int> version,
      Value<String> network,
      Value<String> coordinatorAlias,
      Value<String> role,
      Value<int> orderType,
      Value<int> currencyId,
      Value<double?> amount,
      Value<double?> minAmount,
      Value<double?> maxAmount,
      Value<double> premiumPercent,
      Value<String> paymentMethod,
      Value<double> bondSizePercent,
      Value<int> publicSeconds,
      Value<int> escrowSeconds,
      Value<String?> description,
      Value<bool> hasPassword,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<double> createdPrice,
      Value<double> makerFee,
      Value<int> rowid,
    });

class $$StoredMakerTermsTableFilterComposer
    extends Composer<_$P2pDatabase, $StoredMakerTermsTable> {
  $$StoredMakerTermsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get network => $composableBuilder(
    column: $table.network,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coordinatorAlias => $composableBuilder(
    column: $table.coordinatorAlias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderType => $composableBuilder(
    column: $table.orderType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get currencyId => $composableBuilder(
    column: $table.currencyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get minAmount => $composableBuilder(
    column: $table.minAmount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get maxAmount => $composableBuilder(
    column: $table.maxAmount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get premiumPercent => $composableBuilder(
    column: $table.premiumPercent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bondSizePercent => $composableBuilder(
    column: $table.bondSizePercent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get publicSeconds => $composableBuilder(
    column: $table.publicSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get escrowSeconds => $composableBuilder(
    column: $table.escrowSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasPassword => $composableBuilder(
    column: $table.hasPassword,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get createdPrice => $composableBuilder(
    column: $table.createdPrice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get makerFee => $composableBuilder(
    column: $table.makerFee,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StoredMakerTermsTableOrderingComposer
    extends Composer<_$P2pDatabase, $StoredMakerTermsTable> {
  $$StoredMakerTermsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get network => $composableBuilder(
    column: $table.network,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coordinatorAlias => $composableBuilder(
    column: $table.coordinatorAlias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderType => $composableBuilder(
    column: $table.orderType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get currencyId => $composableBuilder(
    column: $table.currencyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get minAmount => $composableBuilder(
    column: $table.minAmount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get maxAmount => $composableBuilder(
    column: $table.maxAmount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get premiumPercent => $composableBuilder(
    column: $table.premiumPercent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bondSizePercent => $composableBuilder(
    column: $table.bondSizePercent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get publicSeconds => $composableBuilder(
    column: $table.publicSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get escrowSeconds => $composableBuilder(
    column: $table.escrowSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasPassword => $composableBuilder(
    column: $table.hasPassword,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get createdPrice => $composableBuilder(
    column: $table.createdPrice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get makerFee => $composableBuilder(
    column: $table.makerFee,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StoredMakerTermsTableAnnotationComposer
    extends Composer<_$P2pDatabase, $StoredMakerTermsTable> {
  $$StoredMakerTermsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get keyFingerprint => $composableBuilder(
    column: $table.keyFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<int> get robotIndex => $composableBuilder(
    column: $table.robotIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get network =>
      $composableBuilder(column: $table.network, builder: (column) => column);

  GeneratedColumn<String> get coordinatorAlias => $composableBuilder(
    column: $table.coordinatorAlias,
    builder: (column) => column,
  );

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<int> get orderType =>
      $composableBuilder(column: $table.orderType, builder: (column) => column);

  GeneratedColumn<int> get currencyId => $composableBuilder(
    column: $table.currencyId,
    builder: (column) => column,
  );

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<double> get minAmount =>
      $composableBuilder(column: $table.minAmount, builder: (column) => column);

  GeneratedColumn<double> get maxAmount =>
      $composableBuilder(column: $table.maxAmount, builder: (column) => column);

  GeneratedColumn<double> get premiumPercent => $composableBuilder(
    column: $table.premiumPercent,
    builder: (column) => column,
  );

  GeneratedColumn<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => column,
  );

  GeneratedColumn<double> get bondSizePercent => $composableBuilder(
    column: $table.bondSizePercent,
    builder: (column) => column,
  );

  GeneratedColumn<int> get publicSeconds => $composableBuilder(
    column: $table.publicSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get escrowSeconds => $composableBuilder(
    column: $table.escrowSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get hasPassword => $composableBuilder(
    column: $table.hasPassword,
    builder: (column) => column,
  );

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<double> get createdPrice => $composableBuilder(
    column: $table.createdPrice,
    builder: (column) => column,
  );

  GeneratedColumn<double> get makerFee =>
      $composableBuilder(column: $table.makerFee, builder: (column) => column);
}

class $$StoredMakerTermsTableTableManager
    extends
        RootTableManager<
          _$P2pDatabase,
          $StoredMakerTermsTable,
          MakerTermsRow,
          $$StoredMakerTermsTableFilterComposer,
          $$StoredMakerTermsTableOrderingComposer,
          $$StoredMakerTermsTableAnnotationComposer,
          $$StoredMakerTermsTableCreateCompanionBuilder,
          $$StoredMakerTermsTableUpdateCompanionBuilder,
          (
            MakerTermsRow,
            BaseReferences<
              _$P2pDatabase,
              $StoredMakerTermsTable,
              MakerTermsRow
            >,
          ),
          MakerTermsRow,
          PrefetchHooks Function()
        > {
  $$StoredMakerTermsTableTableManager(
    _$P2pDatabase db,
    $StoredMakerTermsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredMakerTermsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoredMakerTermsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoredMakerTermsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> keyFingerprint = const Value.absent(),
                Value<int> robotIndex = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String> network = const Value.absent(),
                Value<String> coordinatorAlias = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<int> orderType = const Value.absent(),
                Value<int> currencyId = const Value.absent(),
                Value<double?> amount = const Value.absent(),
                Value<double?> minAmount = const Value.absent(),
                Value<double?> maxAmount = const Value.absent(),
                Value<double> premiumPercent = const Value.absent(),
                Value<String> paymentMethod = const Value.absent(),
                Value<double> bondSizePercent = const Value.absent(),
                Value<int> publicSeconds = const Value.absent(),
                Value<int> escrowSeconds = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<bool> hasPassword = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<double> createdPrice = const Value.absent(),
                Value<double> makerFee = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoredMakerTermsCompanion(
                keyFingerprint: keyFingerprint,
                robotIndex: robotIndex,
                version: version,
                network: network,
                coordinatorAlias: coordinatorAlias,
                role: role,
                orderType: orderType,
                currencyId: currencyId,
                amount: amount,
                minAmount: minAmount,
                maxAmount: maxAmount,
                premiumPercent: premiumPercent,
                paymentMethod: paymentMethod,
                bondSizePercent: bondSizePercent,
                publicSeconds: publicSeconds,
                escrowSeconds: escrowSeconds,
                description: description,
                hasPassword: hasPassword,
                latitude: latitude,
                longitude: longitude,
                createdPrice: createdPrice,
                makerFee: makerFee,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String keyFingerprint,
                required int robotIndex,
                required int version,
                required String network,
                required String coordinatorAlias,
                required String role,
                required int orderType,
                required int currencyId,
                Value<double?> amount = const Value.absent(),
                Value<double?> minAmount = const Value.absent(),
                Value<double?> maxAmount = const Value.absent(),
                required double premiumPercent,
                required String paymentMethod,
                required double bondSizePercent,
                required int publicSeconds,
                required int escrowSeconds,
                Value<String?> description = const Value.absent(),
                required bool hasPassword,
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                required double createdPrice,
                required double makerFee,
                Value<int> rowid = const Value.absent(),
              }) => StoredMakerTermsCompanion.insert(
                keyFingerprint: keyFingerprint,
                robotIndex: robotIndex,
                version: version,
                network: network,
                coordinatorAlias: coordinatorAlias,
                role: role,
                orderType: orderType,
                currencyId: currencyId,
                amount: amount,
                minAmount: minAmount,
                maxAmount: maxAmount,
                premiumPercent: premiumPercent,
                paymentMethod: paymentMethod,
                bondSizePercent: bondSizePercent,
                publicSeconds: publicSeconds,
                escrowSeconds: escrowSeconds,
                description: description,
                hasPassword: hasPassword,
                latitude: latitude,
                longitude: longitude,
                createdPrice: createdPrice,
                makerFee: makerFee,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StoredMakerTermsTableProcessedTableManager =
    ProcessedTableManager<
      _$P2pDatabase,
      $StoredMakerTermsTable,
      MakerTermsRow,
      $$StoredMakerTermsTableFilterComposer,
      $$StoredMakerTermsTableOrderingComposer,
      $$StoredMakerTermsTableAnnotationComposer,
      $$StoredMakerTermsTableCreateCompanionBuilder,
      $$StoredMakerTermsTableUpdateCompanionBuilder,
      (
        MakerTermsRow,
        BaseReferences<_$P2pDatabase, $StoredMakerTermsTable, MakerTermsRow>,
      ),
      MakerTermsRow,
      PrefetchHooks Function()
    >;

class $P2pDatabaseManager {
  final _$P2pDatabase _db;
  $P2pDatabaseManager(this._db);
  $$RobotBindingsTableTableManager get robotBindings =>
      $$RobotBindingsTableTableManager(_db, _db.robotBindings);
  $$TradesTableTableManager get trades =>
      $$TradesTableTableManager(_db, _db.trades);
  $$StoredTradePayoutsTableTableManager get storedTradePayouts =>
      $$StoredTradePayoutsTableTableManager(_db, _db.storedTradePayouts);
  $$StoredTradeTrailsTableTableManager get storedTradeTrails =>
      $$StoredTradeTrailsTableTableManager(_db, _db.storedTradeTrails);
  $$GarageKeyHistoriesTableTableManager get garageKeyHistories =>
      $$GarageKeyHistoriesTableTableManager(_db, _db.garageKeyHistories);
  $$StoredTradeTermsTableTableManager get storedTradeTerms =>
      $$StoredTradeTermsTableTableManager(_db, _db.storedTradeTerms);
  $$StoredTradePaymentsTableTableManager get storedTradePayments =>
      $$StoredTradePaymentsTableTableManager(_db, _db.storedTradePayments);
  $$StoredTradeChatPinsTableTableManager get storedTradeChatPins =>
      $$StoredTradeChatPinsTableTableManager(_db, _db.storedTradeChatPins);
  $$StoredTradeChatNostrPinsTableTableManager get storedTradeChatNostrPins =>
      $$StoredTradeChatNostrPinsTableTableManager(
        _db,
        _db.storedTradeChatNostrPins,
      );
  $$StoredMakerTermsTableTableManager get storedMakerTerms =>
      $$StoredMakerTermsTableTableManager(_db, _db.storedMakerTerms);
}
