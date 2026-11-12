import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/usecases/delete_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/derive_first_robot_usecase.dart';
import 'package:p2p/src/domain/usecases/generate_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/has_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/import_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/read_garage_key_usecase.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/robot_bindings.dart';

/// A repository that records each call and answers with [failure] when one is set.
final class _RecordingRepository implements GarageKeyRepository {
  final List<String> calls = [];
  final List<GarageKey> imported = [];
  final NetworkGarageKey key;
  final NetworkRobot robot;
  P2pFailure? failure;

  _RecordingRepository(this.key, this.robot);

  Result<T, P2pFailure> _answer<T>(T value) => switch (failure) {
    final P2pFailure failure => Err(failure),
    null => Ok(value),
  };

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> create(
    RobosatsNetwork network,
  ) async {
    calls.add('create ${network.name}');
    return _answer(NetworkGarageKey(network, key.key));
  }

  @override
  Future<Result<void, P2pFailure>> import(
    RobosatsNetwork network,
    GarageKey key,
  ) async {
    calls.add('import ${network.name}');
    imported.add(key);
    return _answer(null);
  }

  @override
  Future<Result<bool, P2pFailure>> exists(RobosatsNetwork network) async {
    calls.add('exists ${network.name}');
    return _answer(true);
  }

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> read(
    RobosatsNetwork network,
  ) async {
    calls.add('read ${network.name}');
    return _answer(key);
  }

  @override
  Future<Result<NetworkRobot, P2pFailure>> firstUsableRobot(
    RobosatsNetwork network,
  ) async {
    calls.add('firstUsableRobot ${network.name}');
    return _answer(robot);
  }

  @override
  Future<Result<void, P2pFailure>> delete(RobosatsNetwork network) async {
    calls.add('delete ${network.name}');
    return _answer(null);
  }
}

/// A repository that draws one key and would read back another: a draw must record the key it drew, never the one in the slot afterwards.
final class _DrawsOneReadsAnother extends _RecordingRepository {
  final GarageKey drawn;

  _DrawsOneReadsAnother(super.key, super.robot, this.drawn);

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> create(
    RobosatsNetwork network,
  ) async {
    calls.add('create ${network.name}');
    return Ok(NetworkGarageKey(network, drawn));
  }
}

