import 'package:robosats/robosats.dart';

/// When the book asks a coordinator for its book again by itself, after a request that got no answer.
///
/// The official client has no such rule: it asks every coordinator once each time the book is shown or refreshed (`loadBook` of `frontend/src/models/Federation.model.ts` at commit ff1998c).
/// Troc asks again, at the owner's request (#73), because the first requests after a cold start of Tor are the ones that fail: right after Tor is ready, Arti still has to fetch the descriptor of each onion service and build its circuits, and the measurements of `docs/spikes/` saw first contacts fail within about 5 seconds (`other`) or at Tor's 60-second budget (`timeout`), while requests on a connection already open did not fail.
/// The transport turns those connection failures into [CoordinatorUnreachable] or [CoordinatorTimedOut].
/// Only a failure that says nothing was answered is asked again: a coordinator that answered something unusable, or something that is not HTTP, would answer it again.
/// Each attempt is a whole request of the transport, which itself tries up to three Tor sessions within 132 seconds before it fails.
final class BookRetry {
  /// The waits before the extra attempts, in order: one attempt more than there are waits.
  final List<Duration> waits;

  const BookRetry._(this.waits);

  /// For a coordinator that has not given its book yet in this book: two extra attempts, about 5 and 15 seconds after the failed ones.
  ///
  /// A request that fails fast fails after about 15 seconds (three Tor sessions of about 5 seconds each), so the third attempt starts about 50 seconds after the first (46 at least, with the spread), well past the 23 seconds after Tor was ready within which the slowest cold first contact measured succeeded.
  static const firstContact = BookRetry._([
    Duration(seconds: 5),
    Duration(seconds: 15),
  ]);

  /// For a coordinator that has given its book before in this book, so whose circuit has worked: one extra attempt, about 5 seconds after the failed one.
  static const reached = BookRetry._([Duration(seconds: 5)]);

  /// How far each wait is spread, up or down, at random: a wait of 5 seconds lasts from 4 to 6 seconds, so that coordinators that failed together, as on a cold start, are not asked again together.
  static const jitter = 0.2;

  /// How long a coordinator is shown awaited at most, from the moment it is asked, before it is shown offline while its attempts go on.
  ///
  /// Each attempt may last up to 132 seconds, so a coordinator that times out every time would otherwise be awaited about seven minutes.
  /// The third attempt of a coordinator that fails fast starts 46 to 54 seconds after the first, with the spread, and the slowest cold first contact measured took 23.2 seconds once Tor was ready: 80 seconds covers the measured cases, and stays a bearable wait to look at.
  /// It is a decision of the project (#73), not of the official client, which stops waiting for a coordinator after 15 seconds but has no second attempt to wait for.
  static const awaitedAtMost = Duration(seconds: 80);

  /// How long a refresh, by a pull or by « Retry », is waited for at most: its indicator closes then, and the row of the coordinators shows those still awaited.
  static const refreshAtMost = Duration(seconds: 10);

  /// How many attempts a coordinator gets in all: the first and one per wait.
  int get maxAttempts => waits.length + 1;

  /// Whether [failure] says that the coordinator answered nothing, so that asking again may get its book.
  ///
  /// Unreachable, timed out and a transport busy for now are asked again.
  /// [CoordinatorTransportFailed] is not: the transport gives it for an answer that is not HTTP, which a new circuit would get again, and otherwise for causes that do not pass (a request it refuses to send, its sessions closed under the request, an exception it let through).
  /// A body too large, an unexpected status, a body that is not JSON or not a book, and an answer that is not the coordinator's are not either: the coordinator answered.
  static bool asksAgainAfter(CoordinatorFailure failure) => switch (failure) {
    CoordinatorUnreachable() ||
    CoordinatorTimedOut() ||
    CoordinatorTransportBusy() => true,
    CoordinatorTransportFailed() ||
    CoordinatorResponseTooLarge() ||
    CoordinatorNotOnNetwork() ||
    CoordinatorUnexpectedStatus() ||
    CoordinatorNotJson() ||
    CoordinatorResponseMalformed() ||
    CoordinatorIdentityFailure() ||
    CoordinatorRobotFailure() => false,
  };

  /// The wait before asking again after [attempts] attempts, the last of which failed with [failure], or `null` when the coordinator is not asked again.
  ///
  /// [draw] gives a number from 0 (included) to 1 (excluded) that spreads the wait by [jitter], and is called only when there is a wait to spread; a draw outside that range counts as its nearest end, and one that is not a number as the middle.
  Duration? waitAfter(
    CoordinatorFailure failure, {
    required int attempts,
    required double Function() draw,
  }) {
    if (!asksAgainAfter(failure)) return null;
    if (attempts < 1 || attempts > waits.length) return null;
    return spread(waits[attempts - 1], draw());
  }

  /// [wait] spread by [jitter] with the draw [random]: 0 gives the shortest wait, 0.5 the wait itself, and a draw near 1 the longest.
  static Duration spread(Duration wait, double random) {
    final draw = random.isNaN ? 0.5 : random.clamp(0.0, 1.0);
    final factor = 1 + jitter * (2 * draw - 1);
    return Duration(microseconds: (wait.inMicroseconds * factor).round());
  }
}
