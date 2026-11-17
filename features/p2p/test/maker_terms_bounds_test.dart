import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/data/robot_binding_repository_impl.dart';
import 'package:p2p/src/data/trade_record_repository_impl.dart';
import 'package:p2p/src/data/trade_trail_repository_impl.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/trade_storable.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:p2p/src/domain/trade/trade_tolerances.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/robot_bindings.dart';

/// The bounds of a maker's terms, kept in three places (#177): `MakeOrderRequest.tryCreate` (what is sent), `MakerTerms` (what is checked and stored) and the CHECKs of `maker_terms` (schema 8, what the database keeps). Each bound is tried at its value and one step past it, in all three, which must give the same verdict.
///
/// Where the database is wider by design (it counts no decimals, cleans no text, knows no currency or coordinator), the last group says so: `MakerTerms.restore` refuses those records, and no code writes them, since every record comes from `MakerTerms.record`.
void main() {
  const testnet = RobosatsNetwork.testnet;

  // Fixed test bytes: not keys anyone uses.
  final fingerprint = switch (GarageKey.fromBytes(
    Uint8List.fromList(List<int>.generate(32, (i) => 1 + i)),
  )) {
    Ok(value: final key) => switch (GarageKeyFingerprint.of(key)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    },
    Err(:final failure) => throw StateError('$failure'),
  };
  final temple = switch (CoordinatorIdentity.of(
    coordinator('temple'),
    testnet,
  )) {
    final identity? => identity,
    null => throw StateError('temple is not on testnet'),
  };

  late P2pDatabase database;
  late RobotBindingRepositoryImpl bindings;
  late TradeRecordRepositoryImpl trades;
  late TradeTrailRepositoryImpl trails;
  var nextIndex = 0;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    database = P2pDatabase.forTesting(NativeDatabase.memory());
    bindings = bindingsInMemory(database: database);
    trades = TradeRecordRepositoryImpl(database, clock: () => testNow);
    trails = TradeTrailRepositoryImpl(database);
    nextIndex = 0;
    expect(await bindings.recordGeneratedKey(testnet, fingerprint), isA<Ok>());
  });

  tearDown(() => database.close());

  /// Whether the database keeps [record] as the terms of a fresh pending make of its role, on temple.
  Future<bool> stored(MakerTermsRecord record) async {
    final robot = RobotSlot(testnet, fingerprint, nextIndex++);
    final reservation = switch (await trades.reserveForNewTrade(
      robot,
      temple,
    )) {
      Ok(value: final reservation?) => reservation,
      final other => throw StateError('not reserved: $other'),
    };
    final role = TradeRole.values.byName(record.role);
    final make = switch (await trades.recordPendingMake(
      reservation,
      role: role,
    )) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
    return switch (await trails.recordMakerTerms(make, record)) {
      Ok() => true,
      Err(failure: P2pStorageFailure()) => false,
      Err(:final failure) => throw StateError('$failure'),
    };
  }

  /// Whether `MakeOrderRequest.tryCreate` takes the request [record] holds: `null` when one of its values is refused before (a primitive that refuses it, an unknown currency or type).
  bool requestTakes(MakerTermsRecord record) {
    final type = OrderType.fromWire(record.type);
    final currency = RobosatsCurrency.fromId(record.currencyId);
    final premium = Premium.tryCreate(record.premiumPercent);
    final bondSize = BondSize.tryCreate(record.bondSizePercent);
    final OrderAmount? amount = switch ((
      record.amount,
      record.minAmount,
      record.maxAmount,
    )) {
      (final fixed?, null, null) => switch (FiatAmount.tryCreate(fixed)) {
        final value? => FixedOrderAmount(value),
        null => null,
      },
      (null, final min?, final max?) => switch ((
        FiatAmount.tryCreate(min),
        FiatAmount.tryCreate(max),
      )) {
        (final low?, final high?) => RangeOrderAmount.tryCreate(low, high),
        _ => null,
      },
      _ => null,
    };
    if (type == null ||
        currency == null ||
        premium == null ||
        bondSize == null ||
        amount == null) {
      return false;
    }
    return MakeOrderRequest.tryCreate(
          type: type,
          currency: currency,
          amount: amount,
          paymentMethod: record.paymentMethod,
          premium: premium,
          publicDuration: Duration(seconds: record.publicSeconds),
          escrowDuration: Duration(seconds: record.escrowSeconds),
          bondSize: bondSize,
          description: record.description,
        ) !=
        null;
  }

  bool termsTake(MakerTermsRecord record) => MakerTerms.restore(record) is Ok;

  MakerTermsRecord base({
    String role = 'buyer',
    int type = 0,
    int currencyId = 2,
    (double?, double?, double?) amounts = (100, null, null),
    double premium = 1.5,
    String paymentMethod = 'Revolut SEPA',
    double bond = 3,
    int publicSeconds = 86340,
    int escrowSeconds = 10800,
    String? description,
    double createdPrice = 93545.25,
    double makerFee = 0.00025,
  }) => MakerTermsRecord(
    version: 1,
    network: 'testnet',
    coordinatorAlias: 'temple',
    role: role,
    type: type,
    currencyId: currencyId,
    amount: amounts.$1,
    minAmount: amounts.$2,
    maxAmount: amounts.$3,
    premiumPercent: premium,
    paymentMethod: paymentMethod,
    bondSizePercent: bond,
    publicSeconds: publicSeconds,
    escrowSeconds: escrowSeconds,
    description: description,
    hasPassword: false,
    latitude: null,
    longitude: null,
    createdPrice: createdPrice,
    makerFee: makerFee,
  );

  /// Each bound of the request, at it and one step past it, with the verdict all three must give.
  final requestBounds = <String, (MakerTermsRecord, bool)>{
    'premium -100': (base(premium: -100), false),
    'premium -99.99': (base(premium: -99.99), true),
    'premium 999': (base(premium: 999), true),
    'premium 999.01': (base(premium: 999.01), false),
    'bond 1.99': (base(bond: 1.99), false),
    'bond 2': (base(bond: 2), true),
    'bond 15': (base(bond: 15), true),
    'bond 15.01': (base(bond: 15.01), false),
    'public 599 s': (base(publicSeconds: 599), false),
    'public 600 s': (base(publicSeconds: 600), true),
    'public 86,400 s': (base(publicSeconds: 86400), true),
    'public 86,401 s': (base(publicSeconds: 86401), false),
    'escrow 1,799 s': (base(escrowSeconds: 1799), false),
    'escrow 1,800 s': (base(escrowSeconds: 1800), true),
    'escrow 36,000 s': (base(escrowSeconds: 36000), true),
    'escrow 36,001 s': (base(escrowSeconds: 36001), false),
    'no payment method': (base(paymentMethod: ''), false),
    '1 code point': (base(paymentMethod: 'a'), true),
    '70 code points': (base(paymentMethod: 'a' * 70), true),
    '71 code points': (base(paymentMethod: 'a' * 71), false),
    '70 code points out of the BMP': (base(paymentMethod: '🐂' * 70), true),
    '71 code points out of the BMP': (base(paymentMethod: '🐂' * 71), false),
    'no description': (base(), true),
    'empty description': (base(description: ''), false),
    'description of 1': (base(description: 'x'), true),
    'description of 240': (base(description: 'x' * 240), true),
    'description of 241': (base(description: 'x' * 241), false),
    'description of 240 out of the BMP': (base(description: '🐂' * 240), true),
    'description of 241 out of the BMP': (base(description: '🐂' * 241), false),
    'amount 0': (base(amounts: (0, null, null)), false),
    'amount 1e-8': (base(amounts: (1e-8, null, null)), true),
    'amount just below 10^10': (
      base(amounts: (9999999999.999998, null, null)),
      true,
    ),
    'amount 10^10': (base(amounts: (1e10, null, null)), false),
    'range of 1.5': (base(amounts: (null, 100, 150)), true),
    'range just under 1.5': (base(amounts: (null, 100, 149.99999999)), false),
    'range of 15': (base(amounts: (null, 100, 1500)), true),
    'range just over 15': (base(amounts: (null, 100, 1500.00000001)), false),
    // 1.5e-8 / 1.5 is 9.999999999999999e-9 in doubles, so this range is under 1.5 for all three, which compare the same doubles.
    'range of 1.5 from 1e-8, under it in doubles': (
      base(amounts: (null, 1e-8, 1.5e-8)),
      false,
    ),
    'range of 2 from 1e-8': (base(amounts: (null, 1e-8, 2e-8)), true),
    'range with a minimum of 0': (base(amounts: (null, 0, 1)), false),
    'range up to 10^10': (base(amounts: (null, 1e9, 1e10)), false),
    'range just below 10^10': (
      base(amounts: (null, 1e9, 9999999999.999998)),
      true,
    ),
    'range upside down': (base(amounts: (null, 600, 100)), false),
    'a sell order\'s seller': (base(role: 'seller', type: 1), true),
  };

  test(
    'the request\'s bounds: the request, the terms and the database agree, at each bound and one step past it',
    () async {
      for (final MapEntry(key: name, value: (record, verdict))
          in requestBounds.entries) {
        expect(requestTakes(record), verdict, reason: 'request: $name');
        expect(termsTake(record), verdict, reason: 'terms: $name');
        expect(await stored(record), verdict, reason: 'database: $name');
      }
    },
  );

  test(
    'the terms\' own bounds, the price and the maker fee: the terms and the database agree',
    () async {
      final bounds = <String, (MakerTermsRecord, bool)>{
        'price 0': (base(createdPrice: 0), false),
        'price -1': (base(createdPrice: -1), false),
        'smallest price': (base(createdPrice: 5e-324), true),
        'price just below 10^15': (
          base(createdPrice: 999999999999999.875),
          true,
        ),
        'price 10^15': (base(createdPrice: 1e15), false),
        'fee 0': (base(makerFee: 0), true),
        'fee 1 %': (base(makerFee: 0.01), true),
        'fee just above 1 %': (base(makerFee: 0.010000000000000002), false),
        'negative fee': (base(makerFee: -1e-9), false),
      };
      expect(MakerTerms.maxCreatedPrice, 1e15);
      expect(TradeTolerances.makerFeeCeiling, 0.01);
      for (final MapEntry(key: name, value: (record, verdict))
          in bounds.entries) {
        expect(termsTake(record), verdict, reason: 'terms: $name');
        expect(await stored(record), verdict, reason: 'database: $name');
      }
    },
  );

  test('every record MakerTerms writes, the database keeps', () async {
    for (final MapEntry(key: name, value: (record, verdict))
        in requestBounds.entries) {
      if (!verdict) continue;
      final terms = switch (MakerTerms.restore(record)) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$name: $failure'),
      };
      expect(terms.record, record, reason: name);
      expect(await stored(terms.record), isTrue, reason: name);
    }
  });

  test(
    'where the database is wider by design: the terms refuse what no code writes',
    () async {
      final wider = <String, MakerTermsRecord>{
        'a premium with three decimals': base(premium: 1.234),
        'a bond with three decimals': base(bond: 3.001),
        'an amount with nine decimals': base(
          amounts: (100.123456789, null, null),
        ),
        'a method with a space at its end': base(paymentMethod: 'Revolut '),
        'a method with a control character': base(
          paymentMethod: 'Rev\u0007olut',
        ),
        'a description with a line break': base(description: 'line\nbreak'),
        'bitcoin, the currency of a swap': base(currencyId: 1000),
        'an unknown currency': base(currencyId: 99999),
      };
      for (final MapEntry(key: name, value: record) in wider.entries) {
        expect(requestTakes(record), isFalse, reason: 'request: $name');
        expect(termsTake(record), isFalse, reason: 'terms: $name');
        expect(await stored(record), isTrue, reason: 'database: $name');
      }
    },
  );
}
