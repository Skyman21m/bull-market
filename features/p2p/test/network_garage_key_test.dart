import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

/// A Garage Key with the network of its slot: every robot it gives carries that network.
void main() {
  // Fixed test bytes, 0x01 to 0x20: not a key anyone uses.
  final fixedKey = switch (GarageKey.fromBytes(
    Uint8List.fromList(List<int>.generate(32, (i) => i + 1)),
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  T ok<T>(Result<T, Failure> result) => switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => fail('expected a value, got $failure'),
  };

  group('a robot of the key', () {
    test('carries the network of the key, whichever index', () {
      for (final network in RobosatsNetwork.values) {
        final key = NetworkGarageKey(network, fixedKey);
        for (final index in [0, 1, 7]) {
          final next = ok(key.firstUsableRobot(index));
          final previous = ok(key.lastUsableRobot(index));
          expect(next.network, network);
          expect(previous.network, network);
          expect(next.accountIndex, index);
          expect(previous.accountIndex, index);
          expect(next.robot, ok(fixedKey.firstUsableRobot(index)));
          expect(next.identity, next.robot.identity);
        }
      }
    });

    test('of the same bytes on the two networks are two robots', () {
      final mainnet = ok(
        NetworkGarageKey(RobosatsNetwork.mainnet, fixedKey).firstUsableRobot(0),
      );
      final testnet = ok(
        NetworkGarageKey(RobosatsNetwork.testnet, fixedKey).firstUsableRobot(0),
      );

      expect(mainnet.robot, testnet.robot);
      expect(mainnet, isNot(testnet));
      expect('$mainnet', contains('mainnet'));
      expect('$testnet', contains('testnet'));
    });

    test('below index 0 or past the last index is unavailable', () {
      final key = NetworkGarageKey(RobosatsNetwork.mainnet, fixedKey);

      expect(
        key.lastUsableRobot(-1),
        isA<Err<NetworkRobot, P2pFailure>>().having(
          (err) => err.failure,
          'failure',
          isA<GarageRobotUnavailableFailure>(),
        ),
      );
      expect(
        key.firstUsableRobot(GarageKey.maxAccountIndex + 1),
        isA<Err<NetworkRobot, P2pFailure>>(),
      );
      expect(
        ok(key.lastUsableRobot(GarageKey.maxAccountIndex + 5)).accountIndex,
        GarageKey.maxAccountIndex,
      );
    });
  });

  group('the robot before', () {
    final identity = ok(fixedKey.deriveIdentity(0));

    test('skips the indexes a coordinator cannot be contacted with', () {
      final asked = <int>[];
      final robot = NetworkGarageKey.lastUsableRobotAmong(5, (index) {
        asked.add(index);
        return index >= 3
            ? const Err(
                TokenEntropyTooLow(
                  TokenEntropy(bitsEntropy: 1, shannonEntropy: 1),
                ),
              )
            : index == 2
            ? const Err(NicknameUnavailable())
            : Ok(identity);
      });

      expect(asked, [5, 4, 3, 2, 1]);
      expect(ok(robot).accountIndex, 1);
    });

    test(
      'stops at index 0 and after as many indexes as the search forward',
      () {
        final asked = <int>[];
        Result<RobotIdentity, RobosatsFailure> never(int index) {
          asked.add(index);
          return const Err(NicknameUnavailable());
        }

        expect(
          NetworkGarageKey.lastUsableRobotAmong(3, never),
          isA<Err<GarageRobot, RobosatsFailure>>(),
        );
        expect(asked, [3, 2, 1, 0]);

        asked.clear();
        NetworkGarageKey.lastUsableRobotAmong(1000, never);
        expect(asked, hasLength(GarageKey.maxAccountSearch));
        expect(asked.last, 1000 - GarageKey.maxAccountSearch + 1);
      },
    );

    test('passes on any other failure at once', () {
      final asked = <int>[];
      final robot = NetworkGarageKey.lastUsableRobotAmong(4, (index) {
        asked.add(index);
        return const Err(AccountIndexOutOfRange());
      });

      expect(asked, [4]);
      expect(robot, isA<Err<GarageRobot, RobosatsFailure>>());
    });
  });

  test('prints its network and never its key', () {
    final key = NetworkGarageKey(RobosatsNetwork.testnet, fixedKey);

    expect('$key', 'NetworkGarageKey(testnet, <redacted>)');
    expect(key, NetworkGarageKey(RobosatsNetwork.testnet, fixedKey));
    expect(key, isNot(NetworkGarageKey(RobosatsNetwork.mainnet, fixedKey)));
    expect(
      key.hashCode,
      NetworkGarageKey(RobosatsNetwork.testnet, fixedKey).hashCode,
    );
  });

  group('the constructor of a key of a network', () {
    // Resolved by the analyzer, so that an alias, a dot shorthand or a prefixed tear-off is the constructor it names; tests run with the package directory as working directory.
    late AnalysisContextCollection collection;

    setUpAll(() {
      collection = AnalysisContextCollection(
        includedPaths: [Directory.current.path],
        sdkPath: _dartSdkPath(),
      );
    });

    Future<List<String>> makersIn(String path) async {
      final absolute = File(path).absolute.path;
      final result = await collection
          .contextFor(absolute)
          .currentSession
          .getResolvedUnit(absolute);
      if (result is! ResolvedUnitResult) return ['$path: unresolved'];
      final makers = <String>[];
      result.unit.accept(_MakerVisitor(path, makers));
      return makers;
    }

    test(
      'is called by the repository only',
      () async {
        final makers = <String>[];
        for (final file
            in Directory('lib')
                .listSync(recursive: true)
                .whereType<File>()
                .where((file) => file.path.endsWith('.dart'))) {
          makers.addAll(await makersIn(file.path));
        }

        expect(makers, ['lib/src/data/garage_key_repository_impl.dart']);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'is found behind an alias, a dot shorthand or a prefix',
      () async {
        expect(await makersIn('test/fixtures/network_garage_key_makers.dart'), [
          for (var i = 0; i < 4; i++)
            'test/fixtures/network_garage_key_makers.dart',
        ]);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}

/// The Dart SDK of the Flutter that runs the tests, found from the workspace's package configuration, as the custody gate finds it.
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

/// Each place that calls or tears off a constructor of `NetworkGarageKey`, resolved: through its name, a `typedef`, a prefix or a dot shorthand.
final class _MakerVisitor extends RecursiveAstVisitor<void> {
  final String path;
  final List<String> makers;

  _MakerVisitor(this.path, this.makers);

  void _check(Element? element) {
    if (element case ConstructorElement(
      enclosingElement: InterfaceElement(name: 'NetworkGarageKey'),
    )) {
      makers.add(path);
    }
  }

  @override
  void visitConstructorName(ConstructorName node) {
    _check(node.element);
    super.visitConstructorName(node);
  }

  @override
  void visitDotShorthandConstructorInvocation(
    DotShorthandConstructorInvocation node,
  ) {
    _check(node.element);
    super.visitDotShorthandConstructorInvocation(node);
  }
}
