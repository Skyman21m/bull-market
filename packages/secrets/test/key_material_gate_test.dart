import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/key_material_gate.dart';

void main() {
  late Directory fixture;
  late AnalysisContextCollection collection;
  late String repository;

  setUpAll(() {
    var current = Directory.current;
    while (!File(
      '${current.path}/packages/secrets/pubspec.yaml',
    ).existsSync()) {
      if (current.parent.path == current.path) {
        throw StateError('No repository');
      }
      current = current.parent;
    }
    repository = current.path;
    fixture = Directory.systemTemp.createTempSync('key_material_gate_');
    final source = File('$repository/.dart_tool/package_config.json');
    final config = jsonDecode(source.readAsStringSync()) as Map;
    for (final package in config['packages'] as List) {
      package['rootUri'] = source.uri
          .resolve(package['rootUri'] as String)
          .toString();
    }
    File('${fixture.path}/.dart_tool/package_config.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(config));
    File('${fixture.path}/bridge.dart').writeAsStringSync('''
export 'package:bip32_keys/bip32_keys.dart';
export 'package:bull_sdk/bdk.dart' show DescriptorSecretKey;
export 'package:recoverbull/recoverbull.dart';
export 'package:secrets/testing.dart';
''');
    File('${fixture.path}/garage_bridge.dart').writeAsStringSync('''
export 'package:robosats/robosats.dart' show GarageKey;
export 'package:secrets/secrets.dart' show GarageKeyMaterial;
''');
    collection = AnalysisContextCollection(
      includedPaths: [fixture.resolveSymbolicLinksSync()],
      sdkPath: dartSdkPath(repository),
    );
  });

  tearDownAll(() async {
    await collection.dispose();
    fixture.deleteSync(recursive: true);
  });

  Future<List<String>> inspect(
    String name,
    String source, {
    String? policyPath,
  }) async {
    final file = File('${fixture.path}/$name.dart')..writeAsStringSync(source);
    final result = await collection
        .contextFor(file.resolveSymbolicLinksSync())
        .currentSession
        .getResolvedUnit(file.resolveSymbolicLinksSync());
    expect(result, isA<ResolvedUnitResult>());
    final resolved = result as ResolvedUnitResult;
    expect(
      resolved.diagnostics.where(
        (d) => d.diagnosticCode.severity.name == 'ERROR',
      ),
      isEmpty,
      reason: 'The regression fixture must resolve successfully',
    );
    return checkUnit(resolved.unit, policyPath ?? 'lib/$name.dart');
  }

  test(
    'aliases and getter access resolve to the private seed declaration',
    () async {
      final violations = await inspect('alias', '''
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as words;
List<int> derive(words.Mnemonic input) => input.seed;
''');
      expect(violations.single, endsWith('#Mnemonic.seed'));
    },
  );

  test(
    're-exports, type aliases and constructor tear-offs retain identity',
    () async {
      final violations = await inspect('reexport', '''
import 'bridge.dart' as bridge;
typedef Root = bridge.Bip32Keys;
final factory = Root.fromSeed;
final decrypt = bridge.RecoverBull.restoreBackup;
final descriptor = bridge.DescriptorSecretKey.fromString;
''');
      expect(violations, hasLength(3));
      expect(violations, contains(endsWith('#Bip32Keys.fromSeed')));
      expect(violations, contains(endsWith('#RecoverBull.restoreBackup')));
      expect(violations, contains(endsWith('#DescriptorSecretKey.fromString')));
    },
  );

  test('raw private-key constructors and tear-offs are checked', () async {
    final violations = await inspect('raw_private', '''
import 'dart:typed_data';
import 'bridge.dart' as bridge;
typedef Root = bridge.Bip32Keys;
String derive(Uint8List key, Uint8List chain, bridge.NetworkType network) =>
    Root(key, null, chain, network)
        .derivePath('m/0').toBase58();
final factory = Root.new;
''');
    expect(violations, contains(endsWith('#Bip32Keys.new')));
  });

  test('Base58 private-key loading and tear-offs are checked', () async {
    final violations = await inspect('private_base58', '''
import 'bridge.dart' as bridge;
typedef Root = bridge.Bip32Keys;
String derive(String xprv) =>
    Root.fromBase58(xprv).derivePath("m/0'").toBase58();
final factory = Root.fromBase58;
''');
    expect(violations, contains(endsWith('#Bip32Keys.fromBase58')));
  });

  test(
    'Base58 exemption requires the public adapter file and method',
    () async {
      const path = 'lib/core/utils/bip32_derivation.dart';
      const source = '''
import 'package:bip32_keys/bip32_keys.dart';
class Bip32Derivation {
  static Bip32Keys getBip32Xpub(String value) => Bip32Keys.fromBase58(value);
}
''';
      expect(
        await inspect('public_adapter', source, policyPath: path),
        isEmpty,
      );
      expect(
        await inspect('wrong_adapter_file', source),
        contains(endsWith('#Bip32Keys.fromBase58')),
      );
      expect(
        await inspect(
          'wrong_adapter_method',
          source.replaceAll('getBip32Xpub', 'other'),
          policyPath: path,
        ),
        contains(endsWith('#Bip32Keys.fromBase58')),
      );
      expect(
        await inspect(
          'wrong_adapter_class',
          source.replaceAll('Bip32Derivation', 'Other'),
          policyPath: path,
        ),
        contains(endsWith('#Bip32Keys.fromBase58')),
      );
    },
  );

  test('test keystore aliases and re-exports retain identity', () async {
    final violations = await inspect('fake_keystore', '''
import 'bridge.dart' as bridge;
typedef Storage = bridge.FakeSecureStoragePlatform;
Object install() => Storage().install();
''');
    expect(violations, isNotEmpty);
    expect(violations, everyElement(contains('package:secrets/src/testing/')));
  });

  test(
    'test support imports and exports are forbidden in production',
    () async {
      expect(
        await inspect('fake_import', '''
import 'package:secrets/testing.dart';
'''),
        isNotEmpty,
      );
      expect(
        await inspect('fake_export', '''
export 'package:secrets/testing.dart';
'''),
        isNotEmpty,
      );
    },
  );

  test(
    'all conditional test-support import and export branches are checked',
    () async {
      for (final directive in ['import', 'export']) {
        for (final (branch, uri) in [
          ('public', 'package:secrets/testing.dart'),
          (
            'internal',
            'package:secrets/src/testing/fake_secure_storage_platform.dart',
          ),
        ]) {
          expect(
            await inspect('conditional_${directive}_$branch', '''
$directive 'dart:core' if (dart.library.html) '$uri';
'''),
            contains(endsWith('$uri#test-only library')),
          );
        }
        expect(
          await inspect('conditional_${directive}_default', '''
$directive 'package:secrets/testing.dart' if (dart.library.io) 'dart:core';
'''),
          contains(endsWith('package:secrets/testing.dart#test-only library')),
        );
      }
    },
  );

  test('test support is blocked across production workspace roots', () async {
    final root = Directory('${fixture.path}/testing_boundary')..createSync();
    const production = [
      'lib/app.dart',
      'packages/consumer/lib/service.dart',
      'features/consumer/lib/feature.dart',
    ];
    for (final path in [...production, 'test/allowed_test.dart']) {
      File('${root.path}/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
import 'package:secrets/testing.dart' as testing;
Object install() => testing.FakeSecureStoragePlatform().install();
''');
    }
    final report = await checkKeyMaterial(root.path);
    expect(report.fileCount, production.length);
    for (final path in production) {
      expect(report.violations, contains(startsWith('$path: ')));
    }
    expect(report.violations, isNot(contains(startsWith('test/'))));
  });

  test('dot shorthand and instance method tear-offs are checked', () async {
    final violations = await inspect('shorthand', '''
import 'package:bull_sdk/bdk.dart' as bdk;
bdk.DescriptorSecretKey secret(String key) => .fromString(privateKey: key);
Object extract(bdk.DescriptorSecretKeyInterface key) => key.secretBytes;
''');
    expect(violations, hasLength(2));
    expect(violations, contains(endsWith('#DescriptorSecretKey.fromString')));
    expect(
      violations,
      contains(endsWith('#DescriptorSecretKeyInterface.secretBytes')),
    );
  });

  test(
    'low-level vault decryption and private BIP85 derivation are checked',
    () async {
      final violations = await inspect('crypto', '''
import 'package:bip85_entropy/bip85_entropy.dart';
import 'package:recoverbull/src/services/encryption.dart';
final child = Bip85Entropy.deriveMnemonic;
final decrypt = EncryptionService.decrypt;
''');
      expect(violations, hasLength(2));
      expect(violations, contains(endsWith('#Bip85Entropy.deriveMnemonic')));
      expect(violations, contains(endsWith('#EncryptionService.decrypt')));
    },
  );

  test(
    'public derivation, validation and child formatting remain available',
    () async {
      expect(
        await inspect('public', '''
import 'dart:typed_data';
import 'package:bip32_keys/bip32_keys.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart';
import 'package:bip85_entropy/bip85_entropy.dart';
Bip32Keys publicKey(Uint8List key, Uint8List chain) =>
    Bip32Keys.fromPublicKey(key, chain).derivePath('m/0');
Object format(List<String> words) => Mnemonic.fromWords(words: words).entropy;
Object path(String value) => MnemonicApplication.parsePath(value);
'''),
        isEmpty,
      );
    },
  );

  test(
    'an unrelated class with the same member name is not forbidden',
    () async {
      expect(
        await inspect('lookalike', '''
class Mnemonic { List<int> get seed => []; }
List<int> value(Mnemonic input) => input.seed;
'''),
        isEmpty,
      );
    },
  );

  test(
    'unresolved sensitive access fails closed, including dynamic access',
    () async {
      final violations = await inspect('dynamic', '''
Object seed(dynamic input) => input.seed;
''');
      expect(violations.single, endsWith('unresolved sensitive member seed'));
    },
  );

  const scan = '''
import 'dart:typed_data';
import 'package:bull_sdk/bdk.dart' as bdk;
Object _performDryScan() {
  final words = bdk.Mnemonic.fromEntropy(entropy: Uint8List(16));
  final key = bdk.DescriptorSecretKey(
    networkKind: bdk.NetworkKind.main, mnemonic: words, password: null);
  return bdk.Descriptor.newBip84(secretKey: key,
    keychainKind: bdk.KeychainKind.external_, networkKind: bdk.NetworkKind.main);
}
''';
  const scanPath =
      'lib/core/wallet/data/datasources/bdk_wallet_datasource.dart';

  test('pre-import exemption requires the named file and function', () async {
    expect(await inspect('scan', scan, policyPath: scanPath), isEmpty);
    expect(await inspect('wrong_file', scan), hasLength(3));
    expect(
      await inspect(
        'wrong_function',
        scan.replaceAll('_performDryScan', 'other'),
        policyPath: scanPath,
      ),
      hasLength(3),
    );
  });

  test(
    'pre-import exemption does not authorize another derivation API',
    () async {
      final violations = await inspect('scan_extra', '''
import 'package:bip32_keys/bip32_keys.dart';
Object _performDryScan() => Bip32Keys.fromSeed;
''', policyPath: scanPath);
      expect(violations.single, endsWith('#Bip32Keys.fromSeed'));
    },
  );

  const swaps = '''
import 'package:bull_sdk/boltz.dart' as boltz;
class SwapMasterKeyModel {
  factory SwapMasterKeyModel.fromBoltz(boltz.SwapMasterKey key) {
    final privateKey = key.xprv;
    final words = key.mnemonic;
    throw StateError('fixture');
  }
  boltz.SwapMasterKey toBoltz() => boltz.SwapMasterKey(
    xprv: '', xpub: '', network: boltz.Network.mainnet, mnemonic: '', fingerprint: '');
}
''';
  const swapPath = 'lib/core/swaps/data/models/swap_master_key_model.dart';

  test('swap exemption permits only the named model operations', () async {
    expect(await inspect('swap', swaps, policyPath: swapPath), isEmpty);
    expect(await inspect('wrong_swap_file', swaps), hasLength(3));
    expect(
      await inspect(
        'wrong_swap_member',
        swaps.replaceAll('toBoltz', 'other'),
        policyPath: swapPath,
      ),
      hasLength(1),
    );
  });

  test(
    'swap exemption does not authorize deriving a child from wallet words',
    () async {
      final violations = await inspect('swap_create', '''
import 'package:bull_sdk/boltz.dart' as boltz;
class SwapMasterKeyModel {
  Object toBoltz() => boltz.SwapMasterKey.create;
}
''', policyPath: swapPath);
      expect(violations.single, endsWith('#SwapMasterKey.create'));
    },
  );

  test(
    'unresolved production units fail the gate before a green report',
    () async {
      final root = Directory('${fixture.path}/unresolved')..createSync();
      File('${root.path}/lib/app.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('Object create() => MissingType();');
      final report = await checkKeyMaterial(root.path);
      expect(report.fileCount, 1);
      expect(report.violations, contains('lib/app.dart: undefined_function'));
    },
  );

  test(
    'production discovery excludes custody, generated code and vendor files',
    () {
      final root = Directory('${fixture.path}/discovery')..createSync();
      const included = [
        'lib/app.dart',
        'packages/other/lib/value.dart',
        'features/other/lib/feature.dart',
      ];
      for (final path in [
        ...included,
        'packages/secrets/lib/private.dart',
        'test/example.dart',
        'lib/example.g.dart',
        'lib/generated/example.dart',
        'lib/vendor/example.dart',
      ]) {
        File('${root.path}/$path')
          ..createSync(recursive: true)
          ..writeAsStringSync('');
      }
      expect(
        productionDartFiles(root.path),
        unorderedEquals([for (final path in included) '${root.path}/$path']),
      );
    },
  );

  test('Silent Payments accounts built from words are checked', () async {
    final violations = await inspect('bwk_constructors', '''
import 'package:bull_sdk/bwk.dart';
final first = SpAccount.createFromMnemonic;
final second = SpAccount.createFromMnemonicWithScanRuntime;
''');
    expect(violations, hasLength(2));
  });

  test(
    'the bridge starts only with its own handler: no tracing handler, no mock',
    () async {
      final violations = await inspect('bridge_init', '''
import 'package:bull_sdk/bull_sdk.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
class Trace extends BaseHandler {}
Future<void> traced() => BullSdk.init(handler: Trace());
void mocked(dynamic api) => BullSdk.initMock(api: api);
Future<void> plain() => BullSdk.init();
''');
      expect(violations, hasLength(2));
      expect(violations.join(), contains('BullSdk.init'));
      expect(violations.join(), contains('BullSdk.initMock'));
    },
  );

  test('an inactive relative alternative to test support is checked', () async {
    final violations = await inspect('conditional_relative', '''
import 'dart:core' if (dart.library.html) '../../secrets/lib/testing.dart';
''');
    expect(violations, isNotEmpty);
  });

  group('a Garage Key is read only where the P2P feature may read it', () {
    const repositoryPath =
        'features/p2p/lib/src/data/garage_key_repository_impl.dart';
    const viewPath = 'features/p2p/lib/src/ui/widgets/garage_key_view.dart';
    const repository = '''
import 'dart:typed_data';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart';
class GarageKeyRepositoryImpl {
  Object toGarageKey(GarageKeyMaterial material) =>
      GarageKey.fromBytes(material.bytes);
  Uint8List toBytes(GarageKey key) => key.revealBytes();
}
''';
    const view = '''
import 'package:robosats/robosats.dart';
class GarageKeyView {
  final GarageKey garageKey;
  const GarageKeyView(this.garageKey);
  String text() => garageKey.revealBech32();
}
''';

    test('reading one is refused anywhere else', () async {
      final fromRepository = await inspect('garage_elsewhere', repository);
      expect(fromRepository, hasLength(2));
      expect(fromRepository, contains(endsWith('#GarageKeyMaterial.bytes')));
      expect(fromRepository, contains(endsWith('#GarageKey.revealBytes')));
      expect(
        (await inspect('garage_view_elsewhere', view)).single,
        endsWith('#GarageKey.revealBech32'),
      );
      expect(
        (await inspect('garage_bytes_elsewhere', '''
import 'package:secrets/secrets.dart';
List<int> copy(GarageKeyMaterial material) => [...material.bytes];
''')).single,
        allOf(
          startsWith('lib/garage_bytes_elsewhere.dart: package:secrets/'),
          endsWith('#GarageKeyMaterial.bytes'),
        ),
      );
    });

    test(
      'it is accepted in the named file and class, for its own use',
      () async {
        expect(
          await inspect(
            'garage_repository',
            repository,
            policyPath: repositoryPath,
          ),
          isEmpty,
        );
        expect(
          await inspect('garage_view', view, policyPath: viewPath),
          isEmpty,
        );

        // Another class of the named file.
        expect(
          await inspect(
            'garage_repository_other_class',
            repository.replaceAll('GarageKeyRepositoryImpl', 'GarageKeyCache'),
            policyPath: repositoryPath,
          ),
          hasLength(2),
        );
        // Code outside any class of the named file.
        expect(
          (await inspect('garage_repository_top_level', '''
import 'package:secrets/secrets.dart';
class GarageKeyRepositoryImpl {}
Object leak(GarageKeyMaterial material) => material.bytes;
''', policyPath: repositoryPath)).single,
          endsWith('#GarageKeyMaterial.bytes'),
        );
        // The repository's reads are not the widget's, and the other way round.
        expect(
          await inspect(
            'garage_repository_in_view_file',
            repository.replaceAll('GarageKeyRepositoryImpl', 'GarageKeyView'),
            policyPath: viewPath,
          ),
          hasLength(2),
        );
        expect(
          (await inspect(
            'garage_view_in_repository_file',
            view.replaceAll('GarageKeyView', 'GarageKeyRepositoryImpl'),
            policyPath: repositoryPath,
          )).single,
          endsWith('#GarageKey.revealBech32'),
        );
        // The same class name in another file of the feature.
        expect(
          await inspect(
            'garage_repository_other_file',
            repository,
            policyPath: 'features/p2p/lib/src/data/robot_repository_impl.dart',
          ),
          hasLength(2),
        );
      },
    );

    test('an import prefix and a type alias keep the identity', () async {
      final violations = await inspect('garage_alias', '''
import 'package:robosats/robosats.dart' as robosats;
import 'package:secrets/secrets.dart' as secrets;
typedef Material = secrets.GarageKeyMaterial;
Object bytesOf(Material material) => material.bytes;
String textOf(robosats.GarageKey key) => key.revealBech32();
''');
      expect(violations, hasLength(2));
      expect(violations, contains(endsWith('#GarageKeyMaterial.bytes')));
      expect(violations, contains(endsWith('#GarageKey.revealBech32')));
    });

    test('a re-export keeps the identity', () async {
      final violations = await inspect('garage_reexport', '''
import 'garage_bridge.dart' as bridge;
Object bytesOf(bridge.GarageKeyMaterial material) => material.bytes;
Object copyOf(bridge.GarageKey key) => key.revealBytes();
''');
      expect(violations, hasLength(2));
      expect(violations, contains(endsWith('#GarageKeyMaterial.bytes')));
      expect(violations, contains(endsWith('#GarageKey.revealBytes')));
    });

    test('a method extraction keeps the identity', () async {
      final violations = await inspect('garage_tear_off', '''
import 'package:robosats/robosats.dart';
String Function() textOf(GarageKey key) => key.revealBech32;
Object copier(GarageKey key) => key.revealBytes;
''');
      expect(violations, hasLength(2));
      expect(violations, contains(endsWith('#GarageKey.revealBech32')));
      expect(violations, contains(endsWith('#GarageKey.revealBytes')));
    });

    test('an object pattern keeps the identity', () async {
      final violations = await inspect('garage_pattern', '''
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart';
Object bytesOf(Object value) => switch (value) {
  GarageKeyMaterial(:final bytes) => bytes,
  GarageKey(revealBech32: final reveal) => reveal,
  _ => 0,
};
''');
      expect(violations, hasLength(2));
      expect(violations, contains(endsWith('#GarageKeyMaterial.bytes')));
      expect(violations, contains(endsWith('#GarageKey.revealBech32')));
    });

    test('dynamic access to a reveal method fails closed', () async {
      final violations = await inspect('garage_dynamic', '''
Object textOf(dynamic key) => key.revealBech32();
Object bytesOf(dynamic key) => key.revealBytes();
''');
      expect(violations, hasLength(2));
      expect(
        violations,
        contains(endsWith('unresolved sensitive member revealBech32')),
      );
      expect(
        violations,
        contains(endsWith('unresolved sensitive member revealBytes')),
      );
    });

    test('constructing a key and deriving from it remain available', () async {
      expect(
        await inspect('garage_public', '''
import 'dart:typed_data';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart';
Object parse(String text) => GarageKey.parse(text);
Object wrap(Uint8List bytes) => GarageKey.fromBytes(bytes);
Object robot(GarageKey key) => key.deriveIdentity(0);
String label(GarageKeyMaterial material) => '\$material';
int length() => GarageKeyMaterial.lengthInBytes;
'''),
        isEmpty,
      );
    });

    test(
      'only the named files pass, across production workspace roots',
      () async {
        final root = Directory('${fixture.path}/garage_boundary')..createSync();
        const reader = '''
import 'package:secrets/secrets.dart';
class GarageKeyRepositoryImpl {
  Object bytesOf(GarageKeyMaterial material) => material.bytes;
}
''';
        const refused = [
          'lib/locator.dart',
          'packages/robosats/lib/src/garage_store.dart',
          'features/p2p/lib/src/data/robot_repository_impl.dart',
          'features/other/lib/src/data/garage_key_repository_impl.dart',
        ];
        for (final path in [
          ...refused,
          repositoryPath,
          'features/p2p/test/garage_key_repository_impl_test.dart',
        ]) {
          File('${root.path}/$path')
            ..createSync(recursive: true)
            ..writeAsStringSync(reader);
        }
        final report = await checkKeyMaterial(root.path);
        expect(report.fileCount, refused.length + 1);
        for (final path in refused) {
          expect(
            report.violations,
            contains(
              '$path: package:secrets/src/domain/garage_key_material.dart#GarageKeyMaterial.bytes',
            ),
          );
        }
        expect(report.violations, hasLength(refused.length));
      },
    );
  });
}
