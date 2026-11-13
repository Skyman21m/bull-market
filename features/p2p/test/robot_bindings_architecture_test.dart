import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart' show parseString;
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:test/test.dart';

/// Where the robot requests, the robot credentials, raw network clients, the bindings and the work on a robot's key pair can be reached in `features/p2p/lib`.
///
/// What refers to them is resolved by the analyzer, calls, tear-offs, cascades, prefixes, extensions and implementations alike, in every Dart file of `lib/` but the committed translations.
/// A member reached through `dynamic` is reported here: `avoid_dynamic_calls`, an error in this feature, refuses a call on an implicitly dynamic value, but lets an explicit `as dynamic` cast through.
/// What imports the database and what its SQL says is read from the syntax tree.
/// The behaviour is tested elsewhere (`robot_binding_repository_test.dart`, `robot_usecases_test.dart`): these keep it from being walked around inside the feature.
/// They do not see code outside `features/p2p/lib` (the robot types stay out of the app-facing library for that, `p2p_feature_test.dart`), `packages/robosats` itself, nor a credential copied into a plain `String` by an allowed file and sent later.
void main() {
  // Tests run with the package directory as working directory.
  final libraries = {
    for (final path in _scanned())
      path: _Facts.of(File(path).readAsStringSync()),
  };

  Set<String> where(bool Function(_Facts facts) test) => {
    for (final MapEntry(key: path, value: facts) in libraries.entries)
      if (test(facts)) path,
  };

  test('the scan reads every Dart file of lib/, the translations included', () {
    for (final (path, scanned) in [
      // The translations gen-l10n writes are code too: a hand-written file named like one was not seen before (review of #67).
      ('lib/generated/l10n/p2p_localizations.dart', true),
      ('lib/generated/l10n/p2p_localizations_fr.dart', true),
      ('lib/generated/l10n/p2p_localizations_zz.dart', true),
      ('lib/generated/l10n/zz_l10n.dart', true),
      ('lib/generated/zz_gen.dart', true),
      ('lib/src/data/p2p_database.g.dart', true),
      ('lib/src/zz.dart', true),
      ('lib/zz.txt', false),
      ('test/zz_test.dart', false),
    ]) {
      expect(_isScanned(path), scanned, reason: path);
    }
  });

  test('the feature\'s analysis options switch no diagnostic off', () {
    // An `ignore` severity, a lint set to false or an excluded file there would silence the analyzer as an `ignore` comment does (review of step 3): the options are pinned, comments aside, as main has them.
    final options = File('analysis_options.yaml')
        .readAsLinesSync()
        .map((line) => line.split('#').first.trim())
        .where((line) => line.isNotEmpty);
    expect(options, [
      'include: package:lints/recommended.yaml',
      'linter:',
      'rules:',
      '- avoid_print',
      '- avoid_dynamic_calls',
      '- implementation_imports',
      '- prefer_final_locals',
      '- require_trailing_commas',
      '- use_super_parameters',
      'analyzer:',
      'errors:',
      'implementation_imports: error',
      'avoid_dynamic_calls: error',
    ]);
  });

  test('no other analysis options lie under the feature', () {
    // The analyzer reads the nearest `analysis_options.yaml` of each file: a nested one could switch a diagnostic off for its folder without a sign (second security pass on step 3, #69).
    // The tool caches of `.dart_tool` and the build output are not sources, and Git ignores them.
    final found = [
      for (final entity in Directory('.').listSync(recursive: true))
        if (entity is File &&
            entity.uri.pathSegments.last == 'analysis_options.yaml' &&
            !entity.path.startsWith('./.dart_tool/') &&
            !entity.path.startsWith('./build/'))
          entity.path,
    ];
    expect(found, ['./analysis_options.yaml']);
  });

  test('an ignore followed by a comment of its own is read whole', () {
    // `// ignore: unused_import // a reason` silences the analyzer all the same: read up to the slash, it passed for the form gen-l10n writes (#69).
    expect(
      _ignores(
        '// ignore: unused_import // a reason\n'
        'x; /* ignore_for_file: type=lint */ y;\n'
        '// ignore_for_file: type=lint, unused_import  \n',
      ),
      [
        'ignore: unused_import // a reason',
        'ignore_for_file: type=lint',
        'ignore_for_file: type=lint, unused_import',
      ],
    );
  });

  test('every Dart file of lib/ is scanned', () {
    final all = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File && file.path.endsWith('.dart')) file.path,
    ];
    expect(libraries.keys, unorderedEquals(all));
    expect(
      libraries.keys,
      containsAll([
        'lib/generated/l10n/p2p_localizations.dart',
        'lib/generated/l10n/p2p_localizations_fr.dart',
        'lib/src/data/p2p_database.dart',
        'lib/src/data/robot_binding_repository_impl.dart',
        'lib/src/domain/usecases/fetch_robot_usecase.dart',
      ]),
    );
    // The Drift code of the database, which `make build-runner` writes and Git does not track: scanned whenever it is there, as in CI; without it the database does not compile, and the feature's other tests fail first.
    if (File('lib/src/data/p2p_database.g.dart').existsSync()) {
      expect(libraries.keys, contains('lib/src/data/p2p_database.g.dart'));
    }
  });

  test(
    'no file silences a diagnostic but those the generators write, and the experimental table migration',
    () {
      // AGENTS.md bans `// ignore`: an `ignore` of `invalid_use_of_internal_member`, or of a whole type of warnings, would let a file call the package's internals without a sign (review of #67).
      // gen-l10n writes `// ignore: unused_import` and `// ignore_for_file: type=lint`, Drift the second in its code and both on one line in its migration steps: lints and unused imports only.
      // The migration to schema 2 rebuilds the histories with drift's `TableMigration`, which drift marks experimental: one `ignore` of that warning, on that line, as the wallet's own migrations have it.
      final offenders = <String>[];
      for (final path in libraries.keys) {
        final ignores = _ignores(File(path).readAsStringSync());
        if (path == 'lib/src/data/p2p_database.dart') {
          expect(ignores, ['ignore: experimental_member_use']);
          continue;
        }
        final allowed = switch (path) {
          _ when path.startsWith('lib/generated/l10n/p2p_localizations') => {
            'ignore: unused_import',
            'ignore_for_file: type=lint',
          },
          _ when path.endsWith('.g.dart') => {'ignore_for_file: type=lint'},
          'lib/src/data/p2p_database.steps.dart' => {
            'ignore_for_file: type=lint, unused_import',
          },
          _ => const <String>{},
        };
        for (final ignore in ignores) {
          if (!allowed.contains(ignore)) offenders.add('$path $ignore');
        }
      }
      expect(offenders, isEmpty);
      // The one `ignore` of the database sits right before the table migration, so that it silences nothing else.
      final database = File('lib/src/data/p2p_database.dart').readAsLinesSync();
      final line = database.indexWhere((l) => l.contains('ignore:'));
      expect(
        database[line + 1].trim(),
        'TableMigration(schema.garageKeyHistories),',
      );
      // The check sees each form.
      // The diagnostic's name is put together at run time: the custody check of CI refuses it written after an `ignore` anywhere, the samples of a test included.
      final internal = ['invalid', 'use', 'of', 'internal', 'member'].join('_');
      expect(
        _ignores(
          '// ignore: $internal\n'
          'x; // ignore:$internal, unused_import\n'
          '/* ignore_for_file: type=warning */\n'
          '// ignore_for_file: type=lint\n',
        ),
        [
          'ignore: $internal',
          'ignore: $internal, unused_import',
          'ignore_for_file: type=warning',
          'ignore_for_file: type=lint',
        ],
      );
    },
  );

  group('resolved by the analyzer,', () {
    late AnalysisContextCollection collection;
    // What each scanned library refers to, by its path.
    late Map<String, Set<String>> references;
    // What the robot panel's file refers to, by its top-level declaration.
    late Map<String, Set<String>> panelDeclarations;

    setUpAll(() async {
      collection = AnalysisContextCollection(
        includedPaths: [Directory.current.path],
        sdkPath: _dartSdkPath(),
      );
      references = {
        for (final path in libraries.keys)
          path: (await _referencesIn(
            collection,
            path,
          )).values.fold(<String>{}, (all, found) => all..addAll(found)),
      };
      panelDeclarations = await _referencesIn(collection, _panel);
    });

    Set<String> referring(bool Function(String reference) test) => {
      for (final MapEntry(key: path, value: found) in references.entries)
        if (found.any(test)) path,
    };

    test(
      'the evasions of a check by names are seen, each where it is',
      () async {
        final found = await _referencesIn(
          collection,
          'test/fixtures/robot_request_makers.dart',
        );
        expect(
          {
            for (final MapEntry(key: declaration, value: references)
                in found.entries)
              declaration: references
                  .where((r) => !r.startsWith('type '))
                  .toSet(),
          }..removeWhere((_, references) => references.isEmpty),
          {
            'fetchByTearOff': {'request CoordinatorClient.fetchKnownRobot'},
            'fetchInCascade': {'request CoordinatorClient.fetchRobot'},
            // An extension on a watched class is reported as such (security review of step 6).
            'ReviewPeek': {
              'extension on CoordinatorClient',
              'request CoordinatorClient.fetchKnownRobot',
            },
            'headerByTearOff': {'credential RobotIdentity.authorizationHeader'},
            'firstContactByTearOff': {
              'credential RobotIdentity.firstContactAuthorizationHeader',
            },
            'rawRequest': {
              'network package:dio/',
              'credential RobotIdentity.tokenSha256Base91',
            },
            'credentials': {
              'credential RobotIdentity.token',
              'credential RobotIdentity.tokenSha256Hex',
              'credential RobotToken.reveal',
            },
            'dynamicCall': {'dynamic fetchKnownRobot'},
            'rawHttpClient': {'network HttpClient'},
            'rawWebSocket': {'network WebSocket'},
            'rawSocket': {'network Socket'},
            'rawProcess': {'network Process'},
            'sendRaw': {'CoordinatorTransport.send'},
            'bindByTearOff': {'RobotBindingRepository.bind'},
            'acknowledgeByTearOff': {
              'RobotBindingRepository.recordAcknowledgedKey',
            },
            'acknowledgeUseCaseByTearOff': {
              'AcknowledgeGarageKeyHistoryUsecase.execute',
            },
            'AcknowledgeWrapper': {
              'extension on RobotCoordinatorCubit',
              'RobotCoordinatorCubit.acknowledge',
            },
            'acknowledgeInVariable': {'RobotCoordinatorCubit.acknowledge'},
            'proveByTearOff': {'UnprovenCoordinatorRobot.prove'},
            'generateByTearOff': {'RobotPgpKey.generate'},
            'fetchByUseCaseTearOff': {'FetchRobotUsecase.execute'},
            'closeByPort': {'CoordinatorSessionsPort.closeRobotSessions'},
            'firstContactOutsidePut': {'RobotContact.firstContact'},
            'reserveByTearOff': {'TradeRecordRepository.reserveForNewTrade'},
            'pendingTakeInClosure': {'TradeRecordRepository.recordPendingTake'},
            'recoveredTradeInVariable': {
              'TradeRecordRepository.recordRecoveredTrade',
            },
          },
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'only the two robot use cases send a robot request, through the use case that binds',
      () {
        // `FetchRobotUsecase` binds and checks a robot before each request; the robot use cases add the places, the retries after a busy answer and the 7004 rules of `RobotRequestLimiter`, which no other file may go around.
        expect(referring((r) => r == 'FetchRobotUsecase.execute'), {
          'lib/src/domain/usecases/put_robot_on_coordinator_usecase.dart',
          'lib/src/domain/usecases/read_robot_on_coordinator_usecase.dart',
        });
        // Its own file and the composition, which builds it, name it too.
        expect(referring((r) => r == 'type FetchRobotUsecase'), {
          'lib/src/domain/usecases/fetch_robot_usecase.dart',
          'lib/src/domain/usecases/put_robot_on_coordinator_usecase.dart',
          'lib/src/domain/usecases/read_robot_on_coordinator_usecase.dart',
          'lib/src/p2p_locator.dart',
        });
      },
    );

    test(
      'only the release of a robot closes its sessions, once its requests have ended',
      () {
        // Closing the sessions of a robot is not a lock: a call still running may open a new session after it, which the release waits for (`CoordinatorSessionsPort.closeRobotSessions`).
        expect(referring((r) => r == 'CloseRobotSessionsUsecase.execute'), {
          'lib/src/domain/usecases/release_robot_usecase.dart',
        });
        // Nor does any other file reach the port's own close of a robot's sessions (review of step 3).
        expect(
          referring((r) => r == 'CoordinatorSessionsPort.closeRobotSessions'),
          {'lib/src/domain/usecases/close_robot_sessions_usecase.dart'},
        );
      },
    );

    test('only the use case that puts a robot makes a first contact', () {
      // A first contact sends a key pair and may create the robot: it is made only on the user's request, with the read before it and the cap of 7004 refusals of that use case.
      expect(referring((r) => r == 'RobotContact.firstContact'), {
        'lib/src/domain/usecases/put_robot_on_coordinator_usecase.dart',
      });
    });

    test(
      'the feature never names a robot\'s token: the proof is the package\'s',
      () {
        expect(
          referring((r) => r == 'credential RobotIdentity.token'),
          isEmpty,
        );
      },
    );

    test('only the use case that binds a robot requests one, or binds', () {
      // Every member of `CoordinatorClient` that takes a robot's identity or token, whatever its name: the requests of later tickets are watched too.
      expect(referring((r) => r.startsWith('request ')), {
        'lib/src/domain/usecases/fetch_robot_usecase.dart',
      });
      expect(referring((r) => r == 'RobotBindingRepository.bind'), {
        'lib/src/domain/usecases/fetch_robot_usecase.dart',
      });
      expect(referring((r) => r == 'CoordinatorTransport.send'), isEmpty);
    });

    test(
      'only the robot layer reserves a robot for a new trade, and only the take and the recovery write a trade',
      () {
        // A reservation binds a robot for good: only the robot layer, which returns the robot it reserved, makes one (#85).
        expect(
          referring((r) => r == 'TradeRecordRepository.reserveForNewTrade'),
          {'lib/src/domain/interim_trade_robots.dart'},
        );
        // A record of origin `takenHere` comes only from the take use case, and one of origin `recovered` only from the user's take-over: no file of this pull request writes either (#87, #79).
        expect(
          referring(
            (r) => r == 'TradeRecordRepository.recordPendingTake',
          ).difference({_takeOrderUseCase}),
          isEmpty,
        );
        expect(
          referring(
            (r) => r == 'TradeRecordRepository.recordRecoveredTrade',
          ).difference({_recoverTradeUseCase}),
          isEmpty,
        );
        // The state of a record follows what the coordinator says: only the trade use cases change it.
        for (final member in [
          'TradeRecordRepository.confirmTake',
          'TradeRecordRepository.closeTrade',
        ]) {
          expect(
            referring((r) => r == member),
            everyElement(startsWith(_tradeUseCases)),
            reason: member,
          );
        }
        // The records are reached through their repository only: its interface, its implementation, the robot layer, and later the composition and the trade use cases.
        final holders = referring((r) => r == 'type TradeRecordRepository');
        expect(
          holders,
          containsAll([
            'lib/src/data/trade_record_repository_impl.dart',
            'lib/src/domain/interim_trade_robots.dart',
          ]),
        );
        expect(
          holders.where(
            (path) =>
                !path.startsWith(_tradeUseCases) &&
                !{
                  'lib/src/domain/repositories/trade_record_repository.dart',
                  'lib/src/data/trade_record_repository_impl.dart',
                  'lib/src/domain/interim_trade_robots.dart',
                  'lib/src/p2p_locator.dart',
                }.contains(path),
          ),
          isEmpty,
        );
      },
    );

    test(
      'only the key work in its own isolate proves a robot, or makes or unlocks a pair',
      () {
        // Each hashes 32 MiB or more: on the UI isolate, the screens would freeze.
        expect(referring((r) => r == 'UnprovenCoordinatorRobot.prove'), {
          'lib/src/data/isolate_robot_key_compute.dart',
        });
        expect(
          referring(
            (r) =>
                r == 'RobotPgpKey.generate' || r == 'RobotPgpKey.generateWith',
          ),
          {'lib/src/data/isolate_robot_key_compute.dart'},
        );
        // Nothing of the feature unlocks a robot's key yet: the proof wipes what it unlocks.
        expect(referring((r) => r == 'RobotPgpKey.unlock'), isEmpty);
      },
    );

    test('no file reaches the package\'s internal proof or reads an answer', () {
      // `proveMadeBy` proves on the calling isolate, and `parse` with a pair as « sent » makes a robot that carries any pair, without a request or a proof (review of #67): only an `invalid_use_of_internal_member` warning stands in their way, and no file may silence it.
      // The fixture of evasions cannot hold such calls: the custody check of CI refuses an `ignore` of that warning anywhere, tests included.
      expect(
        referring(
          (r) => {
            'RobotPgpKey.proveMadeBy',
            'CoordinatorRobotAnswer.parse',
            'UnprovenCoordinatorRobot.parse',
          }.contains(r),
        ),
        isEmpty,
      );
    });

    test('no file reads a robot credential, but the fingerprint its token', () {
      // The fingerprint keys an HMAC with the token of the key's first robot, which never leaves the device.
      expect(referring((r) => r == 'credential RobotToken.reveal'), {
        'lib/src/domain/garage_key_fingerprint.dart',
      });
      // The token hash, the token and the headers made of them: the coordinator client of `package:robosats` builds them for the use case, and no file of the feature reads them.
      expect(
        referring(
          (r) =>
              r.startsWith('credential ') &&
              r != 'credential RobotToken.reveal',
        ),
        isEmpty,
      );
    });

    test('only the transport holds a raw network client', () {
      expect(
        referring(
          (r) =>
              r.startsWith('network ') && r != 'network TorHttpClientFactory',
        ),
        {'lib/src/data/tor_coordinator_transport.dart'},
      );
      // The locator reads the factory from the shell's container and hands it to the transport.
      expect(referring((r) => r == 'network TorHttpClientFactory'), {
        'lib/src/data/tor_coordinator_transport.dart',
        'lib/src/p2p_locator.dart',
      });
    });

    test('nothing is reached through dynamic', () {
      expect(referring((r) => r.startsWith('dynamic ')), isEmpty);
    });

    test(
      'only the draw and the import write a key, and record its history',
      () {
        expect(referring((r) => r == 'GarageKeyRepository.create'), {
          'lib/src/domain/usecases/generate_garage_key_usecase.dart',
        });
        expect(
          referring((r) => r == 'RobotBindingRepository.recordGeneratedKey'),
          {'lib/src/domain/usecases/generate_garage_key_usecase.dart'},
        );
        expect(referring((r) => r == 'GarageKeyRepository.import'), {
          'lib/src/domain/usecases/import_garage_key_usecase.dart',
        });
        expect(
          referring((r) => r == 'RobotBindingRepository.recordImportedKey'),
          {'lib/src/domain/usecases/import_garage_key_usecase.dart'},
        );
        // And only the repository asks the vault to write one.
        for (final member in ['GarageKeys.create', 'GarageKeys.import']) {
          expect(referring((r) => r == member), {
            'lib/src/data/garage_key_repository_impl.dart',
          }, reason: member);
        }
      },
    );

    test('only the acknowledgement of the user records a key as acknowledged', () {
      // It lets the robots of a key of unknown history be bound: no other path may write it on the user's behalf.
      expect(
        referring((r) => r == 'RobotBindingRepository.recordAcknowledgedKey'),
        {'lib/src/domain/usecases/acknowledge_garage_key_history_usecase.dart'},
      );
      // That use case is called by the robot panel's cubit alone, which the panel asks only on « I understand » of « Robots from elsewhere » (#29, step 6): nothing records it at an import, a draw, a display, a migration or in the test seam.
      expect(
        referring((r) => r == 'AcknowledgeGarageKeyHistoryUsecase.execute'),
        {'lib/src/presentation/robot_coordinator_cubit.dart'},
      );
      expect(referring((r) => r == 'RobotCoordinatorCubit.acknowledge'), {
        'lib/src/ui/garage/robot_coordinator_panel.dart',
      });
      // Its own file, the cubit and the composition, which builds it, name it; nothing else holds one.
      expect(referring((r) => r == 'type AcknowledgeGarageKeyHistoryUsecase'), {
        'lib/src/domain/usecases/acknowledge_garage_key_history_usecase.dart',
        'lib/src/presentation/robot_coordinator_cubit.dart',
        'lib/src/p2p_locator.dart',
      });
    });

    test(
      'only the robot panel calls the robot use cases, and reaches nothing behind them',
      () {
        // A robot reaches a coordinator from a screen only through the panel's cubit, which the user drives: « Select Host », then « Continue ».
        const cubit = 'lib/src/presentation/robot_coordinator_cubit.dart';
        for (final member in [
          'PutRobotOnCoordinatorUsecase.execute',
          'ReadRobotOnCoordinatorUsecase.execute',
          'ReleaseRobotUsecase.execute',
        ]) {
          expect(referring((r) => r == member), {cubit}, reason: member);
        }
        // The cubit, its states and every widget reach a robot request only through those use cases: never the use case that binds, the coordinator client, the limiter, the bindings, the database, a credential or a raw client.
        final panel = [
          for (final path in references.keys)
            if (path == cubit ||
                path == 'lib/src/presentation/robot_coordinator_state.dart' ||
                path.startsWith('lib/src/ui/'))
              path,
        ];
        expect(
          panel,
          containsAll([
            cubit,
            'lib/src/ui/garage/robot_coordinator_panel.dart',
            'lib/src/ui/garage/robot_history_dialog.dart',
            'lib/src/ui/garage/select_host_sheet.dart',
            'lib/src/ui/garage/send_robot_dialog.dart',
          ]),
        );
        for (final path in panel) {
          final found = references[path] ?? const <String>{};
          expect(
            found.where(
              (r) =>
                  r.startsWith('request ') ||
                  r.startsWith('credential ') ||
                  r.startsWith('network ') ||
                  r.startsWith('dynamic ') ||
                  r.startsWith('FetchRobotUsecase.') ||
                  r.startsWith('RobotBindingRepository.') ||
                  r.startsWith('TradeRecordRepository.') ||
                  {
                    'type FetchRobotUsecase',
                    'type CoordinatorClient',
                    'type RobotRequestLimiter',
                    'type RobotBindingRepository',
                    'type TradeRecordRepository',
                    'type P2pDatabase',
                  }.contains(r),
            ),
            isEmpty,
            reason: path,
          );
        }
      },
    );

    test(
      'only the panel asks the robot cubit for a first contact or a retry',
      () {
        // « Select Host » and « Continue », and « Retry »: the user's own taps, on the robot shown (security review of step 5).
        for (final member in [
          'RobotCoordinatorCubit.putOn',
          'RobotCoordinatorCubit.retry',
        ]) {
          expect(referring((r) => r == member), {
            'lib/src/ui/garage/robot_coordinator_panel.dart',
          }, reason: member);
        }
      },
    );

    test(
      'the robot cubit\'s actions are reached from the panel\'s own widgets only, and nothing wraps them',
      () {
        // The pins above go by name: a wrapper of the panel's file (an extension, a top-level function or variable) called from another file, or an extension elsewhere, would go around them (security review of step 6).
        const actions = {
          'RobotCoordinatorCubit.putOn',
          'RobotCoordinatorCubit.retry',
          'RobotCoordinatorCubit.acknowledge',
        };
        expect(
          {
            for (final MapEntry(key: declaration, value: found)
                in panelDeclarations.entries)
              if (found.any(actions.contains)) declaration,
          },
          {'_RobotCoordinatorPanelState', '_OnCoordinator'},
        );
        expect(referring((r) => r.startsWith('extension on ')), isEmpty);
      },
    );

    test('deleting a key cannot reach the bindings', () {
      expect(
        references['lib/src/domain/usecases/delete_garage_key_usecase.dart'],
        isNot(
          anyOf(
            contains('type RobotBindingRepository'),
            contains('RobotBindingRepository.bind'),
          ),
        ),
      );
    });
  });

  test('the robot cubit\'s public surface is exactly what the panel uses', () {
    // A public member of the cubit is a way to its use cases: one more, wrapping the acknowledgement or a request, fails here before any review, as the custody gate pins the surfaces of the Garage Key's readers (security review of step 6).
    final unit = parseString(
      content: File(
        'lib/src/presentation/robot_coordinator_cubit.dart',
      ).readAsStringSync(),
    ).unit;
    expect(
      unit.directives.where((d) => d is PartDirective || d is PartOfDirective),
      isEmpty,
    );
    expect(
      [
        for (final declaration in unit.declarations)
          switch (declaration) {
            ClassDeclaration(:final namePart) => namePart.typeName.lexeme,
            GenericTypeAlias(:final name) => name.lexeme,
            _ => declaration.toSource(),
          },
      ].where((name) => !name.startsWith('_')),
      ['RobotCoordinatorCubit'],
    );
    expect(
      _publicSurface(unit.declarations.whereType<ClassDeclaration>().single),
      [
        'field static const stillWaitingAfter',
        'constructor RobotCoordinatorCubit(this._key, this._index, this._readStanding, this._putOnCoordinator, this._readOnCoordinator, this._release, this._watchTor, this._listHosts, this._acknowledge, {this._stillWaitingAfter = RobotCoordinatorCubit.stillWaitingAfter})',
        'method Future<void> load()',
        'method List<RobotHost> hosts()',
        'method Future<void> putOn(Coordinator coordinator)',
        'method Future<void> acknowledge()',
        'method Future<void> retry()',
        'method Future<void> close()',
      ],
    );
    // The check sees a wrapper method, a public field and a named constructor.
    expect(
      _publicSurface(
        parseString(
              content: '''
class RobotCoordinatorCubit {
  final Object _acknowledge;
  RobotCoordinatorCubit(this._acknowledge);
  RobotCoordinatorCubit.other(this._acknowledge);
  final Object leak = 0;
  Future<void> wrapped() async => _acknowledge;
  void _private() {}
}
''',
            ).unit.declarations.single
            as ClassDeclaration,
      ),
      [
        'constructor RobotCoordinatorCubit(this._acknowledge)',
        'constructor RobotCoordinatorCubit.other(this._acknowledge)',
        'field final leak',
        'method Future<void> wrapped()',
      ],
    );
  });

  test('only the data layer and the composition reach the database', () {
    expect(
      where(
        (facts) =>
            facts.imports.any((uri) => uri.endsWith('p2p_database.dart')),
      ),
      {
        'lib/src/data/robot_binding_repository_impl.dart',
        'lib/src/data/trade_record_repository_impl.dart',
        'lib/src/p2p_locator.dart',
        'lib/testing.dart',
      },
    );
    expect(
      where(
        (facts) => facts.imports.any((uri) => uri.startsWith('package:drift')),
      ),
      {
        'lib/src/data/p2p_database.dart',
        // The tables of the database, apart so that `trades.drift` can import them.
        'lib/src/data/p2p_tables.dart',
        // The migration steps `make drift-migrations` writes from the snapshots.
        'lib/src/data/p2p_database.steps.dart',
        'lib/src/data/robot_binding_repository_impl.dart',
        'lib/src/data/trade_record_repository_impl.dart',
        'lib/testing.dart',
      },
    );
    expect(
      where(
        (facts) =>
            facts.imports.any((uri) => uri.endsWith('p2p_database.steps.dart')),
      ),
      {'lib/src/data/p2p_database.dart'},
    );
    expect(where((facts) => facts.constructed.contains('P2pDatabase.open')), {
      'lib/src/p2p_locator.dart',
    });
    expect(
      where((facts) => facts.constructed.contains('P2pDatabase.forTesting')),
      {'lib/testing.dart'},
    );
    // The trade records' implementation is made by the composition only, when a pull request registers it.
    expect(
      where(
        (facts) => facts.constructed.contains('TradeRecordRepositoryImpl'),
      ).difference({'lib/src/p2p_locator.dart'}),
      isEmpty,
    );
    // And the table of the trades is named by its repository, the database and drift's code only.
    expect(where((facts) => facts.names.contains('trades')), {
      'lib/src/data/p2p_database.dart',
      'lib/src/data/p2p_database.steps.dart',
      'lib/src/data/trade_record_repository_impl.dart',
      if (File('lib/src/data/p2p_database.g.dart').existsSync())
        'lib/src/data/p2p_database.g.dart',
    });
    // No SQL text of another file reads or writes the trades, but the triggers as drift copies them.
    expect(
      where(
        (facts) => facts.strings.any(
          (text) =>
              RegExp(
                r'\b(from|into|update|join)\s+"?trades\b',
                caseSensitive: false,
              ).hasMatch(text) &&
              !_tradeTriggers.contains(_squeezed(text)),
        ),
      ),
      {'lib/src/data/trade_record_repository_impl.dart'},
    );
  });

  test('nothing changes or deletes a binding', () {
    final repository =
        libraries['lib/src/data/robot_binding_repository_impl.dart'] ??
        fail('no repository');
    final database =
        libraries['lib/src/data/p2p_database.dart'] ?? fail('no database');
    final steps =
        libraries['lib/src/data/p2p_database.steps.dart'] ??
        fail('no migration steps');
    final tables =
        libraries['lib/src/data/p2p_tables.dart'] ?? fail('no tables');

    for (final (facts, allowed) in [
      (repository, const <String>{}),
      // The database turns its foreign keys on at each opening, with the one statement pinned below.
      (database, const {'customStatement'}),
      (steps, const <String>{}),
      (tables, const <String>{}),
    ]) {
      expect(
        facts.invoked.difference(allowed).intersection({
          'delete',
          'deleteWhere',
          'deleteAll',
          'update',
          'replace',
          'write',
          'customUpdate',
          'customStatement',
          'insertOnConflictUpdate',
          'insertAllOnConflictUpdate',
          'deleteTable',
          'drop',
          // A column of the bindings dropped or renamed, or the table renamed, would lose what a binding records (review of #72).
          'dropColumn',
          'renameColumn',
          'renameTable',
        }),
        isEmpty,
      );
      expect(facts.names, isNot(contains('InsertMode')));
      for (final text in facts.strings) {
        // The steps hold the triggers of `trades.drift` as written, which name an update and a delete only to refuse them (pinned below).
        if (identical(facts, steps) &&
            _tradeTriggers.contains(_squeezed(text))) {
          continue;
        }
        expect(
          RegExp(
            r'\b(delete|update|drop|replace|alter)\b',
            caseSensitive: false,
          ).hasMatch(text),
          isFalse,
          reason: text,
        );
      }
    }
    // The two upserts move the history of a key, to `imported` or to `acknowledged`, never a binding.
    expect(
      repository.namesByMethod.entries
          .where((entry) => entry.value.contains('DoUpdate'))
          .map((entry) => entry.key),
      ['recordImportedKey', 'recordAcknowledgedKey'],
    );
    // The migration rebuilds the histories only: the bindings gain a column, and no binding is copied or dropped.
    expect(database.calls.where((call) => call.startsWith('TableMigration(')), [
      'TableMigration(schema.garageKeyHistories)',
    ]);
    expect(
      database.calls.where((call) => call.startsWith('alterTable(')),
      everyElement(isNot(contains('robotBindings'))),
    );
    expect(database.calls.where((call) => call.startsWith('addColumn(')), [
      'addColumn(schema.robotBindings, schema.robotBindings.provenance)',
    ]);
    // Every call of the migrator, in order: nothing else changes a table; schema 3 adds the table of the trades, the unique index its foreign key needs on the bindings, and its two triggers.
    expect(database.qualifiedCalls.where((call) => call.startsWith('m.')), [
      'm.alterTable(TableMigration(schema.garageKeyHistories))',
      'm.addColumn(schema.robotBindings, schema.robotBindings.provenance)',
      'm.createTable(schema.trades)',
      'm.createIndex(schema.robotBindingsNetwork)',
      'm.createTrigger(schema.tradesNeverDeleted)',
      'm.createTrigger(schema.tradesSetOnce)',
      'm.createTrigger(schema.tradesInsertedOnce)',
    ]);
    // The one `customStatement` the database runs itself: the foreign keys of the trades, on, at each opening.
    expect(
      database.calls.where((call) => call.startsWith('customStatement(')),
      ['customStatement(_foreignKeysOn)'],
    );
    expect(database.constants['_foreignKeysOn'], 'PRAGMA foreign_keys = ON');
    // Its one `customSelect`, the step's look at a column, and its pragmas as written: no other statement could turn the foreign keys off (review of #102).
    expect(database.calls.where((call) => call.startsWith('customSelect(')), [
      startsWith(
        "customSelect('SELECT 1 FROM pragma_table_info(?) WHERE name = ?',",
      ),
    ]);
    expect(
      database.strings.where(
        (text) => RegExp(r'\bpragma\b', caseSensitive: false).hasMatch(text),
      ),
      [
        'PRAGMA foreign_keys = ON',
        // The setup of the app's connection, before any statement.
        'PRAGMA busy_timeout = 2000;',
        'PRAGMA journal_mode = WAL;',
        'PRAGMA synchronous = FULL;',
      ],
    );
    // The database's own rules on the trades, as written in `trades.drift`: the parent key of their foreign key, and the triggers that refuse a delete and any change but the two times set once.
    expect(
      _drifted(File('lib/src/data/trades.drift').readAsStringSync()),
      '${_tradeRules.join(';')};',
    );
  });

  test('nothing in the feature opens a database transaction', () {
    // A reservation or a pending take that answered success inside a transaction is undone by its rollback, after its robot may have been sent: it could then go to a second coordinator (review of #102, R1).
    // By name, so that a torn-off `transaction` counts as a call (second review of #102).
    bool opensOne(_Facts facts) => facts.names.any(
      {'transaction', 'beginTransaction', 'TransactionExecutor'}.contains,
    );
    expect(where(opensOne), isEmpty);
    // The check sees a call, a tear-off and the lower-level way in.
    for (final source in [
      'Future<void> f(GeneratedDatabase d) => d.transaction(() async {});',
      'Future<void> f(GeneratedDatabase d) { final run = d.transaction; return run(() async {}); }',
      'Object f(QueryExecutor e) => e.beginTransaction();',
      'Object f(TransactionExecutor e) => e;',
    ]) {
      expect(opensOne(_Facts.of(source)), isTrue, reason: source);
    }
  });

  test('a trade record is changed only by its two changes, and never deleted', () {
    // A record is written before the take's request and kept: only a pending take turns taken or closed, and a taken trade closed, each time set once (#85, design note § 3.5, § 4.5).
    final trades =
        libraries['lib/src/data/trade_record_repository_impl.dart'] ??
        fail('no trade records');
    expect(
      trades.invoked.intersection({
        'delete',
        'deleteWhere',
        'deleteAll',
        'update',
        'replace',
        'write',
        'into',
        'batch',
        'customInsert',
        'customStatement',
        'insertOnConflictUpdate',
        'insertAllOnConflictUpdate',
        'deleteTable',
        'drop',
        'dropColumn',
        'renameColumn',
        'renameTable',
        'alterTable',
      }),
      isEmpty,
    );
    expect(trades.names, isNot(contains('InsertMode')));
    expect(trades.names, isNot(contains('DoUpdate')));
    for (final text in trades.strings) {
      expect(
        RegExp(
          r'\b(delete|drop|replace|alter|pragma)\b',
          caseSensitive: false,
        ).hasMatch(text),
        isFalse,
        reason: text,
      );
    }
    // Its only SQL that changes a row: the two changes of a record, on the trades, each setting one time that is still unset.
    final confirm = trades.constants['_confirmSql'] ?? fail('no _confirmSql');
    final close = trades.constants['_closeSql'] ?? fail('no _closeSql');
    expect(
      confirm,
      'UPDATE trades SET confirmed_at = ? WHERE key_fingerprint = ? '
      'AND robot_index = ? AND network = ? AND order_id = ? AND origin = ? '
      'AND confirmed_at IS NULL AND closed_at IS NULL',
    );
    expect(
      close,
      'UPDATE trades SET closed_at = ? WHERE key_fingerprint = ? '
      'AND robot_index = ? AND network = ? AND order_id = ? AND origin = ? '
      'AND closed_at IS NULL',
    );
    expect(
      trades.strings.where(
        (text) =>
            RegExp(r'\bupdate\b', caseSensitive: false).hasMatch(text) &&
            !confirm.contains(text) &&
            !close.contains(text),
      ),
      isEmpty,
    );
    // Run by one helper, from the two methods that name them.
    expect(
      trades.calls.where((call) => call.startsWith('customUpdate(')),
      hasLength(1),
    );
    expect(
      trades.callsByMethod['_change']?.where(
        (call) => call.startsWith('customUpdate(sql,'),
      ),
      hasLength(1),
    );
    expect(trades.calls.where((call) => call.startsWith('_change(')), [
      '_change(_confirmSql, record)',
      '_change(_closeSql, record)',
    ]);
    expect(
      trades.callsByMethod['confirmTake'],
      contains('_change(_confirmSql, record)'),
    );
    expect(trades.callsByMethod['closeTrade'], ['_change(_closeSql, record)']);
    // No other file of the feature holds SQL that changes or deletes a trade, but the triggers that refuse it, as drift copies them.
    expect(
      where(
        (facts) => facts.strings.any(
          (text) =>
              RegExp(
                r'\b(update|delete)\b[^;]*\btrades\b',
                caseSensitive: false,
              ).hasMatch(text) &&
              !_tradeTriggers.contains(_squeezed(text)),
        ),
      ),
      {'lib/src/data/trade_record_repository_impl.dart'},
    );
  });

  test(
    'a robot is reserved, and a trade written, by one statement each that reads what decides it',
    () {
      // Each write reads in the same statement the history of the key, the robot's binding and its record: a read followed by a write would let another connection's write land in between (#85).
      final trades =
          libraries['lib/src/data/trade_record_repository_impl.dart'] ??
          fail('no trade records');
      final writes = trades.calls.where(
        (call) => call.startsWith('customWriteReturning('),
      );
      expect(writes, hasLength(3));
      for (final (method, statement) in [
        ('reserveForNewTrade', '_reserveSql'),
        ('recordPendingTake', '_recordPendingTakeSql'),
        ('recordRecoveredTrade', '_recordRecoveredTradeSql'),
      ]) {
        expect(
          trades.callsByMethod[method]?.where(
            (call) => call.startsWith('customWriteReturning('),
          ),
          [startsWith('customWriteReturning($statement,')],
          reason: method,
        );
      }
      // The statements, as written: the reservation binds only a free index of a key drawn here and nothing else anywhere, with no trade; a pending take is `takenHere` and needs a binding drawn here on the reservation's network to that coordinator, under a key still recorded as drawn here only; a recovered trade is `recovered`, confirmed at once, and needs a binding to that coordinator.
      expect(
        trades.constants['_reserveSql'],
        'INSERT INTO robot_bindings (network, key_fingerprint, robot_index, '
        'coordinator_alias, coordinator_onion, coordinator_node_keys, '
        'coordinator_nostr_key, bound_at, provenance) '
        'SELECT ?, ?, ?, ?, ?, ?, ?, ?, origin FROM garage_key_histories '
        'WHERE network = ? AND key_fingerprint = ? AND origin = ? '
        'AND NOT EXISTS (SELECT 1 FROM garage_key_histories '
        'WHERE key_fingerprint = ? AND origin <> ?) '
        'AND NOT EXISTS (SELECT 1 FROM trades '
        'WHERE key_fingerprint = ? AND robot_index = ?) '
        'ON CONFLICT (key_fingerprint, robot_index) DO NOTHING '
        'RETURNING robot_index',
      );
      expect(
        trades.constants['_recordPendingTakeSql'],
        'INSERT INTO trades (network, key_fingerprint, robot_index, '
        'coordinator_alias, coordinator_onion, order_id, role, origin, '
        'taken_at, confirmed_at, closed_at) '
        "SELECT network, key_fingerprint, robot_index, coordinator_alias, "
        "coordinator_onion, ?, ?, 'takenHere', ?, NULL, NULL "
        'FROM robot_bindings WHERE key_fingerprint = ? AND robot_index = ? '
        'AND network = ? AND provenance = ? AND coordinator_alias = ? '
        'AND coordinator_onion = ? AND coordinator_node_keys = ? '
        'AND coordinator_nostr_key = ? '
        'AND NOT EXISTS (SELECT 1 FROM garage_key_histories '
        'WHERE key_fingerprint = ? AND origin <> ?) '
        'ON CONFLICT (key_fingerprint, robot_index) DO NOTHING '
        'RETURNING *',
      );
      expect(
        trades.constants['_recordRecoveredTradeSql'],
        'INSERT INTO trades (network, key_fingerprint, robot_index, '
        'coordinator_alias, coordinator_onion, order_id, role, origin, '
        'taken_at, confirmed_at, closed_at) '
        "SELECT network, key_fingerprint, robot_index, coordinator_alias, "
        "coordinator_onion, ?, ?, 'recovered', ?, ?, NULL "
        'FROM robot_bindings WHERE key_fingerprint = ? AND robot_index = ? '
        'AND network = ? AND coordinator_alias = ? '
        'AND coordinator_onion = ? AND coordinator_node_keys = ? '
        'AND coordinator_nostr_key = ? '
        'ON CONFLICT (key_fingerprint, robot_index) DO NOTHING '
        'RETURNING *',
      );
      final pinned = [
        for (final name in [
          '_reserveSql',
          '_recordPendingTakeSql',
          '_recordRecoveredTradeSql',
        ])
          trades.constants[name] ?? fail('no $name'),
      ];
      // No other SQL text inserts, and an origin is written by its own statement only.
      expect(
        trades.strings.where(
          (text) =>
              RegExp(r'\binsert\b', caseSensitive: false).hasMatch(text) &&
              !pinned.any((statement) => statement.contains(text)),
        ),
        isEmpty,
      );
      expect(
        trades.strings.where((text) => text.contains("'takenHere'")),
        everyElement(predicate<String>((text) => pinned[1].contains(text))),
      );
      expect(
        trades.strings.where((text) => text.contains("'recovered'")),
        everyElement(predicate<String>((text) => pinned[2].contains(text))),
      );
      // And no other file of the feature inserts into the bindings or the trades but the two repositories.
      expect(
        where(
          (facts) => facts.strings.any(
            (text) => RegExp(
              r'\binsert\s+into\s+(robot_bindings|trades)\b',
              caseSensitive: false,
            ).hasMatch(text),
          ),
        ),
        {
          'lib/src/data/robot_binding_repository_impl.dart',
          'lib/src/data/trade_record_repository_impl.dart',
        },
      );
    },
  );

  test('a robot is bound by one statement that reads the history itself', () {
    // The binding may be written only while the key's history allows it: a read of the history followed by a write would let an import of the key, from another connection, land in between (review of #72).
    // The tests of binds at once check the order of their results, not this: these pins guard that the check and the write are one statement.
    final repository =
        libraries['lib/src/data/robot_binding_repository_impl.dart'] ??
        fail('no repository');
    final bind = repository.callsByMethod['bind'] ?? fail('no bind');

    expect(
      bind.where((call) => call.startsWith('customInsert(')),
      hasLength(1),
    );
    expect(
      bind.where((call) => call.startsWith('customInsert(_bindIfFreshSql,')),
      hasLength(1),
    );
    expect(bind.where((call) => call.startsWith('customSelect(')), isEmpty);
    // Across the whole file too: a helper that read the history and wrote the binding, the pinned insert left unused in `bind`, passed a check of `bind` alone (second review of #72).
    expect(
      repository.calls.where((call) => call.startsWith('customInsert(')),
      hasLength(1),
    );
    expect(
      repository.calls.where(
        (call) => call.startsWith('customInsert(_bindIfFreshSql,'),
      ),
      hasLength(1),
    );
    // The table of the bindings is handed to its reads and to that insert only: no typed insert, batch or other write.
    expect(
      repository.calls.where(
        (call) =>
            call.contains('robotBindings') &&
            !RegExp(r'^(select|customSelect|customInsert)\(').hasMatch(call),
      ),
      isEmpty,
    );
    // And no SQL text inserts but the pinned one.
    final pinned =
        repository.constants['_bindIfFreshSql'] ?? fail('no _bindIfFreshSql');
    expect(
      repository.strings.where(
        (text) =>
            RegExp(r'\binsert\b', caseSensitive: false).hasMatch(text) &&
            !pinned.contains(text),
      ),
      isEmpty,
    );
    expect(
      repository.namesByMethod['bind'],
      isNot(contains('garageKeyHistories')),
    );
    expect(
      repository.constants['_bindIfFreshSql'],
      'INSERT INTO robot_bindings (network, key_fingerprint, robot_index, '
      'coordinator_alias, coordinator_onion, coordinator_node_keys, '
      'coordinator_nostr_key, bound_at, provenance) '
      'SELECT ?, ?, ?, ?, ?, ?, ?, ?, origin FROM garage_key_histories '
      'WHERE network = ? AND key_fingerprint = ? AND origin IN (?, ?) '
      'ON CONFLICT (key_fingerprint, robot_index) DO NOTHING',
    );
  });
}

/// What one library imports, names, invokes, constructs and spells out in strings.
final class _Facts {
  final List<String> imports;
  final Set<String> names;
  final Set<String> invoked;
  final Set<String> constructed;
  final List<String> strings;

  /// The names used in the body of each method or function, by its name.
  final Map<String, Set<String>> namesByMethod;

  /// Each invocation, as its name and its arguments, `name(a, b)`.
  final List<String> calls;

  /// The invocations in the body of each method or function, by its name, as [calls] gives them.
  final Map<String, List<String>> callsByMethod;

  /// Each invocation on a simple name, as `target.name(a, b)`.
  final List<String> qualifiedCalls;

  /// The text of each variable initialised with a string literal, by its name.
  final Map<String, String> constants;

  _Facts(
    this.imports,
    this.names,
    this.invoked,
    this.constructed,
    this.strings,
    this.namesByMethod,
    this.calls,
    this.callsByMethod,
    this.qualifiedCalls,
    this.constants,
  );

  factory _Facts.of(String source) {
    final unit = parseString(content: source).unit;
    final visitor = _FactsVisitor();
    unit.accept(visitor);
    return _Facts(
      [
        for (final directive in unit.directives)
          if (directive case UriBasedDirective(:final uri))
            uri.stringValue ?? '?',
      ],
      visitor.names,
      visitor.invoked,
      visitor.constructed,
      visitor.strings,
      visitor.namesByMethod,
      visitor.calls,
      visitor.callsByMethod,
      visitor.qualifiedCalls,
      visitor.constants,
    );
  }
}

final class _FactsVisitor extends RecursiveAstVisitor<void> {
  final Set<String> names = {};
  final Set<String> invoked = {};
  final Set<String> constructed = {};
  final List<String> strings = [];
  final Map<String, Set<String>> namesByMethod = {};
  final List<String> calls = [];
  final Map<String, List<String>> callsByMethod = {};
  final List<String> qualifiedCalls = [];
  final Map<String, String> constants = {};
  String? _method;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final outer = _method;
    _method = node.name.lexeme;
    super.visitMethodDeclaration(node);
    _method = outer;
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    names.add(node.name);
    if (_method case final method?) {
      (namesByMethod[method] ??= {}).add(node.name);
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    names.add(node.name.lexeme);
    if (_method case final method?) {
      (namesByMethod[method] ??= {}).add(node.name.lexeme);
    }
    super.visitNamedType(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    invoked.add(node.methodName.name);
    final call =
        '${node.methodName.name}(${node.argumentList.arguments.map((argument) => argument.toSource()).join(', ')})';
    calls.add(call);
    if (_method case final method?) (callsByMethod[method] ??= []).add(call);
    if (node.target case SimpleIdentifier(:final name)) {
      qualifiedCalls.add('$name.$call');
    }
    // `P2pDatabase.open(…)` parses as an invocation of `open` on `P2pDatabase` when the parser does not resolve it.
    if (node.target case SimpleIdentifier(:final name)) {
      constructed.add('$name.${node.methodName.name}');
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type.name.lexeme;
    final named = node.constructorName.name?.name;
    constructed.add(named == null ? type : '$type.$named');
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (node.initializer case final StringLiteral literal?) {
      if (literal.stringValue case final text?) {
        constants[node.name.lexeme] = text;
      }
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    strings.add(node.value);
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    strings.add(node.stringValue ?? node.toSource());
    super.visitAdjacentStrings(node);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    strings.add(node.toSource());
    super.visitStringInterpolation(node);
  }
}

/// Every `ignore:` or `ignore_for_file:` comment of [source], normalised to `ignore: code, code`.
///
/// What follows the colon is read to the end of the line or of the comment, whatever it holds, so that `// ignore: code // reason`, which the analyzer obeys, is compared whole with the forms allowed and matches none (#69).
List<String> _ignores(String source) => [
  for (final match in RegExp(
    r'(ignore(?:_for_file)?)\s*:(.*?)(?:\*/|$)',
    multiLine: true,
  ).allMatches(source))
    '${match[1]}: ${(match[2] ?? '').split(',').map((code) => code.trim()).where((code) => code.isNotEmpty).join(', ')}',
];

/// The Dart files the tests read: every one under `lib/` that [_isScanned].
List<String> _scanned() => [
  for (final file in Directory('lib').listSync(recursive: true))
    if (file is File && _isScanned(file.path)) file.path,
];

/// Whether the tests read the file at [path]: every Dart file under `lib/`, generated ones included (the translations of gen-l10n were left out before the review of #67, and a hand-written file named like one went unseen).
bool _isScanned(String path) =>
    path.startsWith('lib/') && path.endsWith('.dart');

/// Members watched by name, by the class that declares them and its library: a member of a subtype, an implementation of the interface included, counts as the member of its supertype.
const _watched = {
  'CoordinatorTransport': ('package:robosats/', {'send'}),
  'RobotBindingRepository': (
    'package:p2p/',
    {
      'bind',
      'recordGeneratedKey',
      'recordImportedKey',
      'recordAcknowledgedKey',
    },
  ),
  // The trade records and the reservation of a robot for a new trade (#85): who may reserve a robot, write a record of each origin, or change one.
  'TradeRecordRepository': (
    'package:p2p/',
    {
      'reserveForNewTrade',
      'recordPendingTake',
      'recordRecoveredTrade',
      'confirmTake',
      'closeTrade',
    },
  ),
  'GarageKeyRepository': ('package:p2p/', {'create', 'import'}),
  'GarageKeys': ('package:secrets/', {'create', 'import'}),
  'FetchRobotUsecase': ('package:p2p/', {'execute'}),
  'CloseRobotSessionsUsecase': ('package:p2p/', {'execute'}),
  'CoordinatorSessionsPort': ('package:p2p/', {'closeRobotSessions'}),
  'RobotContact': ('package:p2p/', {'firstContact'}),
  // The robot use cases of the Garage's panel, and what its cubit and widgets must not reach but through them (#29, step 5).
  'PutRobotOnCoordinatorUsecase': ('package:p2p/', {'execute'}),
  'RobotCoordinatorCubit': ('package:p2p/', {'putOn', 'retry', 'acknowledge'}),
  // The acknowledgement of a key of unknown history, which only the user's « I understand » records (#29, step 6).
  'AcknowledgeGarageKeyHistoryUsecase': ('package:p2p/', {'execute'}),
  'ReadRobotOnCoordinatorUsecase': ('package:p2p/', {'execute'}),
  'ReleaseRobotUsecase': ('package:p2p/', {'execute'}),
  'RobotRequestLimiter': ('package:p2p/', <String>{}),
  'CoordinatorClient': ('package:robosats/', <String>{}),
  'P2pDatabase': ('package:p2p/', <String>{}),
  'UnprovenCoordinatorRobot': ('package:robosats/', {'prove', 'parse'}),
  'CoordinatorRobotAnswer': ('package:robosats/', {'parse'}),
  'RobotPgpKey': (
    'package:robosats/',
    {'generate', 'generateWith', 'unlock', 'proveMadeBy'},
  ),
};

/// The members that hold or make a robot's credential: its token, the token's hash in both forms, and the two `Authorization` headers.
const _credentials = {
  'RobotIdentity': {
    'token',
    'tokenSha256Hex',
    'tokenSha256Base91',
    'authorizationHeader',
    'firstContactAuthorizationHeader',
  },
  'RobotToken': {'reveal'},
};

/// The libraries and classes that open a connection without the transport: an HTTP or socket client of its own, a Tor session, or a process (such as `curl`).
///
/// A class counts by the library that declares it, so the HTTP client and the websocket of `dart:io` are listed under `dart:_http`, the private library `dart:io` re-exports them from (the third review of #60 found them unseen when listed under `dart:io`).
/// Of the feature's own dependencies, only `dio`, `bull_tor` and the SDK offer such a route; the other packages listed are not dependencies of the feature, whose `depend_on_referenced_packages` lint refuses their import, and are watched all the same.
const _networkLibraries = [
  'package:dio/',
  'package:http/',
  'package:socks5_proxy/',
  'package:web_socket_channel/',
  'dart:html',
];
const _networkClasses = {
  'package:bull_tor/': {'TorHttpClientFactory', 'TorSessions', 'TorSession'},
  'dart:_http': {
    'HttpClient',
    'HttpServer',
    'WebSocket',
    'WebSocketTransformer',
    'HttpOverrides',
  },
  'dart:io': {
    'Socket',
    'RawSocket',
    'SecureSocket',
    'RawSecureSocket',
    'RawDatagramSocket',
    'ServerSocket',
    'RawServerSocket',
    'SecureServerSocket',
    'RawSecureServerSocket',
    'ConnectionTask',
    'Process',
  },
};

/// What the library at [path] refers to, by the top-level declaration it is in (`''` for directives), each as:
/// - `request CoordinatorClient.member`, for a member of the coordinator client that takes a robot's identity or token;
/// - `credential Class.member`, for a member of [_credentials];
/// - `network <library or class>`, for a raw network client;
/// - `Class.member`, for a member of [_watched], and `type Class`, for a class of it named;
/// - `dynamic member`, for a member reached through a value of type `dynamic`.
Future<Map<String, Set<String>>> _referencesIn(
  AnalysisContextCollection collection,
  String path,
) async {
  final absolute = File(path).absolute.path;
  final result = await collection
      .contextFor(absolute)
      .currentSession
      .getResolvedUnit(absolute);
  if (result is! ResolvedUnitResult) {
    return {
      '': {'$path: unresolved'},
    };
  }
  final visitor = _ReferenceVisitor();
  result.unit.accept(visitor);
  return visitor.found;
}

final class _ReferenceVisitor extends RecursiveAstVisitor<void> {
  final Map<String, Set<String>> found = {};
  String _declaration = '';

  void _add(String reference) => (found[_declaration] ??= {}).add(reference);

  static bool _in(Element element, String library) =>
      element.library?.uri.toString().startsWith(library) ?? false;

  /// The class [type] is, or implements, among [names] declared in [library], if any.
  static String? _ownerAmong(
    InterfaceElement type,
    Iterable<String> names,
    String library,
  ) {
    for (final candidate in [
      type,
      for (final supertype in type.allSupertypes) supertype.element,
    ]) {
      final name = candidate.name;
      if (name != null && names.contains(name) && _in(candidate, library)) {
        return name;
      }
    }
    return null;
  }

  /// Whether [type] is, or holds, a robot's identity or token.
  static bool _isRobot(DartType type) => switch (type) {
    InterfaceType(:final element) =>
      {'RobotIdentity', 'RobotToken'}.contains(element.name) &&
          _in(element, 'package:robosats/'),
    RecordType(:final positionalFields, :final namedFields) =>
      positionalFields.any((field) => _isRobot(field.type)) ||
          namedFields.any((field) => _isRobot(field.type)),
    _ => false,
  };

  void _check(Element? element) {
    if (element == null) return;
    if (element is InterfaceElement) {
      for (final MapEntry(key: watched, value: (library, _))
          in _watched.entries) {
        if (_ownerAmong(element, [watched], library) != null) {
          _add('type $watched');
        }
      }
    }
    for (final library in _networkLibraries) {
      if (_in(element, library)) _add('network $library');
    }
    final named = switch (element) {
      InterfaceElement() => element,
      Element(enclosingElement: final InterfaceElement owner) => owner,
      _ => null,
    };
    if (named != null) {
      for (final MapEntry(key: library, value: classes)
          in _networkClasses.entries) {
        if (_ownerAmong(named, classes, library) case final name?) {
          _add('network $name');
        }
      }
    }
    final name = element.name;
    if (name == null) return;
    if (element case Element(enclosingElement: final InterfaceElement owner)) {
      if (element case ExecutableElement(:final formalParameters)
          when _ownerAmong(owner, ['CoordinatorClient'], 'package:robosats/') !=
                  null &&
              formalParameters.any((parameter) => _isRobot(parameter.type))) {
        _add('request CoordinatorClient.$name');
      }
      for (final MapEntry(key: holder, value: members)
          in _credentials.entries) {
        if (members.contains(name) &&
            _ownerAmong(owner, [holder], 'package:robosats/') != null) {
          _add('credential $holder.$name');
        }
      }
      for (final MapEntry(key: watched, value: (library, members))
          in _watched.entries) {
        if (members.contains(name) &&
            _ownerAmong(owner, [watched], library) != null) {
          _add('$watched.$name');
        }
      }
    }
  }

  /// Whether [expression] has the static type `dynamic`.
  static bool _isDynamic(Expression? expression) =>
      expression?.staticType is DynamicType;

  /// Each reference is kept under the top-level declaration it is in, whatever its kind: a class, a function, an extension, a top-level variable, and any other kind under a label of its own, so that a wrapper is never counted as part of the declaration before it (security review of step 6).
  @override
  void visitCompilationUnit(CompilationUnit node) {
    _declaration = '';
    for (final directive in node.directives) {
      directive.accept(this);
    }
    for (final declaration in node.declarations) {
      _declaration = switch (declaration) {
        ClassDeclaration(:final namePart) => namePart.typeName.lexeme,
        FunctionDeclaration(:final name) => name.lexeme,
        ExtensionDeclaration(:final name) => name?.lexeme ?? 'extension',
        TopLevelVariableDeclaration(:final variables) => [
          for (final variable in variables.variables) variable.name.lexeme,
        ].join(', '),
        _ => '${declaration.runtimeType} at ${declaration.offset}',
      };
      declaration.accept(this);
    }
  }

  /// An extension on a watched class can wrap its members under other names: it is reported as `extension on Class`.
  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    if (node.onClause?.extendedType.type case InterfaceType(:final element)) {
      final name = element.name;
      for (final MapEntry(key: watched, value: (library, _))
          in _watched.entries) {
        if (name == watched && _in(element, library)) {
          _add('extension on $watched');
        }
      }
    }
    super.visitExtensionDeclaration(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    _check(node.element);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    _check(node.element);
    super.visitNamedType(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_isDynamic(node.realTarget)) _add('dynamic ${node.methodName.name}');
    super.visitMethodInvocation(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (_isDynamic(node.realTarget)) _add('dynamic ${node.propertyName.name}');
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.prefix.element is! PrefixElement && _isDynamic(node.prefix)) {
      _add('dynamic ${node.identifier.name}');
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    if (_isDynamic(node.function)) _add('dynamic call');
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitIndexExpression(IndexExpression node) {
    if (_isDynamic(node.realTarget)) _add('dynamic []');
    super.visitIndexExpression(node);
  }

  /// A `[name]` in a doc comment names a member without using it.
  @override
  void visitCommentReference(CommentReference node) {}
}

String _dartSdkPath() {
  var directory = Directory('.').absolute;
  while (true) {
    final config = File('${directory.path}/.dart_tool/package_config.json');
    if (config.existsSync()) {
      final packages =
          (jsonDecode(config.readAsStringSync()) as Map)['packages'] as List;
      final flutter = packages.cast<Map>().firstWhere(
        (p) => p['name'] == 'flutter',
      );
      final root = config.uri
          .resolve(flutter['rootUri'] as String)
          .toFilePath();
      return '${Directory(root).parent.parent.path}/bin/cache/dart-sdk';
    }
    if (directory.parent.path == directory.path) {
      throw StateError('No package_config.json');
    }
    directory = directory.parent;
  }
}

/// The file of the robot panel of the Garage.
const _panel = 'lib/src/ui/garage/robot_coordinator_panel.dart';

/// The folder of the trade use cases, and the two that may write a trade record (#87, #79).
const _tradeUseCases = 'lib/src/domain/usecases/trade/';
const _takeOrderUseCase = '${_tradeUseCases}take_order_usecase.dart';
const _recoverTradeUseCase = '${_tradeUseCases}recover_trade_usecase.dart';

/// The public members of [declaration] (constructors, fields, methods, getters and setters whose names do not start with `_`), each as `<kind> <source without body>`.
List<String> _publicSurface(ClassDeclaration declaration) => [
  for (final member in switch (declaration.body) {
    BlockClassBody(:final members) => members,
    _ => const <ClassMember>[],
  })
    ...switch (member) {
      ConstructorDeclaration(:final name, :final parameters)
          when !(name?.lexeme.startsWith('_') ?? false) =>
        [
          'constructor ${declaration.namePart.typeName.lexeme}${name == null ? '' : '.${name.lexeme}'}${parameters.toSource()}',
        ],
      FieldDeclaration(:final fields, :final isStatic) => [
        for (final variable in fields.variables)
          if (!variable.name.lexeme.startsWith('_'))
            [
              'field',
              if (isStatic) 'static',
              ?fields.keyword?.lexeme,
              variable.name.lexeme,
            ].join(' '),
      ],
      MethodDeclaration(:final name) when !name.lexeme.startsWith('_') => [
        '${['method', if (member.isStatic) 'static', if (member.isGetter) 'get', if (member.isSetter) 'set', ?member.returnType?.toSource(), name.lexeme].join(' ')}${member.parameters?.toSource() ?? ''}',
      ],
      _ => const <String>[],
    },
];

/// [text] without its white space, so that a statement compares the same however drift lays it out (drift writes `RAISE (ABORT, …);END` for `RAISE(ABORT, …); END`).
String _squeezed(String text) => text.replaceAll(RegExp(r'\s+'), '');

/// The statements of a `.drift` file, comments and the import left out, squeezed and joined, each ended by `;`.
String _drifted(String source) => _squeezed(
  source
      .split('\n')
      .where((line) {
        final trimmed = line.trimLeft();
        return !trimmed.startsWith('--') && !trimmed.startsWith('import ');
      })
      .join('\n'),
);

/// The two triggers of the trades, as `trades.drift` writes them.
final _tradeTriggers = {
  for (final trigger in _tradeTriggersAsWritten) _squeezed(trigger),
};

/// The two triggers, as `trades.drift` writes them.
const _tradeTriggersAsWritten = [
  "CREATE TRIGGER IF NOT EXISTS trades_never_deleted BEFORE DELETE ON trades BEGIN SELECT RAISE(ABORT, 'a trade record is kept'); END",
  "CREATE TRIGGER IF NOT EXISTS trades_set_once BEFORE UPDATE ON trades WHEN OLD.closed_at IS NOT NULL OR (OLD.confirmed_at IS NOT NULL AND NEW.confirmed_at IS NOT OLD.confirmed_at) OR NEW.network IS NOT OLD.network OR NEW.key_fingerprint IS NOT OLD.key_fingerprint OR NEW.robot_index IS NOT OLD.robot_index OR NEW.coordinator_alias IS NOT OLD.coordinator_alias OR NEW.coordinator_onion IS NOT OLD.coordinator_onion OR NEW.order_id IS NOT OLD.order_id OR NEW.role IS NOT OLD.role OR NEW.origin IS NOT OLD.origin OR NEW.taken_at IS NOT OLD.taken_at BEGIN SELECT RAISE(ABORT, 'a trade record only gains its times'); END",
  "CREATE TRIGGER IF NOT EXISTS trades_inserted_once BEFORE INSERT ON trades WHEN EXISTS (SELECT 1 FROM trades WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index) BEGIN SELECT RAISE(IGNORE); END",
];

/// The statements of `trades.drift`, in order.
final _tradeRules = [
  _squeezed(
    'CREATE UNIQUE INDEX IF NOT EXISTS robot_bindings_network ON robot_bindings (key_fingerprint, robot_index, network)',
  ),
  ..._tradeTriggers,
];
