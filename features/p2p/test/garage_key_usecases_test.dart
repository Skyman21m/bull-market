import 'dart:convert';
import 'dart:io';

import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/garage_keyring.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/usecases/delete_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/derive_first_robot_usecase.dart';
import 'package:p2p/src/domain/usecases/has_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/import_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/new_garage_key_usecase.dart';
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
  Future<Result<GarageKeyring, P2pFailure>> keyring(
    RobosatsNetwork network,
  ) async {
    calls.add('keyring ${network.name}');
    return _answer(_keyring);
  }

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> derived(
    RobosatsNetwork network,
    int index,
  ) async {
    calls.add('derived ${network.name} $index');
    return _answer(key);
  }

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> forNewTrade(
    RobosatsNetwork network,
  ) async {
    calls.add('forNewTrade ${network.name}');
    return _answer(key);
  }

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> ofSlot(RobotSlot slot) async {
    calls.add('ofSlot ${slot.network.name}');
    return _answer(key);
  }

  @override
  Future<Result<int, P2pFailure>> activateNext(
    RobosatsNetwork network, {
    required int after,
  }) async {
    calls.add('activateNext ${network.name} $after');
    return _answer(after + 1);
  }

  @override
  Future<Result<void, P2pFailure>> select(
    RobosatsNetwork network,
    GarageKeySelection selection,
  ) async {
    calls.add('select ${network.name} $selection');
    return _answer(null);
  }

  @override
  Future<Result<void, P2pFailure>> delete(RobosatsNetwork network) async {
    calls.add('delete ${network.name}');
    return _answer(null);
  }

  @override
  Future<Result<void, P2pFailure>> selectInternal(
    RobosatsNetwork network,
  ) async {
    calls.add('selectInternal ${network.name}');
    return _answer(null);
  }

  @override
  Future<Result<int?, P2pFailure>> internalIndexOf(
    RobosatsNetwork network,
    GarageKeyFingerprint fingerprint,
  ) async => const Ok(null);

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> external(
    RobosatsNetwork network,
  ) async {
    calls.add('external ${network.name}');
    return _answer(key);
  }

  @override
  Future<Result<void, P2pFailure>> externalNoticeShown() async {
    calls.add('externalNoticeShown');
    return _answer(null);
  }
}

const _keyring = GarageKeyring(highest: 0, selected: SelectedWordsKey(0));

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
          'keyring mainnet': (
            (r) => ReadGarageKeyUsecase(r).keyring(RobosatsNetwork.mainnet),
            _keyring,
          ),
          'select mainnet SelectedExternalKey()': (
            (r) => ReadGarageKeyUsecase(
              r,
            ).select(RobosatsNetwork.mainnet, const SelectedExternalKey()),
            null,
          ),
          'delete mainnet': (
            (r) => DeleteGarageKeyUsecase(r).execute(RobosatsNetwork.mainnet),
            null,
          ),
          'derived testnet 0': (
            (r) => ReadGarageKeyUsecase(r).derived(RobosatsNetwork.testnet, 0),
            networkKey,
          ),
          'activateNext mainnet 2': (
            (r) => NewGarageKeyUsecase(
              r,
            ).execute(RobosatsNetwork.mainnet, after: 2),
            3,
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
