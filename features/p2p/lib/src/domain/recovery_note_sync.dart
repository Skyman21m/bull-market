import 'dart:async';
import 'dart:math' show max;

import 'package:bull_logger/bull_logger.dart';
import 'package:bull_tor/tor.dart' show torConnectDeadline;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart'
    show
        Federation,
        GarageRecoveryNote,
        GarageRecoveryReading,
        NostrKeyPair,
        NostrRelayFilter,
        OwnSessionNostrRelayTransport,
        RobosatsNetwork,
        nostrRelaysOfNetwork;

import 'garage_key_fingerprint.dart';
import 'garage_note_compute_port.dart';
import 'network_garage_key.dart';
import 'p2p_failure.dart';
import 'p2p_tor_state.dart';
import 'repositories/garage_key_repository.dart';
import 'repositories/garage_recovery_note_repository.dart';
import 'usecases/trade/follow_trades_usecase.dart' show NewTradeStandingOf;
import 'robot_binding.dart';
import 'trade_record.dart';

/// The longest a reading of a key's note takes in all (#81): the read of every relay at once, each bounded by `relayReadDeadline` of the transport ([torConnectDeadline]), then the reading of its events in an isolate, within what is left of 30 seconds more: a thousand events a hostile relay made up take about 25 seconds on a desktop (`packages/robosats/README.md`); a relay whose events are not read by then counts as not answered.
final noteReadDeadline = torConnectDeadline + const Duration(seconds: 30);

/// The longest the reservation of a new trade's robot waits for the reading of its key's note (#81, design note `docs/design/garage-key-from-the-words.md` § 3, « As PR 3 built it »), for a key never read for good on this installation, as the official client reads the note of a key entered for at most 5 seconds before it goes on (`RoboPool/index.ts:640`, commit babf62e), over sockets already open.
///
/// Here the relays are reached through Tor, each on a new session: on cold installs a first onion contact took up to 34 seconds, as measured in the comment of `torConnectBudget` of `bull_tor` (whose value is 60 seconds), and the answer of a relay for a few notes and their reading take a few seconds more. Forty seconds keeps that worst observed contact; in most cases the reading started earlier, at the first showing of the P2P tab of the key's network or when the Garage showed the key, so a user waits less, or not at all. The wait ends as soon as a strict majority of the relays gave their whole answer, the floors they gave recorded (review of #302); past it the trade goes on with the floor recorded so far.
///
/// It is waited again by each new trade of such a key as long as the reading of this run has not reached a majority nor ended (a reading still waiting for Tor, say): waiting again is the safe side.
const newTradeNoteWait = Duration(seconds: 40);

/// The longest a reading of a note waits for the embedded Tor to be ready before it gives up until the next run: the start of Tor took 62 seconds on 10/11/2026, and the Snowflake fallback takes longer.
const noteTorWait = Duration(minutes: 5);

/// Keeps the RoboSats recovery note of the Garage Keys on the coordinators' relays (#81, design note `docs/design/garage-key-from-the-words.md` § 3, « As PR 3 built it »), as the official client keeps it (`GarageKey.model.ts:89-119`, `Garage.model.ts:547-569`, commit babf62e): the note of a key says the index of its last robot used.
///
/// - **Read once per key and per run of the app**, never in a loop: at the first showing of the P2P tab of a network, for the key new trades take there ([opened], with [GarageKeyRepository.forNewTrade]) and for every key with a robot in use there (their writes wait for it); when the Garage shows a key, internal or external, imported or not ([visit]); before the reservation of a new trade's robot ([beforeNewTrade]). On every coordinator relay of the key's network, for its recovery identity and its legacy one, each relay read apart ([OwnSessionNostrRelayTransport.readOnOwnSession]) and its events read apart in an isolate ([GarageNoteComputePort.readNotes]); a relay whose reading fails counts as not answered, the others keep theirs.
/// - **The floor**, recorded relay by relay as soon as one gave a note (review of #302): the index of each note read raises the floor of the key's new trades, which only goes up ([GarageRecoveryNoteRepository.recordReading]), whatever number of relays answered; it never lowers anything, it can only help, and one slow relay never holds back what the others gave.
/// - **A majority**: a reading reaches it once a strict majority of the network's relays ([nostrRelaysOfNetwork]: 4 of 6, 2 of 2, 1 of 1) gave their whole answer and their events were read in time, a note found or not (review of #302). The key is then recorded read for good on this installation, which serves one thing only: new trades of the key no longer wait for its reading in later runs.
/// - **Written** only after a reading of this run that reached a majority (review of #302): after each make and take the coordinator confirmed ([tradeConfirmed]) and at the first showing of the P2P tab of each network in a run ([opened]), for every key with a robot in use there, each write waits for the end of the reading of this run, and carries the highest of what the device knows ([NewTradeStanding.highestKnown]: its robots in use and the floor) and of what this reading gave. A run whose reading did not reach a majority writes nothing for the key, even for a key read for good in an earlier run: a note written since by another device, higher, is never covered by an older knowledge. On every coordinator relay of the key's network, each publication on a Tor session of its own. The writes of one key run one after the other, the next after the one before it, whatever that one gave.
/// - What this does not guarantee: two devices that read at the same moment, then write each; four relays of six that agree to serve an old note while the two others are unreachable; three relays of six down, or one of the two of testnet, stop every write.
/// - Nothing here retries in a tight loop, delays a trade more than [newTradeNoteWait], or makes one fail: a relay that cannot be reached costs the user nothing, and every outcome stays out of the screens.
/// - Nothing of the key, of its recovery identity, of a note or of a relay goes to a log; at most a fixed word.
final class RecoveryNoteSync {
  final OwnSessionNostrRelayTransport _relays;
  final GarageNoteComputePort _compute;
  final GarageRecoveryNoteRepository _notes;

