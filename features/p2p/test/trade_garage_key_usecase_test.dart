import 'dart:typed_data';

import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/usecases/trade/trade_garage_key_usecase.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/garage_words.dart';
import 'support/prepared_takes.dart';

/// The vault as the use case reads it: [newTrade], what `forNewTrade` gives, and [externalKey], what `external` gives.
final class _Keys with KeysFromRead implements GarageKeyRepository {
  Result<NetworkGarageKey, P2pFailure> newTrade = const Err(
    GarageKeyMissingFailure(),
  );
  Result<NetworkGarageKey, P2pFailure> externalKey = const Err(
    GarageKeyMissingFailure(),
  );

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> read(
    RobosatsNetwork network,
  ) async => newTrade;

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> forNewTrade(
    RobosatsNetwork network,
  ) async => newTrade;

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> external(
    RobosatsNetwork network,
  ) async => externalKey;

  @override
  Future<Result<void, P2pFailure>> import(
    RobosatsNetwork network,
    GarageKey key,
  ) => throw UnimplementedError();

  @override
  Future<Result<bool, P2pFailure>> exists(RobosatsNetwork network) =>
      throw UnimplementedError();

  @override
  Future<Result<NetworkRobot, P2pFailure>> firstUsableRobot(
    RobosatsNetwork network,
  ) => throw UnimplementedError();
}

/// Which key « Store your garage key » is shown for and which key its copy may give (#318): the external Garage Key only, and, for a take, only the very key of the take's robot (security review of #320, R8; functional review, C1).
void main() {
  const mainnet = RobosatsNetwork.mainnet;

  // Fixed test bytes: not keys anyone uses.
  GarageKey keyOf(int first) => switch (GarageKey.fromBytes(
    Uint8List.fromList(List<int>.generate(32, (i) => first + i)),
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
  final keyA = keyOf(1);
  final keyB = keyOf(2);
  final fingerprintA = switch (GarageKeyFingerprint.of(keyA)) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  late _Keys keys;
  RobotSlot? robotOfTake;
  late TradeGarageKeyUsecase usecase;

  setUp(() {
    keys = _Keys();
    robotOfTake = null;
    usecase = TradeGarageKeyUsecase(keys, (_) => robotOfTake);
  });

  group('makeUsesExternalKey', () {
    test('the external Garage Key: the reminder', () async {
      keys.newTrade = Ok(NetworkGarageKey(mainnet, keyA));
      expect(await usecase.makeUsesExternalKey(mainnet), isTrue);
    });

    test('an internal Garage Key: no reminder', () async {
      keys.newTrade = Ok(NetworkGarageKey(mainnet, keyA, index: 0));
      expect(await usecase.makeUsesExternalKey(mainnet), isFalse);
    });

    test(
      'a key that cannot be read: the reminder, as before #318 (functional review of #320, C1)',
      () async {
        keys.newTrade = const Err(GarageKeyLockedFailure());
        expect(await usecase.makeUsesExternalKey(mainnet), isTrue);
        keys.newTrade = const Err(GarageKeyMissingFailure());
        expect(await usecase.makeUsesExternalKey(mainnet), isTrue);
      },
    );
  });

  group('externalKeyOfMake', () {
    test('gives the external Garage Key new trades take', () async {
      final external = NetworkGarageKey(mainnet, keyA);
      keys.newTrade = Ok(external);
      expect(await usecase.externalKeyOfMake(mainnet), external);
    });

    test(
      'never gives an internal Garage Key, the key of the words (security review of #320, R8)',
      () async {
        keys.newTrade = Ok(NetworkGarageKey(mainnet, keyA, index: 0));
        expect(await usecase.externalKeyOfMake(mainnet), isNull);
        keys.newTrade = Ok(NetworkGarageKey(mainnet, keyB, index: 3));
        expect(await usecase.externalKeyOfMake(mainnet), isNull);
      },
    );

    test('gives nothing for a key that cannot be read', () async {
      keys.newTrade = const Err(GarageKeyLockedFailure());
      expect(await usecase.externalKeyOfMake(mainnet), isNull);
    });
  });

  group('externalKeyOfTake', () {
    test('gives the external key whose robot takes the order', () async {
      final prepared = await preparedTake();
      final external = NetworkGarageKey(mainnet, keyA);
      keys.externalKey = Ok(external);
      robotOfTake = RobotSlot(mainnet, fingerprintA, 2);
      expect(await usecase.externalKeyOfTake(prepared), external);
    });

    test(
      'gives nothing when the external key the vault keeps now is another one than the take\'s robot\'s: never the wrong key to back up (security review of #320, R8)',
      () async {
        final prepared = await preparedTake();
        // The take prepared with a robot of key A; key B imported since in its place.
        robotOfTake = RobotSlot(mainnet, fingerprintA, 2);
        keys.externalKey = Ok(NetworkGarageKey(mainnet, keyB));
        expect(await usecase.externalKeyOfTake(prepared), isNull);
      },
    );

    test(
      'gives nothing for a take whose robot is not of the external key, or no longer prepared',
      () async {
        final prepared = await preparedTake();
        keys.externalKey = Ok(NetworkGarageKey(mainnet, keyA));
        robotOfTake = null;
        expect(await usecase.externalKeyOfTake(prepared), isNull);
      },
    );

    test('gives nothing when the vault cannot be read', () async {
      final prepared = await preparedTake();
      robotOfTake = RobotSlot(mainnet, fingerprintA, 2);
      keys.externalKey = const Err(GarageKeyLockedFailure());
      expect(await usecase.externalKeyOfTake(prepared), isNull);
    });
  });
}
