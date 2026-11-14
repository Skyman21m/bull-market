import 'dart:typed_data';

import 'package:bech32/bech32.dart' as bech32_package;
import 'package:convert/convert.dart' show hex;
import 'package:crypto/crypto.dart' show sha256;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:robosats/src/bech32_checksum.dart';
import 'package:robosats/src/bitcoin_address.dart'
    show SegwitProgram, decodeSegwit;
import 'package:test/test.dart';

import 'support/bech32_encode.dart';
import 'support/pgp.dart';

const _mainnet = RobosatsNetwork.mainnet;
const _testnet = RobosatsNetwork.testnet;

/// The valid segwit addresses of BIP-350 (« Test vectors for v0-v16 native segregated witness addresses »), with their scriptPubKey: the first, second and sixth are BIP-173's too, copied verbatim from the `bech32` package's tests; the others are BIP-350's.
const _bip350Valid = {
  'BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4':
      '0014751e76e8199196d454941c45d1b3a323f1433bd6',
  'tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7':
      '00201863143c14c5166804bd19203356da136c985678cd4d27a1b8c6329604903262',
  'bc1pw508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7kt5nd6y':
      '5128751e76e8199196d454941c45d1b3a323f1433bd6751e76e8199196d454941c45d1b3a323f1433bd6',
  'BC1SW50QGDZ25J': '6002751e',
  'bc1zw508d6qejxtdg4y5r3zarvaryvaxxpcs':
      '5210751e76e8199196d454941c45d1b3a323',
  'tb1qqqqqp399et2xygdj5xreqhjjvcmzhxw4aywxecjdzew6hylgvsesrxh6hy':
      '0020000000c4a5cad46221b2a187905e5266362b99d5e91c6ce24d165dab93e86433',
  'tb1pqqqqp399et2xygdj5xreqhjjvcmzhxw4aywxecjdzew6hylgvsesf3hn0c':
      '5120000000c4a5cad46221b2a187905e5266362b99d5e91c6ce24d165dab93e86433',
  'bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0':
      '512079be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798',
};

/// The invalid segwit addresses of BIP-350, with the failure each gets and BIP-350's reason.
final _bip350Invalid = <String, (Matcher, String)>{
  'tc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vq5zuyut': (
    isA<PayoutDestinationMalformed>(),
    'invalid human-readable part',
  ),
  'bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqh2y7hd': (
    isA<PayoutDestinationBadChecksum>(),
    'bech32 instead of bech32m',
  ),
  'tb1z0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqglt7rf': (
    isA<PayoutDestinationBadChecksum>(),
    'bech32 instead of bech32m',
  ),
  'BC1S0XLXVLHEMJA6C4DQV22UAPCTQUPFHLXM9H8Z3K2E72Q4K9HCZ7VQ54WELL': (
    isA<PayoutDestinationBadChecksum>(),
    'bech32 instead of bech32m',
  ),
  'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kemeawh': (
    isA<PayoutDestinationBadChecksum>(),
    'bech32m instead of bech32',
  ),
  'tb1q0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vq24jc47': (
    isA<PayoutDestinationBadChecksum>(),
    'bech32m instead of bech32',
  ),
  'bc1p38j9r5y49hruaue7wxjce0updqjuyyx0kh56v8s25huc6995vvpql3jow4': (
    isA<PayoutDestinationMalformed>(),
    'invalid character in checksum',
  ),
  'BC130XLXVLHEMJA6C4DQV22UAPCTQUPFHLXM9H8Z3K2E72Q4K9HCZ7VQ7ZWS8R': (
    isA<PayoutDestinationMalformed>(),
    'invalid witness version',
  ),
  'bc1pw5dgrnzv': (
    isA<PayoutDestinationMalformed>(),
    'invalid program length (1 byte)',
  ),
  'bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7v8n0nx0muaewav253zgeav':
      (isA<PayoutDestinationMalformed>(), 'invalid program length (41 bytes)'),
  'BC1QR508D6QEJXTDG4Y5R3ZARVARYV98GJ9P': (
    isA<PayoutDestinationMalformed>(),
    'invalid program length for witness version 0',
  ),
  'tb1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vq47Zagq': (
    isA<PayoutDestinationMalformed>(),
    'mixed case',
  ),
  'bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7v07qwwzcrf': (
    isA<PayoutDestinationMalformed>(),
    'zero padding of more than 4 bits',
  ),
  'tb1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vpggkg4j': (
    isA<PayoutDestinationMalformed>(),
    'non-zero padding in 8-to-5 conversion',
  ),
  'bc1gmk9yu': (isA<PayoutDestinationMalformed>(), 'empty data section'),
};