void main() {
  // The example key of the RoboSats frontend tests, as `packages/robosats` records it (tests run in the package directory).
  final exampleText =
      ((jsonDecode(
                    File(
                      '../../packages/robosats/test/fixtures/robot-identity-vectors.json',
                    ).readAsStringSync(),
                  )
                  as Map<String, dynamic>)['garage_key']
              as Map<String, dynamic>)['garage_key']
          as String;
  final exampleKey = switch (GarageKey.parse(exampleText)) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
  final networkKey = NetworkGarageKey(RobosatsNetwork.testnet, exampleKey);
  final exampleRobot = switch (networkKey.firstUsableRobot(0)) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  final exampleFingerprint = switch (GarageKeyFingerprint.of(exampleKey)) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  late _RecordingRepository repository;
  late RecordingBindings bindings;

  setUp(() {
    repository = _RecordingRepository(networkKey, exampleRobot);
    bindings = RecordingBindings();
  });

  group('importing a Garage Key', () {
    test('stores the key the text names, for the network given', () async {
      final result = await ImportGarageKeyUsecase(
        repository,
        bindings,
      ).execute(RobosatsNetwork.testnet, text: exampleText);

      expect(result, isA<Ok<void, P2pFailure>>());
      expect(repository.calls, ['import testnet']);
      expect(repository.imported, [exampleKey]);
      expect(bindings.calls, [
        ('recordImportedKey', RobosatsNetwork.testnet, exampleFingerprint),
      ]);
    });

    test(
      'records the key as imported first, and stores nothing when it cannot',
      () async {
        bindings.failure = const P2pStorageFailure();

        final result = await ImportGarageKeyUsecase(
          repository,
          bindings,
        ).execute(RobosatsNetwork.mainnet, text: exampleText);

        expect(
          result,
          isA<Err<void, P2pFailure>>().having(
            (err) => err.failure,
            'failure',
            isA<P2pStorageFailure>(),
          ),
        );
        expect(bindings.calls, [
          ('recordImportedKey', RobosatsNetwork.mainnet, exampleFingerprint),
        ]);
        expect(repository.calls, isEmpty);
      },
    );

    test('refuses text that is not a key before anything is stored', () async {
      for (final (text, reason) in [
        ('', isA<GarageKeyEmpty>()),
        ('not a key', isA<GarageKeyWrongPrefix>()),
        (
          '${exampleText.substring(0, exampleText.length - 1)}q',
          isA<GarageKeyBadChecksum>(),
        ),
        (' $exampleText', isA<GarageKeyWrongPrefix>()),
      ]) {
        final result = await ImportGarageKeyUsecase(
          repository,
          bindings,
        ).execute(RobosatsNetwork.mainnet, text: text);

        expect(
          result,
          isA<Err<void, P2pFailure>>().having(
            (err) => err.failure,
            'failure',
            isA<GarageKeyInvalidFailure>().having(
              (failure) => failure.reason,
              'reason',
              reason,
            ),
          ),
        );
      }
      expect(repository.calls, isEmpty);
      expect(bindings.calls, isEmpty);
    });

    test('a failure for a rejected text carries none of it', () async {
      // Not keys: text that passes the prefix and length checks, and text that does not.
      for (final text in [
        'robo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqzzzz',
        'robo1notakeyatallbutlongenoughtopassthelengthcheckxxxxxxxxxxxxx',
        '${exampleText.substring(0, exampleText.length - 1)}q',
        'somethingelse',
      ]) {
        final failure = switch (await ImportGarageKeyUsecase(
          repository,
          bindings,
        ).execute(RobosatsNetwork.mainnet, text: text)) {
          Err(:final failure) => failure,
          Ok() => fail('a text that is not a key was accepted'),
        };

        expect(failure, isA<GarageKeyInvalidFailure>());
        expect(failure.logMessage, isNull);
        for (final shown in [
          '$failure',
          '${(failure as GarageKeyInvalidFailure).reason}',
        ]) {
          // A boolean, so that a failure does not print the text.
          expect(shown.contains(text.substring(5, 12)), isFalse);
        }
      }
      expect(repository.calls, isEmpty);
    });

    test('reports a refused import as the repository says it', () async {
      repository.failure = const GarageKeyAlreadyStoredFailure();

      final result = await ImportGarageKeyUsecase(
        repository,
        bindings,
      ).execute(RobosatsNetwork.mainnet, text: exampleText);

      expect(
        result,
        isA<Err<void, P2pFailure>>().having(
          (err) => err.failure,
          'failure',
          isA<GarageKeyAlreadyStoredFailure>(),
        ),
      );
      expect(repository.calls, ['import mainnet']);
    });
  });

  group('generating a Garage Key', () {
    Matcher drawnWith(GarageKeyHistory history) =>
        isA<Ok<GarageKeyHistory, P2pFailure>>().having(
          (ok) => ok.value,
          'history',
          history,
        );

    for (final network in RobosatsNetwork.values) {
      test(
        'on ${network.name}: draws it and records the key it drew as drawn on this device, for that network',
        () async {
          final result = await GenerateGarageKeyUsecase(
            repository,
            bindings,
          ).execute(network);

          expect(result, drawnWith(GarageKeyHistory.drawnHere));
          // No read of the slot between the draw and the record.
          expect(repository.calls, ['create ${network.name}']);
          expect(bindings.calls, [
            ('recordGeneratedKey', network, exampleFingerprint),
          ]);
        },
      );
    }

    test(
      'records the key the vault drew, not the one the slot holds afterwards',
      () async {
        // Fixed test bytes, 0x07 to 0x26: not a key anyone uses.
        final drawn = switch (GarageKey.fromBytes(
          Uint8List.fromList(List<int>.generate(32, (i) => 7 + i)),
        )) {
          Ok(:final value) => value,
          Err(:final failure) => throw StateError('$failure'),
        };
        final drawingAnother = _DrawsOneReadsAnother(
          networkKey,
          exampleRobot,
          drawn,
        );

        expect(
          await GenerateGarageKeyUsecase(
            drawingAnother,
            bindings,
          ).execute(RobosatsNetwork.testnet),
          drawnWith(GarageKeyHistory.drawnHere),
        );
        expect(drawingAnother.calls, ['create testnet']);
        final recorded = bindings.calls.single.$3;
        expect(recorded, isNot(exampleFingerprint));
        expect(recorded, switch (GarageKeyFingerprint.of(drawn)) {
          Ok(:final value) => value,
          Err(:final failure) => throw StateError('$failure'),
        });
      },
    );

    test('a key not drawn is not recorded', () async {
      repository.failure = const GarageKeyAlreadyStoredFailure();

      final result = await GenerateGarageKeyUsecase(
        repository,
        bindings,
      ).execute(RobosatsNetwork.mainnet);

      expect(
        result,
        isA<Err<GarageKeyHistory, P2pFailure>>().having(
          (err) => err.failure,
          'failure',
          isA<GarageKeyAlreadyStoredFailure>(),
        ),
      );
      expect(repository.calls, ['create mainnet']);
      expect(bindings.calls, isEmpty);
    });

    test(
      'a key drawn whose record cannot be written is stored, and its history is reported unknown',
      () async {
        bindings.failure = const P2pStorageFailure();

        expect(
          await GenerateGarageKeyUsecase(
            repository,
            bindings,
          ).execute(RobosatsNetwork.testnet),
          drawnWith(GarageKeyHistory.unknown),
        );
        expect(repository.calls, ['create testnet']);
        expect(bindings.calls, hasLength(1));
      },
    );
  });

  group('each other use-case asks the repository once, for its network', () {
    final cases =
        <
          String,
          (
            Future<Result<Object?, P2pFailure>> Function(_RecordingRepository),
            Object?,
          )
        >{
          'exists mainnet': (
            (r) => HasGarageKeyUsecase(r).execute(RobosatsNetwork.mainnet),
            true,
          ),
          'read testnet': (
            (r) => ReadGarageKeyUsecase(r).execute(RobosatsNetwork.testnet),
            networkKey,
          ),
          'firstUsableRobot testnet': (
            (r) => DeriveFirstRobotUsecase(r).execute(RobosatsNetwork.testnet),
            exampleRobot,
          ),
          'delete mainnet': (
            (r) => DeleteGarageKeyUsecase(r).execute(RobosatsNetwork.mainnet),
            null,
          ),
        };

    for (final MapEntry(key: call, value: (run, expected)) in cases.entries) {
      test('$call: its answer, then its failure, passed on', () async {
        expect(
          await run(repository),
          isA<Ok<Object?, P2pFailure>>().having(
            (ok) => ok.value,
            'value',
            expected,
          ),
        );
        repository.failure = const GarageKeyLockedFailure();
        expect(
          await run(repository),
          isA<Err<Object?, P2pFailure>>().having(
            (err) => err.failure,
            'failure',
            isA<GarageKeyLockedFailure>(),
          ),
        );
        expect(repository.calls, [call, call]);
      });
    }
  });
}
