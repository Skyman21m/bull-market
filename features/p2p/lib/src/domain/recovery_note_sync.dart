import 'dart:async';

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

/// The longest a first reading of a key's note takes in all (#81): the read of every relay at once, each bounded by `relayReadDeadline` of the transport ([torConnectDeadline]), then the reading of its events in an isolate, within what is left of 30 seconds more: a thousand events a hostile relay made up take about 25 seconds on a desktop (`packages/robosats/README.md`); a relay whose events are not read by then counts as not answered.
final noteReadDeadline = torConnectDeadline + const Duration(seconds: 30);

/// The longest the reservation of a new trade's robot waits for the first reading of its key's note still running (#81, design note `docs/design/garage-key-from-the-words.md` § 3, « As PR 3 built it »), as the official client reads the note of a key entered for at most 5 seconds before it goes on (`RoboPool/index.ts:640`, commit babf62e), over sockets already open.
///
/// Here the relays are reached through Tor, each on a new session: on cold installs a first onion contact took up to 34 seconds, as measured in the comment of `torConnectBudget` of `bull_tor` (whose value is 60 seconds), and the answer of a relay for a few notes and their reading take a few seconds more. Forty seconds keeps that worst observed contact; in most cases the reading started earlier, at the first showing of the P2P tab of the key's network or when the Garage showed the key, so a user waits less, or not at all. Past it the trade goes on with what the device knows.
///
/// It is waited again by each new trade of the key as long as the reading of this run has not ended (a reading still waiting for Tor, say): waiting again is the safe side. Once the reading of this run ended, read or not, a new trade does not wait.
const newTradeNoteWait = Duration(seconds: 40);

/// The longest a reading or a writing of a note waits for the embedded Tor to be ready before it gives up until the next occasion: the start of Tor took 62 seconds on 10/11/2026, and the Snowflake fallback takes longer.
const noteTorWait = Duration(minutes: 5);