/// The invalid segwit addresses of BIP-173, copied verbatim from the `bech32` package's tests, with the failure each gets.
final _bip173Invalid = <String, Matcher>{
  'tc1qw508d6qejxtdg4y5r3zarvary0c5xw7kg3g4ty':
      isA<PayoutDestinationMalformed>(),
  'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t5':
      isA<PayoutDestinationBadChecksum>(),
  'BC13W508D6QEJXTDG4Y5R3ZARVARY0C5XW7KN40WF2':
      isA<PayoutDestinationMalformed>(),
  'bc1rw5uspcuh': isA<PayoutDestinationMalformed>(),
  'bc10w508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7kw5rljs90':
      isA<PayoutDestinationMalformed>(),
  'BC1QR508D6QEJXTDG4Y5R3ZARVARYV98GJ9P': isA<PayoutDestinationMalformed>(),
  'tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sL5k7':
      isA<PayoutDestinationMalformed>(),
  'bc1zw508d6qejxtdg4y5r3zarvaryvqyzf3du': isA<PayoutDestinationMalformed>(),
  'tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3pjxtptv':
      isA<PayoutDestinationMalformed>(),
  'bc1gmk9yu': isA<PayoutDestinationMalformed>(),
};

/// The segwit addresses BIP-173 gave as valid for versions 1 and later, with a bech32 checksum: BIP-350 makes them invalid (copied verbatim from the `bech32` package's tests).
const _bip173FutureVersions = [
  'bc1pw508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7k7grplx',
  'BC1SW50QA3JX3S',
  'bc1zw508d6qejxtdg4y5r3zarvaryvg6kdaj',
];

/// Base58Check addresses with their hash, from the test vectors of the `blockchain_utils` package (`test/address/p2sh/test_vector.dart`), and the address of the genesis block's coinbase.
const _base58Vectors = <(String, RobosatsNetwork, BitcoinAddressKind)>[
  ('37xLrhtoYnTJ3womrCBAvjaD8mMCh6vhUf', _mainnet, BitcoinAddressKind.p2sh),
  ('3EnqecARRLK1e2DRfWYpauSRRXgn9jUacm', _mainnet, BitcoinAddressKind.p2sh),
  ('3C1pJkSRoZxGyAfpRCSmgXRkYcGtZfiB7c', _mainnet, BitcoinAddressKind.p2sh),
  ('2NCefBbdbkb9sxfEHW3UbU3VQPVwWBa25YB', _testnet, BitcoinAddressKind.p2sh),
  ('1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa', _mainnet, BitcoinAddressKind.p2pkh),
];

/// The hash of the public key of BIP-173's examples, `0279BE66…` (`751e76e8…`), from which the tests build addresses of every kind.
final _hash160 = Uint8List.fromList(
  hex.decode('751e76e8199196d454941c45d1b3a323f1433bd6'),
);

/// Base58Check of [version] and [payload], written here independently of the package.
String _base58Check(int version, List<int> payload) {
  const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  final data = [version, ...payload];
  final full = [
    ...data,
    ...sha256.convert(sha256.convert(data).bytes).bytes.sublist(0, 4),
  ];
  var value = BigInt.zero;
  for (final byte in full) {
    value = value << 8 | BigInt.from(byte);
  }
  final digits = <String>[];
  while (value > BigInt.zero) {
    digits.add(alphabet[(value % BigInt.from(58)).toInt()]);
    value ~/= BigInt.from(58);
  }
  for (final byte in full) {
    if (byte != 0) break;
    digits.add('1');
  }
  return digits.reversed.join();
}