  /// `TradeRecordRepository.newTradeStandingOf`: the robots in use of a key and its floor.
  final NewTradeStandingOf _standing;

  /// `TradeRecordRepository.keysInUse`: the keys with a robot bound or recorded on a network.
  final Future<Result<Set<GarageKeyFingerprint>, P2pFailure>> Function(
    RobosatsNetwork network,
  )
  _keysInUse;
  final GarageKeyRepository _keys;
  final Federation _federation;
  final DateTime Function() _clock;
  final Stream<P2pTorReport> Function()? _torReports;
  final Duration _readDeadline;
  final Duration _newTradeWait;
  final Duration _torWait;

  /// The reading of each key of each network in this run of the app.
  final Map<(RobosatsNetwork, GarageKeyFingerprint), _Reading> _reads = {};

  /// The last write of each key of each network, which the next one waits for, whatever it gave.
  final Map<(RobosatsNetwork, GarageKeyFingerprint), Future<void>> _writes = {};

  /// The networks whose P2P tab was shown in this run of the app.
  final Set<RobosatsNetwork> _opened = {};

  RecoveryNoteSync({
    required this._relays,
    required this._compute,
    required this._notes,
    required this._standing,
    required this._keysInUse,
    required this._keys,
    required this._federation,
    required this._clock,
    this._torReports,
    Duration? readDeadline,
    this._newTradeWait = newTradeNoteWait,
    this._torWait = noteTorWait,
  }) : _readDeadline = readDeadline ?? noteReadDeadline;

  /// The Garage shows [key]: its note is read in the background, unless this run already reads it.
  void visit(NetworkGarageKey key) => _readingOf(key);

  /// Before the robot of a new trade of [key] is reserved: the reading of its note in this run starts, if it has not; a key never read for good on this installation waits for it at most [newTradeNoteWait], until a strict majority of the relays answered or the reading ended; a key read for good does not wait. Then the trade goes on with the floor recorded. It never fails.
  Future<void> beforeNewTrade(NetworkGarageKey key) async {
    final reading = _readingOf(key);
    if (reading == null) return;
    if (await _guardedRead(_readForGood(key))) return;
    await reading.majority.future.timeout(
      _newTradeWait,
      onTimeout: () => false,
    );
  }

  /// The coordinator confirmed the make or the take of [record]: the note of its key is written in the background, once the reading of this run reached a majority.
  void tradeConfirmed(TradeRecord record) =>
      unawaited(_guarded(_writeForRobot(record.robot)));

  /// The P2P tab of [network] is shown: at the first time in this run of the app, in the background, the reading of the key new trades take on [network] starts ([GarageKeyRepository.forNewTrade]), with robots in use or not, so that after a reinstall it runs well before the first trade (functional review of #302); and the note of every key with a robot in use on [network] is written again, after the reading of this run reached a majority.
  ///
  /// A key that cannot be had (no default wallet, a passphrase, a wallet locked, words that no longer give the key recorded) is neither read nor written, and nothing is shown.
  void opened(RobosatsNetwork network) {
    if (!_opened.add(network)) return;
    unawaited(_guarded(_readForNewTrade(network)));
    unawaited(_guarded(_writeAll(network)));
  }

