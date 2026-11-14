import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:primitives/primitives.dart';

/// How long a write of the tests of two connections may keep giving up on SQLite's busy timeout: far more than the slowest commit seen under load (603 ms, #65), and short enough that the tests end before their timeout if a write never succeeded.
const busyBudget = Duration(seconds: 20);

/// Opens [databases] one after the other, before anything runs on them at once.
///
/// drift keeps the error of an open that gave up on SQLite's busy timeout, so a connection opened inside the part at once could fail for good, where a busy statement fails once and may be asked again (second review of #72).
Future<void> openInTurn(Iterable<P2pDatabase> databases) async {
  for (final database in databases) {
    await database.customSelect('SELECT 1').get();
  }
}

/// Asks [write] again while it gives up with a [P2pStorageFailure], for at most [busyBudget] of real time, counting time rather than attempts (#65).
///
/// Two connections of one file wait for each other's write lock through SQLite's busy timeout of 2 s, but in the test runner that timeout gives up after about 30 ms of real time: each sleep of SQLite's busy handler ends at the next sample of the VM's profiler, every millisecond (measured for #65: 2 s in a plain `dart` run, about 40 ms with `--profiler`, about 150 ms and 500 ms with a sample every 5 and 20 ms).
/// Under the load of the whole suite, a commit synced to disk (`synchronous = FULL`) can hold the lock for hundreds of milliseconds, longer than eleven such attempts together.
/// A write that gave up is asked again as a user's « Retry » would: a bind writes only when the robot has no binding, then reads the binding that won, and a reservation for a new trade writes only an index still free and says whether it wrote, so asking again never makes a second one.
/// The app opens one connection, whose statements drift runs one at a time, so it never waits for another connection.
Future<Result<T, P2pFailure>> untilNotBusy<T>(
  Future<Result<T, P2pFailure>> Function() write,
) async {
  bool gaveUp(Result<T, P2pFailure> result) => switch (result) {
    Err(failure: P2pStorageFailure()) => true,
    _ => false,
  };
  final elapsed = Stopwatch()..start();
  var result = await write();
  while (gaveUp(result) && elapsed.elapsed < busyBudget) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    result = await write();
  }
  return result;
}
