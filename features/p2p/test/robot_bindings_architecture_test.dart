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
            'ReviewPeek': {'request CoordinatorClient.fetchKnownRobot'},
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
            'proveByTearOff': {'UnprovenCoordinatorRobot.prove'},
            'generateByTearOff': {'RobotPgpKey.generate'},
          },
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
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
    });

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

  test('only the data layer and the composition reach the database', () {
    expect(
      where(
        (facts) =>
            facts.imports.any((uri) => uri.endsWith('p2p_database.dart')),
      ),
      {
        'lib/src/data/robot_binding_repository_impl.dart',
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
        // The migration steps `make drift-migrations` writes from the snapshots.
        'lib/src/data/p2p_database.steps.dart',
        'lib/src/data/robot_binding_repository_impl.dart',
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

    for (final facts in [repository, database, steps]) {
      expect(
        facts.invoked.intersection({
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
    // Every call of the migrator, in order: nothing else changes a table.
    expect(database.qualifiedCalls.where((call) => call.startsWith('m.')), [
      'm.alterTable(TableMigration(schema.garageKeyHistories))',
      'm.addColumn(schema.robotBindings, schema.robotBindings.provenance)',
    ]);
  });

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
List<String> _ignores(String source) => [
  for (final match in RegExp(
    r'(ignore(?:_for_file)?)\s*:\s*([A-Za-z0-9_=,\s-]*?)\s*(?:\*/|$)',
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
  'GarageKeyRepository': ('package:p2p/', {'create', 'import'}),
  'GarageKeys': ('package:secrets/', {'create', 'import'}),
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

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _declaration = node.name.lexeme;
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _declaration = node.namePart.typeName.lexeme;
    super.visitClassDeclaration(node);
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    _declaration = node.name?.lexeme ?? '';
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
