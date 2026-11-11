import 'dart:io';
import 'dart:typed_data';

import 'package:analyzer/dart/analysis/utilities.dart' show parseString;
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
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

  test('only the repository makes a key of a network', () {
    // Tests run with the package directory as working directory.
    final makers = <String>[];
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      final visitor = _MakerVisitor();
      parseString(content: file.readAsStringSync()).unit.accept(visitor);
      if (visitor.found > 0) makers.add(file.path);
    }

    expect(makers, ['lib/src/data/garage_key_repository_impl.dart']);
  });

  test('the check sees each way to make one', () {
    for (final source in [
      'f(k) => NetworkGarageKey(RobosatsNetwork.mainnet, k);',
      'f(k) => const NetworkGarageKey(RobosatsNetwork.mainnet, k);',
      'f(k) => new NetworkGarageKey(RobosatsNetwork.mainnet, k);',
      'final make = NetworkGarageKey.new;',
      'f(k) => p2p.NetworkGarageKey(RobosatsNetwork.mainnet, k);',
    ]) {
      final visitor = _MakerVisitor();
      parseString(content: source).unit.accept(visitor);

      expect(visitor.found, 1, reason: source);
    }
  });
}

/// Counts the calls and tear-offs of the constructor of `NetworkGarageKey`, read from the syntax tree.
final class _MakerVisitor extends RecursiveAstVisitor<void> {
  int found = 0;

  static const _name = 'NetworkGarageKey';

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == _name) found++;
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.name.lexeme == _name) found++;
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.prefix.name == _name && node.identifier.name == 'new') found++;
    super.visitPrefixedIdentifier(node);
  }
}
