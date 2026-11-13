import 'package:p2p/src/domain/book_retry.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

void main() {
  group('which failures are asked again', () {
    // Every failure the coordinator client can give for a book, and more: the switch of `asksAgainAfter` is exhaustive, so a new failure of the package does not compile until it is placed.
    const nothingAnswered = <CoordinatorFailure>[
      CoordinatorUnreachable(),
      CoordinatorTimedOut(),
      CoordinatorTransportBusy(),
    ];
    const answered = <CoordinatorFailure>[
      CoordinatorTransportFailed(),
      CoordinatorResponseTooLarge(),
      CoordinatorNotOnNetwork(),
      CoordinatorUnexpectedStatus(500),
      CoordinatorNotJson(),
      CoordinatorResponseMalformed('orders'),
      CoordinatorNetworkMismatch(),
      CoordinatorNodeIdMismatch(),
      RobotUnknown(),
      RobotCredentialsRejected(),
      RobotKeysRefused(RobotKeysRefusal.unspecified),
      RobotNicknameTaken(),
      RobotHashIdMismatch(),
      RobotNicknameMismatch(),
      RobotPgpKeyNotProven(),
    ];

    for (final failure in nothingAnswered) {
      test('${failure.runtimeType}: nothing was answered, asked again', () {
        expect(BookRetry.asksAgainAfter(failure), isTrue);
        expect(
          BookRetry.firstContact.waitAfter(
            failure,
            attempts: 1,
            draw: () => 0.5,
          ),
          const Duration(seconds: 5),
        );
      });
    }

    for (final failure in answered) {
      test(
        '${failure.runtimeType}: the coordinator answered, not asked again',
        () {
          expect(BookRetry.asksAgainAfter(failure), isFalse);
          expect(
            BookRetry.firstContact.waitAfter(
              failure,
              attempts: 1,
              draw: () => 0.5,
            ),
            isNull,
          );
          expect(
            BookRetry.reached.waitAfter(failure, attempts: 1, draw: () => 0.5),
            isNull,
          );
        },
      );
    }
  });

  group('how many attempts, and the waits between them', () {
    const unreachable = CoordinatorUnreachable();

    test('a first contact: three attempts, after 5 then 15 seconds', () {
      const retry = BookRetry.firstContact;
      expect(retry.maxAttempts, 3);
      expect(retry.waits, const [Duration(seconds: 5), Duration(seconds: 15)]);
      expect(
        retry.waitAfter(unreachable, attempts: 1, draw: () => 0.5),
        const Duration(seconds: 5),
      );
      expect(
        retry.waitAfter(unreachable, attempts: 2, draw: () => 0.5),
        const Duration(seconds: 15),
      );
      expect(
        retry.waitAfter(unreachable, attempts: 3, draw: () => 0.5),
        isNull,
      );
      expect(
        retry.waitAfter(unreachable, attempts: 4, draw: () => 0.5),
        isNull,
      );
    });

    test('a coordinator reached before: two attempts, after 5 seconds', () {
      const retry = BookRetry.reached;
      expect(retry.maxAttempts, 2);
      expect(
        retry.waitAfter(unreachable, attempts: 1, draw: () => 0.5),
        const Duration(seconds: 5),
      );
      expect(
        retry.waitAfter(unreachable, attempts: 2, draw: () => 0.5),
        isNull,
      );
    });

    test('draws only when there is a wait to spread', () {
      Never drawn() => throw StateError('drawn');
      expect(
        BookRetry.firstContact.waitAfter(
          const CoordinatorNotJson(),
          attempts: 1,
          draw: drawn,
        ),
        isNull,
      );
      expect(
        BookRetry.firstContact.waitAfter(unreachable, attempts: 3, draw: drawn),
        isNull,
      );
    });

    test('no attempt counted yet gives no wait', () {
      expect(
        BookRetry.firstContact.waitAfter(
          unreachable,
          attempts: 0,
          draw: () => 0.5,
        ),
        isNull,
      );
      expect(
        BookRetry.firstContact.waitAfter(
          unreachable,
          attempts: -1,
          draw: () => 0.5,
        ),
        isNull,
      );
    });
  });

  group('the spread of a wait', () {
    const five = Duration(seconds: 5);
    const fifteen = Duration(seconds: 15);

    test('is 20 % at most, up or down, the middle draw spreading none', () {
      expect(BookRetry.jitter, 0.2);
      expect(BookRetry.spread(five, 0), const Duration(seconds: 4));
      expect(BookRetry.spread(five, 0.25), const Duration(milliseconds: 4500));
      expect(BookRetry.spread(five, 0.5), five);
      expect(BookRetry.spread(five, 0.75), const Duration(milliseconds: 5500));
      expect(
        BookRetry.spread(five, 0.999999),
        const Duration(microseconds: 5999998),
      );
      expect(BookRetry.spread(fifteen, 0), const Duration(seconds: 12));
      expect(
        BookRetry.spread(fifteen, 0.999999),
        const Duration(microseconds: 17999994),
      );
    });

    test('stays within its bounds whatever the draw', () {
      for (var i = 0; i <= 1000; i++) {
        final wait = BookRetry.spread(fifteen, i / 1000);
        expect(wait, greaterThanOrEqualTo(const Duration(seconds: 12)));
        expect(wait, lessThanOrEqualTo(const Duration(seconds: 18)));
      }
    });

    test(
      'a draw out of range counts as its nearest end, and one that is not a number as the middle',
      () {
        expect(BookRetry.spread(five, -1), const Duration(seconds: 4));
        expect(BookRetry.spread(five, 2), const Duration(seconds: 6));
        expect(
          BookRetry.spread(five, double.infinity),
          const Duration(seconds: 6),
        );
        expect(
          BookRetry.spread(five, double.negativeInfinity),
          const Duration(seconds: 4),
        );
        expect(BookRetry.spread(five, double.nan), five);
      },
    );

    test('applies to the waits of both rules', () {
      const unreachable = CoordinatorUnreachable();
      expect(
        BookRetry.firstContact.waitAfter(
          unreachable,
          attempts: 2,
          draw: () => 0,
        ),
        const Duration(seconds: 12),
      );
      expect(
        BookRetry.reached.waitAfter(unreachable, attempts: 1, draw: () => 0),
        const Duration(seconds: 4),
      );
    });
  });
}
