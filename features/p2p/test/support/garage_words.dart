import 'package:p2p/p2p.dart'
    show
        P2pGarageKeyPort,
        P2pGarageKeyRefusal,
        P2pGarageKeyRefusalReason,
        RobosatsNetwork;
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/garage_keyring.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:primitives/primitives.dart';
import 'package:test/test.dart' show Matcher, equals, isA;
import 'package:secrets/secrets.dart';

/// The public test phrase « abandon ×11 about »: never a real wallet's.
const abandonWords = [
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'about',
];

/// The public test phrase « legal winner … yellow »: never a real wallet's.
const legalWords = [
  'legal',
  'winner',
  'thank',
  'year',
  'wave',
  'sausage',
  'worth',
  'useful',
  'legal',
  'winner',
  'thank',
  'yellow',
];

/// The `robo1…` texts of the design note's vectors for « abandon ×11 about » (`docs/design/garage-key-from-the-words.md` § 1).
const abandonMainnet0 =
    'robo17u5x0ykpntv26907967s76hh058dwwjc8936zq55wcyyk9r3h87qd7k9t2';
const abandonMainnet1 =
    'robo15tu0dg5wknex0g75zk4p79u282ugrxlcmcsj20cswlwfap0e7j3s06neq4';
const abandonMainnet2 =
    'robo15ec96eeuau87588swfvh032rcrkzjymcgz60uspk06elcgxe3u9qzzdfrw';
const abandonTestnet0 =
    'robo1vsap3v8a45z0uw66q26hywyyl0kh727q48dqeac9wra7wt2dgg2s3mfwmz';

/// The keys of public test words, derived by the real package over the test's keystore, as the shell's adapter derives them (`secret.derive.garageKey`), never a wallet's: for the tests of the Garage and of the keys of the words (#81).
///
/// The words are imported at the first derivation into the keystore the test installed (`FakeSecureStoragePlatform`); [words] may change between calls, as another wallet restored in the same book; [refusal], when set, answers instead, as the adapter refuses (no default wallet, a passphrase, …). It records every index asked.
final class TestWordsPort implements P2pGarageKeyPort {
  List<String> words;
  P2pGarageKeyRefusalReason? refusal;
  final List<(RobosatsNetwork, int)> asked = [];
  final Secrets _secrets = Secrets(scratchDirectory: () async => '.');
  final Map<String, Secret> _imported = {};

  final Map<(String, RobosatsNetwork, int), GarageKeyMaterial> _derived = {};

  TestWordsPort({this.words = abandonWords, this.refusal});

  /// Derives the keys of [keys] now, for a widget test, whose fake time does not run the vault's real work: call it in `tester.runAsync`; the keys are then given from memory.
  Future<void> precompute(List<(RobosatsNetwork, int)> keys) async {
    for (final (network, index) in keys) {
      if (await garageKey(network, index: index) case Ok(:final value)) {
        _derived[(words.join(' '), network, index)] = value;
      }
    }
    asked.clear();
  }

  @override
  Future<Result<GarageKeyMaterial, P2pGarageKeyRefusal>> garageKey(
    RobosatsNetwork network, {
    required int index,
  }) async {
    if (index < 0 || index > 0x7fffffff) {
      throw ArgumentError.value(index, 'index');
    }
    asked.add((network, index));
    if (refusal case final reason?) return Err(P2pGarageKeyRefusal(reason));
    if (_derived[(words.join(' '), network, index)] case final material?) {
      return Ok(material);
    }
    final secret = _imported[words.join(' ')] ??= await _secretOf(words);
    return switch (await secret.derive.garageKey(
      network: switch (network) {
        RobosatsNetwork.mainnet => GarageKeySlot.mainnet,
        RobosatsNetwork.testnet => GarageKeySlot.testnet,
      },
      index: index,
    )) {
      Ok(:final value) => Ok(value),
      Err() => const Err(
        P2pGarageKeyRefusal(P2pGarageKeyRefusalReason.unreadable),
      ),
    };
  }

