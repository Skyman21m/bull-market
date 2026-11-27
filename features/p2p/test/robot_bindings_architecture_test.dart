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

  /// Whether [text] of [facts] is a trigger as drift copies it into its code: one the `.drift` files write, or, in the generated migration steps only, one schema 8 replaced.
  bool isDriftTrigger(_Facts facts, String text) =>
      _driftTriggers.contains(_squeezed(text)) ||
      (identical(facts, libraries['lib/src/data/p2p_database.steps.dart']) &&
          _replacedTriggers.contains(_squeezed(text)));

  /// Whether [text] of [facts] is one of the step to schema 8's copies of the trades, the trails or the payments, exactly, in `p2p_database.dart` only (security review of #176).
  bool isSchema8Rebuild(_Facts facts, String text) =>
      identical(facts, libraries['lib/src/data/p2p_database.dart']) &&
      _schema8RebuildTexts.contains(text);

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
            'networkImage': {'network NetworkImage'},
            'imageNetwork': {'network Image.network'},
            'fadeInNetwork': {
              'network FadeInImage.assetNetwork',
              'network FadeInImage.memoryNetwork',
            },
            'networkBundle': {'network NetworkAssetBundle'},
            'lookUp': {'network InternetAddress'},
            'rawSynchronousSocket': {'network RawSynchronousSocket'},
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
            'readerKeepByTearOff': {'TradeReader.keep'},
            'acknowledgedByTearOff': {
              'BondLossAcknowledged.fromConfirmationDialog',
            },
            'unlockByTearOff': {'RobotKeyComputePort.unlock'},
            'signInCascade': {'UnlockedRobotPgpKey.signPayoutInvoice'},
            'leaseInVariable': {'TradeKeyring.lease'},
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
      'the feature names a robot\'s token only for the chat\'s export, as the reference\'s: the proof is the package\'s',
      () {
        expect(referring((r) => r == 'credential RobotIdentity.token'), {
          'lib/src/domain/usecases/trade/export_chat_usecase.dart',
        });
      },
    );

    test('only the use case that binds a robot requests one, or binds', () {
      // Every member of `CoordinatorClient` that takes a robot's identity or token, whatever its name: the requests of later tickets are watched too.
      // The trade use cases (#87) send the order's requests of the robot of a trade, which a trade's record binds, each through the robot's places in `RobotRequestLimiter`: the read in the file they share, the take and the cancel in their own use case, and nothing else.
      expect(
        referring(
          (r) => r.startsWith('request '),
        ).where((path) => !path.startsWith(_tradeUseCases)),
        {'lib/src/domain/usecases/fetch_robot_usecase.dart'},
      );
      expect(referring((r) => r == 'request CoordinatorClient.fetchOrder'), {
        '${_tradeUseCases}trade_reader.dart',
      });
      expect(referring((r) => r == 'request CoordinatorClient.takeOrder'), {
        _takeOrderUseCase,
      });
      expect(referring((r) => r == 'request CoordinatorClient.cancelOrder'), {
        '${_tradeUseCases}cancel_trade_usecase.dart',
      });
      // The make (#179): sent by its own use case only, as the take; the pause by its own too (#184).
      expect(referring((r) => r == 'request CoordinatorClient.makeOrder'), {
        _makeOrderUseCase,
      });
      expect(referring((r) => r == 'request CoordinatorClient.pauseOrder'), {
        '${_tradeUseCases}pause_order_usecase.dart',
      });
      for (final member in ['submitPayoutInvoice', 'submitPayoutAddress']) {
        expect(referring((r) => r == 'request CoordinatorClient.$member'), {
          '${_tradeUseCases}submit_payout_usecase.dart',
        }, reason: member);
      }
      // The chat of a trade (#93): read by its own use case, and read again by the one that sends, after a post whose outcome is unknown; posted by the one that sends.
      expect(referring((r) => r == 'request CoordinatorClient.fetchChat'), {
        '${_tradeUseCases}watch_chat_usecase.dart',
        '${_tradeUseCases}send_chat_message_usecase.dart',
      });
      expect(referring((r) => r == 'request CoordinatorClient.postChat'), {
        '${_tradeUseCases}send_chat_message_usecase.dart',
      });
      // The chat step's actions (the seller's « received » too, #96) and the rating at the end (#95): one use case, which reads and sends under the order's lock.
      for (final member in [
        'confirmFiat',
        'releaseEscrow',
        'undoConfirmFiat',
        'openDispute',
        'ratePlatform',
      ]) {
        expect(referring((r) => r == 'request CoordinatorClient.$member'), {
          '${_tradeUseCases}chat_step_action_usecase.dart',
        }, reason: member);
      }
      // « Rate your host » (#95): the token to rate the coordinator on Nostr, asked by its own use case.
      expect(
        referring((r) => r == 'request CoordinatorClient.fetchReviewToken'),
        {'${_tradeUseCases}rate_host_usecase.dart'},
      );
      for (final path in referring((r) => r.startsWith('request '))) {
        if (!path.startsWith(_tradeUseCases)) continue;
        expect(
          (references[path] ?? const <String>{}).where(
            (r) => r.startsWith('request '),
          ),
          everyElement(
            isIn({
              'request CoordinatorClient.fetchOrder',
              'request CoordinatorClient.takeOrder',
              'request CoordinatorClient.cancelOrder',
              'request CoordinatorClient.makeOrder',
              'request CoordinatorClient.pauseOrder',
              'request CoordinatorClient.submitPayoutInvoice',
              'request CoordinatorClient.submitPayoutAddress',
              'request CoordinatorClient.fetchChat',
              'request CoordinatorClient.postChat',
              'request CoordinatorClient.confirmFiat',
              'request CoordinatorClient.releaseEscrow',
              'request CoordinatorClient.undoConfirmFiat',
              'request CoordinatorClient.openDispute',
              'request CoordinatorClient.ratePlatform',
              'request CoordinatorClient.fetchReviewToken',
            }),
          ),
          reason: path,
        );
        // And through the robot's places only: the file holds a limiter.
        expect(
          references[path],
          anyOf(
            contains('type RobotRequestLimiter'),
            contains('type RobotRequests'),
          ),
          reason: path,
        );
      }
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
        // A record of origin `madeHere` comes only from the make use case (#179), and its order id only from a read that shows its robot as the maker: only it writes, confirms or closes a pending make, or writes a make's terms (#176), as only the take writes a pending take.
        for (final member in [
          'TradeRecordRepository.recordPendingMake',
          'TradeRecordRepository.confirmMake',
          'TradeRecordRepository.closePendingMake',
          'TradeTrailRepository.recordMakerTerms',
        ]) {
          expect(referring((r) => r == member), {
            _makeOrderUseCase,
          }, reason: member);
        }
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
      'only the take writes the terms of a trade, only the trade use cases store a trail, and only the take starts a trade',
      () {
        // The terms are written once, with the pending take, before its request leaves (#87).
        expect(referring((r) => r == 'TradeTrailRepository.recordTerms'), {
          _takeOrderUseCase,
        });
        // A trail is stored by the take (its first trail, and the take's own answer) and by the file the trade use cases share, which asks `whyNotReplace` through the repository.
        expect(referring((r) => r == 'TradeTrailRepository.storeTrail'), {
          _takeOrderUseCase,
          '${_tradeUseCases}trade_reader.dart',
        });
        expect(
          referring((r) => r == 'type TradeTrailRepository').where(
            (path) =>
                !path.startsWith(_tradeUseCases) &&
                !{
                  'lib/src/domain/repositories/trade_trail_repository.dart',
                  'lib/src/data/trade_trail_repository_impl.dart',
                  'lib/src/p2p_locator.dart',
                }.contains(path),
          ),
          isEmpty,
        );
        // A trade starts from the take's own answer only; a pending take with no trail is read once on its own trail, by the take or the resolution of a pending take; a recovered trail only where a recorded trade has none (`AGENTS.md`, « Rules for the trade use cases (#87) »).
        expect(referring((r) => r == 'TradeStatus.afterTake'), {
          _takeOrderUseCase,
        });
        // Since the review of #117 a pending take without its first trail is closed as never sent: only the take names this factory.
        expect(referring((r) => r == 'TradeTrail.forPendingTake'), {
          _takeOrderUseCase,
        });
        expect(referring((r) => r == 'TradeTrail.recovered'), {
          '${_tradeUseCases}trade_reader.dart',
        });
        // A maker's trade starts from the first read of its order (#179): only the make use case names `afterMake`, after the make's answer and at the resolution of a pending make; a confirmed make whose first trail was not written is read once on its own fresh trail, by the make use case (what stays when that trail cannot be stored) and by the reader that resumes a recorded trade, as `forPendingTake` was named by the take only.
        expect(referring((r) => r == 'TradeStatus.afterMake'), {
          _makeOrderUseCase,
        });
        expect(referring((r) => r == 'TradeTrail.forConfirmedMake'), {
          _makeOrderUseCase,
          '${_tradeUseCases}trade_reader.dart',
        });
        // The gap is computed by the state machine, from the order's `satoshis_now`, which `package:robosats` bounds (#178), and since #237 by the owner's payment rule on a buyer's side from the same bounded figure of the order it compares (`CheckPayoutRateUsecase.againstOf`, status 15 carrying no gap of its own).
        expect(referring((r) => r == 'MakerTerms.rateGap'), {
          'lib/src/domain/trade/trade_status.dart',
          '${_tradeUseCases}check_payout_rate_usecase.dart',
        });
      },
    );

    test(
      'only the trade use cases reach the reader they share, and no file of lib/ builds an acknowledgement of a bond lost yet',
      () {
        // Its members store trails, confirm and close records: only the trade use cases and the composition name it (review of #117).
        expect(
          referring(
            (r) => r.startsWith('TradeReader.'),
          ).where((path) => !path.startsWith(_tradeUseCases)),
          isEmpty,
        );
        expect(
          referring((r) => r == 'type TradeReader').where(
            (path) =>
                !path.startsWith(_tradeUseCases) &&
                path != 'lib/src/p2p_locator.dart',
          ),
          isEmpty,
        );
        // The trade screen's cancel confirmation (#88) is the one file that builds it.
        expect(
          referring((r) => r == 'BondLossAcknowledged.fromConfirmationDialog'),
          {'lib/src/ui/trade/confirm_cancel_dialog.dart'},
        );
      },
    );

    test(
      'the screens take in two steps through the composition, and nothing in lib/ takes in one step',
      () {
        // The take's cubit is given the use case's steps by the composition (`TakeCalls`), its only caller (#119).
        // Since #245 the read and the preparation of a password-protected order too.
        for (final step in [
          'prepare',
          'confirm',
          'abandon',
          'abandonOrder',
          'readUnlisted',
          'prepareUnlisted',
          'abandonRead',
        ]) {
          expect(referring((r) => r == 'TakeOrderUsecase.$step'), {
            'lib/src/p2p_locator.dart',
          }, reason: step);
        }
        // `execute` stays for the tests of the domain: no file of lib/ calls it.
        expect(referring((r) => r == 'TakeOrderUsecase.execute'), isEmpty);
      },
    );

    test(
      'only the take reaches the takes prepared, which hold reserved robots and their tokens',
      () {
        // A screen holds a prepared take, never its robot: only the take use case keeps, reads or forgets one (#119, review of #126).
        expect(referring((r) => r.startsWith('PreparedTakes.')), {
          _takeOrderUseCase,
        });
        expect(
          referring((r) => r == 'type PreparedTakes').difference({
            _takeOrderUseCase,
            '${_tradeUseCases}prepared_takes.dart',
            'lib/src/p2p_locator.dart',
          }),
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
        // The unlock of a trade's robot key (#90), in that isolate too; the proof wipes what it unlocks.
        expect(referring((r) => r == 'RobotPgpKey.unlock'), {
          'lib/src/data/isolate_robot_key_compute.dart',
        });
      },
    );

    test(
      'only the keyring of the trades unlocks a robot\'s key, only the payout signs with it, and nothing else reaches the unlocked key',
      () {
        // The keyring reads the robot's proven pair back and has it unlocked away from the UI isolate, and keeps it no longer than its rules say (#90, design note § 3.4).
        const keyring = '${_tradeUseCases}trade_keyring.dart';
        const payout = '${_tradeUseCases}submit_payout_usecase.dart';
        // The chat (#93): decrypted in the file the read and the send share, encrypted in the send's own.
        const chatRead = '${_tradeUseCases}watch_chat_usecase.dart';
        const chatSend = '${_tradeUseCases}send_chat_message_usecase.dart';
        // The chat as the reference exports it, on the user's tap (#93): the encrypted private key from a lease.
        const chatExport = '${_tradeUseCases}export_chat_usecase.dart';
        expect(referring((r) => r == 'RobotKeyComputePort.unlock'), {keyring});
        expect(
          referring((r) => r == 'ReadRobotOnCoordinatorUsecase.provenPairOf'),
          {keyring},
        );
        // Since the fix of GHSA-22q8-9ghc-jg3h (RoboSats pull request 2955), every request of a robot that changes a state is signed by its key, which the client of the package takes from a lease: the make and the take (a robot reserved, `leaseRobot`), the cancel, the pause, the chat step's actions and the token to rate the coordinator.
        const make = '${_tradeUseCases}make_order_usecase.dart';
        const take = '${_tradeUseCases}take_order_usecase.dart';
        const cancel = '${_tradeUseCases}cancel_trade_usecase.dart';
        const pause = '${_tradeUseCases}pause_order_usecase.dart';
        const chatStep = '${_tradeUseCases}chat_step_action_usecase.dart';
        const rateHost = '${_tradeUseCases}rate_host_usecase.dart';
        // A lease only for a signature (the payout's, the actions' of the robot) and the chat's messages, a hold only through the use case the screens call.
        expect(referring((r) => r == 'TradeKeyring.lease'), {
          chatExport,
          payout,
          chatRead,
          chatSend,
          cancel,
          pause,
          chatStep,
          rateHost,
        });
        expect(referring((r) => r == 'TradeKeyring.leaseRobot'), {make, take});
        // The lease of an action kept for its request only, closed as soon as the request has ended.
        expect(referring((r) => r == 'TradeKeyring.signWith'), {
          make,
          take,
          cancel,
          pause,
          chatStep,
        });
        expect(referring((r) => r == 'TradeKeyLease.key'), {
          keyring,
          chatExport,
          payout,
          chatRead,
          chatSend,
          rateHost,
        });
        expect(referring((r) => r == 'TradeKeyring.hold'), {
          '${_tradeUseCases}hold_trade_key_usecase.dart',
        });
        expect(
          referring((r) => r == 'type TradeKeyring'),
          everyElement(
            isIn({
              keyring,
              payout,
              chatRead,
              chatSend,
              chatExport,
              make,
              take,
              cancel,
              pause,
              chatStep,
              rateHost,
              '${_tradeUseCases}hold_trade_key_usecase.dart',
              'lib/src/p2p_locator.dart',
            }),
          ),
        );
        // What is signed is a payout, decoded and checked, in the payout's own file: never free text there; a chat message only as the one value `postChat` sends, in the send's file, and decrypted in the read's (#93); `signCleartext` and `encryptChatMessage` nowhere.
        expect(
          referring(
            (r) =>
                r == 'UnlockedRobotPgpKey.signPayoutInvoice' ||
                r == 'UnlockedRobotPgpKey.signPayoutAddress',
          ),
          {payout},
        );
        expect(
          referring((r) => r == 'UnlockedRobotPgpKey.encryptChatMessageToPost'),
          {chatSend},
        );
        // Decrypted away from the UI isolate, by the key work's own file, which only the chat's read asks for it, with the part of the key that decrypts and nothing else: never the identity, nor its token (review of #93).
        expect(
          referring((r) => r == 'UnlockedRobotPgpKey.decryptChatMessage'),
          isEmpty,
        );
        expect(referring((r) => r == 'UnlockedRobotPgpKey.chatDecryption'), {
          'lib/src/data/isolate_robot_key_compute.dart',
        });
        expect(referring((r) => r.startsWith('ChatDecryptionKey.')), {
          'lib/src/data/isolate_robot_key_compute.dart',
        });
        expect(referring((r) => r == 'RobotKeyComputePort.decryptChat'), {
          chatRead,
        });
        expect(
          referring(
            (r) =>
                r.startsWith('UnlockedRobotPgpKey.') &&
                r != 'UnlockedRobotPgpKey.signPayoutInvoice' &&
                r != 'UnlockedRobotPgpKey.signPayoutAddress' &&
                r != 'UnlockedRobotPgpKey.encryptChatMessageToPost' &&
                r != 'UnlockedRobotPgpKey.chatDecryption',
          ),
          isEmpty,
        );
        expect(
          referring((r) => r == 'type UnlockedRobotPgpKey'),
          everyElement(
            isIn({
              'lib/src/domain/robot_key_compute_port.dart',
              'lib/src/data/isolate_robot_key_compute.dart',
              keyring,
              payout,
              chatRead,
              chatSend,
              // The chat step's actions name the key their requests are signed with (GHSA-22q8-9ghc-jg3h), and hand it to the client only.
              chatStep,
              // The tests' library, which names the type for the app's captures to encrypt the maker's messages (#93); no library of the app imports it.
              'lib/testing.dart',
            }),
          ),
        );
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
        // The chat's export, as the reference's, holds the token as the private key's passphrase (#93, the owner's choice): on the user's tap only, through the chat panel's cubit.
        'lib/src/domain/usecases/trade/export_chat_usecase.dart',
      });
      // The token hash, the token and the headers made of them: the coordinator client of `package:robosats` builds them for the use case, and no file of the feature reads them.
      expect(
        referring(
          (r) =>
              r.startsWith('credential ') &&
              r != 'credential RobotToken.reveal' &&
              r != 'credential RobotIdentity.token',
        ),
        isEmpty,
      );
      expect(referring((r) => r == 'credential RobotIdentity.token'), {
        'lib/src/domain/usecases/trade/export_chat_usecase.dart',
      });
      // Its encrypted private key too, which the token unlocks.
      expect(referring((r) => r == 'RobotPgpKey.encryptedPrivateKeyArmored'), {
        'lib/src/domain/usecases/trade/export_chat_usecase.dart',
      });
    });

    test('only the transport and the tile client hold a raw network client', () {
      expect(
        referring(
          (r) =>
              r.startsWith('network ') && r != 'network TorHttpClientFactory',
        ),
        {
          'lib/src/data/tor_coordinator_transport.dart',
          // The tiles of the maps (#246): the one connection the feature opens itself outside Tor, the owner's decision of 2026-11-23; the wallet's price and swap service, outside Tor too, are reached through the wallet's port (`wallet_port_architecture_test.dart`).
          'lib/src/data/osm_map_tile_adapter.dart',
        },
      );
      // The tile client holds `dart:io`'s HTTP client and nothing else: no Tor session, no Tor client factory, no `dio`, no socket of its own.
      expect(
        references['lib/src/data/osm_map_tile_adapter.dart']
            ?.where((r) => r.startsWith('network '))
            .toSet(),
        {'network HttpClient'},
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
      'only « New key » activates a key of the words, only the import writes the vault, and nothing records a key as drawn here but the activation',
      () {
        // Since #81 nothing draws a key: the keys of the words are activated by the repository, at the first opening (key 0) and on « New key », and recorded as drawn here by the book's own activation, never through the bindings' repository.
        expect(referring((r) => r == 'GarageKeyRepository.activateNext'), {
          'lib/src/domain/usecases/new_garage_key_usecase.dart',
        });
        expect(referring((r) => r == 'NewGarageKeyUsecase.execute'), {
          'lib/src/presentation/garage_cubit.dart',
        });
        expect(referring((r) => r == 'GarageKeyBookRepository.activate'), {
          'lib/src/data/garage_key_repository_impl.dart',
        });
        expect(
          referring((r) => r == 'RobotBindingRepository.recordGeneratedKey'),
          isEmpty,
        );
        expect(referring((r) => r == 'GarageKeyRepository.import'), {
          'lib/src/domain/usecases/import_garage_key_usecase.dart',
        });
        expect(
          referring((r) => r == 'RobotBindingRepository.recordImportedKey'),
          {'lib/src/domain/usecases/import_garage_key_usecase.dart'},
        );
        // And only the repository asks the vault to write or delete one (the external key, #81); nothing asks it to draw one.
        for (final member in ['GarageKeys.import', 'GarageKeys.delete']) {
          expect(referring((r) => r == member), {
            'lib/src/data/garage_key_repository_impl.dart',
          }, reason: member);
        }
        expect(referring((r) => r == 'GarageKeys.create'), isEmpty);
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
        expect(referring((r) => r == 'ReleaseRobotUsecase.execute'), {cubit});
        // And the make (#179), which reads its robot back from the coordinator its binding names to resolve a make whose answer was lost: the robot's active or last order, through the same use case.
        expect(referring((r) => r == 'ReadRobotOnCoordinatorUsecase.execute'), {
          cubit,
          _makeOrderUseCase,
        });
        // And the take (#87) and the make (#179), which put the fresh robot they reserved on the order's coordinator before their pending record: its first contact, through the same use case.
        expect(referring((r) => r == 'PutRobotOnCoordinatorUsecase.execute'), {
          cubit,
          _takeOrderUseCase,
          _makeOrderUseCase,
        });
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
        // Schema 10 (#81): the keys of the words activated, and the key selected.
        'lib/src/data/garage_key_book_repository_impl.dart',
        // Schema 11 (#81): what this device read of the recovery notes.
        'lib/src/data/garage_recovery_note_repository_impl.dart',
        'lib/src/data/robot_binding_repository_impl.dart',
        'lib/src/data/trade_chat_pin_repository_impl.dart',
        'lib/src/data/trade_payment_repository_impl.dart',
        // Schema 9 (#204): the payouts a buyer gave, per contract.
        'lib/src/data/trade_payout_repository_impl.dart',
        'lib/src/data/trade_record_repository_impl.dart',
        'lib/src/data/trade_trail_repository_impl.dart',
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
        // Schema 10 (#81): the keys of the words activated, and the key selected.
        'lib/src/data/garage_key_book_repository_impl.dart',
        // Schema 11 (#81): what this device read of the recovery notes.
        'lib/src/data/garage_recovery_note_repository_impl.dart',
        'lib/src/data/robot_binding_repository_impl.dart',
        'lib/src/data/trade_chat_pin_repository_impl.dart',
        'lib/src/data/trade_payment_repository_impl.dart',
        // Schema 9 (#204): the payouts a buyer gave, per contract.
        'lib/src/data/trade_payout_repository_impl.dart',
        'lib/src/data/trade_record_repository_impl.dart',
        'lib/src/data/trade_trail_repository_impl.dart',
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
    // No SQL text of another file reads or writes the trades, but the triggers as drift copies them, and the statements of the step to schema 8 (#176) that copy the rows of the rebuilt tables aside and back, each pinned as written in the database (`_schema8Rebuild`).
    expect(
      where(
        (facts) => facts.strings.any(
          (text) =>
              RegExp(
                r'\b(from|into|update|join)\s+"?trades\b',
                caseSensitive: false,
              ).hasMatch(text) &&
              !isDriftTrigger(facts, text) &&
              !isSchema8Rebuild(facts, text),
        ),
      ),
      {'lib/src/data/trade_record_repository_impl.dart'},
    );
  });

  test(
    'the payouts a buyer gave are written by their repository alone, one statement each, never deleted (schema 9, #204)',
    () {
      // No other file holds SQL that writes the payouts, but the triggers as drift copies them and the marks the step to schema 9 writes, pinned in the database by value.
      expect(
        where(
          (facts) => facts.strings.any(
            (text) =>
                RegExp(
                  r'\b(into|update|delete\s+from)\s+"?trade_payouts\b',
                  caseSensitive: false,
                ).hasMatch(text) &&
                !isDriftTrigger(facts, text) &&
                !(identical(
                      facts,
                      libraries['lib/src/data/p2p_database.dart'],
                    ) &&
                    text.startsWith(
                      'INSERT INTO trade_payouts (key_fingerprint, robot_index, take, source, kind, submitted_at) ',
                    )),
          ),
        ),
        {'lib/src/data/trade_payout_repository_impl.dart'},
      );
      final payouts =
          libraries['lib/src/data/trade_payout_repository_impl.dart'] ??
          fail('no payout repository');
      expect(payouts.constants, {
        '_replaceSql':
            'UPDATE trade_payouts SET source = ?, kind = ?, submitted_at = ? '
            'WHERE key_fingerprint = ? AND robot_index = ? AND take = ? '
            'RETURNING robot_index',
        '_insertSql':
            'INSERT INTO trade_payouts (key_fingerprint, robot_index, take, source, '
            'kind, submitted_at) VALUES (?, ?, ?, ?, ?, ?) '
            'RETURNING robot_index',
        '_traceSql':
            'SELECT source, kind, submitted_at FROM trade_payouts '
            'WHERE key_fingerprint = ? AND robot_index = ? AND take = ?',
      });
      expect(
        payouts.strings.where(
          (text) => RegExp(r'\bdelete\b', caseSensitive: false).hasMatch(text),
        ),
        isEmpty,
      );
      // Only the payout's use case records a payout, and only the reader reads where it came from.
      expect(where((facts) => facts.invoked.contains('recordPayout')), {
        'lib/src/domain/usecases/trade/submit_payout_usecase.dart',
      });
      expect(where((facts) => facts.invoked.contains('traceOf')), {
        'lib/src/domain/usecases/trade/trade_reader.dart',
      });
    },
  );

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
        if (identical(facts, steps) && isDriftTrigger(facts, text)) {
          continue;
        }
        // The steps to schema 7 and 8 rebuild the payments, the trades and their trails (#97, #176), never a binding: their drops, of tables and of triggers, pinned as written below.
        if (identical(facts, database) && _rebuildDrops.contains(text)) {
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
      // Schema 9 (#233, #231): the amount of a payment and the trace of terms shown otherwise, columns of tables that are not the bindings.
      'addColumn(schema.tradePayments, schema.tradePayments.confirmedSats)',
      'addColumn(schema.tradeTrails, schema.tradeTrails.termsChangedAt)',
      'addColumn(schema.tradeTrails, schema.tradeTrails.termsChangedPremiumLow)',
      'addColumn(schema.tradeTrails, schema.tradeTrails.termsChangedPremiumHigh)',
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
      // Schema 4 (#87): the terms and the trails of the trades, and the triggers that keep them.
      'm.createTable(schema.tradeTerms)',
      'm.createTable(schema.tradeTrails)',
      'm.createTrigger(schema.tradesOneOpenPerOrder)',
      'm.createTrigger(schema.tradeTermsNeverDeleted)',
      'm.createTrigger(schema.tradeTermsSetOnce)',
      'm.createTrigger(schema.tradeTermsInsertedOnce)',
      'm.createTrigger(schema.tradeTermsOfTheirTrade)',
      'm.createTrigger(schema.tradeTrailsNeverDeleted)',
      'm.createTrigger(schema.tradeTrailsInsertedOnce)',
      'm.createTrigger(schema.tradeTrailsOfTheirTrade)',
      'm.createTrigger(schema.tradeTrailsClosed)',
      'm.createTrigger(schema.tradeTrailsForward)',
      'm.createTable(schema.tradePayments)',
      'm.createTrigger(schema.tradePaymentsNeverDeleted)',
      'm.createTrigger(schema.tradePaymentsInsertedOnce)',
      'm.createTrigger(schema.tradePaymentsOfTheirTrade)',
      'm.createTrigger(schema.tradePaymentsForward)',
      // Schema 6 (#139, part of #159): the PGP and Nostr pins of the trades' chats.
      'm.createTable(schema.tradeChatPins)',
      'm.createTrigger(schema.tradeChatPinsNeverDeleted)',
      'm.createTrigger(schema.tradeChatPinsNeverChanged)',
      'm.createTrigger(schema.tradeChatPinsInsertedOnce)',
      'm.createTrigger(schema.tradeChatPinsOfTheirTrade)',
      'm.createTable(schema.tradeChatNostrPins)',
      'm.createTrigger(schema.tradeChatNostrPinsNeverDeleted)',
      'm.createTrigger(schema.tradeChatNostrPinsNeverChanged)',
      'm.createTrigger(schema.tradeChatNostrPinsInsertedOnce)',
      'm.createTrigger(schema.tradeChatNostrPinsOfTheirTrade)',
      // Schema 7 (#97): the payments rebuilt with the escrow's step, and their triggers made again.
      'm.createTable(schema.tradePayments)',
      'm.createTrigger(schema.tradePaymentsNeverDeleted)',
      'm.createTrigger(schema.tradePaymentsInsertedOnce)',
      'm.createTrigger(schema.tradePaymentsOfTheirTrade)',
      'm.createTrigger(schema.tradePaymentsForward)',
      // Schema 8 (#176): the trades, their trails and their payments rebuilt, the maker's terms, and every trigger of the three tables made again, the new ones and the replaced ones included.
      'm.createTable(schema.trades)',
      'm.createTable(schema.tradeTrails)',
      'm.createTable(schema.tradePayments)',
      'm.createTable(schema.makerTerms)',
      // Each table's triggers in the order a new file has them (functional review of #176): SQLite fires the triggers of one event newest first.
      'm.createTrigger(schema.tradesOneOpenPerOrder)',
      'm.createTrigger(schema.tradesOneOpenPerOrderUpdate)',
      'm.createTrigger(schema.tradesNeverDeleted)',
      'm.createTrigger(schema.tradesSetOnce)',
      'm.createTrigger(schema.tradesMadePending)',
      'm.createTrigger(schema.tradesInsertedOnce)',
      'm.createTrigger(schema.makerTermsNeverDeleted)',
      'm.createTrigger(schema.makerTermsSetOnce)',
      'm.createTrigger(schema.makerTermsInsertedOnce)',
      'm.createTrigger(schema.makerTermsOfTheirMake)',
      'm.createTrigger(schema.tradeTermsOfTheirTrade)',
      'm.createTrigger(schema.tradeTrailsNeverDeleted)',
      'm.createTrigger(schema.tradeTrailsInsertedOnce)',
      'm.createTrigger(schema.tradeTrailsOfTheirTrade)',
      'm.createTrigger(schema.tradeTrailsClosed)',
      'm.createTrigger(schema.tradeTrailsForward)',
      'm.createTrigger(schema.tradePaymentsNeverDeleted)',
      'm.createTrigger(schema.tradePaymentsInsertedOnce)',
      'm.createTrigger(schema.tradePaymentsOfTheirTrade)',
      'm.createTrigger(schema.tradePaymentsForward)',
      'm.createTrigger(schema.tradePaymentsHashOnce)',
      // Schema 9 (#204, #231, #233): four columns added, the payouts' table, its triggers, and the new triggers of the trails and the payments, each the newest of its table.
      'm.addColumn(schema.tradePayments, schema.tradePayments.confirmedSats)',
      'm.addColumn(schema.tradeTrails, schema.tradeTrails.termsChangedAt)',
      'm.addColumn(schema.tradeTrails, schema.tradeTrails.termsChangedPremiumLow)',
      'm.addColumn(schema.tradeTrails, schema.tradeTrails.termsChangedPremiumHigh)',
      'm.createTable(schema.tradePayouts)',
      'm.createTrigger(schema.tradePayoutsNeverDeleted)',
      'm.createTrigger(schema.tradePayoutsForward)',
      'm.createTrigger(schema.tradePayoutsOfTheirTrade)',
      'm.createTrigger(schema.tradePayoutsInsertedOnce)',
      'm.createTrigger(schema.tradeTrailsTermsTrace)',
      'm.createTrigger(schema.tradePaymentsSatsKnown)',
      'm.createTrigger(schema.tradePaymentsSatsForward)',
      // Schema 10 (#81): the keys of the words and the key selected, the Garage's notices, and their triggers; nothing else, no row changed.
      'm.createTable(schema.derivedGarageKeys)',
      'm.createTable(schema.selectedGarageKeys)',
      'm.createTrigger(schema.derivedGarageKeysNeverDeleted)',
      'm.createTrigger(schema.derivedGarageKeysNeverChanged)',
      'm.createTrigger(schema.derivedGarageKeysInOrder)',
      'm.createTrigger(schema.derivedGarageKeysInsertedOnce)',
      'm.createTable(schema.garageNotices)',
      'm.createTrigger(schema.garageNoticesShownOnce)',
      'm.createTrigger(schema.garageNoticesNeverDeleted)',
      // Schema 11 (#81): what this device read of the recovery notes, one table and its triggers.
      'm.createTable(schema.garageRecoveryNotes)',
      'm.createTrigger(schema.garageRecoveryNotesNeverDeleted)',
      'm.createTrigger(schema.garageRecoveryNotesInsertedOnce)',
      'm.createTrigger(schema.garageRecoveryNotesForward)',
    ]);
    // The `customStatement`s the database runs itself: the rebuild of the payments in the step to schema 7 (#97), which names the payments' table and its copy only; the rebuild of the trades, their trails and their payments in the step to schema 8 (#176), which names those tables, their copies and their triggers and the trigger it replaces on `trade_terms` only, and turns the foreign keys off when a connection has them on; and the foreign keys of the trades, on, at each opening.
    expect(database.calls.where((call) => call.startsWith('customStatement(')), [
      'customStatement(_dropPaymentsCopy)',
      'customStatement(_copyPayments)',
      'customStatement(_dropPayments)',
      'customStatement(_restorePayments)',
      'customStatement(_dropPaymentsCopy)',
      'customStatement(_foreignKeysOff)',
      'customStatement(_dropTradesCopy)',
      'customStatement(_copyTrades)',
      'customStatement(_dropTrades)',
      'customStatement(_restoreTrades)',
      'customStatement(_dropTrailsCopy)',
      'customStatement(_copyTrails)',
      'customStatement(_dropTrails)',
      'customStatement(_restoreTrails)',
      'customStatement(_dropPaymentsOfSchema7)',
      'customStatement(_copyPaymentsOfSchema7)',
      'customStatement(_dropPayments)',
      'customStatement(_restorePaymentsOfSchema7)',
      'customStatement(_dropTradesOneOpenPerOrder)',
      'customStatement(_dropTradesOneOpenPerOrderUpdate)',
      'customStatement(_dropTradesNeverDeleted)',
      'customStatement(_dropTradesSetOnce)',
      'customStatement(_dropTradesMadePending)',
      'customStatement(_dropTradesInsertedOnce)',
      'customStatement(_dropTermsOfTheirTrade)',
      'customStatement(_dropTradeTrailsNeverDeleted)',
      'customStatement(_dropTradeTrailsInsertedOnce)',
      'customStatement(_dropTradeTrailsOfTheirTrade)',
      'customStatement(_dropTradeTrailsClosed)',
      'customStatement(_dropTradeTrailsForward)',
      'customStatement(_dropTradePaymentsNeverDeleted)',
      'customStatement(_dropTradePaymentsInsertedOnce)',
      'customStatement(_dropTradePaymentsOfTheirTrade)',
      'customStatement(_dropTradePaymentsForward)',
      'customStatement(_dropTradePaymentsHashOnce)',
      'customStatement(_dropTradesCopy)',
      'customStatement(_dropTrailsCopy)',
      'customStatement(_dropPaymentsOfSchema7)',
      'customStatement(_dropTradePayoutsNeverDeleted)',
      'customStatement(_dropTradePayoutsForward)',
      'customStatement(_dropTradePayoutsOfTheirTrade)',
      'customStatement(_dropTradePayoutsInsertedOnce)',
      'customStatement(_markPayoutsUnrecorded)',
      // The step to schema 10 (#81): « Your Garage Keys » made due, in its own new table.
      'customStatement(_externalKeyNamedDue)',
      'customStatement(_foreignKeysOn)',
    ]);
    // The step to schema 8, call by call, in its order (#176): the foreign keys found off before anything, or turned off and read again, each rebuilt table copied aside only while it is schema 7's, made again only while missing, filled again from its copy only while the copy exists, `trades` first; then the maker's terms, the triggers (each replaced one dropped first), the foreign keys of the file checked, and only then the copies dropped.
    final migration =
        database.callsByMethod['migration'] ?? fail('no migration');
    expect(migration.skip(migration.indexOf('_foreignKeysAreOn()')), [
      '_foreignKeysAreOn()',
      'customStatement(_foreignKeysOff)',
      '_foreignKeysAreOn()',
      '_tableText(_trades)',
      'contains("\'madeHere\'")',
      'customStatement(_dropTradesCopy)',
      'customStatement(_copyTrades)',
      'customStatement(_dropTrades)',
      '_tableText(_trades)',
      'createTable(schema.trades)',
      '_tableText(_tradesCopy)',
      'customStatement(_restoreTrades)',
      '_tableText(_trails)',
      '_hasColumn(_trails, \'take\')',
      'customStatement(_dropTrailsCopy)',
      'customStatement(_copyTrails)',
      'customStatement(_dropTrails)',
      '_tableText(_trails)',
      'createTable(schema.tradeTrails)',
      '_tableText(_trailsCopy)',
      'customStatement(_restoreTrails)',
      '_tableText(_payments)',
      '_hasColumn(_payments, \'take\')',
      'customStatement(_dropPaymentsOfSchema7)',
      'customStatement(_copyPaymentsOfSchema7)',
      'customStatement(_dropPayments)',
      '_tableText(_payments)',
      'createTable(schema.tradePayments)',
      '_tableText(_paymentsOfSchema7)',
      'customStatement(_restorePaymentsOfSchema7)',
      'createTable(schema.makerTerms)',
      'customStatement(_dropTradesOneOpenPerOrder)',
      'customStatement(_dropTradesOneOpenPerOrderUpdate)',
      'customStatement(_dropTradesNeverDeleted)',
      'customStatement(_dropTradesSetOnce)',
      'customStatement(_dropTradesMadePending)',
      'customStatement(_dropTradesInsertedOnce)',
      'createTrigger(schema.tradesOneOpenPerOrder)',
      'createTrigger(schema.tradesOneOpenPerOrderUpdate)',
      'createTrigger(schema.tradesNeverDeleted)',
      'createTrigger(schema.tradesSetOnce)',
      'createTrigger(schema.tradesMadePending)',
      'createTrigger(schema.tradesInsertedOnce)',
      'createTrigger(schema.makerTermsNeverDeleted)',
      'createTrigger(schema.makerTermsSetOnce)',
      'createTrigger(schema.makerTermsInsertedOnce)',
      'createTrigger(schema.makerTermsOfTheirMake)',
      'customStatement(_dropTermsOfTheirTrade)',
      'createTrigger(schema.tradeTermsOfTheirTrade)',
      'customStatement(_dropTradeTrailsNeverDeleted)',
      'customStatement(_dropTradeTrailsInsertedOnce)',
      'customStatement(_dropTradeTrailsOfTheirTrade)',
      'customStatement(_dropTradeTrailsClosed)',
      'customStatement(_dropTradeTrailsForward)',
      'createTrigger(schema.tradeTrailsNeverDeleted)',
      'createTrigger(schema.tradeTrailsInsertedOnce)',
      'createTrigger(schema.tradeTrailsOfTheirTrade)',
      'createTrigger(schema.tradeTrailsClosed)',
      'createTrigger(schema.tradeTrailsForward)',
      'customStatement(_dropTradePaymentsNeverDeleted)',
      'customStatement(_dropTradePaymentsInsertedOnce)',
      'customStatement(_dropTradePaymentsOfTheirTrade)',
      'customStatement(_dropTradePaymentsForward)',
      'customStatement(_dropTradePaymentsHashOnce)',
      'createTrigger(schema.tradePaymentsNeverDeleted)',
      'createTrigger(schema.tradePaymentsInsertedOnce)',
      'createTrigger(schema.tradePaymentsOfTheirTrade)',
      'createTrigger(schema.tradePaymentsForward)',
      'createTrigger(schema.tradePaymentsHashOnce)',
      '_breaksAForeignKey()',
      'customStatement(_dropTradesCopy)',
      'customStatement(_dropTrailsCopy)',
      'customStatement(_dropPaymentsOfSchema7)',
      // The step to schema 9 (#204, #231, #233), call by call: each column added only while missing, the payouts' table made only while missing, its triggers dropped, the marks of the contracts under way written, its triggers made again in a new file's order, then the new triggers of the trails and the payments.
      '_hasColumn(_payments, \'confirmed_sats\')',
      'addColumn(schema.tradePayments, schema.tradePayments.confirmedSats)',
      '_hasColumn(_trails, \'terms_changed_at\')',
      'addColumn(schema.tradeTrails, schema.tradeTrails.termsChangedAt)',
      '_hasColumn(_trails, \'terms_changed_premium_low\')',
      'addColumn(schema.tradeTrails, schema.tradeTrails.termsChangedPremiumLow)',
      '_hasColumn(_trails, \'terms_changed_premium_high\')',
      'addColumn(schema.tradeTrails, schema.tradeTrails.termsChangedPremiumHigh)',
      'createTable(schema.tradePayouts)',
      'customStatement(_dropTradePayoutsNeverDeleted)',
      'customStatement(_dropTradePayoutsForward)',
      'customStatement(_dropTradePayoutsOfTheirTrade)',
      'customStatement(_dropTradePayoutsInsertedOnce)',
      'customStatement(_markPayoutsUnrecorded)',
      'createTrigger(schema.tradePayoutsNeverDeleted)',
      'createTrigger(schema.tradePayoutsForward)',
      'createTrigger(schema.tradePayoutsOfTheirTrade)',
      'createTrigger(schema.tradePayoutsInsertedOnce)',
      'createTrigger(schema.tradeTrailsTermsTrace)',
      'createTrigger(schema.tradePaymentsSatsKnown)',
      'createTrigger(schema.tradePaymentsSatsForward)',
      // Schema 10 (#81): three tables and their triggers, then « Your Garage Keys » made due, the one row the step writes, in its own new table.
      'createTable(schema.derivedGarageKeys)',
      'createTable(schema.selectedGarageKeys)',
      'createTrigger(schema.derivedGarageKeysNeverDeleted)',
      'createTrigger(schema.derivedGarageKeysNeverChanged)',
      'createTrigger(schema.derivedGarageKeysInOrder)',
      'createTrigger(schema.derivedGarageKeysInsertedOnce)',
      'createTable(schema.garageNotices)',
      'createTrigger(schema.garageNoticesShownOnce)',
      'createTrigger(schema.garageNoticesNeverDeleted)',
      'customStatement(_externalKeyNamedDue)',
      // Schema 11 (#81): one table and its triggers, no row written.
      'createTable(schema.garageRecoveryNotes)',
      'createTrigger(schema.garageRecoveryNotesNeverDeleted)',
      'createTrigger(schema.garageRecoveryNotesInsertedOnce)',
      'createTrigger(schema.garageRecoveryNotesForward)',
      'customStatement(_foreignKeysOn)',
    ]);
    // What the two checks read (an invocation is listed before the one it is made on).
    expect(database.callsByMethod['_foreignKeysAreOn'], [
      'getSingle()',
      'customSelect(_foreignKeys)',
    ]);
    expect(database.callsByMethod['_breaksAForeignKey'], [
      'get()',
      'customSelect(_foreignKeyCheck)',
    ]);
    expect(database.constants['_foreignKeysOn'], 'PRAGMA foreign_keys = ON');
    expect(
      database.constants['_dropPaymentsCopy'],
      'DROP TABLE IF EXISTS trade_payments_of_schema6',
    );
    expect(
      database.constants['_copyPayments'],
      'CREATE TABLE trade_payments_of_schema6 AS SELECT * FROM trade_payments',
    );
    expect(database.constants['_dropPayments'], 'DROP TABLE trade_payments');
    // Every string constant of the database, each value as written: the rebuilds' statements that write rows (`_restorePayments`, and since schema 8 `_restoreTrades`, `_restoreTrails`, `_restorePaymentsOfSchema7`) copy each table's own columns from its copy back into that table, each row once, and nowhere else; the copies are the tables as they were; the drops name the rebuilt tables, their copies, their triggers and the trigger schema 8 replaces on `trade_terms`; the pragmas read whether the foreign keys are on and which rows break one, and turn them off for the step to schema 8; a new constant, or another value, fails here (security review of #172).
    expect(database.constants, {
      '_foreignKeysOn': 'PRAGMA foreign_keys = ON',
      'fileName': 'p2p.sqlite',
      '_payments': 'trade_payments',
      '_paymentsCopy': 'trade_payments_of_schema6',
      '_dropPaymentsCopy': 'DROP TABLE IF EXISTS trade_payments_of_schema6',
      '_copyPayments':
          'CREATE TABLE trade_payments_of_schema6 AS SELECT * FROM trade_payments',
      '_dropPayments': 'DROP TABLE trade_payments',
      '_restorePayments':
          'INSERT INTO trade_payments (key_fingerprint, robot_index, step, payment_hash, started_at, wallet_payment_id) '
          'SELECT key_fingerprint, robot_index, step, payment_hash, started_at, wallet_payment_id FROM trade_payments_of_schema6 AS copy '
          'WHERE NOT EXISTS (SELECT 1 FROM trade_payments WHERE trade_payments.key_fingerprint = copy.key_fingerprint AND trade_payments.robot_index = copy.robot_index AND trade_payments.step = copy.step)',
      '_trades': 'trades',
      '_tradesCopy': 'trades_of_schema7',
      '_dropTradesCopy': 'DROP TABLE IF EXISTS trades_of_schema7',
      '_copyTrades': 'CREATE TABLE trades_of_schema7 AS SELECT * FROM trades',
      '_dropTrades': 'DROP TABLE trades',
      '_restoreTrades':
          'INSERT INTO trades (network, key_fingerprint, robot_index, coordinator_alias, coordinator_onion, order_id, role, origin, taken_at, confirmed_at, closed_at) '
          'SELECT network, key_fingerprint, robot_index, coordinator_alias, coordinator_onion, order_id, role, origin, taken_at, confirmed_at, closed_at FROM trades_of_schema7 AS copy '
          'WHERE NOT EXISTS (SELECT 1 FROM trades WHERE trades.key_fingerprint = copy.key_fingerprint AND trades.robot_index = copy.robot_index)',
      '_trails': 'trade_trails',
      '_trailsCopy': 'trade_trails_of_schema7',
      '_dropTrailsCopy': 'DROP TABLE IF EXISTS trade_trails_of_schema7',
      '_copyTrails':
          'CREATE TABLE trade_trails_of_schema7 AS SELECT * FROM trade_trails',
      '_dropTrails': 'DROP TABLE trade_trails',
      '_restoreTrails':
          'INSERT INTO trade_trails (key_fingerprint, robot_index, version, network, coordinator_alias, order_id, role, position, read_at, bond_hash, escrow_hash, deadline, bond_step_seen_at, bond_step_deadline, breached, history_unknown) '
          'SELECT key_fingerprint, robot_index, version, network, coordinator_alias, order_id, role, position, read_at, bond_hash, escrow_hash, deadline, bond_step_seen_at, bond_step_deadline, breached, history_unknown FROM trade_trails_of_schema7 AS copy '
          'WHERE NOT EXISTS (SELECT 1 FROM trade_trails WHERE trade_trails.key_fingerprint = copy.key_fingerprint AND trade_trails.robot_index = copy.robot_index)',
      '_paymentsOfSchema7': 'trade_payments_of_schema7',
      '_dropPaymentsOfSchema7':
          'DROP TABLE IF EXISTS trade_payments_of_schema7',
      '_copyPaymentsOfSchema7':
          'CREATE TABLE trade_payments_of_schema7 AS SELECT * FROM trade_payments',
      '_restorePaymentsOfSchema7':
          'INSERT INTO trade_payments (key_fingerprint, robot_index, step, payment_hash, started_at, wallet_payment_id, take) '
          'SELECT key_fingerprint, robot_index, step, payment_hash, started_at, wallet_payment_id, 0 FROM trade_payments_of_schema7 AS copy '
          'WHERE NOT EXISTS (SELECT 1 FROM trade_payments WHERE trade_payments.key_fingerprint = copy.key_fingerprint AND trade_payments.robot_index = copy.robot_index AND trade_payments.step = copy.step AND trade_payments.take = 0)',
      '_dropTradesOneOpenPerOrder':
          'DROP TRIGGER IF EXISTS trades_one_open_per_order',
      '_dropTradesOneOpenPerOrderUpdate':
          'DROP TRIGGER IF EXISTS trades_one_open_per_order_update',
      '_dropTradesNeverDeleted': 'DROP TRIGGER IF EXISTS trades_never_deleted',
      '_dropTradesSetOnce': 'DROP TRIGGER IF EXISTS trades_set_once',
      '_dropTradesMadePending': 'DROP TRIGGER IF EXISTS trades_made_pending',
      '_dropTradesInsertedOnce': 'DROP TRIGGER IF EXISTS trades_inserted_once',
      '_dropTradeTrailsNeverDeleted':
          'DROP TRIGGER IF EXISTS trade_trails_never_deleted',
      '_dropTradeTrailsInsertedOnce':
          'DROP TRIGGER IF EXISTS trade_trails_inserted_once',
      '_dropTradeTrailsOfTheirTrade':
          'DROP TRIGGER IF EXISTS trade_trails_of_their_trade',
      '_dropTradeTrailsClosed': 'DROP TRIGGER IF EXISTS trade_trails_closed',
      '_dropTradeTrailsForward': 'DROP TRIGGER IF EXISTS trade_trails_forward',
      '_dropTradePaymentsNeverDeleted':
          'DROP TRIGGER IF EXISTS trade_payments_never_deleted',
      '_dropTradePaymentsInsertedOnce':
          'DROP TRIGGER IF EXISTS trade_payments_inserted_once',
      '_dropTradePaymentsOfTheirTrade':
          'DROP TRIGGER IF EXISTS trade_payments_of_their_trade',
      '_dropTradePaymentsForward':
          'DROP TRIGGER IF EXISTS trade_payments_forward',
      '_dropTradePaymentsHashOnce':
          'DROP TRIGGER IF EXISTS trade_payments_hash_once',
      '_dropTermsOfTheirTrade':
          'DROP TRIGGER IF EXISTS trade_terms_of_their_trade',
      // Schema 9 (#204): the triggers of the payouts, dropped while the step writes the marks of the contracts under way, and the statement that writes them, the one row it writes being a mark of a buyer's contract under way, each once.
      '_dropTradePayoutsNeverDeleted':
          'DROP TRIGGER IF EXISTS trade_payouts_never_deleted',
      '_dropTradePayoutsForward':
          'DROP TRIGGER IF EXISTS trade_payouts_forward',
      '_dropTradePayoutsOfTheirTrade':
          'DROP TRIGGER IF EXISTS trade_payouts_of_their_trade',
      '_dropTradePayoutsInsertedOnce':
          'DROP TRIGGER IF EXISTS trade_payouts_inserted_once',
      '_markPayoutsUnrecorded':
          'INSERT INTO trade_payouts (key_fingerprint, robot_index, take, source, kind, submitted_at) '
          "SELECT key_fingerprint, robot_index, take, 'unrecorded', NULL, NULL FROM trade_trails AS trail "
          "WHERE role = 'buyer' AND position NOT IN ('start', 'makerBondStep', 'public', 'paused', 'bondStep', 'preTakeUnavailable', 'publicAgain', 'notAvailable') "
          'AND NOT EXISTS (SELECT 1 FROM trade_payouts WHERE trade_payouts.key_fingerprint = trail.key_fingerprint AND trade_payouts.robot_index = trail.robot_index AND trade_payouts.take = trail.take)',
      '_externalKeyNamedDue':
          "INSERT INTO garage_notices (notice, shown) VALUES ('externalKeyNamed', 0) "
          'ON CONFLICT (notice) DO NOTHING',
      '_foreignKeys': 'PRAGMA foreign_keys',
      '_foreignKeysOff': 'PRAGMA foreign_keys = OFF',
      '_foreignKeyCheck': 'PRAGMA foreign_key_check',
    });
    expect(_rebuildDrops, {
      for (final MapEntry(:key, :value) in database.constants.entries)
        if (key.startsWith('_drop')) value,
    });
    expect(_schema8Rebuild, {
      for (final name in [
        '_copyTrades',
        '_restoreTrades',
        '_copyTrails',
        '_restoreTrails',
        '_copyPaymentsOfSchema7',
        '_restorePaymentsOfSchema7',
      ])
        database.constants[name],
    });
    // The database writes through its pinned `customStatement`s only, and reads through `customSelect` (pinned below): no `customInsert`, `customWriteReturning` or `customUpdate`, whose text could start with an exempted literal of the step's copies (security review of #176, C1).
    expect(
      database.invoked.intersection({
        'customInsert',
        'customWriteReturning',
        'customUpdate',
        'customSelect',
      }),
      {'customSelect'},
    );
    // Its two `customSelect`s, the steps' looks at a table and at a column, and its pragmas as written: no other statement could turn the foreign keys off (review of #102).
    expect(database.calls.where((call) => call.startsWith('customSelect(')), [
      // The step to schema 7's look at a table's text (#97).
      startsWith(
        "customSelect(\"SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?\",",
      ),
      startsWith(
        "customSelect('SELECT 1 FROM pragma_table_info(?) WHERE name = ?',",
      ),
      // The step to schema 8's two checks of the foreign keys (#176), which read and change nothing.
      'customSelect(_foreignKeys)',
      'customSelect(_foreignKeyCheck)',
    ]);
    expect(
      database.strings.where(
        (text) => RegExp(r'\bpragma\b', caseSensitive: false).hasMatch(text),
      ),
      [
        'PRAGMA foreign_keys = ON',
        'PRAGMA foreign_keys',
        // The step to schema 8 turns them off when a connection has them on, before it drops `trades`, and `beforeOpen` turns them on again after every step (functional review of #176).
        'PRAGMA foreign_keys = OFF',
        'PRAGMA foreign_key_check',
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
    // And on the terms and trails, as written in `trade_trails.drift` (#87).
    expect(
      _drifted(File('lib/src/data/trade_trails.drift').readAsStringSync()),
      '${_trailTriggers.join(';')};',
    );
    // And on the payments of the trades' invoices, as written in `trade_payments.drift` (#100).
    expect(
      _drifted(File('lib/src/data/trade_payments.drift').readAsStringSync()),
      '${_paymentTriggers.join(';')};',
    );
    // And on the pins of the trades' chats, PGP and Nostr, as written in `trade_chat_pins.drift` (#139, part of #159).
    expect(
      _drifted(File('lib/src/data/trade_chat_pins.drift').readAsStringSync()),
      '${_pinTriggers.join(';')};',
    );
    // And on the terms a maker asked, as written in `maker_terms.drift` (#176).
    expect(
      _drifted(File('lib/src/data/maker_terms.drift').readAsStringSync()),
      '${_makerTermsTriggers.join(';')};',
    );
    // And on the payouts a buyer gave, per contract, as written in `trade_payouts.drift` (schema 9, #204).
    expect(
      _drifted(File('lib/src/data/trade_payouts.drift').readAsStringSync()),
      '${_payoutTriggers.join(';')};',
    );
    // And on the keys of the words, as written in `garage_keys.drift` (schema 10, #81).
    expect(
      _drifted(File('lib/src/data/garage_keys.drift').readAsStringSync()),
      '${_garageKeyTriggers.join(';')};',
    );
    // No other file holds SQL that writes either table of the pins, but the triggers as drift copies them.
    expect(
      where(
        (facts) => facts.strings.any(
          (text) =>
              RegExp(
                r'\b(into|update|delete\s+from)\s+"?trade_chat_(nostr_)?pins\b',
                caseSensitive: false,
              ).hasMatch(text) &&
              !isDriftTrigger(facts, text),
        ),
      ),
      {'lib/src/data/trade_chat_pin_repository_impl.dart'},
    );
  });

  test(
    'the terms and trails of the trades are written by their repository alone, one statement each, a trail only after whyNotReplace',
    () {
      // No other file holds SQL that writes any of the three tables, but the triggers as drift copies them (#87) and the step to schema 8's copy of the trails back into their table (#176, pinned in the database).
      expect(
        where(
          (facts) => facts.strings.any(
            (text) =>
                RegExp(
                  r'\b(into|update|delete\s+from)\s+"?(trade_(terms|trails)|maker_terms)\b',
                  caseSensitive: false,
                ).hasMatch(text) &&
                !isDriftTrigger(facts, text) &&
                !isSchema8Rebuild(facts, text),
          ),
        ),
        {'lib/src/data/trade_trail_repository_impl.dart'},
      );
      // The tables are named by the database, its repository and drift's code only.
      expect(
        where(
          (facts) =>
              facts.names.contains('storedTradeTerms') ||
              facts.names.contains('storedMakerTerms'),
        ),
        {
          'lib/src/data/trade_trail_repository_impl.dart',
          if (File('lib/src/data/p2p_database.g.dart').existsSync())
            'lib/src/data/p2p_database.g.dart',
        },
      );
      // The trails too, and the trade records' repository, which reads their last position with the closed records in one statement for the history of the Garage (#253) and never writes them: no SQL of it writes a trail (above).
      expect(where((facts) => facts.names.contains('storedTradeTrails')), {
        'lib/src/data/trade_trail_repository_impl.dart',
        'lib/src/data/trade_record_repository_impl.dart',
        if (File('lib/src/data/p2p_database.g.dart').existsSync())
          'lib/src/data/p2p_database.g.dart',
      });
      expect(
        {
          for (final MapEntry(key: method, value: names)
              in (libraries['lib/src/data/trade_record_repository_impl.dart']
                          ?.namesByMethod ??
                      const <String, Set<String>>{})
                  .entries)
            if (names.contains('storedTradeTrails')) method,
        },
        {'watchClosedTrades'},
      );
      final trails =
          libraries['lib/src/data/trade_trail_repository_impl.dart'] ??
          fail('no trails');
      expect(
        trails.invoked.intersection({
          'delete',
          'deleteWhere',
          'deleteAll',
          'update',
          'replace',
          'write',
          'into',
          'batch',
          'customInsert',
          'customUpdate',
          'customStatement',
          'insertOnConflictUpdate',
          'insertAllOnConflictUpdate',
          'transaction',
        }),
        isEmpty,
      );
      for (final text in trails.strings) {
        expect(
          RegExp(
            r'\b(delete|drop|replace|alter|pragma)\b',
            caseSensitive: false,
          ).hasMatch(text),
          isFalse,
          reason: text,
        );
      }
      // Its four writes, as written: the terms of a take, the terms of a make (#176) and a first trail inserted once, a later trail only over the one compared, every column of it, the maker's contract included (#176).
      expect(
        trails.constants['_recordMakerTermsSql'],
        'INSERT INTO maker_terms (key_fingerprint, robot_index, version, '
        'network, coordinator_alias, role, order_type, currency_id, amount, '
        'min_amount, max_amount, premium_percent, payment_method, '
        'bond_size_percent, public_seconds, escrow_seconds, description, '
        'has_password, latitude, longitude, created_price, maker_fee) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT (key_fingerprint, robot_index) DO NOTHING '
        'RETURNING robot_index',
      );
      expect(
        trails.constants['_makerTermsSql'],
        'SELECT version, network, coordinator_alias, role, order_type, '
        'currency_id, amount, min_amount, max_amount, premium_percent, '
        'payment_method, bond_size_percent, public_seconds, escrow_seconds, '
        'description, has_password, latitude, longitude, created_price, '
        'maker_fee FROM maker_terms WHERE key_fingerprint = ? AND robot_index = ?',
      );
      expect(
        trails.constants['_recordTermsSql'],
        'INSERT INTO trade_terms (key_fingerprint, robot_index, version, '
        'network, coordinator_alias, order_id, role, order_type, currency_id, '
        'amount, is_range, premium_percent, explicit_satoshis, '
        'bond_size_percent, escrow_seconds, book_price, taker_fee) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT (key_fingerprint, robot_index) DO NOTHING '
        'RETURNING robot_index',
      );
      expect(
        trails.constants['_insertTrailSql'],
        'INSERT INTO trade_trails (key_fingerprint, robot_index, version, '
        'network, coordinator_alias, order_id, role, position, read_at, '
        'bond_hash, escrow_hash, deadline, bond_step_seen_at, '
        'bond_step_deadline, breached, history_unknown, take, take_deadline, '
        'taker_hash_id, taken_amount, earlier_escrows, seen_late, '
        'terms_changed_at, terms_changed_premium_low, terms_changed_premium_high) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '
        '?, ?, ?) '
        'ON CONFLICT (key_fingerprint, robot_index) DO NOTHING '
        'RETURNING robot_index',
      );
      expect(
        trails.constants['_replaceTrailSql'],
        'UPDATE trade_trails SET version = ?, position = ?, read_at = ?, '
        'bond_hash = ?, escrow_hash = ?, deadline = ?, bond_step_seen_at = ?, '
        'bond_step_deadline = ?, breached = ?, history_unknown = ?, take = ?, '
        'take_deadline = ?, taker_hash_id = ?, taken_amount = ?, '
        'earlier_escrows = ?, seen_late = ?, terms_changed_at = ?, '
        'terms_changed_premium_low = ?, terms_changed_premium_high = ? '
        'WHERE key_fingerprint = ? AND robot_index = ? AND version IS ? '
        'AND network IS ? AND coordinator_alias IS ? AND order_id IS ? '
        'AND role IS ? AND position IS ? AND read_at IS ? AND bond_hash IS ? '
        'AND escrow_hash IS ? AND deadline IS ? AND bond_step_seen_at IS ? '
        'AND bond_step_deadline IS ? AND breached IS ? AND history_unknown IS ? '
        'AND take IS ? AND take_deadline IS ? AND taker_hash_id IS ? '
        'AND taken_amount IS ? AND earlier_escrows IS ? AND seen_late IS ? '
        'AND terms_changed_at IS ? AND terms_changed_premium_low IS ? '
        'AND terms_changed_premium_high IS ? '
        'RETURNING robot_index',
      );
      final pinned = [
        for (final name in [
          '_recordMakerTermsSql',
          '_recordTermsSql',
          '_insertTrailSql',
          '_replaceTrailSql',
        ])
          trails.constants[name] ?? fail('no $name'),
      ];
      expect(
        trails.strings.where(
          (text) =>
              RegExp(
                r'\b(insert|update)\b',
                caseSensitive: false,
              ).hasMatch(text) &&
              !pinned.any((statement) => statement.contains(text)),
        ),
        isEmpty,
      );
      // The terms by `recordTerms` alone, a make's terms by `recordMakerTerms` alone; the trails by `storeTrail` alone, which asks `whyNotReplace` of the stored trail before either write.
      final writes = trails.calls.where(
        (call) => call.startsWith('customWriteReturning('),
      );
      expect(writes, hasLength(4));
      expect(
        trails.callsByMethod['recordTerms']?.where(
          (call) => call.startsWith('customWriteReturning('),
        ),
        [startsWith('customWriteReturning(_recordTermsSql,')],
      );
      expect(
        trails.callsByMethod['recordMakerTerms']?.where(
          (call) => call.startsWith('customWriteReturning('),
        ),
        [startsWith('customWriteReturning(_recordMakerTermsSql,')],
      );
      final store = trails.callsByMethod['storeTrail'] ?? fail('no storeTrail');
      final asked = store.indexWhere(
        (call) => call.startsWith('whyNotReplace('),
      );
      final firstWrite = store.indexWhere(
        (call) => call.startsWith('customWriteReturning('),
      );
      expect(asked, isNonNegative);
      expect(firstWrite, greaterThan(asked));
      expect(store.where((call) => call.startsWith('customWriteReturning(')), [
        startsWith('customWriteReturning(_insertTrailSql,'),
        startsWith('customWriteReturning(_replaceTrailSql,'),
      ]);
    },
  );

  test(
    'only the database runs a pragma, a statement of its own or a CREATE, the pragmas it runs pinned above',
    () {
      // A pragma turns a protection of the whole connection on or off (`PRAGMA foreign_keys = OFF` in a repository would let every write that needs a trade through until the next start): only `P2pDatabase` holds one, each pinned by value in « nothing changes or deletes a binding » (security review of #176).
      expect(
        where(
          (facts) => facts.strings.any(
            (text) => RegExp(
              r'\bpragma\b|foreign_keys',
              caseSensitive: false,
            ).hasMatch(text),
          ),
        ),
        {'lib/src/data/p2p_database.dart'},
      );
      // And no other file names `customStatement`, called or torn off, through which any statement could run unseen by the pins of the repositories' writes.
      expect(where((facts) => facts.names.contains('customStatement')), {
        'lib/src/data/p2p_database.dart',
      });
      // Nor makes a table, a trigger, an index or a view: the database's copies of the step to schema 8 and drift's code only (a repository could otherwise copy a table aside unseen).
      expect(
        where(
          (facts) => facts.strings.any(
            (text) => RegExp(
              r'\bcreate\s+(unique\s+|temp\s+|temporary\s+)?(table|trigger|index|view)\b',
              caseSensitive: false,
            ).hasMatch(text),
          ),
        ),
        {
          'lib/src/data/p2p_database.dart',
          'lib/src/data/p2p_database.steps.dart',
          if (File('lib/src/data/p2p_database.g.dart').existsSync())
            'lib/src/data/p2p_database.g.dart',
        },
      );
      // The check sees a pragma in an adjacent string and a torn-off `customStatement`.
      final mutant = _Facts.of(
        "Future<void> f(dynamic d) async { final run = d.customStatement; await run('PRAGMA ' 'foreign_keys = OFF'); }",
      );
      expect(mutant.names, contains('customStatement'));
      expect(
        mutant.strings.any(
          (text) => RegExp(r'\bpragma\b', caseSensitive: false).hasMatch(text),
        ),
        isTrue,
      );
    },
  );

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
    // Its only SQL that changes a row: the two changes of a record, on the trades, each setting one time that is still unset, and the two of a pending make (#176): its order id with its confirmation, once, or its close.
    final confirm = trades.constants['_confirmSql'] ?? fail('no _confirmSql');
    final close = trades.constants['_closeSql'] ?? fail('no _closeSql');
    final confirmMake =
        trades.constants['_confirmMakeSql'] ?? fail('no _confirmMakeSql');
    final closeMake =
        trades.constants['_closePendingMakeSql'] ??
        fail('no _closePendingMakeSql');
    expect(
      confirmMake,
      'UPDATE trades SET order_id = ?, confirmed_at = ? WHERE key_fingerprint = ? '
      "AND robot_index = ? AND network = ? AND origin = 'madeHere' "
      'AND order_id IS NULL AND confirmed_at IS NULL AND closed_at IS NULL',
    );
    expect(
      closeMake,
      'UPDATE trades SET closed_at = ? WHERE key_fingerprint = ? '
      "AND robot_index = ? AND network = ? AND origin = 'madeHere' "
      'AND order_id IS NULL AND closed_at IS NULL',
    );
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
            !close.contains(text) &&
            !confirmMake.contains(text) &&
            !closeMake.contains(text),
      ),
      isEmpty,
    );
    // The two of a record run by one helper, from the two methods that name them; the two of a pending make each by its own method.
    expect(
      trades.calls.where((call) => call.startsWith('customUpdate(')),
      hasLength(3),
    );
    expect(
      trades.callsByMethod['confirmMake']?.where(
        (call) => call.startsWith('customUpdate('),
      ),
      [startsWith('customUpdate(_confirmMakeSql,')],
    );
    expect(
      trades.callsByMethod['closePendingMake']?.where(
        (call) => call.startsWith('customUpdate('),
      ),
      [startsWith('customUpdate(_closePendingMakeSql,')],
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
              !isDriftTrigger(facts, text),
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
      expect(writes, hasLength(4));
      for (final (method, statement) in [
        ('reserveForNewTrade', '_reserveSql'),
        ('recordPendingTake', '_recordPendingTakeSql'),
        ('recordPendingMake', '_recordPendingMakeSql'),
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
      // The statements, as written: the reservation binds only a free index with no trade, of any key (decided on 2026-11-26, #81), as `generated`; a pending take is `takenHere` and needs a binding `generated` on the reservation's network to that coordinator; a recovered trade is `recovered`, confirmed at once, and needs a binding to that coordinator.
      expect(
        trades.constants['_reserveSql'],
        'INSERT INTO robot_bindings (network, key_fingerprint, robot_index, '
        'coordinator_alias, coordinator_onion, coordinator_node_keys, '
        'coordinator_nostr_key, bound_at, provenance) '
        'SELECT ?, ?, ?, ?, ?, ?, ?, ?, ? '
        'WHERE NOT EXISTS (SELECT 1 FROM trades '
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
        'ON CONFLICT (key_fingerprint, robot_index) DO NOTHING '
        'RETURNING *',
      );
      // A pending make (#176) is `madeHere`, has no order id yet, and needs what a pending take needs.
      expect(
        trades.constants['_recordPendingMakeSql'],
        'INSERT INTO trades (network, key_fingerprint, robot_index, '
        'coordinator_alias, coordinator_onion, order_id, role, origin, '
        'taken_at, confirmed_at, closed_at) '
        "SELECT network, key_fingerprint, robot_index, coordinator_alias, "
        "coordinator_onion, NULL, ?, 'madeHere', ?, NULL, NULL "
        'FROM robot_bindings WHERE key_fingerprint = ? AND robot_index = ? '
        'AND network = ? AND provenance = ? AND coordinator_alias = ? '
        'AND coordinator_onion = ? AND coordinator_node_keys = ? '
        'AND coordinator_nostr_key = ? '
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
          '_recordPendingMakeSql',
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
      // `madeHere` is written by the pending make alone; the make's two changes and the pending makes' read only name it.
      final makes = [
        pinned[3],
        for (final name in [
          '_confirmMakeSql',
          '_closePendingMakeSql',
          '_pendingMakesSql',
        ])
          trades.constants[name] ?? fail('no $name'),
      ];
      expect(
        trades.strings.where((text) => text.contains("'madeHere'")),
        everyElement(
          predicate<String>(
            (text) => makes.any((statement) => statement.contains(text)),
          ),
        ),
      );
      expect(
        makes.skip(1),
        everyElement(
          isNot(matches(RegExp(r'\binsert\b', caseSensitive: false))),
        ),
      );
      // And no other file of the feature inserts into the bindings or the trades but the two repositories, and the step to schema 8's copy of the trades back.
      expect(
        where(
          (facts) => facts.strings.any(
            (text) =>
                RegExp(
                  r'\binsert\s+into\s+(robot_bindings|trades)\b',
                  caseSensitive: false,
                ).hasMatch(text) &&
                // The step to schema 8 copies the trades back from their copy, as pinned in the database (#176).
                !isSchema8Rebuild(facts, text),
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
      // The pending make (#176): who writes it, confirms it with its order id, or closes it.
      'recordPendingMake',
      'confirmMake',
      'closePendingMake',
    },
  ),
  // The terms and trails of the trades (#87), and the terms of a make (#176): who writes them.
  'TradeTrailRepository': (
    'package:p2p/',
    {'recordTerms', 'storeTrail', 'recordMakerTerms'},
  ),
  // The fresh trails of the state machine (#86, #87): only the take starts a trade, only the take and the resolution of a pending take read one on a pending take's trail.
  // A maker's trade starts from the first read of its order (#178), which only the make use case and its resumptions are to name (#179).
  'TradeStatus': ('package:p2p/', {'afterTake', 'afterMake'}),
  // The gap from the rate of the creation, slow on a huge figure: only the state machine computes it, from an order the package bounded (#178).
  'MakerTerms': ('package:p2p/', {'rateGap'}),
  'TradeTrail': (
    'package:p2p/',
    {'forPendingTake', 'recovered', 'forConfirmedMake'},
  ),
  // What the trade use cases share, which writes trails and closes records, and the acknowledgement of a bond lost (review of #117).
  'TradeReader': (
    'package:p2p/',
    {
      'open',
      'readOrder',
      'readOrderOf',
      'advance',
      'keep',
      'closeAtEnd',
      'closeNeverSent',
    },
  ),
  'BondLossAcknowledged': ('package:p2p/', {'fromConfirmationDialog'}),
  // The steps of a take, which only the take's cubit calls, through the composition (#119): the take in one step is for the tests alone; since #245 the read and the preparation of a password-protected order too, which the cubits of its page call through the composition.
  'TakeOrderUsecase': (
    'package:p2p/',
    {
      'execute',
      'prepare',
      'confirm',
      'abandon',
      'abandonOrder',
      'readUnlisted',
      'prepareUnlisted',
      'abandonRead',
    },
  ),
  // The takes prepared and not sent, which hold a reserved robot and its token (review of #126).
  'PreparedTakes': (
    'package:p2p/',
    {
      'robotFor',
      'keepRobot',
      'add',
      'robotOf',
      'forget',
      'release',
      'releaseOrder',
    },
  ),
  'GarageKeyRepository': ('package:p2p/', {'import', 'activateNext'}),
  'GarageKeys': ('package:secrets/', {'create', 'import', 'delete'}),
  // The keys of the words (#81): who activates one.
  'GarageKeyBookRepository': ('package:p2p/', {'activate'}),
  'NewGarageKeyUsecase': ('package:p2p/', {'execute'}),
  'FetchRobotUsecase': ('package:p2p/', {'execute'}),
  'CloseRobotSessionsUsecase': ('package:p2p/', {'execute'}),
  'CoordinatorSessionsPort': ('package:p2p/', {'closeRobotSessions'}),
  'RobotContact': ('package:p2p/', {'firstContact'}),
  // The robot use cases of the Garage's panel, and what its cubit and widgets must not reach but through them (#29, step 5).
  'PutRobotOnCoordinatorUsecase': ('package:p2p/', {'execute'}),
  'RobotCoordinatorCubit': ('package:p2p/', {'putOn', 'retry', 'acknowledge'}),
  // The acknowledgement of a key of unknown history, which only the user's « I understand » records (#29, step 6).
  'AcknowledgeGarageKeyHistoryUsecase': ('package:p2p/', {'execute'}),
  'ReadRobotOnCoordinatorUsecase': (
    'package:p2p/',
    {'execute', 'provenPairOf'},
  ),
  // The keyring of the trades (#90): who unlocks a robot's key, who keeps it, who signs with it.
  'TradeKeyring': ('package:p2p/', {'hold', 'lease', 'leaseRobot', 'signWith'}),
  'TradeKeyLease': ('package:p2p/', {'key'}),
  'RobotKeyComputePort': ('package:p2p/', {'unlock', 'decryptChat'}),
  'UnlockedRobotPgpKey': (
    'package:robosats/',
    {
      'signCleartext',
      'signPayoutInvoice',
      'signPayoutAddress',
      'encryptChatMessage',
      'encryptChatMessageWith',
      'encryptChatMessageToPost',
      'decryptChatMessage',
      'chatDecryption',
    },
  ),
  'ChatDecryptionKey': ('package:robosats/', {'decryptChatMessage'}),
  'ReleaseRobotUsecase': ('package:p2p/', {'execute'}),
  'RobotRequestLimiter': ('package:p2p/', <String>{}),
  // The requests of one call, through the limiter's places (#87: a trade use case reads only through them).
  'RobotRequests': ('package:p2p/', <String>{}),
  'CoordinatorClient': ('package:robosats/', <String>{}),
  'P2pDatabase': ('package:p2p/', <String>{}),
  'UnprovenCoordinatorRobot': ('package:robosats/', {'prove', 'parse'}),
  'CoordinatorRobotAnswer': ('package:robosats/', {'parse'}),
  'RobotPgpKey': (
    'package:robosats/',
    {
      'generate',
      'generateWith',
      'unlock',
      'proveMadeBy',
      'encryptedPrivateKeyArmored',
    },
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
  // Flutter's own ways to an image or a file over the network, each with `dart:io`'s client and its default user agent (security review of #246).
  'package:flutter/src/painting/': {'NetworkImage'},
  'package:flutter/src/services/': {'NetworkAssetBundle'},
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
    // A name resolved by the device's resolver, and a socket that blocks (security review of #246).
    'InternetAddress',
    'RawSynchronousSocket',
  },
};

/// The constructors that fetch over the network, by the library and the class that declare them: their class is no client of its own (`Image` also draws a bundled asset).
const _networkConstructors = {
  'package:flutter/src/widgets/': {
    'Image': {'network'},
    'FadeInImage': {'assetNetwork', 'memoryNetwork'},
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

  /// A constructor named, invoked or torn off, of [_networkConstructors].
  @override
  void visitConstructorName(ConstructorName node) {
    final constructor = node.element;
    if (constructor != null) {
      final owner = constructor.enclosingElement;
      for (final MapEntry(key: library, value: classes)
          in _networkConstructors.entries) {
        if (_in(owner, library) &&
            (classes[owner.name]?.contains(constructor.name) ?? false)) {
          _add('network ${owner.name}.${constructor.name}');
        }
      }
    }
    super.visitConstructorName(node);
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
const _makeOrderUseCase = '${_tradeUseCases}make_order_usecase.dart';
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

/// The four triggers of the trades, as `trades.drift` writes them.
final _tradeTriggers = {
  for (final trigger in _tradeTriggersAsWritten) _squeezed(trigger),
};

/// The four triggers, as `trades.drift` writes them: since schema 8 (#176), `trades_set_once` lets a pending make gain its order id once, with its confirmation, once its terms are recorded, and `trades_made_pending` records a make pending only.
const _tradeTriggersAsWritten = [
  "CREATE TRIGGER IF NOT EXISTS trades_never_deleted BEFORE DELETE ON trades BEGIN SELECT RAISE(ABORT, 'a trade record is kept'); END",
  "CREATE TRIGGER IF NOT EXISTS trades_set_once BEFORE UPDATE ON trades WHEN OLD.closed_at IS NOT NULL OR (OLD.confirmed_at IS NOT NULL AND NEW.confirmed_at IS NOT OLD.confirmed_at) OR NEW.network IS NOT OLD.network OR NEW.key_fingerprint IS NOT OLD.key_fingerprint OR NEW.robot_index IS NOT OLD.robot_index OR NEW.coordinator_alias IS NOT OLD.coordinator_alias OR NEW.coordinator_onion IS NOT OLD.coordinator_onion OR (NEW.order_id IS NOT OLD.order_id AND NOT (OLD.origin IS 'madeHere' AND OLD.order_id IS NULL AND OLD.confirmed_at IS NULL AND NEW.confirmed_at IS NOT NULL AND EXISTS (SELECT 1 FROM maker_terms WHERE key_fingerprint = OLD.key_fingerprint AND robot_index = OLD.robot_index))) OR NEW.role IS NOT OLD.role OR NEW.origin IS NOT OLD.origin OR NEW.taken_at IS NOT OLD.taken_at BEGIN SELECT RAISE(ABORT, 'a trade record only gains its times'); END",
  "CREATE TRIGGER IF NOT EXISTS trades_made_pending BEFORE INSERT ON trades WHEN NEW.origin IS 'madeHere' AND (NEW.order_id IS NOT NULL OR NEW.closed_at IS NOT NULL) BEGIN SELECT RAISE(ABORT, 'a make is recorded pending'); END",
  "CREATE TRIGGER IF NOT EXISTS trades_inserted_once BEFORE INSERT ON trades WHEN EXISTS (SELECT 1 FROM trades WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index) BEGIN SELECT RAISE(IGNORE); END",
];

/// The statements of `trades.drift`, in order.
final _tradeRules = [
  _squeezed(
    'CREATE UNIQUE INDEX IF NOT EXISTS robot_bindings_network ON robot_bindings (key_fingerprint, robot_index, network)',
  ),
  ..._tradeTriggers,
];

/// The statements of `trade_trails.drift` (#87), as written: the terms set once and kept, the trails written once, then only forward, never deleted, never written again once their trade is closed; since schema 8 (#176), one open trade per order when an order id is written later too, a taker's terms only for a trade taken here or recovered, a trail only for a trade whose order id is known, and a maker's contract only forward.
const _trailTriggersAsWritten = [
  "CREATE TRIGGER IF NOT EXISTS trades_one_open_per_order BEFORE INSERT ON trades WHEN EXISTS (SELECT 1 FROM trades WHERE network = NEW.network AND coordinator_alias = NEW.coordinator_alias AND order_id = NEW.order_id AND closed_at IS NULL) BEGIN SELECT RAISE(ABORT, 'an order has one open trade'); END",
  "CREATE TRIGGER IF NOT EXISTS trades_one_open_per_order_update BEFORE UPDATE OF order_id ON trades WHEN EXISTS (SELECT 1 FROM trades WHERE network = NEW.network AND coordinator_alias = NEW.coordinator_alias AND order_id = NEW.order_id AND closed_at IS NULL AND NOT (key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index)) BEGIN SELECT RAISE(ABORT, 'an order has one open trade'); END",
  "CREATE TRIGGER IF NOT EXISTS trade_terms_never_deleted BEFORE DELETE ON trade_terms BEGIN SELECT RAISE(ABORT, 'the terms of a trade are kept'); END",
  "CREATE TRIGGER IF NOT EXISTS trade_terms_set_once BEFORE UPDATE ON trade_terms BEGIN SELECT RAISE(ABORT, 'the terms of a trade are set once'); END",
  "CREATE TRIGGER IF NOT EXISTS trade_terms_inserted_once BEFORE INSERT ON trade_terms WHEN EXISTS (SELECT 1 FROM trade_terms WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index) BEGIN SELECT RAISE(IGNORE); END",
  "CREATE TRIGGER IF NOT EXISTS trade_terms_of_their_trade BEFORE INSERT ON trade_terms WHEN NOT EXISTS (SELECT 1 FROM trades WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index AND network = NEW.network AND coordinator_alias = NEW.coordinator_alias AND order_id = NEW.order_id AND role = NEW.role AND origin IN ('takenHere', 'recovered') AND closed_at IS NULL) BEGIN SELECT RAISE(ABORT, 'terms of no open trade'); END",
  "CREATE TRIGGER IF NOT EXISTS trade_trails_never_deleted BEFORE DELETE ON trade_trails BEGIN SELECT RAISE(ABORT, 'the trail of a trade is kept'); END",
  "CREATE TRIGGER IF NOT EXISTS trade_trails_inserted_once BEFORE INSERT ON trade_trails WHEN EXISTS (SELECT 1 FROM trade_trails WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index) BEGIN SELECT RAISE(IGNORE); END",
  "CREATE TRIGGER IF NOT EXISTS trade_trails_of_their_trade BEFORE INSERT ON trade_trails WHEN NOT EXISTS (SELECT 1 FROM trades WHERE trades.key_fingerprint = NEW.key_fingerprint AND trades.robot_index = NEW.robot_index AND trades.network = NEW.network AND trades.coordinator_alias = NEW.coordinator_alias AND trades.order_id = NEW.order_id AND trades.role = NEW.role AND trades.closed_at IS NULL AND NEW.take = 0 AND ((trades.origin IN ('takenHere', 'recovered') AND NEW.take_deadline IS NULL AND NEW.taker_hash_id IS NULL AND NEW.taken_amount IS NULL AND EXISTS (SELECT 1 FROM trade_terms WHERE trade_terms.key_fingerprint = trades.key_fingerprint AND trade_terms.robot_index = trades.robot_index)) OR (trades.origin = 'madeHere' AND EXISTS (SELECT 1 FROM maker_terms WHERE maker_terms.key_fingerprint = trades.key_fingerprint AND maker_terms.robot_index = trades.robot_index)))) BEGIN SELECT RAISE(ABORT, 'a trail of no open trade'); END",
  "CREATE TRIGGER IF NOT EXISTS trade_trails_closed BEFORE UPDATE ON trade_trails WHEN EXISTS (SELECT 1 FROM trades WHERE key_fingerprint = OLD.key_fingerprint AND robot_index = OLD.robot_index AND closed_at IS NOT NULL) BEGIN SELECT RAISE(IGNORE); END",
  "CREATE TRIGGER IF NOT EXISTS trade_trails_forward BEFORE UPDATE ON trade_trails WHEN NEW.key_fingerprint IS NOT OLD.key_fingerprint OR NEW.robot_index IS NOT OLD.robot_index OR NEW.network IS NOT OLD.network OR NEW.coordinator_alias IS NOT OLD.coordinator_alias OR NEW.order_id IS NOT OLD.order_id OR NEW.role IS NOT OLD.role OR NEW.version < OLD.version OR NEW.read_at < OLD.read_at OR NEW.breached < OLD.breached OR NEW.history_unknown IS NOT OLD.history_unknown OR (OLD.bond_hash IS NOT NULL AND NEW.bond_hash IS NOT OLD.bond_hash) OR (OLD.escrow_hash IS NOT NULL AND NEW.escrow_hash IS NOT OLD.escrow_hash AND NEW.take IS OLD.take) OR (OLD.escrow_hash IS NOT NULL AND NEW.escrow_hash IS OLD.escrow_hash AND NEW.take IS NOT OLD.take) OR (OLD.bond_step_seen_at IS NOT NULL AND (NEW.bond_step_seen_at IS NULL OR NEW.bond_step_seen_at < OLD.bond_step_seen_at)) OR (OLD.bond_step_deadline IS NOT NULL AND NEW.bond_step_deadline IS NULL) OR (OLD.position IN ('succeeded', 'makerLostDispute', 'takerLostDispute', 'expired', 'cancelled', 'publicAgain', 'notAvailable') AND NEW.position IS NOT OLD.position) OR (NEW.take IS NOT OLD.take AND NOT (NEW.take IS OLD.take + 1 AND OLD.position IN ('public', 'paused', 'waitingForBoth', 'waitingForEscrow', 'waitingForPayout') AND NOT (OLD.position = 'waitingForPayout' AND OLD.role = 'buyer') AND OLD.take_deadline IS NOT NULL AND ((NEW.position IN ('waitingForBoth', 'waitingForEscrow', 'waitingForPayout') AND NEW.take_deadline IS NOT NULL AND NEW.take_deadline > OLD.take_deadline AND NEW.seen_late = 0) OR (NEW.position IN ('chatting', 'fiatSent', 'inDispute', 'sendingSats', 'succeeded', 'routingFailed', 'waitingDisputeResolution', 'makerLostDispute', 'takerLostDispute') AND NEW.take_deadline IS OLD.take_deadline AND NEW.taker_hash_id IS NOT NULL AND NEW.escrow_hash IS NULL AND (OLD.position IN ('public', 'paused') OR NEW.taker_hash_id IS NOT OLD.taker_hash_id) AND NEW.seen_late = 1)) AND NEW.earlier_escrows IS (OLD.earlier_escrows || coalesce(OLD.escrow_hash || ';', '')) AND EXISTS (SELECT 1 FROM trades WHERE key_fingerprint = OLD.key_fingerprint AND robot_index = OLD.robot_index AND origin = 'madeHere'))) OR (NEW.take IS OLD.take AND (NEW.earlier_escrows IS NOT OLD.earlier_escrows OR NEW.seen_late IS NOT OLD.seen_late)) OR (NEW.escrow_hash IS NOT NULL AND instr(';' || NEW.earlier_escrows, ';' || NEW.escrow_hash || ';') > 0) OR (OLD.take_deadline IS NOT NULL AND NEW.take_deadline IS NULL) OR (OLD.taker_hash_id IS NOT NULL AND NEW.taker_hash_id IS NULL) OR (OLD.taken_amount IS NOT NULL AND NEW.taken_amount IS NULL) OR (NEW.take IS OLD.take AND OLD.take_deadline IS NOT NULL AND NEW.take_deadline IS NOT OLD.take_deadline) OR (NEW.take IS OLD.take AND OLD.taker_hash_id IS NOT NULL AND NEW.taker_hash_id IS NOT OLD.taker_hash_id) OR (NEW.take IS OLD.take AND OLD.taken_amount IS NOT NULL AND NEW.taken_amount IS NOT OLD.taken_amount) OR (NEW.take IS NOT OLD.take AND OLD.taker_hash_id IS NULL AND NEW.taker_hash_id IS NOT NULL) OR (NEW.take IS NOT OLD.take AND OLD.taken_amount IS NULL AND NEW.taken_amount IS NOT NULL) OR ((NEW.take_deadline IS NOT NULL OR NEW.taker_hash_id IS NOT NULL OR NEW.taken_amount IS NOT NULL) AND NOT EXISTS (SELECT 1 FROM trades WHERE key_fingerprint = OLD.key_fingerprint AND robot_index = OLD.robot_index AND origin = 'madeHere')) BEGIN SELECT RAISE(ABORT, 'a trail only moves forward'); END",
  // Schema 9 (#231; security verification, R8): the trace of terms shown otherwise, its time set once with its read's, its lowest premium only going down, its highest only up, neither cleared, without a subquery.
  "CREATE TRIGGER IF NOT EXISTS trade_trails_terms_trace BEFORE UPDATE ON trade_trails WHEN (OLD.terms_changed_at IS NOT NULL AND NEW.terms_changed_at IS NOT OLD.terms_changed_at) OR (OLD.terms_changed_at IS NULL AND NEW.terms_changed_at IS NOT NULL AND NEW.terms_changed_at IS NOT NEW.read_at) OR (OLD.terms_changed_premium_low IS NOT NULL AND (NEW.terms_changed_premium_low IS NULL OR NEW.terms_changed_premium_low > OLD.terms_changed_premium_low)) OR (OLD.terms_changed_premium_high IS NOT NULL AND (NEW.terms_changed_premium_high IS NULL OR NEW.terms_changed_premium_high < OLD.terms_changed_premium_high)) BEGIN SELECT RAISE(ABORT, 'the trace of terms shown otherwise is kept'); END",
];

/// The triggers of `trade_trails.drift`, squeezed.
final _trailTriggers = [
  for (final trigger in _trailTriggersAsWritten) _squeezed(trigger),
];

/// The statements of `trade_payments.drift` (#100), as written: the payments of the trades' invoices written once per trade, step and contract (schema 8, #176), only for an open trade whose trail is recorded at that contract, then only forward, never deleted, and never two of one payment hash.
const _paymentTriggersAsWritten = [
  "CREATE TRIGGER IF NOT EXISTS trade_payments_never_deleted BEFORE DELETE ON trade_payments BEGIN SELECT RAISE(ABORT, 'the payment of a trade is kept'); END",
  "CREATE TRIGGER IF NOT EXISTS trade_payments_inserted_once BEFORE INSERT ON trade_payments WHEN EXISTS (SELECT 1 FROM trade_payments WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index AND step = NEW.step AND take = NEW.take) BEGIN SELECT RAISE(IGNORE); END",
  "CREATE TRIGGER IF NOT EXISTS trade_payments_of_their_trade BEFORE INSERT ON trade_payments WHEN NOT EXISTS (SELECT 1 FROM trades JOIN trade_trails ON trade_trails.key_fingerprint = trades.key_fingerprint AND trade_trails.robot_index = trades.robot_index WHERE trades.key_fingerprint = NEW.key_fingerprint AND trades.robot_index = NEW.robot_index AND trades.closed_at IS NULL AND trade_trails.take = NEW.take AND (NEW.take = 0 OR trades.origin = 'madeHere')) BEGIN SELECT RAISE(ABORT, 'a payment of no open trade'); END",
  "CREATE TRIGGER IF NOT EXISTS trade_payments_forward BEFORE UPDATE ON trade_payments WHEN NEW.key_fingerprint IS NOT OLD.key_fingerprint OR NEW.robot_index IS NOT OLD.robot_index OR NEW.step IS NOT OLD.step OR NEW.payment_hash IS NOT OLD.payment_hash OR NEW.started_at < OLD.started_at OR NEW.take IS NOT OLD.take BEGIN SELECT RAISE(ABORT, 'a payment only moves forward'); END",
  "CREATE TRIGGER IF NOT EXISTS trade_payments_hash_once BEFORE INSERT ON trade_payments WHEN EXISTS (SELECT 1 FROM trade_payments WHERE payment_hash = NEW.payment_hash AND NOT (key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index AND step = NEW.step AND take = NEW.take)) BEGIN SELECT RAISE(ABORT, 'an invoice is paid once'); END",
  // Schema 9 (#233): a payment recorded with its amount, which never goes down, nor appears for a payment whose amount was unknown.
  "CREATE TRIGGER IF NOT EXISTS trade_payments_sats_known BEFORE INSERT ON trade_payments WHEN NEW.confirmed_sats IS NULL BEGIN SELECT RAISE(ABORT, 'a payment is recorded with its amount'); END",
  "CREATE TRIGGER IF NOT EXISTS trade_payments_sats_forward BEFORE UPDATE ON trade_payments WHEN (OLD.confirmed_sats IS NULL AND NEW.confirmed_sats IS NOT NULL) OR (OLD.confirmed_sats IS NOT NULL AND (NEW.confirmed_sats IS NULL OR NEW.confirmed_sats < OLD.confirmed_sats)) BEGIN SELECT RAISE(ABORT, 'the amount of a payment never goes down'); END",
];

/// The triggers of `trade_payments.drift`, squeezed.
final _paymentTriggers = [
  for (final trigger in _paymentTriggersAsWritten) _squeezed(trigger),
];

/// The statements of `trade_chat_pins.drift` (#139, part of #159), as written: the PGP pin and the Nostr pin of a trade's chat each written once, only for an open trade, never changed nor deleted.
const _pinTriggersAsWritten = [
  "CREATE TRIGGER IF NOT EXISTS trade_chat_pins_never_deleted BEFORE DELETE ON trade_chat_pins BEGIN SELECT RAISE(ABORT, 'the pinned key of a trade is kept'); END",
  "CREATE TRIGGER IF NOT EXISTS trade_chat_pins_never_changed BEFORE UPDATE ON trade_chat_pins BEGIN SELECT RAISE(ABORT, 'the pinned key of a trade never changes'); END",
  "CREATE TRIGGER IF NOT EXISTS trade_chat_pins_inserted_once BEFORE INSERT ON trade_chat_pins WHEN EXISTS (SELECT 1 FROM trade_chat_pins WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index) BEGIN SELECT RAISE(IGNORE); END",
  "CREATE TRIGGER IF NOT EXISTS trade_chat_pins_of_their_trade BEFORE INSERT ON trade_chat_pins WHEN NOT EXISTS (SELECT 1 FROM trades WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index AND closed_at IS NULL) BEGIN SELECT RAISE(ABORT, 'a pin of no open trade'); END",
  "CREATE TRIGGER IF NOT EXISTS trade_chat_nostr_pins_never_deleted BEFORE DELETE ON trade_chat_nostr_pins BEGIN SELECT RAISE(ABORT, 'the Nostr keys of a trade are kept'); END",
  "CREATE TRIGGER IF NOT EXISTS trade_chat_nostr_pins_never_changed BEFORE UPDATE ON trade_chat_nostr_pins BEGIN SELECT RAISE(ABORT, 'the Nostr keys of a trade never change'); END",
  "CREATE TRIGGER IF NOT EXISTS trade_chat_nostr_pins_inserted_once BEFORE INSERT ON trade_chat_nostr_pins WHEN EXISTS (SELECT 1 FROM trade_chat_nostr_pins WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index) BEGIN SELECT RAISE(IGNORE); END",
  "CREATE TRIGGER IF NOT EXISTS trade_chat_nostr_pins_of_their_trade BEFORE INSERT ON trade_chat_nostr_pins WHEN NOT EXISTS (SELECT 1 FROM trades WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index AND closed_at IS NULL) BEGIN SELECT RAISE(ABORT, 'a Nostr pin of no open trade'); END",
];

/// The triggers of `trade_chat_pins.drift`, squeezed.
final _pinTriggers = [
  for (final trigger in _pinTriggersAsWritten) _squeezed(trigger),
];

/// The statements of `maker_terms.drift` (#176), as written: the terms a maker asked written once, only for a pending make of the same network, coordinator and role, never changed nor deleted.
const _makerTermsTriggersAsWritten = [
  "CREATE TRIGGER IF NOT EXISTS maker_terms_never_deleted BEFORE DELETE ON maker_terms BEGIN SELECT RAISE(ABORT, 'the terms of a make are kept'); END",
  "CREATE TRIGGER IF NOT EXISTS maker_terms_set_once BEFORE UPDATE ON maker_terms BEGIN SELECT RAISE(ABORT, 'the terms of a make are set once'); END",
  "CREATE TRIGGER IF NOT EXISTS maker_terms_inserted_once BEFORE INSERT ON maker_terms WHEN EXISTS (SELECT 1 FROM maker_terms WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index) BEGIN SELECT RAISE(IGNORE); END",
  "CREATE TRIGGER IF NOT EXISTS maker_terms_of_their_make BEFORE INSERT ON maker_terms WHEN NOT EXISTS (SELECT 1 FROM trades WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index AND network = NEW.network AND coordinator_alias = NEW.coordinator_alias AND role = NEW.role AND origin = 'madeHere' AND order_id IS NULL AND closed_at IS NULL) BEGIN SELECT RAISE(ABORT, 'terms of no pending make'); END",
];

/// The triggers of `maker_terms.drift`, squeezed.
final _makerTermsTriggers = [
  for (final trigger in _makerTermsTriggersAsWritten) _squeezed(trigger),
];

/// The statements of `trade_payouts.drift` (schema 9, #204), as written: the payout of a buyer's contract, given from this wallet or pasted, written for an open trade whose trail stands at its contract, never deleted, never turned back into a mark of the step to schema 9.
const _payoutTriggersAsWritten = [
  "CREATE TRIGGER IF NOT EXISTS trade_payouts_never_deleted BEFORE DELETE ON trade_payouts BEGIN SELECT RAISE(ABORT, 'the payout of a contract is kept'); END",
  "CREATE TRIGGER IF NOT EXISTS trade_payouts_forward BEFORE UPDATE ON trade_payouts WHEN NEW.key_fingerprint IS NOT OLD.key_fingerprint OR NEW.robot_index IS NOT OLD.robot_index OR NEW.take IS NOT OLD.take OR NEW.source IS 'unrecorded' OR (OLD.submitted_at IS NOT NULL AND (NEW.submitted_at IS NULL OR NEW.submitted_at < OLD.submitted_at)) OR NOT EXISTS (SELECT 1 FROM trades JOIN trade_trails ON trade_trails.key_fingerprint = trades.key_fingerprint AND trade_trails.robot_index = trades.robot_index WHERE trades.key_fingerprint = NEW.key_fingerprint AND trades.robot_index = NEW.robot_index AND trades.closed_at IS NULL AND trades.role = 'buyer' AND trade_trails.take = NEW.take) BEGIN SELECT RAISE(ABORT, 'a payout only moves forward'); END",
  "CREATE TRIGGER IF NOT EXISTS trade_payouts_of_their_trade BEFORE INSERT ON trade_payouts WHEN (NEW.source IS NOT 'thisWallet' AND NEW.source IS NOT 'pasted') OR NOT EXISTS (SELECT 1 FROM trades JOIN trade_trails ON trade_trails.key_fingerprint = trades.key_fingerprint AND trade_trails.robot_index = trades.robot_index WHERE trades.key_fingerprint = NEW.key_fingerprint AND trades.robot_index = NEW.robot_index AND trades.closed_at IS NULL AND trades.role = 'buyer' AND trade_trails.take = NEW.take) BEGIN SELECT RAISE(ABORT, 'a payout of no open trade'); END",
  "CREATE TRIGGER IF NOT EXISTS trade_payouts_inserted_once BEFORE INSERT ON trade_payouts WHEN EXISTS (SELECT 1 FROM trade_payouts WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index AND take = NEW.take) BEGIN SELECT RAISE(IGNORE); END",
];

/// The triggers of `trade_payouts.drift`, squeezed.
final _payoutTriggers = [
  for (final trigger in _payoutTriggersAsWritten) _squeezed(trigger),
];

/// The triggers of the keys of the words (schema 10, #81), as `garage_keys.drift` writes them.
const _garageKeyTriggersAsWritten = [
  "CREATE TRIGGER IF NOT EXISTS derived_garage_keys_never_deleted BEFORE DELETE ON derived_garage_keys BEGIN SELECT RAISE(ABORT, 'an activated Garage Key is kept'); END",
  "CREATE TRIGGER IF NOT EXISTS derived_garage_keys_never_changed BEFORE UPDATE ON derived_garage_keys BEGIN SELECT RAISE(ABORT, 'an activated Garage Key never changes'); END",
  "CREATE TRIGGER IF NOT EXISTS derived_garage_keys_in_order BEFORE INSERT ON derived_garage_keys WHEN NEW.key_index > 0 AND NOT EXISTS (SELECT 1 FROM derived_garage_keys WHERE network = NEW.network AND key_index = NEW.key_index - 1) BEGIN SELECT RAISE(ABORT, 'a Garage Key out of order'); END",
  "CREATE TRIGGER IF NOT EXISTS derived_garage_keys_inserted_once BEFORE INSERT ON derived_garage_keys WHEN EXISTS (SELECT 1 FROM derived_garage_keys WHERE network = NEW.network AND key_index = NEW.key_index) BEGIN SELECT RAISE(IGNORE); END",
  "CREATE TRIGGER IF NOT EXISTS garage_notices_shown_once BEFORE UPDATE ON garage_notices WHEN NOT (OLD.shown = 0 AND NEW.shown = 1 AND NEW.notice = OLD.notice) BEGIN SELECT RAISE(ABORT, 'a Garage notice only turns shown'); END",
  "CREATE TRIGGER IF NOT EXISTS garage_notices_never_deleted BEFORE DELETE ON garage_notices BEGIN SELECT RAISE(ABORT, 'a Garage notice is kept'); END",
];

final _garageKeyTriggers = [
  for (final trigger in _garageKeyTriggersAsWritten) _squeezed(trigger),
];

/// The triggers of what this device read of the recovery notes (schema 11, #81), as `garage_recovery_notes.drift` writes them: a reading never deleted, a row written once (review of #302), the floor only going up, a reading recorded kept.
const _noteTriggersAsWritten = [
  "CREATE TRIGGER IF NOT EXISTS garage_recovery_notes_never_deleted BEFORE DELETE ON garage_recovery_notes BEGIN SELECT RAISE(ABORT, 'a recovery note read is kept'); END",
  'CREATE TRIGGER IF NOT EXISTS garage_recovery_notes_inserted_once BEFORE INSERT ON garage_recovery_notes WHEN EXISTS (SELECT 1 FROM garage_recovery_notes WHERE network = NEW.network AND key_fingerprint = NEW.key_fingerprint) BEGIN SELECT RAISE(IGNORE); END',
  "CREATE TRIGGER IF NOT EXISTS garage_recovery_notes_forward BEFORE UPDATE ON garage_recovery_notes WHEN NEW.network IS NOT OLD.network OR NEW.key_fingerprint IS NOT OLD.key_fingerprint OR (OLD.account_floor IS NOT NULL AND (NEW.account_floor IS NULL OR NEW.account_floor < OLD.account_floor)) OR (OLD.read_at IS NOT NULL AND NEW.read_at IS NOT OLD.read_at) BEGIN SELECT RAISE(ABORT, 'a recovery note read only goes forward'); END",
];

final _noteTriggers = [
  for (final trigger in _noteTriggersAsWritten) _squeezed(trigger),
];

/// The triggers schema 8 replaced (#176), as the `.drift` files wrote them up to schema 7: the migration steps keep them in the schemas of their versions, as drift copies them.
const _replacedTriggersAsWritten = [
  "CREATE TRIGGER IF NOT EXISTS trades_set_once BEFORE UPDATE ON trades WHEN OLD.closed_at IS NOT NULL OR (OLD.confirmed_at IS NOT NULL AND NEW.confirmed_at IS NOT OLD.confirmed_at) OR NEW.network IS NOT OLD.network OR NEW.key_fingerprint IS NOT OLD.key_fingerprint OR NEW.robot_index IS NOT OLD.robot_index OR NEW.coordinator_alias IS NOT OLD.coordinator_alias OR NEW.coordinator_onion IS NOT OLD.coordinator_onion OR NEW.order_id IS NOT OLD.order_id OR NEW.role IS NOT OLD.role OR NEW.origin IS NOT OLD.origin OR NEW.taken_at IS NOT OLD.taken_at BEGIN SELECT RAISE(ABORT, 'a trade record only gains its times'); END",
  "CREATE TRIGGER IF NOT EXISTS trade_terms_of_their_trade BEFORE INSERT ON trade_terms WHEN NOT EXISTS (SELECT 1 FROM trades WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index AND network = NEW.network AND coordinator_alias = NEW.coordinator_alias AND order_id = NEW.order_id AND role = NEW.role AND closed_at IS NULL) BEGIN SELECT RAISE(ABORT, 'terms of no open trade'); END",
  "CREATE TRIGGER IF NOT EXISTS trade_trails_of_their_trade BEFORE INSERT ON trade_trails WHEN NOT EXISTS (SELECT 1 FROM trades JOIN trade_terms ON trade_terms.key_fingerprint = trades.key_fingerprint AND trade_terms.robot_index = trades.robot_index WHERE trades.key_fingerprint = NEW.key_fingerprint AND trades.robot_index = NEW.robot_index AND trades.network = NEW.network AND trades.coordinator_alias = NEW.coordinator_alias AND trades.order_id = NEW.order_id AND trades.role = NEW.role AND trades.closed_at IS NULL) BEGIN SELECT RAISE(ABORT, 'a trail of no open trade'); END",
  "CREATE TRIGGER IF NOT EXISTS trade_trails_forward BEFORE UPDATE ON trade_trails WHEN NEW.key_fingerprint IS NOT OLD.key_fingerprint OR NEW.robot_index IS NOT OLD.robot_index OR NEW.network IS NOT OLD.network OR NEW.coordinator_alias IS NOT OLD.coordinator_alias OR NEW.order_id IS NOT OLD.order_id OR NEW.role IS NOT OLD.role OR NEW.version < OLD.version OR NEW.read_at < OLD.read_at OR NEW.breached < OLD.breached OR NEW.history_unknown IS NOT OLD.history_unknown OR (OLD.bond_hash IS NOT NULL AND NEW.bond_hash IS NOT OLD.bond_hash) OR (OLD.escrow_hash IS NOT NULL AND NEW.escrow_hash IS NOT OLD.escrow_hash) OR (OLD.bond_step_seen_at IS NOT NULL AND (NEW.bond_step_seen_at IS NULL OR NEW.bond_step_seen_at < OLD.bond_step_seen_at)) OR (OLD.bond_step_deadline IS NOT NULL AND NEW.bond_step_deadline IS NULL) OR (OLD.position IN ('succeeded', 'makerLostDispute', 'takerLostDispute', 'expired', 'cancelled', 'publicAgain', 'notAvailable') AND NEW.position IS NOT OLD.position) BEGIN SELECT RAISE(ABORT, 'a trail only moves forward'); END",
  "CREATE TRIGGER IF NOT EXISTS trade_payments_inserted_once BEFORE INSERT ON trade_payments WHEN EXISTS (SELECT 1 FROM trade_payments WHERE key_fingerprint = NEW.key_fingerprint AND robot_index = NEW.robot_index AND step = NEW.step) BEGIN SELECT RAISE(IGNORE); END",
  "CREATE TRIGGER IF NOT EXISTS trade_payments_of_their_trade BEFORE INSERT ON trade_payments WHEN NOT EXISTS (SELECT 1 FROM trades JOIN trade_trails ON trade_trails.key_fingerprint = trades.key_fingerprint AND trade_trails.robot_index = trades.robot_index WHERE trades.key_fingerprint = NEW.key_fingerprint AND trades.robot_index = NEW.robot_index AND trades.closed_at IS NULL) BEGIN SELECT RAISE(ABORT, 'a payment of no open trade'); END",
  "CREATE TRIGGER IF NOT EXISTS trade_payments_forward BEFORE UPDATE ON trade_payments WHEN NEW.key_fingerprint IS NOT OLD.key_fingerprint OR NEW.robot_index IS NOT OLD.robot_index OR NEW.step IS NOT OLD.step OR NEW.payment_hash IS NOT OLD.payment_hash OR NEW.started_at < OLD.started_at BEGIN SELECT RAISE(ABORT, 'a payment only moves forward'); END",
];

/// Every trigger the `.drift` files write, as drift copies them into its code: the only SQL text there that names an update or a delete, to refuse it.
final _driftTriggers = {
  ..._garageKeyTriggers,
  ..._noteTriggers,
  ..._tradeTriggers,
  ..._trailTriggers,
  ..._paymentTriggers,
  ..._pinTriggers,
  ..._makerTermsTriggers,
  ..._payoutTriggers,
};

/// The triggers schema 8 replaced, squeezed: an exemption for the generated migration steps only, which keep them in the schemas of their versions.
final _replacedTriggers = {
  for (final trigger in _replacedTriggersAsWritten) _squeezed(trigger),
};

/// The drops of the steps to schema 7 (#97), 8 (#176) and 9 (#204): the tables they rebuild, their copies, the triggers of the tables schema 8 rebuilds (made again together, in a new file's order), the one it replaces on a table it does not rebuild, and the triggers of the payouts' new table, which schema 9 drops before it writes their marks and makes again after, never a binding.
const _rebuildDrops = {
  'DROP TABLE IF EXISTS trade_payments_of_schema6',
  'DROP TABLE trade_payments',
  'DROP TABLE IF EXISTS trades_of_schema7',
  'DROP TABLE trades',
  'DROP TABLE IF EXISTS trade_trails_of_schema7',
  'DROP TABLE trade_trails',
  'DROP TABLE IF EXISTS trade_payments_of_schema7',
  'DROP TRIGGER IF EXISTS trades_one_open_per_order',
  'DROP TRIGGER IF EXISTS trades_one_open_per_order_update',
  'DROP TRIGGER IF EXISTS trades_never_deleted',
  'DROP TRIGGER IF EXISTS trades_set_once',
  'DROP TRIGGER IF EXISTS trades_made_pending',
  'DROP TRIGGER IF EXISTS trades_inserted_once',
  'DROP TRIGGER IF EXISTS trade_trails_never_deleted',
  'DROP TRIGGER IF EXISTS trade_trails_inserted_once',
  'DROP TRIGGER IF EXISTS trade_trails_of_their_trade',
  'DROP TRIGGER IF EXISTS trade_trails_closed',
  'DROP TRIGGER IF EXISTS trade_trails_forward',
  'DROP TRIGGER IF EXISTS trade_payments_never_deleted',
  'DROP TRIGGER IF EXISTS trade_payments_inserted_once',
  'DROP TRIGGER IF EXISTS trade_payments_of_their_trade',
  'DROP TRIGGER IF EXISTS trade_payments_forward',
  'DROP TRIGGER IF EXISTS trade_payments_hash_once',
  'DROP TRIGGER IF EXISTS trade_terms_of_their_trade',
  'DROP TRIGGER IF EXISTS trade_payouts_never_deleted',
  'DROP TRIGGER IF EXISTS trade_payouts_forward',
  'DROP TRIGGER IF EXISTS trade_payouts_of_their_trade',
  'DROP TRIGGER IF EXISTS trade_payouts_inserted_once',
};

/// The statements of the step to schema 8 (#176) that copy the rows of the trades, their trails and their payments aside and back, as `P2pDatabase` writes them (pinned there by value), each as the literals its constant is written with.
const _schema8RebuildParts = [
  ['CREATE TABLE trades_of_schema7 AS SELECT * FROM trades'],
  [
    'INSERT INTO trades (network, key_fingerprint, robot_index, coordinator_alias, coordinator_onion, order_id, role, origin, taken_at, confirmed_at, closed_at) ',
    'SELECT network, key_fingerprint, robot_index, coordinator_alias, coordinator_onion, order_id, role, origin, taken_at, confirmed_at, closed_at FROM trades_of_schema7 AS copy ',
    'WHERE NOT EXISTS (SELECT 1 FROM trades WHERE trades.key_fingerprint = copy.key_fingerprint AND trades.robot_index = copy.robot_index)',
  ],
  ['CREATE TABLE trade_trails_of_schema7 AS SELECT * FROM trade_trails'],
  [
    'INSERT INTO trade_trails (key_fingerprint, robot_index, version, network, coordinator_alias, order_id, role, position, read_at, bond_hash, escrow_hash, deadline, bond_step_seen_at, bond_step_deadline, breached, history_unknown) ',
    'SELECT key_fingerprint, robot_index, version, network, coordinator_alias, order_id, role, position, read_at, bond_hash, escrow_hash, deadline, bond_step_seen_at, bond_step_deadline, breached, history_unknown FROM trade_trails_of_schema7 AS copy ',
    'WHERE NOT EXISTS (SELECT 1 FROM trade_trails WHERE trade_trails.key_fingerprint = copy.key_fingerprint AND trade_trails.robot_index = copy.robot_index)',
  ],
  ['CREATE TABLE trade_payments_of_schema7 AS SELECT * FROM trade_payments'],
  [
    'INSERT INTO trade_payments (key_fingerprint, robot_index, step, payment_hash, started_at, wallet_payment_id, take) ',
    'SELECT key_fingerprint, robot_index, step, payment_hash, started_at, wallet_payment_id, 0 FROM trade_payments_of_schema7 AS copy ',
    'WHERE NOT EXISTS (SELECT 1 FROM trade_payments WHERE trade_payments.key_fingerprint = copy.key_fingerprint AND trade_payments.robot_index = copy.robot_index AND trade_payments.step = copy.step AND trade_payments.take = 0)',
  ],
];

/// Those statements whole, as the constants of `P2pDatabase` hold them.
final _schema8Rebuild = {
  for (final parts in _schema8RebuildParts) parts.join(),
};

/// The texts the step to schema 8 may hold that name the trades or their trails as SQL: each statement whole and each literal it is written with, exactly; an exemption for `p2p_database.dart` only (security review of #176: a fragment of these, or the same text in another file, is no exemption).
final _schema8RebuildTexts = {
  ..._schema8Rebuild,
  for (final parts in _schema8RebuildParts) ...parts,
};
