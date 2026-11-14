import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/src/domain/book_filter.dart';
import 'package:p2p/src/domain/option_search.dart';
import 'package:p2p/src/presentation/book_filter_text.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart';

RobosatsCurrency _currency(String code) =>
    RobosatsCurrency.all.firstWhere((currency) => currency.code == code);

final _eur = _currency('EUR');
final _usd = _currency('USD');
final _chf = _currency('CHF');

/// The ids of [orders] that [filter] keeps, in the order it gives them.
List<int> _kept(BookFilter filter, List<PublicOrder> orders) => [
  for (final order in filter.apply(orders)) order.id,
];

void main() {
  // Orders 1 to 4 on temple, 5 and 6 on lake, 7 on freeport; 8 is a swap.
  late List<PublicOrder> book;

  setUpAll(() async {
    book = [
      ...await parseOrders([
        bookOrder(id: 1, currency: 2, paymentMethod: 'Revolut Instant SEPA'),
        bookOrder(id: 2, currency: 1, paymentMethod: 'Wise', makerSeed: 2),
        bookOrder(id: 3, currency: 7, paymentMethod: 'Cash F2F', makerSeed: 3),
        bookOrder(
          id: 4,
          type: 0,
          currency: 2,
          paymentMethod: 'revolut',
          makerSeed: 4,
        ),
      ]),
      ...await parseOrders([
        bookOrder(id: 5, currency: 1, paymentMethod: 'Zelle', makerSeed: 5),
        bookOrder(id: 6, currency: 2, paymentMethod: 'SEPA', makerSeed: 6),
      ], alias: 'lake'),
      ...await parseOrders([
        bookOrder(
          id: 7,
          currency: 7,
          paymentMethod: 'Paypal Friends & Family',
          makerSeed: 7,
        ),
      ], alias: 'freeport'),
      ...await parseOrders([
        bookOrder(
          id: 8,
          currency: 1000,
          paymentMethod: 'On-Chain BTC',
          makerSeed: 8,
        ),
      ]),
    ];
  });

  test('the fixture has the currencies it says', () {
    expect(
      [for (final order in book) order.currency.code],
      ['EUR', 'USD', 'CHF', 'EUR', 'USD', 'EUR', 'CHF', 'BTC'],
    );
  });

  group('currencies', () {
    test('none chosen keeps every currency but the swaps', () {
      expect(_kept(BookFilter(), book), [1, 2, 3, 4, 5, 6, 7]);
    });

    test('one keeps its orders only', () {
      expect(_kept(BookFilter(currencies: [_eur]), book), [1, 4, 6]);
    });

    test('several keep the orders of any of them', () {
      expect(_kept(BookFilter(currencies: [_usd, _chf]), book), [2, 3, 5, 7]);
      expect(_kept(BookFilter(currencies: [_eur, _usd, _chf]), book), [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
      ]);
    });
  });

  group('hosts', () {
    test('none chosen keeps every coordinator', () {
      expect(_kept(BookFilter(hosts: const []), book), [1, 2, 3, 4, 5, 6, 7]);
    });

    test('one keeps its orders only', () {
      expect(_kept(BookFilter(hosts: [coordinator('lake')]), book), [5, 6]);
    });

    test('several keep the orders of any of them', () {
      expect(
        _kept(
          BookFilter(hosts: [coordinator('lake'), coordinator('freeport')]),
          book,
        ),
        [5, 6, 7],
      );
    });

    test('a coordinator without orders keeps nothing', () {
      expect(_kept(BookFilter(hosts: [coordinator('bazaar')]), book), isEmpty);
    });
  });

  // The official client's `filterByPayment` (`utils/filterOrders.ts:19` at commit ff1998c): none chosen keeps every order; otherwise an order is kept when `order.payment_method.includes(method)` for at least one method chosen.
  group('payment methods, by the official client\'s rule', () {
    test('none chosen keeps every order', () {
      expect(_kept(BookFilter(paymentMethods: const []), book), [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
      ]);
    });

    test('one keeps the orders whose text contains it', () {
      expect(_kept(BookFilter(paymentMethods: ['Wise']), book), [2]);
    });

    test('several keep the orders that contain at least one of them', () {
      expect(_kept(BookFilter(paymentMethods: ['Wise', 'Zelle']), book), [
        2,
        5,
      ]);
      expect(
        _kept(BookFilter(paymentMethods: ['Wise', 'Not in the book']), book),
        [2],
      );
    });

    test('an order with two of the methods chosen is kept once', () {
      expect(
        _kept(BookFilter(paymentMethods: ['Revolut', 'Instant SEPA']), book),
        [1],
      );
    });

    test('contains means anywhere in the text: SEPA keeps Instant SEPA', () {
      expect(_kept(BookFilter(paymentMethods: ['SEPA']), book), [1, 6]);
      expect(_kept(BookFilter(paymentMethods: ['Instant SEPA']), book), [1]);
    });

    test('case included: Revolut does not keep an order written revolut', () {
      expect(_kept(BookFilter(paymentMethods: ['Revolut']), book), [1]);
      expect(_kept(BookFilter(paymentMethods: ['revolut']), book), [4]);
    });

    test('a part of a word counts, as with includes', () {
      expect(_kept(BookFilter(paymentMethods: ['Pay']), book), [7]);
    });

    test('the swaps stay out whatever the method', () {
      expect(
        _kept(BookFilter(paymentMethods: ['On-Chain BTC']), book),
        isEmpty,
      );
    });

    test('matchesPaymentMethods is the rule alone', () {
      final swap = book.last;
      expect(
        BookFilter(paymentMethods: ['On-Chain']).matchesPaymentMethods(swap),
        isTrue,
      );
      expect(BookFilter().matchesPaymentMethods(swap), isTrue);
      expect(
        BookFilter(paymentMethods: ['Wise']).matchesPaymentMethods(swap),
        isFalse,
      );
    });
  });

  group('together', () {
    test('each selector narrows what the others keep', () {
      final filter = BookFilter(
        side: BookSide.buy,
        currencies: [_eur, _chf],
        paymentMethods: ['SEPA', 'Cash'],
        hosts: [coordinator('temple'), coordinator('lake')],
      );
      // 1: EUR, SEPA, temple. 3: CHF, Cash, temple. 6: EUR, SEPA, lake. 4 is a buy order, 7 is on freeport.
      expect(_kept(filter, book), [1, 3, 6]);
    });

    test('the depth chart follows the currencies and hosts only', () {
      final filter = BookFilter(
        side: BookSide.sell,
        currencies: [_eur, _usd],
        paymentMethods: ['Nothing'],
        hosts: [coordinator('temple'), coordinator('lake')],
      );
      expect(
        [
          for (final order in book)
            if (filter.showsInDepthChart(order)) order.id,
        ],
        [1, 2, 4, 5, 6],
      );
      expect(
        [
          for (final order in book)
            if (BookFilter().showsInDepthChart(order)) order.id,
        ],
        [1, 2, 3, 4, 5, 6, 7, 8],
      );
    });
  });

  // #118: how many orders each method would keep alone, by the filter's own rule, and the order of the sheet.
  group('the counts of the payment method sheet', () {
    test('a method counts the orders the filter would keep with it alone', () {
      final counts = BookFilter().paymentMethodCounts(book, [
        'Revolut',
        'Instant SEPA',
        'SEPA',
        'Wise',
        'Cash F2F',
        'On-Chain BTC',
        'Advcash',
      ]);
      expect(counts, {
        // Case included: order 4 is written « revolut ».
        'Revolut': 1,
        'Instant SEPA': 1,
        // A name inside another's: « SEPA » counts the order of « Instant SEPA » too, as the filter keeps it.
        'SEPA': 2,
        'Wise': 1,
        'Cash F2F': 1,
        // The swaps are never in the list, so never counted.
        'On-Chain BTC': 0,
        'Advcash': 0,
      });
    });

    test('the count follows the side, the currencies and the hosts', () {
      expect(
        BookFilter(
          side: BookSide.sell,
        ).paymentMethodCounts(book, ['Revolut', 'revolut']),
        {'Revolut': 0, 'revolut': 1},
      );
      expect(
        BookFilter(side: BookSide.buy).paymentMethodCounts(book, ['revolut']),
        {'revolut': 0},
      );
      expect(
        BookFilter(
          currencies: [_eur],
        ).paymentMethodCounts(book, ['SEPA', 'Wise']),
        {'SEPA': 2, 'Wise': 0},
      );
      expect(
        BookFilter(
          currencies: [_eur, _usd],
          hosts: [coordinator('lake')],
        ).paymentMethodCounts(book, ['SEPA', 'Zelle', 'Revolut']),
        {'SEPA': 1, 'Zelle': 1, 'Revolut': 0},
      );
    });

    test('the methods chosen do not change the count of another', () {
      expect(
        BookFilter(
          paymentMethods: ['Wise'],
        ).paymentMethodCounts(book, ['Zelle']),
        {'Zelle': 1},
      );
    });

    test('every count agrees with what the filter keeps', () {
      for (final filter in [
        BookFilter(),
        BookFilter(side: BookSide.buy, currencies: [_eur, _chf]),
        BookFilter(hosts: [coordinator('temple')]),
      ]) {
        final counts = filter.paymentMethodCounts(book, [
          for (final method in PaymentMethods.fiat) method.name,
        ]);
        for (final MapEntry(key: method, value: count) in counts.entries) {
          expect(
            filter.withPaymentMethods([method]).apply(book).length,
            count,
            reason: '$filter $method',
          );
        }
      }
    });

    test(
      'the sheet: the methods of the book by count, ties in the list order, then the others',
      () async {
        final orders = await parseOrders([
          for (var id = 1; id <= 3; id++)
            bookOrder(id: id, paymentMethod: 'Wise', makerSeed: id),
          for (var id = 4; id <= 5; id++)
            bookOrder(id: id, paymentMethod: 'Zelle', makerSeed: id),
          bookOrder(id: 6, paymentMethod: 'Revolut', makerSeed: 6),
          bookOrder(id: 7, paymentMethod: 'Bizum', makerSeed: 7),
          bookOrder(id: 8, paymentMethod: 'revolut', makerSeed: 8),
        ]);
        final sheet = BookFilter().paymentMethodSheet(orders);
        expect(sheet.chosen, isEmpty);
        // Revolut and Bizum, one order each: in the official list's order.
        expect(sheet.available, ['Wise', 'Zelle', 'Bizum', 'Revolut']);
        expect(sheet.unavailable, [
          for (final method in PaymentMethods.fiat)
            if (!sheet.available.contains(method.name)) method.name,
        ]);
        expect(sheet.countOf('Wise'), 3);
        expect(sheet.countOf('Revolut'), 1);
        expect(sheet.countOf('Advcash'), 0);
        expect(
          {...sheet.chosen, ...sheet.available, ...sheet.unavailable},
          {for (final method in PaymentMethods.fiat) method.name},
        );
        expect(
          sheet.chosen.length +
              sheet.available.length +
              sheet.unavailable.length,
          95,
        );
      },
    );

    test(
      'the sheet: the methods chosen first, in the order chosen, zero included',
      () async {
        final orders = await parseOrders([
          bookOrder(id: 1, paymentMethod: 'Wise'),
          bookOrder(id: 2, paymentMethod: 'Zelle', makerSeed: 2),
          bookOrder(id: 3, paymentMethod: 'Zelle', makerSeed: 3),
        ]);
        final sheet = BookFilter(
          paymentMethods: ['Zelle', 'Advcash'],
        ).paymentMethodSheet(orders);
        expect(sheet.chosen, ['Zelle', 'Advcash']);
        expect(sheet.available, ['Wise']);
        expect(sheet.unavailable, isNot(contains('Advcash')));
        expect(sheet.unavailable, isNot(contains('Zelle')));
        expect(sheet.countOf('Zelle'), 2);
        expect(sheet.countOf('Advcash'), 0);
        expect(sheet.unavailable.length, 95 - 3);
      },
    );

    test('the sheet follows the other choices', () {
      final euros = BookFilter(currencies: [_eur]).paymentMethodSheet(book);
      // Euros: order 1 (Revolut Instant SEPA), 4 (revolut, matching no name with its case), 6 (SEPA, no name of the list).
      expect(euros.available, ['Instant SEPA', 'Revolut']);
      final lake = BookFilter(
        hosts: [coordinator('lake')],
      ).paymentMethodSheet(book);
      expect(lake.available, ['Zelle']);
    });
  });

  group('the search of the sheet, as the official client\'s list filters', () {
    test('the name contains the text anywhere, case and accents ignored', () {
      expect(matchesOptionSearch('Revolut', 'rev'), isTrue);
      expect(matchesOptionSearch('Revolut', 'REV'), isTrue);
      expect(matchesOptionSearch('Revolut', 'Rév'), isTrue);
      expect(matchesOptionSearch('Revolut', 'olu'), isTrue);
      expect(matchesOptionSearch('Instant SEPA', 'sépa'), isTrue);
      expect(
        matchesOptionSearch('Paypal Friends & Family', 'friends &'),
        isTrue,
      );
      expect(matchesOptionSearch('Revolut', ''), isTrue);
      expect(matchesOptionSearch('Revolut', 'wise'), isFalse);
      // The text as typed: MUI does not trim it by default.
      expect(matchesOptionSearch('Revolut', ' rev'), isFalse);
      expect(matchesOptionSearch('Revolut', 'revolut '), isFalse);
    });

    test(
      'every letter of the table folds to its base, in lower and upper case',
      () {
        // The table of `foldForSearch`, written out again: Latin-1, Latin Extended-A, and the Romanian « ș » and « ț ».
        const table = {
          'àáâãäåāăą': 'a',
          'çćĉċč': 'c',
          'ď': 'd',
          'èéêëēĕėęě': 'e',
          'ĝğġģ': 'g',
          'ĥ': 'h',
          'ìíîïĩīĭį': 'i',
          'ĵ': 'j',
          'ķ': 'k',
          'ĺļľ': 'l',
          'ñńņň': 'n',
          'òóôõöōŏő': 'o',
          'ŕŗř': 'r',
          'śŝşšș': 's',
          'ţťț': 't',
          'ùúûüũūŭůűų': 'u',
          'ŵ': 'w',
          'ýÿŷ': 'y',
          'źżž': 'z',
        };
        var letters = 0;
        for (final MapEntry(key: group, value: base) in table.entries) {
          for (final rune in group.runes) {
            final letter = String.fromCharCode(rune);
            expect(foldForSearch(letter), base, reason: letter);
            expect(foldForSearch(letter.toUpperCase()), base, reason: letter);
            letters++;
          }
        }
        expect(letters, 82);
        expect(foldForSearch('ȘȚ'), 'st');
      },
    );

    test('the folding', () {
      expect(foldForSearch('ÀÉÎÕÜ çñ ăşž'), 'aeiou cn asz');
      // No decomposition, as with NFD: kept.
      expect(foldForSearch('ŁØŒß'), 'łøœß');
      expect(foldForSearch('İ'), 'i');
      // Already decomposed: the combining mark dropped.
      expect(foldForSearch('e\u0301'), 'e');
    });
  });

  group('the value of the filter', () {
    test('equal whatever the order the choices were made in', () {
      final a = BookFilter(
        currencies: [_eur, _usd],
        paymentMethods: ['Wise', 'SEPA'],
        hosts: [coordinator('lake'), coordinator('temple')],
      );
      final b = BookFilter(
        currencies: [_usd, _eur],
        paymentMethods: ['SEPA', 'Wise'],
        hosts: [coordinator('temple'), coordinator('lake')],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.currencies.map((c) => c.code), ['EUR', 'USD']);
      expect(b.currencies.map((c) => c.code), ['USD', 'EUR']);
    });

    test('not equal when a member differs', () {
      expect(
        BookFilter(currencies: [_eur]),
        isNot(BookFilter(currencies: [_usd])),
      );
      expect(
        BookFilter(currencies: [_eur]),
        isNot(BookFilter(currencies: [_eur, _usd])),
      );
      expect(BookFilter(paymentMethods: ['Wise']), isNot(BookFilter()));
      expect(BookFilter(hosts: [coordinator('lake')]), isNot(BookFilter()));
      expect(BookFilter(side: BookSide.buy), isNot(BookFilter()));
      expect(BookFilter(), const BookFilter.any());
    });

    test('a list changed afterwards does not change the filter', () {
      final chosen = [_eur];
      final filter = BookFilter(currencies: chosen);
      chosen.add(_usd);
      expect(filter.currencies, {_eur});
      expect(() => filter.currencies.add(_usd), throwsUnsupportedError);
      expect(
        () => filter.hosts.add(coordinator('lake')),
        throwsUnsupportedError,
      );
      expect(() => filter.paymentMethods.add('Wise'), throwsUnsupportedError);
    });

    test('a choice made twice counts once', () {
      expect(BookFilter(currencies: [_eur, _eur]).currencies, hasLength(1));
    });

    test('each with keeps the other choices', () {
      final filter = BookFilter(
        side: BookSide.sell,
        currencies: [_eur],
        paymentMethods: ['Wise'],
        hosts: [coordinator('lake')],
      );
      expect(
        filter.withSide(BookSide.buy),
        BookFilter(
          side: BookSide.buy,
          currencies: [_eur],
          paymentMethods: ['Wise'],
          hosts: [coordinator('lake')],
        ),
      );
      expect(filter.withCurrencies(const []).currencies, isEmpty);
      expect(filter.withCurrencies(const []).hosts, {coordinator('lake')});
      expect(filter.withPaymentMethods(['SEPA']).paymentMethods, {'SEPA'});
      expect(filter.withPaymentMethods(['SEPA']).side, BookSide.sell);
      expect(filter.withHosts(const []).hosts, isEmpty);
      expect(filter.withHosts(const []).paymentMethods, {'Wise'});
    });

    test('its text names no payment method', () {
      expect(
        BookFilter(
          side: BookSide.buy,
          currencies: [_eur],
          paymentMethods: ['Wise'],
          hosts: [coordinator('lake')],
        ).toString(),
        'BookFilter(buy, [EUR], [lake])',
      );
    });
  });

  group('the texts of the sentence', () {
    final en = BookFilterText(lookupP2pLocalizations(const Locale('en')));
    final fr = BookFilterText(lookupP2pLocalizations(const Locale('fr')));
    // Another locale has no texts of its own yet and falls back to English.
    final de = BookFilterText(lookupP2pLocalizations(const Locale('de')));
    final temple = coordinator('temple');
    final lake = coordinator('lake');
    final templeName = BookFilterText.hostName(temple);
    final lakeName = BookFilterText.hostName(lake);

    /// The sentence as it reads, each choice in brackets.
    String sentence(BookFilterText t, BookFilter filter) => [
      t.start(filter.side),
      '[${t.side(filter.side)}]',
      t.l10n.p2pBookFilterAndUse,
      '[${t.currencies(filter)}]',
      t.l10n.p2pBookFilterPayWith,
      '[${t.paymentMethods(filter)}]',
      t.l10n.p2pBookFilterHostedBy,
      '[${t.hosts(filter)}]',
    ].join(' ');

    final nothing = BookFilter();
    final one = BookFilter(
      side: BookSide.buy,
      currencies: [_eur],
      paymentMethods: ['Revolut'],
      hosts: [temple],
    );
    final several = BookFilter(
      side: BookSide.sell,
      currencies: [_eur, _usd, _chf],
      paymentMethods: ['Revolut', 'Wise'],
      hosts: [temple, lake],
    );

    test('nothing chosen: each selector names its subject', () {
      expect(
        sentence(en, nothing),
        'I want [Any type] and use [Any currency] pay with [Any payment method] hosted by [Any host]',
      );
      expect(
        sentence(fr, nothing),
        'Je veux [Tout type] et utiliser [Toute devise] payer avec [Tout mode de paiement] hébergé par [Tout hôte]',
      );
      expect(sentence(de, nothing), sentence(en, nothing));
    });

    test('one choice each: the choice', () {
      expect(
        sentence(en, one),
        'I want to [Buy] and use [EUR] pay with [Revolut] hosted by [$templeName]',
      );
      expect(
        sentence(fr, one),
        'Je veux [Acheter] et utiliser [EUR] payer avec [Revolut] hébergé par [$templeName]',
      );
    });

    test('several choices: the first chosen and how many more', () {
      expect(
        sentence(en, several),
        'I want to [Sell] and use [EUR +2] pay with [Revolut +1] hosted by [$templeName +1]',
      );
      expect(
        sentence(fr, several),
        'Je veux [Vendre] et utiliser [EUR +2] payer avec [Revolut +1] hébergé par [$templeName +1]',
      );
    });

    test('the first named is the first chosen', () {
      expect(en.currencies(BookFilter(currencies: [_usd, _eur])), 'USD +1');
      expect(en.hosts(BookFilter(hosts: [lake, temple])), '$lakeName +1');
    });

    test('a type chosen, the rest any', () {
      expect(
        sentence(en, BookFilter(side: BookSide.sell)),
        'I want to [Sell] and use [Any currency] pay with [Any payment method] hosted by [Any host]',
      );
      expect(
        sentence(fr, BookFilter(side: BookSide.buy)),
        'Je veux [Acheter] et utiliser [Toute devise] payer avec [Tout mode de paiement] hébergé par [Tout hôte]',
      );
    });

    test('a screen reader hears the subject and every choice', () {
      expect(en.sideSemantics(BookSide.any), 'Any type');
      expect(en.sideSemantics(BookSide.buy), 'Order type: Buy');
      expect(fr.sideSemantics(BookSide.sell), "Type d'ordre : Vendre");
      expect(en.currenciesSemantics(nothing), 'Any currency');
      expect(en.currenciesSemantics(one), 'Currency: EUR');
      expect(en.currenciesSemantics(several), 'Currency: EUR, USD or CHF');
      expect(fr.currenciesSemantics(several), 'Devise : EUR, USD ou CHF');
      expect(en.paymentMethodsSemantics(nothing), 'Any payment method');
      expect(
        en.paymentMethodsSemantics(several),
        'Payment method: Revolut or Wise',
      );
      expect(
        fr.paymentMethodsSemantics(several),
        'Mode de paiement : Revolut ou Wise',
      );
      expect(en.hostsSemantics(nothing), 'Any host');
      expect(en.hostsSemantics(several), 'Host: $templeName or $lakeName');
      expect(fr.hostsSemantics(one), 'Hôte : $templeName');
    });

    test('the empty book names the currencies', () {
      expect(
        en.emptyBook(nothing),
        'No orders found to buy BTC for any currency',
      );
      expect(
        fr.emptyBook(nothing),
        "Aucun ordre trouvé pour acheter des BTC contre n'importe quelle devise",
      );
      expect(en.emptyBook(one), 'No orders found to buy BTC for EUR');
      expect(
        en.emptyBook(several),
        'No orders found to sell BTC for EUR, USD or CHF',
      );
      expect(
        fr.emptyBook(several),
        'Aucun ordre trouvé pour vendre des BTC contre EUR, USD ou CHF',
      );
      expect(
        en.emptyBook(BookFilter(currencies: [_usd, _eur])),
        'No orders found to buy BTC for USD or EUR',
      );
    });

    test('a list of choices', () {
      expect(en.orList(const []), '');
      expect(en.orList(const ['A']), 'A');
      expect(en.orList(const ['A', 'B']), 'A or B');
      expect(en.orList(const ['A', 'B', 'C', 'D']), 'A, B, C or D');
      expect(fr.orList(const ['A', 'B', 'C']), 'A, B ou C');
    });
  });
}