  /// The reading of the key new trades take on [network] started, when there is one.
  Future<void> _readForNewTrade(RobosatsNetwork network) async {
    if (await _keys.forNewTrade(network) case Ok(:final value)) {
      _readingOf(value);
    }
  }

  /// The reading of [key] in this run, started at the first call; `null` for a key without a fingerprint.
  _Reading? _readingOf(NetworkGarageKey key) {
    final fingerprint = switch (key.fingerprint) {
      Ok(:final value) => value,
      Err() => null,
    };
    if (fingerprint == null) return null;
    return _reads.putIfAbsent((key.network, fingerprint), () {
      final reading = _Reading();
      // Whatever the reading gives or throws, it ends: an Error is reported to the zone, and the reading then reached no majority.
      unawaited(
        _guarded(
          _readOnce(key, fingerprint, reading),
        ).whenComplete(() => reading.end(majority: false, highest: null)),
      );
      return reading;
    });
  }

  /// Whether [key] was read for good on this installation, at a run before or in this one.
  Future<bool> _readForGood(NetworkGarageKey key) async {
    final fingerprint = switch (key.fingerprint) {
      Ok(:final value) => value,
      Err() => null,
    };
    if (fingerprint == null) return false;
    return switch (await _notes.standingOf(key.network, fingerprint)) {
      Ok(value: GarageNoteStanding(read: true)) => true,
      Ok() || Err() => false,
    };
  }

  Future<void> _readOnce(
    NetworkGarageKey key,
    GarageKeyFingerprint fingerprint,
    _Reading reading,
  ) async {
    final clock = Stopwatch()..start();
    if (!await _torReady()) return;
    clock.reset();
    final relays = nostrRelaysOfNetwork(_federation, key.network);
    if (relays.isEmpty) return;
    final identities = [
      key.key.recoveryNostrKeyPair,
      key.key.legacyRecoveryNostrKeyPair,
    ];
    final filters = GarageRecoveryNote.filters(key.key);
    int? highest;
    var answers = 0;
    var settled = false;
    // Each relay read apart, and its events read apart: one relay's events never hide another's, and one slow relay never holds back the floor the others gave (review of #302).
    Future<void> readOne(Uri relay) async {
      final read = await _readRelay(relay, filters, identities, clock);
      if (read.note case final note?) {
        highest = max(highest ?? note.accountIndex, note.accountIndex);
        if (await _notes.recordReading(
              key.network,
              fingerprint,
              floor: note.accountIndex,
              answered: false,
            )
            case Err()) {
          log.info('P2P recovery note: floor not recorded');
        }
      }
      if (!read.answered) return;
      answers++;
      if (settled || answers * 2 <= relays.length) return;
      settled = true;
      // A strict majority answered in full, their floors recorded: read for good on this installation, and a new trade waits no longer.
      if (await _notes.recordReading(
            key.network,
            fingerprint,
            floor: null,
            answered: true,
          )
          case Err()) {
        log.info('P2P recovery note: reading not recorded');
      }
      reading.reachMajority();
    }

    await Future.wait([for (final relay in relays) readOne(relay)]);
    final majority = answers * 2 > relays.length;
    if (!majority) log.info('P2P recovery note: not read');
    reading.end(majority: majority, highest: highest);
  }

  /// One relay's reading: the note its events hold, and whether it gave its whole answer and its events were read within the reading's deadline. A failure of this relay's reading, whatever it is, makes it a relay that did not answer, and leaves the others' (review of #302); an [Error] is reported to the zone.
  Future<({GarageRecoveryReading? note, bool answered})> _readRelay(
    Uri relay,
    List<NostrRelayFilter> filters,
    List<NostrKeyPair> identities,
    Stopwatch clock,
  ) async {
    try {
      final read = await _relays.readOnOwnSession(relay, filters);
      final left = _readDeadline - clock.elapsed;
      if (left <= Duration.zero) return (note: null, answered: false);
      if (read.events.isEmpty) return (note: null, answered: read.complete);
      return switch (await _compute.readNotes(
        identities,
        read.events,
        limit: left,
      )) {
        Ok(:final value) => (note: value, answered: read.complete),
        Err() => (note: null, answered: false),
      };
    } on Object catch (error, trace) {
      if (error is! Exception) Zone.current.handleUncaughtError(error, trace);
      return (note: null, answered: false);
    }
  }

