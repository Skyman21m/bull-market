import 'package:bb_mobile/features/settings/presentation/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatAppVersion', () {
    test('keeps the version alone when no commit is known', () {
      expect(formatAppVersion('6.13.0+228', commit: ''), '6.13.0+228');
    });

    test('appends the commit in parentheses', () {
      expect(
        formatAppVersion('6.13.0+228', commit: 'abc1234'),
        '6.13.0+228 (abc1234)',
      );
    });

    test('ignores a commit made only of spaces', () {
      expect(formatAppVersion('6.13.0+228', commit: '   '), '6.13.0+228');
    });

    test('trims the commit before appending it', () {
      expect(
        formatAppVersion('6.13.0+228', commit: ' abc1234 '),
        '6.13.0+228 (abc1234)',
      );
    });
  });
}
