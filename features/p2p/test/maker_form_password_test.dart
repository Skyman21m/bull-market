import 'package:p2p/src/domain/trade/maker_form.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/make_form.dart';

/// « Password » and « Face to Face Location » of the create form (#189), as the reference sends them (`buildOrderAttributes`, `MakerForm.tsx:257-275`, commit ff1998c): the password only as its SHA-256 and whatever the options say, none for an empty field; the meeting point as saved; the line of the options sent; and what the form says of a coordinator older than 0.8.7.
void main() {
  late CurrencyLimits limits;
  setUpAll(() async {
    limits = await limitsOf({2: (50000, 100, 1000)});
  });

  MakerFormCheck checkOf({
    String password = '',
    OrderLocation? location,
    bool advanced = true,
    List<String> methods = const ['Revolut'],
  }) => MakerFormCheck.of(
    MakerFormInput(
      type: OrderType.buy,
      currency: eur,
      amount: '200',
      paymentMethods: methods,
      premium: '',
      advanced: advanced,
      rangeEnabled: false,
      password: password,
      location: location,
    ),
    coordinatorsLoaded: true,
    market: MakerFormLimitsRead(limits),
    sizeLimitSats: 21 * 100000000,
  );

  group('« Password »', () {
    test('its SHA-256 sent, never the text; none for an empty field', () {
      final none = checkOf().request ?? fail('request');
      expect(none.hasPassword, isFalse);
      expect(none.passwordHash, isNull);
      final protected = checkOf(password: 'abc').request ?? fail('request');
      expect(protected.hasPassword, isTrue);
      expect(
        protected.passwordHash?.hex,
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(protected.isSendable, isTrue);
      expect(checkOf(password: 'abc').hasPassword, isTrue);
      expect(checkOf().hasPassword, isFalse);
      // A password changes nothing else of the order, and blocks nothing.
      expect(protected, isNot(none));
      expect(checkOf(password: 'abc').block, isNull);
    });

    test(
      'as typed: neither trimmed nor bounded, as the reference takes it',
      () {
        for (final typed in [' ', ' abc ', 'é🔑', 'x' * 3000]) {
          final request = checkOf(password: typed).request ?? fail(typed);
          expect(request.passwordHash, OrderPasswordHash.of(typed));
        }
        expect(
          checkOf(password: ' abc ').request?.passwordHash,
          isNot(OrderPasswordHash.of('abc')),
        );
      },
    );

    test(
      'kept and sent while the options are closed, as the reference sends it, and named in the line of the options sent',
      () {
        final closed = checkOf(password: 'abc', advanced: false);
        expect(closed.request?.hasPassword, isTrue);
        expect(closed.optionsSent.password, isTrue);
        expect(closed.optionsSent.any, isTrue);
        expect(checkOf().optionsSent.password, isFalse);
        expect(checkOf(advanced: false).optionsSent.any, isFalse);
      },
    );
  });

  group('« Face to Face Location »', () {
    test('the point saved is the point sent', () {
      final point =
          OrderLocation.tryCreate(48.8816, 2.3272) ?? fail('location');
      final check = checkOf(location: point, methods: const ['Cash F2F']);
      expect(check.location, point);
      expect(check.request?.location, point);
      expect(checkOf().request?.location, isNull);
      expect(check.block, isNull);
    });
  });

  group('a coordinator older than 0.8.7 (`GHSA-r6f6-x59j-8q69`)', () {
    test(
      'said by its version, unknown when its info could not be read',
      () async {
        Future<PasswordExposure?> at(int major, int minor, int patch) async =>
            PasswordExposure.of(
              await infoAt(
                'temple',
                version: (major: major, minor: minor, patch: patch),
              ),
            );
        expect(
          await at(0, 8, 6),
          PasswordExposedByVersion(const CoordinatorVersion(0, 8, 6)),
        );
        expect(await at(0, 7, 9), isA<PasswordExposedByVersion>());
        expect(await at(0, 8, 7), isNull);
        expect(await at(0, 8, 8), isNull);
        expect(await at(0, 9, 0), isNull);
        expect(await at(1, 0, 0), isNull);
        expect(PasswordExposure.of(null), isA<PasswordExposureUnknown>());
      },
    );
  });
}
