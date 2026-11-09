import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/vectors.dart';

RobosatsFailure _rejection(String hex) => switch (RobotHashId.parse(hex)) {
  Ok() => fail('expected "$hex" to be rejected'),
  Err(:final failure) => failure,
};

void main() {
  group('RobotHashId.parse', () {
    test('gives the nickname of a peer from its hash id', () {
      for (final reference in referenceNicknames.take(20)) {
        final result = RobotHashId.parse(reference['hash_id'] as String);
        expect(result, isA<Ok<RobotHashId, RobosatsFailure>>());
        final hashId = (result as Ok<RobotHashId, RobosatsFailure>).value;
        expect(hashId.hex, reference['hash_id']);
        expect(hashId.nickname, reference['nickname']);
      }
    });

    test('rejects anything but 64 lowercase hexadecimal characters', () {
      const valid =
          'ed7d3b2b2e589ab26720605e7414ab4fbca21cb4b31e5b4e62a6fa51c24a9eab';
      final malformed = [
        '',
        valid.substring(1),
        '${valid}0',
        valid.toUpperCase(),
        valid.replaceRange(10, 11, 'g'),
        valid.replaceRange(0, 2, '0x'),
        ' ${valid.substring(1)}',
        '${valid.substring(1)}\n',
        '-${valid.substring(1)}',
      ];
      for (final input in malformed) {
        expect(_rejection(input), isA<HashIdMalformed>(), reason: input);
      }
    });

    test('reports a hash id for which RoboSats has no nickname', () {
      expect(_rejection('f' * 64), isA<NicknameUnavailable>());
    });

    test('has value equality and prints the public hash id', () {
      const hex =
          'ed7d3b2b2e589ab26720605e7414ab4fbca21cb4b31e5b4e62a6fa51c24a9eab';
      RobotHashId parse() =>
          (RobotHashId.parse(hex) as Ok<RobotHashId, RobosatsFailure>).value;
      expect(parse(), parse());
      expect({parse(), parse()}, hasLength(1));
      expect('${parse()}', contains(hex));
      expect('${parse()}', contains('UptightPub730'));
    });
  });
}