/// A bech32 (not bech32m) segwit address, written by the `bech32` package: version 0 only is valid this way.
String _segwitV0(String humanReadablePart, List<int> program) {
  final words = <int>[0];
  var accumulator = 0;
  var bits = 0;
  for (final byte in program) {
    accumulator = accumulator << 8 | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      words.add(accumulator >> bits & 31);
    }
  }
  if (bits > 0) words.add(accumulator << (5 - bits) & 31);
  return bech32_package.bech32.encode(
    bech32_package.Bech32(humanReadablePart, words),
  );
}

String _scriptPubKey(SegwitProgram decoded) => hex.encode([
  decoded.version == 0 ? 0 : decoded.version + 0x50,
  decoded.program.length,
  ...decoded.program,
]);

BitcoinAddress _ok(String text, RobosatsNetwork network) =>
    expectOk(BitcoinAddress.check(text, network));

PayoutDestinationFailure _err(String text, RobosatsNetwork network) =>
    expectErr(BitcoinAddress.check(text, network));

void main() {
  group('bech32 strings', () {
    test(
      'the separator is the last 1, the human-readable part may hold others',
      () {
        for (final humanReadablePart in [
          'bc',
          'ln1tb',
          'lntb1639610n',
          '1',
          'a1b1c',
        ]) {
          for (final bech32m in [false, true]) {
            final words = [for (var i = 0; i < 40; i++) (i * 7) % 32];
            final read = readBech32(
              encodeBech32(humanReadablePart, words, bech32m: bech32m),
              maxLength: 200,
            );
            final parts = read.parts;
            if (parts == null) fail('$humanReadablePart: ${read.refusal}');
            expect(parts.humanReadablePart, humanReadablePart);
            expect(parts.words, words);
            expect(
              parts.variant,
              bech32m ? Bech32Variant.bech32m : Bech32Variant.bech32,
            );
          }
        }
      },
    );

    test('the invalid strings of BIP-173 and BIP-350 are refused, none throws', () {
      // « Test vectors » of both BIPs, the strings that are not valid bech32 or bech32m: out-of-range characters, no separator, an empty human-readable part, a too short checksum, invalid characters, a checksum made over the uppercase form.
      for (final text in [
        '\u00201nwldj5',
        '\u007f1axkwrx',
        '\u00801eym55h',
        'an84characterslonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1569pvx',
        'pzry9x0s0muk',
        '1pzry9x0s0muk',
        'x1b4n0q5v',
        'li1dgmt3',
        'de1lg7wt\u00ff',
        'A1G7SGD8',
        '10a06t8',
        '1qzzfhee',
        '\u00201xj0phk',
        '\u007f1g6xzxy',
        '\u00801vctc34',
        'qyrz8wqd2c9m',
        '1qyrz8wqd2c9m',
        'y1b0jsk6g',
        'lt1igcx5c0',
        'in1muywd',
        'mm1crxm3i',
        'au1s5cgom',
        'M1VUXWEZ',
        '16plkw9',
        '1p2gdwpf',
      ]) {
        final read = readBech32(text, maxLength: 90);
        expect(read.parts, isNull, reason: text);
        expect(read.refusal, isNotNull, reason: text);
      }
      // Those whose only fault is their human-readable part, or a checksum too short, are malformed, not a typo.
      for (final text in [
        '\u00201nwldj5',
        '\u007f1axkwrx',
        '1pzry9x0s0muk',
        '10a06t8',
        '1qzzfhee',
        'li1dgmt3',
        'in1muywd',
        '16plkw9',
        '1p2gdwpf',
      ]) {
        expect(
          readBech32(text, maxLength: 90).refusal,
          Bech32Refusal.malformed,
          reason: text,
        );
      }
    });

    test('a data part under 6 characters is malformed and never throws', () {
      const charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
      for (final humanReadablePart in ['a', 'bc', 'lntb10n', '1']) {
        for (final first in charset.split('')) {
          for (final second in charset.split('')) {
            for (final data in [
              '',
              first,
              '$first$second',
              '$first$second$first$second$first',
            ]) {
              final text = '${humanReadablePart}1$data';
              final read = readBech32(text, maxLength: 90);
              expect(read.refusal, Bech32Refusal.malformed, reason: text);
            }
          }
        }
      }
    });

    test('the length bound is read before anything else', () {
      final text = encodeBech32('lntb', List.filled(100, 3));
      expect(readBech32(text, maxLength: text.length).parts, isNotNull);
      expect(
        readBech32(text, maxLength: text.length - 1).refusal,
        Bech32Refusal.malformed,
      );
    });
  });

  group('BIP-173 and BIP-350 vectors', () {
    for (final MapEntry(key: address, value: script) in _bip350Valid.entries) {
      test('$address decodes to its scriptPubKey', () {
        expect(_scriptPubKey(expectOk(decodeSegwit(address))), script);
      });
    }

    for (final MapEntry(key: address, value: (matcher, reason))
        in _bip350Invalid.entries) {
      test('$address is refused: $reason', () {
        expect(expectErr(decodeSegwit(address)), matcher);
        for (final network in RobosatsNetwork.values) {
          expect(_err(address, network), matcher);
        }
      });
    }

    for (final MapEntry(key: address, value: matcher)
        in _bip173Invalid.entries) {
      test('BIP-173 $address is refused', () {
        for (final network in RobosatsNetwork.values) {
          expect(_err(address, network), matcher);
        }
      });
    }

    test(
      'the versions 1 and later of BIP-173, with a bech32 checksum, are refused',
      () {
        for (final address in _bip173FutureVersions) {
          for (final network in RobosatsNetwork.values) {
            expect(
              _err(address, network),
              isA<PayoutDestinationBadChecksum>(),
              reason: address,
            );
          }
        }
      },
    );
  });

  group('what a payout accepts', () {
    test('segwit version 0 and taproot, on their own network only', () {
      for (final (address, network, kind) in [
        (
          'BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4',
          _mainnet,
          BitcoinAddressKind.p2wpkh,
        ),
        (
          'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4',
          _mainnet,
          BitcoinAddressKind.p2wpkh,
        ),
        (
          'tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7',
          _testnet,
          BitcoinAddressKind.p2wsh,
        ),
        (
          'tb1qqqqqp399et2xygdj5xreqhjjvcmzhxw4aywxecjdzew6hylgvsesrxh6hy',
          _testnet,
          BitcoinAddressKind.p2wsh,
        ),
        (
          'bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0',
          _mainnet,
          BitcoinAddressKind.p2tr,
        ),
        (
          'tb1pqqqqp399et2xygdj5xreqhjjvcmzhxw4aywxecjdzew6hylgvsesf3hn0c',
          _testnet,
          BitcoinAddressKind.p2tr,
        ),
        (_segwitV0('tb', _hash160), _testnet, BitcoinAddressKind.p2wpkh),
      ]) {
        final checked = _ok(address, network);
        expect(checked.kind, kind, reason: address);
        expect(checked.network, network);
        expect(checked.text, address, reason: 'kept exactly as given');
        final other = network == _mainnet ? _testnet : _mainnet;
        expect(
          _err(address, other),
          isA<PayoutDestinationWrongNetwork>(),
          reason: address,
        );
      }
    });

    test('Base58Check P2PKH and P2SH, on their own network only', () {
      final built = [
        (_base58Check(0x00, _hash160), _mainnet, BitcoinAddressKind.p2pkh),
        (_base58Check(0x05, _hash160), _mainnet, BitcoinAddressKind.p2sh),
        (_base58Check(0x6f, _hash160), _testnet, BitcoinAddressKind.p2pkh),
        (_base58Check(0xc4, _hash160), _testnet, BitcoinAddressKind.p2sh),
        // A hash of zero bytes, written with leading `1`s for the zero version byte.
        (
          _base58Check(0x00, List.filled(20, 0)),
          _mainnet,
          BitcoinAddressKind.p2pkh,
        ),
      ];
      expect(built.map((entry) => entry.$1.substring(0, 1)), [
        '1',
        '3',
        'm',
        '2',
        '1',
      ]);
      for (final (address, network, kind) in [..._base58Vectors, ...built]) {
        final checked = _ok(address, network);
        expect(checked.kind, kind, reason: address);
        expect(checked.text, address);
        final other = network == _mainnet ? _testnet : _mainnet;
        expect(
          _err(address, other),
          isA<PayoutDestinationWrongNetwork>(),
          reason: address,
        );
      }
    });

    test(
      'a valid segwit address of a later version is valid but unsupported',
      () {
        for (final address in [
          'bc1pw508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7kt5nd6y',
          'BC1SW50QGDZ25J',
          'bc1zw508d6qejxtdg4y5r3zarvaryvaxxpcs',
        ]) {
          expect(
            _err(address, _mainnet),
            isA<PayoutDestinationUnsupported>(),
            reason: address,
          );
          expect(
            _err(address, _testnet),
            isA<PayoutDestinationWrongNetwork>(),
            reason: address,
          );
        }
      },
    );

    test('a program with 5 bits of padding is refused', () {
      // A 20-byte program is exactly 32 words; one more zero word leaves 5 bits of padding, which BIP-173 refuses.
      final words = <int>[0];
      var accumulator = 0;
      var bits = 0;
      for (final byte in _hash160) {
        accumulator = accumulator << 8 | byte;
        bits += 8;
        while (bits >= 5) {
          bits -= 5;
          words.add(accumulator >> bits & 31);
        }
      }
      expect(words, hasLength(33));
      final valid = encodeBech32('bc', words);
      expect(_ok(valid, _mainnet).kind, BitcoinAddressKind.p2wpkh);
      final padded = encodeBech32('bc', [...words, 0]);
      expect(
        expectErr(decodeSegwit(padded)),
        isA<PayoutDestinationMalformed>(),
      );
      for (final network in RobosatsNetwork.values) {
        expect(_err(padded, network), isA<PayoutDestinationMalformed>());
      }
    });

    test('a regtest address is another network, whatever the trade', () {
      final regtest = _segwitV0('bcrt', _hash160);
      expect(expectOk(decodeSegwit(regtest)).humanReadablePart, 'bcrt');
      for (final network in RobosatsNetwork.values) {
        expect(_err(regtest, network), isA<PayoutDestinationWrongNetwork>());
      }
    });

    test('a Base58Check payload of another coin or kind is malformed', () {
      for (final address in [
        // Litecoin and Zcash script hashes (`blockchain_utils` vectors).
        'MN9Lj8PUwww1VXCa1H5kDzwHgS3cCe37BX',
        'QNQPGRSHMXGoQ5kQGRoJB89mpfpabBbjzV',
        't3UTk6K3icSd7Bwaxe6zt6ioCrYbYB8TJZj',
        // A version byte Bitcoin does not use for addresses, with a valid checksum.
        _base58Check(0x30, _hash160),
        _base58Check(0x80, _hash160),
        // A 19- and a 21-byte hash.
        _base58Check(0x00, _hash160.sublist(1)),
        _base58Check(0x00, [..._hash160, 0]),
      ]) {
        for (final network in RobosatsNetwork.values) {
          expect(
            _err(address, network),
            isA<PayoutDestinationMalformed>(),
            reason: address,
          );
        }
      }
    });

    test('what is not an address is malformed', () {
      final privateKey = List<int>.generate(32, (i) => i + 1);
      for (final text in [
        '',
        ' ',
        // A private key in wallet import format, uncompressed and compressed, mainnet and testnet.
        _base58Check(0x80, privateKey),
        _base58Check(0x80, [...privateKey, 1]),
        _base58Check(0xef, [...privateKey, 1]),
        // An address with what a paste may bring around it.
        ' bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4',
        'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4\n',
        'bitcoin:bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4',
        'bitcoin:1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa',
        '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa ',
        // An invoice, and text far over the bound.
        'lnbc1pvjluezpp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypq',
        'bc1q${'q' * 200}',
        '1' * 10000,
        // Characters outside ASCII that look like the real ones.
        'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3tд',
        '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfΝa',
      ]) {
        for (final network in RobosatsNetwork.values) {
          expect(
            _err(text, network),
            isA<PayoutDestinationMalformed>(),
            reason: text.length > 60 ? '${text.length} characters' : text,
          );
        }
      }
    });

    test('says only its kind and network', () {
      final address = _ok(
        'bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0',
        _mainnet,
      );
      expect('$address', 'BitcoinAddress(p2tr, mainnet)');
    });
  });

  group('properties', () {
    final valid = <(String, RobosatsNetwork)>[
      ('bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4', _mainnet),
      ('BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4', _mainnet),
      (
        'tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7',
        _testnet,
      ),
      (
        'bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0',
        _mainnet,
      ),
      (
        'tb1pqqqqp399et2xygdj5xreqhjjvcmzhxw4aywxecjdzew6hylgvsesf3hn0c',
        _testnet,
      ),
      for (final (address, network, _) in _base58Vectors) (address, network),
      (_base58Check(0x6f, _hash160), _testnet),
    ];
    const alphabet =
        '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

    test('any change of one character is refused, on both networks', () {
      var tried = 0;
      for (final (address, _) in valid) {
        for (var i = 0; i < address.length; i++) {
          for (final replacement in alphabet.split('')) {
            if (replacement == address[i]) continue;
            final changed =
                address.substring(0, i) +
                replacement +
                address.substring(i + 1);
            for (final network in RobosatsNetwork.values) {
              tried++;
              expect(
                BitcoinAddress.check(changed, network),
                isA<Err<BitcoinAddress, PayoutDestinationFailure>>(),
                reason: '$address at $i: $replacement',
              );
            }
          }
        }
      }
      expect(tried, greaterThan(40000));
    });

    test(
      'a swap of two neighbours, a character dropped or added is refused',
      () {
        for (final (address, network) in valid) {
          for (var i = 0; i + 1 < address.length; i++) {
            if (address[i] == address[i + 1]) continue;
            final swapped =
                address.substring(0, i) +
                address[i + 1] +
                address[i] +
                address.substring(i + 2);
            expect(
              BitcoinAddress.check(swapped, network),
              isA<Err<BitcoinAddress, PayoutDestinationFailure>>(),
              reason: '$address swapped at $i',
            );
          }
          for (var i = 0; i < address.length; i++) {
            final dropped = address.substring(0, i) + address.substring(i + 1);
            expect(
              BitcoinAddress.check(dropped, network),
              isA<Err<BitcoinAddress, PayoutDestinationFailure>>(),
              reason: '$address without $i',
            );
          }
          for (final extra in ['q', 'p', '1', 'z']) {
            expect(
              BitcoinAddress.check(address + extra, network),
              isA<Err<BitcoinAddress, PayoutDestinationFailure>>(),
              reason: '$address + $extra',
            );
          }
        }
      },
    );

    test('the network is never confused', () {
      for (final (address, network) in valid) {
        for (final asked in RobosatsNetwork.values) {
          switch (BitcoinAddress.check(address, asked)) {
            case Ok(:final value):
              expect(asked, network, reason: address);
              expect(value.network, asked);
            case Err(:final failure):
              expect(asked, isNot(network), reason: address);
              expect(failure, isA<PayoutDestinationWrongNetwork>());
          }
        }
      }
    });

    test('random text is never an address', () {
      final random = DeterministicRandom('not an address');
      const characters =
          '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyzqpzry9x8gf2tvdw0s3jn54khce6mua7l';
      for (var i = 0; i < 3000; i++) {
        final length = 8 + random.nextInt(256) % 80;
        final prefix = switch (i % 4) {
          0 => 'bc1',
          1 => 'tb1',
          2 => '',
          _ => i.isEven ? '1' : '3',
        };
        final text =
            prefix +
            [
              for (var j = 0; j < length; j++)
                characters[random.nextInt(256) % characters.length],
            ].join();
        for (final network in RobosatsNetwork.values) {
          expect(
            BitcoinAddress.check(text, network),
            isA<Err<BitcoinAddress, PayoutDestinationFailure>>(),
            reason: text,
          );
        }
      }
    });
  });
}
