import 'dart:typed_data';

import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/garage_opening.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

/// The Garage opens on the robot of the key's recovery note when the device knows nothing better (#81, design note `docs/design/garage-key-from-the-words.md` § 3, « Opens on the note's robot, else robot 0 »).
void main() {
  NetworkGarageKey keyOf(int byte) => NetworkGarageKey(
    RobosatsNetwork.testnet,
    switch (GarageKey.fromBytes(Uint8List.fromList(List.filled(32, byte)))) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    },
  );
  GarageKeyFingerprint fingerprintOf(NetworkGarageKey key) =>
      switch (key.fingerprint) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };

  final key = keyOf(1);
  final other = keyOf(2);

  test('no record of the key: the robot the note names', () {
    final noted = RobotSlot(RobosatsNetwork.testnet, fingerprintOf(key), 6);
    expect(
      GarageOpening.of(
        key,
        GarageRecords(inProgress: const [], closed: const [], fresh: null, noted: noted),
      ),
      noted,
    );
  });

  test('no note: robot 0, as before', () {
    expect(
      GarageOpening.of(
        key,
        GarageRecords(inProgress: const [], closed: const [], fresh: null),
      ),
      isNull,
    );
  });

  test('the note of another key is never the robot of this one', () {
    expect(
      GarageOpening.of(
        key,
        GarageRecords(
          inProgress: const [],
          closed: const [],
          fresh: null,
          noted: RobotSlot(RobosatsNetwork.testnet, fingerprintOf(other), 6),
        ),
      ),
      isNull,
    );
  });
}
