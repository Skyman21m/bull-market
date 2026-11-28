import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/presentation/settled_state.dart';

/// The wait of a tap on an order of the book for the active trades' read, and of « Renew » for the renewals' read (#314): what it gives in the cases it was written for, and an `Error` that reaches the caller instead of being taken for the current state.
final class _Reads extends Cubit<int> {
  _Reads() : super(0);

  void read(int value) => emit(value);
}

void main() {
  const wait = Duration(seconds: 10);

  test('the first state that settles the wait', () async {
    final cubit = _Reads();
    addTearDown(cubit.close);
    final settled = settledState(cubit, (state) => state >= 2, wait: wait);
    cubit
      ..read(1)
      ..read(2)
      ..read(3);
    expect(await settled, 2);
  });

  test('a read that does not end: the state at the end of the wait', () async {
    final cubit = _Reads();
    addTearDown(cubit.close);
    final watch = Stopwatch()..start();
    final settled = settledState(
      cubit,
      (state) => state >= 2,
      wait: const Duration(milliseconds: 200),
    );
    cubit.read(1);
    expect(await settled, 1);
    expect(
      watch.elapsed,
      greaterThanOrEqualTo(const Duration(milliseconds: 200)),
    );
  });

  test(
    'the cubit closed before it settles (a screen left meanwhile): its state then, nothing thrown',
    () async {
      final cubit = _Reads();
      final settled = settledState(cubit, (state) => state >= 2, wait: wait);
      cubit.read(1);
      await cubit.close();
      expect(await settled, 1);
      // Closed before the wait starts: the same.
      expect(await settledState(cubit, (state) => state >= 2, wait: wait), 1);
    },
  );

  test(
    'an Error of the test reaches the caller: never taken for the state',
    () async {
      final cubit = _Reads();
      addTearDown(cubit.close);
      final settled = settledState(
        cubit,
        (state) => throw StateError('a bug'),
        wait: wait,
      );
      cubit.read(1);
      await expectLater(settled, throwsA(isA<StateError>()));
    },
  );
}