  Future<void> _writeAll(RobosatsNetwork network) async {
    final Set<GarageKeyFingerprint> keys;
    switch (await _keysInUse(network)) {
      case Ok(:final value):
        keys = value;
      case Err():
        return;
    }
    await Future.wait([
      for (final fingerprint in keys)
        _writeForRobot(RobotSlot(network, fingerprint, 0)),
    ]);
  }

  /// The note of the key of [robot] written, the key found as a trade finds it ([GarageKeyRepository.ofSlot]); nothing when it is no longer there.
  Future<void> _writeForRobot(RobotSlot robot) async {
    switch (await _keys.ofSlot(robot)) {
      case Ok(:final value):
        await _write(value);
      case Err():
        return;
    }
  }

  /// The note of [key] written on every relay of its network, after the write before it of the same key, whatever that one gave: its failure was reported to its own caller, and never stops the writes after it (review of #302).
  Future<void> _write(NetworkGarageKey key) {
    final fingerprint = switch (key.fingerprint) {
      Ok(:final value) => value,
      Err() => null,
    };
    if (fingerprint == null) return Future.value();
    final id = (key.network, fingerprint);
    final previous = _writes[id] ?? Future<void>.value();
    final next = previous
        .then<void>((_) {}, onError: (Object _) {})
        .then((_) => _writeNow(key, fingerprint));
    _writes[id] = next;
    return next;
  }

  Future<void> _writeNow(
    NetworkGarageKey key,
    GarageKeyFingerprint fingerprint,
  ) async {
    final reading = _readingOf(key);
    if (reading == null) return;
    // Never without a reading of this run that reached a majority (review of #302): a note written since by another device may be higher than all the device knew.
    final run = await reading.ended.future;
    if (!run.majority) return;
    final int highest;
    switch (await _standing(key.network, fingerprint)) {
      case Ok(value: NewTradeStanding(:final highestKnown)):
        final known = [highestKnown, run.highest].nonNulls;
        if (known.isEmpty) return;
        highest = known.reduce(max);
      case Err():
        return;
    }
    if (!await _torReady()) return;
    final relays = nostrRelaysOfNetwork(_federation, key.network);
    if (relays.isEmpty) return;
    switch (await _compute.composeNote(
      key.key.recoveryNostrKeyPair,
      accountIndex: highest,
      now: _clock(),
    )) {
      case Ok(value: Ok(value: final note)):
        await Future.wait([
          for (final relay in relays) _relays.publishOnOwnSession(relay, note),
        ]);
      case Ok(value: Err()) || Err():
        log.info('P2P recovery note: not composed');
    }
  }

  /// Whether the embedded Tor is ready, waiting for it at most [noteTorWait]; `true` where nothing reports it, `false` when its reports end without « ready » (review of #302).
  Future<bool> _torReady() async {
    final reports = _torReports;
    if (reports == null) return true;
    try {
      return await reports()
          .any((report) => report.state == P2pTorState.ready)
          .timeout(_torWait);
    } on Exception {
      return false;
    }
  }

  /// [work], whose failure stays out of the trades and the screens: an [Exception] gives `false`, an [Error], a bug, is reported to the zone and gives `false` too, so that this optional path never makes a trade fail.
  static Future<bool> _guardedRead(Future<bool> work) => work.then(
    (value) => value,
    onError: (Object error, StackTrace trace) {
      if (error is! Exception) Zone.current.handleUncaughtError(error, trace);
      return false;
    },
  );

  /// [work], whose failure stays out of the trades and the screens, as [_guardedRead].
  static Future<void> _guarded(Future<void> work) => work.then(
    (_) {},
    onError: (Object error, StackTrace trace) {
      if (error is! Exception) Zone.current.handleUncaughtError(error, trace);
    },
  );
}

/// The reading of one key's note in one run of the app.
final class _Reading {
  /// `true` once a strict majority of the relays gave their whole answer, the floors they gave recorded; `false` when the reading ended without.
  final Completer<bool> majority = Completer<bool>();

  /// The end of the reading: whether it reached a majority, and the highest index of the notes it read.
  final Completer<({bool majority, int? highest})> ended = Completer();

  void reachMajority() {
    if (!majority.isCompleted) majority.complete(true);
  }

  void end({required bool majority, required int? highest}) {
    if (!this.majority.isCompleted) this.majority.complete(majority);
    if (!ended.isCompleted) {
      ended.complete((majority: majority, highest: highest));
    }
  }
}
