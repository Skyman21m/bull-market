import 'dart:async';

import 'package:p2p/src/domain/usecases/trade/trade_make_locks.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;
import 'package:test/test.dart';

/// The makes and resolutions of a network run one at a time (#179): never two at once, in the order they came, however many wait.
void main() {
  test(
    'four runs queued on one network: never two at once, each in turn, a run of the other network apart',
    () async {
      final locks = TradeMakeLocks();
      var running = 0;
      var most = 0;
      final order = <int>[];
      final gates = List.generate(5, (_) => Completer<void>());
      Future<void> run(int index, RobosatsNetwork network) =>
          locks.run(network, () async {
            running++;
            if (running > most) most = running;
            order.add(index);
            await gates[index].future;
            running--;
          });

      final first = run(0, RobosatsNetwork.testnet);
      final second = run(1, RobosatsNetwork.testnet);
      final third = run(2, RobosatsNetwork.testnet);
      await pumpEventQueue();
      expect(order, [0]);
      // The first ends: the second runs, the third still waits; a fourth then comes, behind the third.
      gates[0].complete();
      await pumpEventQueue();
      expect(order, [0, 1]);
      final fourth = run(3, RobosatsNetwork.testnet);
      // Another network is not held back.
      final other = run(4, RobosatsNetwork.mainnet);
      await pumpEventQueue();
      expect(order, [0, 1, 4]);
      gates[4].complete();
      gates[1].complete();
      await pumpEventQueue();
      expect(order, [0, 1, 4, 2]);
      gates[2].complete();
      await pumpEventQueue();
      expect(order, [0, 1, 4, 2, 3]);
      gates[3].complete();
      await Future.wait([first, second, third, fourth, other]);
      // At most one per network: the run of the other network made two at once, never two of one network.
      expect(most, 2);
    },
  );

  test('a run that throws lets the next one run', () async {
    final locks = TradeMakeLocks();
    final failing = locks.run<void>(
      RobosatsNetwork.testnet,
      () async => throw StateError('stopped'),
    );
    await expectLater(failing, throwsStateError);
    expect(
      await locks.run(RobosatsNetwork.testnet, () async => 'next'),
      'next',
    );
  });
}
