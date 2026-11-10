import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:robosats/src/pgp/armor.dart';
import 'package:robosats/src/pgp/bytes.dart';
import 'package:test/test.dart';

import 'deterministic_random.dart';
import 'vectors.dart';

export 'deterministic_random.dart';

T expectOk<T, F extends Failure>(Result<T, F> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final failure) => fail('expected a value, got $failure'),
};

F expectErr<T, F extends Failure>(Result<T, F> result) => switch (result) {
  Ok() => fail('expected a failure, got a value'),
  Err(:final failure) => failure,
};

RobotIdentity identityOf(String token) =>
    expectOk(RobotIdentity.fromToken(expectOk(RobotToken.parse(token))));

/// A file of `tests/robots/<number>/` in the RoboSats repository (commit ff1998c), copied verbatim.
///
/// The keys were made by the official client with OpenPGP.js, `pub_key` was then re-exported by GnuPG, and the passphrase of each private key is the public test token of the vectors file.
String repositoryRobotFile(int number, String name) =>
    File('test/fixtures/robosats_tests_robot_$number/$name').readAsStringSync();

/// The identity of test robot [number], from 1 to 3.
RobotIdentity repositoryRobotIdentity(int number) =>
    identityOf(repositoryRobots[number - 1]['token'] as String);

/// The key pair of test robot [number], from 1 to 3.
RobotPgpKey repositoryRobotKey(int number) => expectOk(
  RobotPgpKey.parse(
    publicKey: repositoryRobotFile(number, 'pub_key'),
    encryptedPrivateKey: repositoryRobotFile(number, 'enc_priv_key'),
  ),
);

/// A fixed "now" for every generated artefact: a key is then dated 2026-11-08 12:00:00 UTC.
final interopNow = DateTime.utc(2026, 11, 9, 12);

/// The robot whose key was shown to GnuPG: index 0 of the example Garage Key, for which the RoboSats repository has no key.
RobotIdentity get interopIdentity =>
    identityOf(garageKeyRobots.first['token'] as String);

/// The key `tool/pgp_interop.sh` showed to GnuPG, generated again: same identity, same clock, same bytes of randomness.
RobotPgpKey generateInteropKey() => expectOk(
  RobotPgpKey.generateWith(
    interopIdentity,
    now: interopNow,
    random: DeterministicRandom('troc'),
  ),
);

/// A second robot, the peer of the deterministic chat message: index 1 of the example Garage Key.
RobotIdentity get interopPeerIdentity =>
    identityOf(garageKeyRobots[1]['token'] as String);

RobotPgpKey generateInteropPeerKey() => expectOk(
  RobotPgpKey.generateWith(
    interopPeerIdentity,
    now: interopNow,
    random: DeterministicRandom('troc-peer'),
  ),
);

/// The robot whose token locks the key OpenPGP.js generates during the run: test robot 2 of the RoboSats repository.
RobotIdentity get interopOpenPgpJsIdentity => repositoryRobotIdentity(2);

/// The invoice and the chat text of the interoperability run.
const interopInvoice = 'lnbcrt500u1p5xyzzypp5examplexexamplexexample';
const interopChatText = 'Hola, envío 50 € por Bizum ⚡\nGracias';

/// The chat message of the run that is a pure function of its inputs: from the robot to itself and to [generateInteropPeerKey].
String encryptInteropChatMessage(UnlockedRobotPgpKey unlocked) => expectOk(
  unlocked.encryptChatMessageWith(
    interopChatText,
    peer: generateInteropPeerKey().publicKey,
    now: interopNow,
    random: DeterministicRandom('troc-chat'),
  ),
);

/// A clock for reading the artefacts of the run: later than every date in them.
final interopReplayTime = DateTime.utc(2027);

/// A file of `test/fixtures/pgp_interop/`, an artefact of the last run of `tool/pgp_interop.sh` against GnuPG and OpenPGP.js: `transcript.txt`, next to it, is what they printed.
String interopFile(String name) =>
    File('test/fixtures/pgp_interop/$name').readAsStringSync();

/// The packets inside an armored block.
List<RawPacket> packetsOf(ArmorBlock block, String armored) {
  final bytes = armorDecode(block, armored);
  if (bytes == null) fail('not an armored ${block.label}');
  return decodePackets(bytes, maxPackets: 64);
}

/// The shape of a key block, with every value that legitimately differs between two keys left out: key material, times, salts, fingerprints, signatures.
///
/// Two keys with the same shape are indistinguishable to a coordinator by anything but those values.
List<String> keyShape(ArmorBlock block, String armored) => [
  for (final packet in packetsOf(block, armored))
    switch (packet.tag) {
      PacketTag.publicKey ||
      PacketTag.publicSubkey ||
      PacketTag.secretKey ||
      PacketTag.secretSubkey => _keyPacketShape(packet),
      PacketTag.userId =>
        'user id: ${utf8.decode(packet.body).replaceAll(RegExp('[0-9a-f]{64}'), '<hash id>')}',
      PacketTag.signature => _signatureShape(packet.body),
      _ => 'packet ${packet.tag}',
    },
];

String _keyPacketShape(RawPacket packet) {
  final reader = ByteReader(packet.body);
  final version = reader.u8();
  reader.u32();
  final algorithm = reader.u8();
  final oid = reader.take(reader.u8());
  final pointLength = reader.mpi().length;
  final kdf = algorithm == 18 ? reader.take(reader.u8()) : Uint8List(0);
  final public =
      'tag ${packet.tag}: v$version algorithm $algorithm curve ${_hex(oid)} '
      'point of $pointLength bytes kdf ${_hex(kdf)}';
  if (reader.isDone) return public;
  final usage = reader.u8();
  final cipher = reader.u8();
  final s2kType = reader.u8();
  final s2kHash = reader.u8();
  final saltLength = reader.take(8).length;
  final count = reader.u8();
  final ivLength = reader.take(16).length;
  return '$public; secret: usage $usage cipher $cipher s2k $s2kType hash $s2kHash '
      'salt of $saltLength bytes count $count iv of $ivLength bytes';
}

String _signatureShape(Uint8List body) {
  final reader = ByteReader(body);
  final head = [reader.u8(), reader.u8(), reader.u8(), reader.u8()];
  final hashed = _subpacketShapes(reader.take(reader.u16()));
  final unhashed = _subpacketShapes(reader.take(reader.u16()));
  return 'signature: v${head[0]} type 0x${head[1].toRadixString(16)} '
      'algorithm ${head[2]} hash ${head[3]} hashed $hashed unhashed $unhashed';
}

/// Subpackets whose content is specific to one key or one moment.
const _variableSubpackets = {2, 16, 33};

List<String> _subpacketShapes(Uint8List area) {
  final reader = ByteReader(area);
  final shapes = <String>[];
  while (!reader.isDone) {
    final length = reader.u8();
    final typeByte = reader.u8();
    final data = reader.take(length - 1);
    final type = typeByte & 0x7f;
    shapes.add(
      '${typeByte & 0x80 != 0 ? 'critical ' : ''}$type:'
      '${_variableSubpackets.contains(type) ? '<${data.length} bytes>' : _hex(data)}',
    );
  }
  return shapes;
}

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
