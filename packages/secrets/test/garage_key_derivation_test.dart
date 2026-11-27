import 'dart:convert';

import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:bip85_entropy/bip85_entropy.dart';
import 'package:convert/convert.dart' as convert;
import 'package:flutter_test/flutter_test.dart';
import 'package:primitives/primitives.dart';
import 'package:secrets/secrets.dart';
import 'package:secrets/src/crypto/crypto.dart' show Backup, GarageDeriver;
import 'package:secrets/src/crypto/derivers/derivers.dart' show Deriver;
import 'package:secrets/src/data/secret_repository.dart' show SecretRepository;
import 'package:secrets/testing.dart';

import 'result_helpers.dart';

/// The Garage Key derived from a secret's words (#81), pinned through the real `bip85_entropy`.
///
/// Every value below was computed by two independent implementations of BIP32, BIP39 and BIP85 and recomputed by an independent reviewer before it was pinned here (`vecteurs_simple.json` of the design study). Once a version that derives a key has shipped, these keys are the user's robots: a value that moves is a Garage that no longer finds its robots.
void main() {
  const abandon = [
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
  const legal = [
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
  // The master key of the BIP85 specification's test vectors.
  const specMaster =
      'xprv9s21ZrQH143K2LBWUUQRFXhucrQqBpKdRRxNVq2zBqsx8HVqFk2uYo8kmbaLL'
      'HRdqtQpUm98uKfu3vca1LqdGhUtyoFnCNkfmXRyPXLjbKb';
  const mainnet = GarageKeySlot.mainnet;
  const testnet = GarageKeySlot.testnet;

  // Keys 0, 1 and 2 of both networks, for both test phrases.
  const vectors = <(List<String>, GarageKeySlot, int, String)>[
    (
      abandon,
      mainnet,
      0,
      'f7286792c19ad8ad15fe2ebd0f6af77d0ed73a583963a1029476084b1471b9fc',
    ),
    (
      abandon,
      mainnet,
      1,
      'a2f8f6a28eb4f267a3d415aa1f178a3ab8819bf8de21253f1077dc9e85f9f4a3',
    ),
    (
      abandon,
      mainnet,
      2,
      'a6705d673cef0fea1cf0725977c543c0ec29137840b4fe40367eb3fc20d98f0a',
    ),
    (
      abandon,
      testnet,
      0,
      '643a18b0fdad04fe3b5a02b5723884fbed7f2bc0a9da0cf70570fbe72d4d4215',
    ),
    (
      abandon,
      testnet,
      1,
      '95eb09e13c7f653e092b6ad54592887f2b4e749bf070114a996509a844e4dc17',
    ),
    (
      abandon,
      testnet,
      2,
      '943618638a12878dc01e7928ee14db54c235f86d58dea91284a8730d25f7161f',
    ),
    (
      legal,
      mainnet,
      0,
      '90d5bdb59edac8192f1cdc132520247ea238f40a16132c6e8863b0f8556f131e',
    ),
    (
      legal,
      mainnet,
      1,
      'd9774e97d2a9dff59dcab72ca537d3e79fbe78dcd23c739ea1e9a88b682f0d85',
    ),
    (
      legal,
      mainnet,
      2,
      '099475e0ab217883506fa320df56d18663842571fc8f55459f5c94912208e4fd',
    ),
    (
      legal,
      testnet,
      0,
      '522a75ad745453472dab6afcfcf58616e11581e4256224d3b6afbaa134bad509',
    ),
    (
      legal,
      testnet,
      1,
      '09ade627c2b386272cbc2d8f49d446f3e592086f12bcde3cc89d10be6c4cf81b',
    ),
    (
      legal,
      testnet,
      2,
      'b27d19d9df5a14d1727c72acc95a8c617f6cf9132262bbb29178b04673f80bd8',
    ),
  ];

  // The edges, all for « abandon ».
  const edges = <(GarageKeySlot, int, String, String)>[
    (
      mainnet,
      0x7fffffff,
      'the largest index',
      '62fc9d0ab27d6471c85ed04bf08beb2e4a7ea1170d9d42e6a8fa31f06dcb8aad',
    ),
    (
      testnet,
      0x7fffffff,
      'the largest index',
      '188900f6db41babf9917d0d39e03789e0dd9a54ee6ec42041fccb6326a037d7d',
    ),
    // The first index whose BIP32 private key at the last step starts with a zero byte, which catches a dropped leading zero before the HMAC.
    (
      mainnet,
      131,
      'a BIP32 key with a leading zero byte',
      '68a1ef4f6634b4adec706f2ceccec0f8a8a3246f6f97e95eb91e0f7f1b8afd65',
    ),
    (
      testnet,
      1566,
      'a BIP32 key with a leading zero byte',
      'a4d2eec4a4755c5d42520596e52ee2e5689fdfb8ae46b03fb271bd5245976cd9',
    ),
    // The value the independent reviewer computed for this very layout.
    (
      mainnet,
      474480,
      'the cross-check',
      'cf9949747916416e7e5d6dbd0181df7eb8a002e97f16b2dead57194471a22c22',
    ),
  ];

  String hexOf(GarageKeyMaterial key) => convert.hex.encode(key.bytes);

  Secrets service(FakeSecureStoragePlatform storage) {
    storage.install();
    return Secrets(scratchDirectory: () async => '/tmp');
  }

  Future<Secret> imported(
    Secrets secrets,
    List<String> words, {
    String? passphrase,
  }) async => ok(await secrets.import(words: words, passphrase: passphrase));

  group('the path', () {
    test('is built from the network and the index, every step hardened', () {
      expect(
        GarageDeriver.path(network: mainnet, index: 0),
        "m/83696968'/82796679'/0'/0'/0'",
      );
      expect(
        GarageDeriver.path(network: testnet, index: 0x7fffffff),
        "m/83696968'/82796679'/0'/1'/2147483647'",
      );
    });

    test('the application number is « ROBO » in ASCII decimal', () {
      expect(GarageDeriver.application, int.parse('ROBO'.codeUnits.join()));
      expect(GarageDeriver.purpose, 0);
    });
  });

  group('pinned keys', () {
    test('keys 0, 1 and 2 of both networks, from the words', () async {
      final secrets = service(FakeSecureStoragePlatform());
      final secretOf = {
        abandon: await imported(secrets, abandon),
        legal: await imported(secrets, legal),
      };
      for (final (words, network, index, expected) in vectors) {
        final secret = secretOf[words] ?? fail('no secret');
        expect(
          hexOf(
            ok(await secret.derive.garageKey(network: network, index: index)),
          ),
          expected,
          reason: '${words.last} ${network.name} $index',
        );
      }
    });

    for (final (network, index, label, expected) in edges) {
      test('$label, ${network.name} $index', () async {
        final secret = await imported(
          service(FakeSecureStoragePlatform()),
          abandon,
        );
        expect(
          hexOf(
            ok(await secret.derive.garageKey(network: network, index: index)),
          ),
          expected,
        );
      });
    }

    test("keys 0, 1 and 2 from the BIP85 specification's master key", () {
      const fromSpec = <(GarageKeySlot, int, String)>[
        (
          mainnet,
          0,
          '2c05ea71cdef50cad52421e00191c992425d0f216c327314909b6e61e3f4bb02',
        ),
        (
          mainnet,
          1,
          '1980f9c01b5a2df4ab3d046be8d8ad34ca64430866b8b8f0dce0c5c2f774f2a5',
        ),
        (
          mainnet,
          2,
          '64db1002ec2263bffc82f4bb1c810af3e36aeefa9eab2a08f4fc553fd7a108f7',
        ),
        (
          testnet,
          0,
          'a4b52892469676685990fd9061ddf4a287a064e0188ffb179406ce62737796fe',
        ),
        (
          testnet,
          1,
          '16204be9be39ffdda8763dcc8f567abc0da80d0f2e9bafa26b1ce974cee0333d',
        ),
        (
          testnet,
          2,
          '028c0fecaeae59a93e17fc7cf57175787dbe2a80817cb757c8ab63c6dd5960ef',
        ),
      ];
      for (final (network, index, expected) in fromSpec) {
        expect(
          hexOf(
            Deriver.garage.keyFromRoot(
              specMaster,
              network: network,
              index: index,
            ),
          ),
          expected,
          reason: '${network.name} $index',
        );
      }
    });
  });

  group('refusals', () {
    test('an unhardened step is refused before bip85_entropy is called', () {
      // The trap: the library derives this path without a word, and its first 32 bytes are the value below. The deriver must refuse it, so the value never leaves.
      const neverProduced =
          '14a2f33b94e6d90054018a68b804dcb1d99e126f3346dca56f86e35fb1a66e18';
      expect(
        convert.hex.encode(
          Bip85Entropy.derive(
            xprvBase58: _abandonMaster,
            application: CustomApplication.fromNumber(82796679),
            path: "0'/0'/0",
          ).sublist(0, 32),
        ),
        neverProduced,
        reason: 'bip85_entropy accepts the unhardened step',
      );
      expect(
        () => Deriver.garage.keyAtPath(
          _abandonMaster,
          "m/83696968'/82796679'/0'/0'/0",
        ),
        throwsArgumentError,
      );
    });

    test(
      'a step of 2147483648 without apostrophe is read by the library as 0\' and refused by the deriver',
      () {
        // Observed during the design study, pinned here (#81, design note § 1): the library takes the unmarked number 2^31 for the hardened index 0, so this path would give key 0 itself. The deriver refuses the path, so no caller can reach a key by that spelling.
        const key0 =
            'f7286792c19ad8ad15fe2ebd0f6af77d0ed73a583963a1029476084b1471b9fc';
        expect(
          convert.hex.encode(
            Bip85Entropy.derive(
              xprvBase58: _abandonMaster,
              application: CustomApplication.fromNumber(82796679),
              path: "0'/0'/2147483648",
            ).sublist(0, 32),
          ),
          key0,
          reason: 'bip85_entropy reads 2147483648 as the hardened index 0',
        );
        expect(
          () => Deriver.garage.keyAtPath(
            _abandonMaster,
            "m/83696968'/82796679'/0'/0'/2147483648",
          ),
          throwsArgumentError,
        );
      },
    );

    test('every path that is not a Garage Key path is refused', () {
      for (final path in [
        "m/83696968'/82796679'/0'/0/0'",
        "m/83696968'/82796679/0'/0'/0'",
        "m/83696968/82796679'/0'/0'/0'",
        "83696968'/82796679'/0'/0'/0'",
        "m/83696968'/82796679'/0'/0'",
        "m/83696968'/82796679'/0'/0'/0'/0'",
        "m/83696968'/82796680'/0'/0'/0'",
        "m/83696968'/82796679'/1'/0'/0'",
        "m/83696968'/82796679'/0'/2'/0'",
        "m/83696968'/82796679'/0'/0'/-1'",
        "m/83696968'/82796679'/0'/0'/2147483648'",
        "m/83696968'/82796679'/0'/0'/00'",
        "m/83696968'/82796679'/0'/0'/0h",
        "m/83696968'/82796679'/0'/0'/ 0'",
        "m/83696968'/128169'/0'/0'/0'",
      ]) {
        expect(
          () => Deriver.garage.keyAtPath(_abandonMaster, path),
          throwsArgumentError,
          reason: path,
        );
      }
    });

    test(
      'a secret with a passphrase is refused, and its key never computed',
      () async {
        // What the words with « TREZOR » would give at mainnet index 0: the refusal withholds exactly this.
        const neverProduced =
            '73c94c4bdbdad068444c58e28897b4f22a0d025125d66c7e2429fa0dd15b3bca';
        FakeSecureStoragePlatform().install();
        final repository = SecretRepository();
        final info = ok(
          await repository.store(words: abandon, passphrase: 'TREZOR'),
        );
        final root = ok(
          await repository.use(info, (m) => Deriver.bip85.root(m)),
        );
        expect(
          hexOf(Deriver.garage.keyFromRoot(root, network: mainnet, index: 0)),
          neverProduced,
        );

        final secret = await imported(
          service(FakeSecureStoragePlatform()),
          abandon,
          passphrase: 'TREZOR',
        );
        for (final network in GarageKeySlot.values) {
          expect(
            err(await secret.derive.garageKey(network: network, index: 0)),
            isA<PassphraseUnsupportedFailure>(),
            reason: network.name,
          );
        }
      },
    );

    test(
      'a seed-only secret is refused: the words must give the key back',
      () async {
        final storage = FakeSecureStoragePlatform(
          entries: {
            'seed_aabbccdd': jsonEncode({
              'bytes': List<int>.filled(64, 7),
              'runtimeType': 'bytes',
            }),
          },
        );
        final secret = ok(
          await service(storage).fetch(Fingerprint('aabbccdd')),
        );
        expect(
          err(await secret.derive.garageKey(network: mainnet, index: 0)),
          isA<MnemonicRequiredFailure>(),
        );
      },
    );

    test(
      'an index outside 0 … 2^31−1 is refused before any keystore read',
      () async {
        final storage = FakeSecureStoragePlatform();
        final secret = await imported(service(storage), abandon);
        storage.locked = true;
        final before = storage.reads;
        for (final index in [-1, 0x80000000, 0x100000000]) {
          for (final network in GarageKeySlot.values) {
            expect(
              () => secret.derive.garageKey(network: network, index: index),
              throwsArgumentError,
              reason: '${network.name} $index',
            );
          }
        }
        expect(storage.reads, before);

        for (final index in [0, 0x7fffffff]) {
          expect(
            err(await secret.derive.garageKey(network: mainnet, index: index)),
            isA<KeystoreLockedFailure>(),
          );
        }
        expect(storage.reads, greaterThan(before));
      },
    );
  });

  test('the key never prints itself', () async {
    final secret = await imported(
      service(FakeSecureStoragePlatform()),
      abandon,
    );
    final result = await secret.derive.garageKey(network: mainnet, index: 0);
    expect(ok(result).toString(), 'GarageKeyMaterial(•••)');
    expect(result.toString(), isNot(contains('f7286792')));
  });

  test(
    'no key collides with the other children the package derives from the same words',
    () async {
      FakeSecureStoragePlatform().install();
      final repository = SecretRepository();
      final info = ok(await repository.store(words: abandon));
      final material = ok(await repository.use(info, (m) => m));
      final root = Deriver.bip85.root(material);
      expect(root, _abandonMaster);

      const indexes = 16;
      final garage = <String>{
        for (final network in GarageKeySlot.values)
          for (var index = 0; index < indexes; index++)
            hexOf(
              Deriver.garage.keyFromRoot(root, network: network, index: index),
            ),
      };
      expect(
        garage,
        hasLength(2 * indexes),
        reason: 'Garage Keys among themselves',
      );

      String entropyOf(List<String> words) => bip39.Mnemonic.fromWords(
        words: words,
      ).entropy.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final others = <String>[
        for (var index = 0; index < indexes; index++) ...[
          Deriver.bip85.hex(material, numBytes: 32, index: index),
          Deriver.bip85
              .hex(material, numBytes: 64, index: index)
              .substring(0, 64),
          Backup.recoverbull.backupKey(
            masterXprv: root,
            path: "1608'/0'/$index'",
          ),
          for (final length in [
            bip39.MnemonicLength.words12,
            bip39.MnemonicLength.words24,
          ])
            entropyOf(
              Deriver.bip85.mnemonic(
                material,
                language: bip39.Language.english,
                length: length,
                index: index,
              ),
            ),
        ],
        // The swap key's mnemonic, the child boltz derives (`swap_key_vector_test.dart`).
        entropyOf(
          Deriver.bip85.mnemonic(
            material,
            language: bip39.Language.english,
            length: bip39.MnemonicLength.words12,
            index: 26589,
          ),
        ),
      ];
      for (final other in others) {
        expect(
          garage.any((key) => other.startsWith(key)),
          isFalse,
          reason: other,
        );
        expect(
          garage.any((key) => key.startsWith(other)),
          isFalse,
          reason: other,
        );
      }
    },
  );
}

/// The master xprv of « abandon … about » without a passphrase, pinned in `derivation_vectors_test.dart`.
const _abandonMaster =
    'xprv9s21ZrQH143K3GJpoapnV8SFfukcVBSfeCficPSGfubmSFDxo1kuHnLisriDv'
    'SnRRuL2Qrg5ggqHKNVpxR86QEC8w35uxmGoggxtQTPvfUu';