  /// The secret of [words] in the test's keystore: imported, or found there when an earlier port of the test imported it.
  Future<Secret> _secretOf(List<String> words) async {
    switch (await _secrets.import(words: words)) {
      case Ok(:final value):
        return value;
      case Err(failure: SecretAlreadyExistsFailure()):
        final listed = await _secrets.list();
        if (listed case Ok(value: final entries)) {
          for (final entry in entries.whereType<Secret>()) {
            if (await entry.verify.mnemonic(words) case Ok(value: true)) {
              return entry;
            }
          }
        }
        throw StateError('the test words are stored but not found');
      case Err(:final failure):
        throw StateError('$failure');
    }
  }
}

/// The members a fake of [GarageKeyRepository] that holds one key answers from [read]: for the fakes of the tests of trades, written before #81, whose key is key 0 of the words.
mixin KeysFromRead implements GarageKeyRepository {
  @override
  Future<Result<GarageKeyring, P2pFailure>> keyring(
    RobosatsNetwork network,
  ) async => switch (await read(network)) {
    Ok() => const Ok(GarageKeyring(highest: 0, selected: SelectedWordsKey(0))),
    Err(:final failure) => Err(failure),
  };

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> derived(
    RobosatsNetwork network,
    int index,
  ) => index == 0
      ? read(network)
      : Future.value(const Err(GarageKeyMissingFailure()));

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> forNewTrade(
    RobosatsNetwork network,
  ) => read(network);

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> ofSlot(RobotSlot slot) =>
      read(slot.network);

  @override
  Future<Result<int, P2pFailure>> activateNext(
    RobosatsNetwork network, {
    required int after,
  }) => throw UnimplementedError();

  @override
  Future<Result<void, P2pFailure>> select(
    RobosatsNetwork network,
    GarageKeySelection selection,
  ) => throw UnimplementedError();

  @override
  Future<Result<void, P2pFailure>> delete(RobosatsNetwork network) =>
      throw UnimplementedError();

  @override
  Future<Result<void, P2pFailure>> selectInternal(RobosatsNetwork network) =>
      throw UnimplementedError();

  @override
  Future<Result<int?, P2pFailure>> internalIndexOf(
    RobosatsNetwork network,
    GarageKeyFingerprint fingerprint,
  ) async => const Ok(null);

  @override
  Future<Result<void, P2pFailure>> externalNoticeShown() async =>
      const Ok(null);
}

/// Key 0 of the words as the key the test stored in the vault's slot of the network, every other index refused, as `setUpP2pForTesting` does by default: for the tests written before #81 around a fixed key, never a derivation.
final class SlotAsWordsPort implements P2pGarageKeyPort {
  final GarageKeys _vault;

  const SlotAsWordsPort(this._vault);

  @override
  Future<Result<GarageKeyMaterial, P2pGarageKeyRefusal>> garageKey(
    RobosatsNetwork network, {
    required int index,
  }) async {
    if (index != 0) {
      return const Err(
        P2pGarageKeyRefusal(P2pGarageKeyRefusalReason.unreadable),
      );
    }
    return switch (await _vault.read(
      slot: switch (network) {
        RobosatsNetwork.mainnet => GarageKeySlot.mainnet,
        RobosatsNetwork.testnet => GarageKeySlot.testnet,
      },
    )) {
      Ok(:final value) => Ok(value),
      Err() => const Err(
        P2pGarageKeyRefusal(P2pGarageKeyRefusalReason.unreadable),
      ),
    };
  }
}

/// A result that is `Ok` with [value] (`Ok` and `Err` have no equality of their own).
Matcher isOk(Object? value) => isA<Ok<Object?, Failure>>().having(
  (ok) => ok.value,
  'value',
  value is Matcher ? value : equals(value),
);

/// A result that is `Err` with a failure of type [F].
Matcher isErr<F extends Failure>() => isA<Err<Object?, Failure>>().having(
  (err) => err.failure,
  'failure',
  isA<F>(),
);

/// A result that is `Err` with a failure of the type of [failure].
Matcher isErrLike(Failure failure) => isA<Err<Object?, Failure>>().having(
  (err) => err.failure.runtimeType,
  'failure',
  failure.runtimeType,
);