/// Keeps the RoboSats recovery note of the Garage Keys on the coordinators' relays (#81, design note `docs/design/garage-key-from-the-words.md` § 3, « As PR 3 built it »), as the official client keeps it (`GarageKey.model.ts:89-119`, `Garage.model.ts:547-569`, commit babf62e): the note of a key says the index of its last robot used.
///
/// - **Read**, once per key and per run of the app while the key is not read: at the first showing of the P2P tab of a network, for the key new trades take there ([opened], with [GarageKeyRepository.forNewTrade]); when the Garage shows a key, internal or external, imported or not ([visit]); and before the reservation of a new trade's robot ([beforeNewTrade]). On every coordinator relay of the key's network, for its recovery identity and its legacy one, each relay read apart ([OwnSessionNostrRelayTransport.readOnOwnSession]) and its events read apart in an isolate ([GarageNoteComputePort.readNotes]), then the latest note among the relays' readings ([GarageRecoveryNote.latestOf]). Its index raises the floor of the key's new trades, which only goes up ([GarageRecoveryNoteRepository.recordReading]), whatever number of relays answered: a floor never lowers anything, it can only help.
/// - **Read for good** only when a strict majority of the network's relays ([nostrRelaysOfNetwork]: 4 of 6, 2 of 3, 1 of 1) gave their whole answer and their events were read in time, a note found or not (review of #302): the key is then not read again on this installation. Short of that, a relay that answers at once with nothing, or with an old note, while the others are unreachable or late, could have deprived the key of its floor for good, and the next write would have put a newer, lower note in front of the right one. Without a majority the key stays unread: the floor found is recorded, nothing is written for the key, and it is read again at the next run of the app, never in a loop.
/// - **Written**, with the highest robot index this device knows was used for the key ([NewTradeStanding.highestKnown]: its robots in use and the floor read), after each make and take the coordinator confirmed ([tradeConfirmed]) and again at the first showing of the P2P tab of each network in a run of the app ([opened]), for every key with a robot in use there; on every coordinator relay of the key's network, each publication on a Tor session of its own. Only once the key was read for good: a device that could not read the note from a majority of the relays does not write over a note it may not have seen. The writes of one key run one after the other, the next after the one before it, whatever that one gave.
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

  /// The first reading of each key of each network in this run of the app: whether the key counts as read for good (a strict majority of the relays answered in full) and it was recorded.
  final Map<(RobosatsNetwork, GarageKeyFingerprint), Future<bool>> _reads = {};

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

  /// The Garage shows [key]: its note is read in the background unless it was read for good on this installation or this run already tried.
  void visit(NetworkGarageKey key) => unawaited(_firstReading(key));

  /// Before the robot of a new trade of [key] is reserved: the first reading of its note in this run, started now if this run has not tried it yet, is awaited at most [newTradeNoteWait], by each new trade as long as it has not ended; then the trade goes on with what the device knows, whatever the reading gave. It never fails.
  Future<void> beforeNewTrade(NetworkGarageKey key) =>
      _firstReading(key).timeout(_newTradeWait, onTimeout: () => false);

  /// The coordinator confirmed the make or the take of [record]: the note of its key is written in the background, with the highest robot index this device knows was used for that key.
  void tradeConfirmed(TradeRecord record) =>
      unawaited(_guardedWrite(_writeForRobot(record.robot)));

  /// The P2P tab of [network] is shown: at the first time in this run of the app, in the background, the first reading of the key new trades take on [network] starts ([GarageKeyRepository.forNewTrade]), with robots in use or not, so that after a reinstall it runs well before the first trade (functional review of #302); and the note of every key with a robot in use on [network] is written again, after its first reading.
  ///
  /// A key that cannot be had (no default wallet, a passphrase, a wallet locked, words that no longer give the key recorded) is neither read nor written, and nothing is shown.
  void opened(RobosatsNetwork network) {
    if (!_opened.add(network)) return;
    unawaited(_guardedRead(_readForNewTrade(network)));
    unawaited(_guardedWrite(_writeAll(network)));
  }

  /// The first reading of the key new trades take on [network]: `false` when there is none.
  Future<bool> _readForNewTrade(RobosatsNetwork network) async =>
      switch (await _keys.forNewTrade(network)) {
        Ok(:final value) => await _firstReading(value),
        Err() => false,
      };

  /// The first reading of [key] in this run: `true` when the key counts as read for good.
  Future<bool> _firstReading(NetworkGarageKey key) {
    final fingerprint = switch (key.fingerprint) {
      Ok(:final value) => value,
      Err() => null,
    };
    if (fingerprint == null) return Future.value(false);
    return _reads[(key.network, fingerprint)] ??= _guardedRead(
      _readOnce(key, fingerprint),
    );
  }

  Future<bool> _readOnce(
    NetworkGarageKey key,
    GarageKeyFingerprint fingerprint,
  ) async {
    switch (await _notes.standingOf(key.network, fingerprint)) {
      case Ok(value: GarageNoteStanding(read: true)):
        return true;
      case Ok():
        break;
      case Err():
        return false;
    }
    final clock = Stopwatch()..start();
    if (!await _torReady()) return false;
    clock.reset();
    final relays = nostrRelaysOfNetwork(_federation, key.network);
    if (relays.isEmpty) return false;
    final identities = [
      key.key.recoveryNostrKeyPair,
      key.key.legacyRecoveryNostrKeyPair,
    ];
    final filters = GarageRecoveryNote.filters(key.key);
    // Each relay read apart, and its events read apart: one relay's events never hide another's.
    final readings = await Future.wait([
      for (final relay in relays) _readRelay(relay, filters, identities, clock),
    ]);
    // Read for good only on the whole answer of a strict majority of the network's relays (review of #302): one relay, empty or holding an old note, never settles the key while the others are unreachable or late.
    final answers = readings.where((reading) => reading.answered).length;
    final read = answers * 2 > relays.length;
    final latest = GarageRecoveryNote.latestOf([
      for (final reading in readings) reading.note,
    ]);
    if (!read && latest == null) {
      log.info('P2P recovery note: not read');
      return false;
    }
    // The floor found is recorded with or without a majority: it only goes up.
    final recorded = await _notes.recordReading(
      key.network,
      fingerprint,
      floor: latest?.accountIndex,
      answered: read,
    );
    return read && recorded is Ok;
  }

  /// One relay's reading: the note its events hold, and whether it gave its whole answer and its events were read within the reading's deadline.
  Future<({GarageRecoveryReading? note, bool answered})> _readRelay(
    Uri relay,
    List<NostrRelayFilter> filters,
    List<NostrKeyPair> identities,
    Stopwatch clock,
  ) async {
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
    // Never over a note this device has not read from a majority of the relays: it could hide a higher index.
    if (!await _firstReading(key)) return;
    final int highest;
    switch (await _standing(key.network, fingerprint)) {
      case Ok(value: NewTradeStanding(highestKnown: final known?)):
        highest = known;
      case Ok() || Err():
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
  static Future<void> _guardedWrite(Future<void> work) => work.then(
    (_) {},
    onError: (Object error, StackTrace trace) {
      if (error is! Exception) Zone.current.handleUncaughtError(error, trace);
    },
  );
}
