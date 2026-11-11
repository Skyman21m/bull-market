import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/order_search.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart';

void main() {
  late List<PublicOrder> book;

  setUpAll(() async {
    book = await parseOrders([
      bookOrder(id: 48213, makerSeed: 1),
      bookOrder(id: 7, makerSeed: 2),
    ]);
  });

  OrderSearchOutcome search(String text) => OrderSearch.run(text, book);

  const onion =
      'http://ngdk7ocdzmz5kzsysa3om6du7ycj2evxp2f2olfkyq37htx3gllwp2yd.onion';

  test('an order of the book is found by the URL RoboSats shares', () {
    for (final url in [
      '$onion/order/temple/48213',
      '$onion/order/temple/48213/',
      'https://robosats.example/order/temple/48213',
      // The host is not read, as in the official client.
      'http://127.0.0.1:12596/order/temple/48213',
      // The pattern lets spaces through after the number, which the official client then ignores.
      '$onion/order/temple/48213 ',
      '$onion/order/temple/48213\n',
    ]) {
      expect(
        search(url),
        isA<OrderSearchFound>().having((found) => found.order.id, 'id', 48213),
        reason: url,
      );
    }
    expect(
      search('$onion/order/temple/7'),
      isA<OrderSearchFound>().having((found) => found.order.id, 'id', 7),
    );
  });

  test('a text that is not an order URL is refused', () {
    for (final text in [
      '',
      '48213',
      'temple/48213',
      'order/temple/48213',
      'ftp://host/order/temple/48213',
      'http:/host/order/temple/48213',
      'http://host/order/temple',
      'http://host/order/temple/',
      'http://host/order//48213',
      'http://host/orders/temple/48213',
      'http://host/order/temple/48213/x',
      'http://ho st/order/temple/48213',
      // As in the official client, the text is not trimmed before the pattern.
      ' $onion/order/temple/48213',
    ]) {
      expect(search(text), isA<OrderSearchInvalidUrl>(), reason: text);
    }
  });

  test('an order URL that the public book does not hold needs a robot', () {
    for (final url in [
      // Another order, maybe protected by a password.
      '$onion/order/temple/1',
      // The same number on another coordinator.
      '$onion/order/lake/48213',
      // A coordinator Troc does not know.
      '$onion/order/nowhere/48213',
      // Not a number: the official client asks the coordinator anyway.
      '$onion/order/temple/abc',
      // Numbers that `Number` of the official client reads (16, 1000, 48213) and Troc, which reads decimal integers only, does not: such a URL needs a robot instead of opening the order.
      '$onion/order/temple/0x10',
      '$onion/order/temple/1e3',
      '$onion/order/temple/48213.0',
      // Blanks only: `Number` reads 0, an order that does not exist.
      '$onion/order/temple/   ',
      // The alias is matched as written.
      '$onion/order/Temple/48213',
    ]) {
      expect(search(url), isA<OrderSearchNeedsRobot>(), reason: url);
    }
  });

  test('an empty book finds nothing', () {
    expect(
      OrderSearch.run('$onion/order/temple/48213', const []),
      isA<OrderSearchNeedsRobot>(),
    );
  });
}
