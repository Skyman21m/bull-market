import 'dart:convert';
import 'dart:io';

import 'package:bull_ui/bull_ui.dart' show BullCopyField;
import 'package:bull_ui/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/presentation/coordinator_details_cubit.dart';
import 'package:p2p/src/presentation/coordinator_text.dart';
import 'package:p2p/src/ui/coordinator_details_dialog.dart';
import 'package:p2p/src/ui/widgets/coordinator_link_sheet.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

/// A recorded `/api/info/` of the federation, `<alias>-<network>-info.json`.
Map<String, Object?> recordedInfo(String alias, RobosatsNetwork network) =>
    jsonDecode(
          File(
            '../../packages/robosats/test/fixtures/coordinator/$alias-${network.name}-info.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

/// [base] with the texts, contacts, badges and policies a test chooses.
Coordinator rewrite(
  Coordinator base, {
  String? longAlias,
  String? description,
  String? motto,
  CoordinatorContact? contact,
  CoordinatorBadges? badges,
  Map<String, String>? policies,
  CoordinatorOrigins? mainnet,
}) => Coordinator(
  shortAlias: base.shortAlias,
  longAlias: longAlias ?? base.longAlias,
  identifier: base.identifier,
  description: description ?? base.description,
  motto: motto ?? base.motto,
  color: base.color,
  established: base.established,
  nostrHexPubkey: base.nostrHexPubkey,
  contact: contact ?? base.contact,
  badges: badges ?? base.badges,
  policies: policies ?? base.policies,
  mainnet: mainnet ?? base.mainnet,
  testnet: base.testnet,
  mainnetNodesPubkeys: base.mainnetNodesPubkeys,
  testnetNodesPubkeys: base.testnetNodesPubkeys,
  federated: base.federated,
);

void main() {
  late List<String> copied;

  setUp(() => copied = []);

  /// Shows a button that opens the dialog of [of] on [network], over [transport].
  Future<void> open(
    WidgetTester tester,
    FakeTransport transport, {
    Coordinator? of,
    RobosatsNetwork network = RobosatsNetwork.mainnet,
    Locale locale = const Locale('en'),
    CoordinatorInfo? known,
  }) async {
    usePhoneScreen(tester);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add('${(call.arguments as Map<Object?, Object?>)['text']}');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => CoordinatorDetailsDialog.show(
              context,
              () => CoordinatorDetailsCubit(
                CoordinatorDetailsRequest(
                  of ?? coordinator('temple'),
                  network,
                  known: known,
                ),
                FetchCoordinatorInfoUsecase(CoordinatorClient(transport)),
                now: testNow,
              ),
            ),
            child: const Text('open'),
          ),
        ),
        locale: locale,
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  /// The scrollable content of the dialog.
  final dialog = find
      .descendant(
        of: find.byType(CoordinatorDetailsDialog),
        matching: find.byType(Scrollable),
      )
      .first;

  Future<void> openSection(WidgetTester tester, String title) async {
    await tester.scrollUntilVisible(find.text(title), 200, scrollable: dialog);
    await tester.tap(find.text(title));
    await settle(tester);
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) =>
      tester.scrollUntilVisible(finder, 200, scrollable: dialog);

  testWidgets('a coordinator, in the order of the official client', (
    tester,
  ) async {
    await open(
      tester,
      FakeTransport(
        infos: {'temple': recordedInfo('temple', RobosatsNetwork.mainnet)},
      ),
    );

    expect(find.text('Temple of Sats'), findsOneWidget);
    expect(
      find.text(
        "Privacy and Integrity: Temple of Sats, where Bitcoin's essence thrives.",
      ),
      findsOneWidget,
    );
    // Temple announces an « Info » notice with no text: the official client shows its box all the same.
    expect(find.text('Coordinator Notice'), findsOneWidget);
    expect(find.byType(CoordinatorBadge), findsNWidgets(4));
    expect(find.text('Coordinator description'), findsOneWidget);
    expect(find.text('12/2/2023'), findsOneWidget);
    expect(find.text('Established'), findsOneWidget);
    expect(
      find.text(
        'http://ngdk7ocdzmz5kzsysa3om6du7ycj2evxp2f2olfkyq37htx3gllwp2yd.onion',
      ),
      findsOneWidget,
    );
    expect(find.text('Coordinator hosted web app'), findsOneWidget);
    // Nostr, PGP, email, Telegram, website, Matrix, Simplex: temple gives no X nor Reddit.
    for (final contact in [
      'Nostr',
      'PGP Pubkey fingerprint',
      'Send Email',
      'Telegram',
      'Website',
      'Matrix',
      'Simplex',
    ]) {
      expect(find.byTooltip(contact), findsOneWidget, reason: contact);
    }
    expect(find.byTooltip('X'), findsNothing);
    expect(find.byTooltip('Reddit'), findsNothing);
    // No rating: Troc does not read the Nostr relays it comes from.
    expect(find.byIcon(Icons.star), findsNothing);

    await scrollTo(tester, find.text('Stats for Nerds'));
    expect(find.text('Policies'), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Evidence in Disputes'), findsNothing);

    await openSection(tester, 'Policies');
    expect(find.text('Evidence in Disputes'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    await openSection(tester, 'Summary');
    // One section at a time, as in the official client.
    expect(find.text('Evidence in Disputes'), findsNothing);
    expect(find.text('6,000,000 Sats'), findsNWidgets(2));
    expect(find.text('Maximum order size'), findsOneWidget);
    expect(find.text('0.025%'), findsOneWidget);
    expect(find.text('Maker fee'), findsOneWidget);
    expect(find.text('0.175%'), findsOneWidget);
    expect(find.text('Taker fee'), findsOneWidget);
    expect(find.text('3.44%'), findsOneWidget);
    expect(find.text('Current onchain payout fee'), findsOneWidget);
    expect(find.text('Maximum onchain swap size'), findsOneWidget);
    await scrollTo(
      tester,
      find.text('Market price sources (for multiple the median is calculated)'),
    );
    expect(find.text('30% of profits'), findsOneWidget);
    expect(find.text('Zaps voluntarily for development'), findsOneWidget);
    expect(find.text('19'), findsOneWidget);
    expect(find.text('Public buy orders'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
    expect(find.text('Public sell orders'), findsOneWidget);
    expect(find.text('56,634,461 Sats'), findsOneWidget);
    expect(find.text('Book liquidity'), findsOneWidget);
    expect(find.text('2,348'), findsOneWidget);
    expect(find.text('Today active robots'), findsOneWidget);
    expect(find.text('0.95%'), findsOneWidget);
    expect(find.text('24h non-KYC bitcoin premium'), findsOneWidget);
    expect(
      find.text(
        'https://blockchain.info/ticker, https://api.yadio.io/exrates/BTC',
      ),
      findsOneWidget,
    );

    await openSection(tester, 'Stats for Nerds');
    expect(find.text('Book liquidity'), findsNothing);
    expect(find.text('Coordinator v0.8.8'), findsOneWidget);
    expect(find.text('RoboSats version'), findsOneWidget);
    expect(find.text('v0.21.5-beta'), findsOneWidget);
    expect(find.text('LND version'), findsOneWidget);
    // « Not installed » is a version for the official client too.
    expect(find.text('Not installed'), findsOneWidget);
    expect(find.text('CLN version'), findsOneWidget);
    await scrollTo(tester, find.text('Lifetime contracted volume'));
    expect(find.text('0226f31c5f3a... (AMBOSS)'), findsOneWidget);
    expect(find.textContaining('TempleOfSats-Reborn'), findsOneWidget);
    expect(find.text('9526aad5...'), findsOneWidget);
    expect(find.text('Coordinator commit hash'), findsOneWidget);
    expect(find.text('0.23644465'), findsOneWidget);
    expect(find.text('24h contracted volume'), findsOneWidget);
    expect(find.text('196.68313773'), findsOneWidget);
  });

  testWidgets('in French', (tester) async {
    await open(
      tester,
      FakeTransport(
        infos: {'temple': recordedInfo('temple', RobosatsNetwork.mainnet)},
      ),
      locale: const Locale('fr'),
    );

    expect(find.text('Avis du coordinateur'), findsOneWidget);
    expect(find.text('Description du coordinateur'), findsOneWidget);
    expect(find.text('02/12/2023'), findsOneWidget);
    expect(find.text('Date de création'), findsOneWidget);
    expect(
      find.text('Application web hébergée par le coordinateur'),
      findsOneWidget,
    );
    expect(find.byTooltip('Envoyer un e-mail'), findsOneWidget);
    expect(find.byTooltip('Empreinte de la clé publique PGP'), findsOneWidget);

    await openSection(tester, 'Résumé');
    expect(find.text("Taille maximale de l'ordre"), findsOneWidget);
    expect(find.text('Frais du créateur'), findsOneWidget);
    expect(find.text('Frais du preneur'), findsOneWidget);
    expect(find.text('3,44\u00a0%'), findsOneWidget);
    expect(find.text('Frais actuels de paiement on-chain'), findsOneWidget);
    expect(find.text("Taille maximale d'un échange on-chain"), findsOneWidget);
    await scrollTo(tester, find.text('Liquidité du carnet'));
    expect(find.text('30 % des bénéfices'), findsOneWidget);
    expect(find.text('Donne volontairement au développement'), findsOneWidget);
    expect(find.text("Ordres d'achat publics"), findsOneWidget);
    expect(find.text('Ordres de vente publics'), findsOneWidget);
    expect(find.text("Robots actifs aujourd'hui"), findsOneWidget);

    await openSection(tester, 'Stats pour les geeks');
    expect(find.text('Coordinateur v0.8.8'), findsOneWidget);
    expect(find.text('Version RoboSats'), findsOneWidget);
    expect(find.text('Version LND'), findsOneWidget);
    await scrollTo(tester, find.text('Volume total des échanges'));
    expect(
      find.text('Empreinte de la révision du coordinateur'),
      findsOneWidget,
    );
    expect(find.text('0,23644465'), findsOneWidget);
    expect(find.text('Volume des échanges sur 24h'), findsOneWidget);
  });

  testWidgets('waits for the coordinator, then shows its sections', (
    tester,
  ) async {
    final transport = FakeTransport(
      infos: {'temple': recordedInfo('temple', RobosatsNetwork.mainnet)},
      held: {'temple'},
    );
    await open(tester, transport);

    // What the federation list says is shown at once.
    expect(find.text('Temple of Sats'), findsOneWidget);
    expect(find.text('Coordinator description'), findsOneWidget);
    await scrollTo(tester, find.byType(CircularProgressIndicator));
    expect(find.text('Summary'), findsNothing);
    expect(find.text('Coordinator Notice'), findsNothing);

    transport.release('temple');
    await settle(tester);
    await scrollTo(tester, find.text('Summary'));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Coordinator offline'), findsNothing);
  });

  testWidgets('a coordinator that cannot be asked is offline, with a retry', (
    tester,
  ) async {
    final transport = FakeTransport(
      infos: {'temple': recordedInfo('temple', RobosatsNetwork.mainnet)},
      failures: {'temple': const CoordinatorTimedOut()},
    );
    await open(tester, transport);

    await scrollTo(tester, find.text('Coordinator offline'));
    expect(find.text('Summary'), findsNothing);
    expect(find.text('Policies'), findsNothing);

    transport.failures.clear();
    await scrollTo(tester, find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await settle(tester);

    await scrollTo(tester, find.text('Summary'));
    expect(find.text('Coordinator offline'), findsNothing);
    expect(transport.requested, ['temple/api/info/', 'temple/api/info/']);
  });

  testWidgets('closing the dialog before the coordinator answers', (
    tester,
  ) async {
    final transport = FakeTransport(
      infos: {'temple': recordedInfo('temple', RobosatsNetwork.mainnet)},
      held: {'temple'},
    );
    await open(tester, transport);

    // A tap outside the dialog closes it, as in the official client.
    await tester.tapAt(const Offset(4, 4));
    await settle(tester);
    expect(find.byType(CoordinatorDetailsDialog), findsNothing);

    transport.release('temple');
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  group('every link and contact is shown in full and copied, never opened', () {
    const templeOnion =
        'http://ngdk7ocdzmz5kzsysa3om6du7ycj2evxp2f2olfkyq37htx3gllwp2yd.onion';
    final temple = coordinator('temple');
    // Temple gives no X nor Reddit: they are added, as another coordinator could.
    final linked = rewrite(
      temple,
      contact: CoordinatorContact(
        email: temple.contact.email,
        telegram: temple.contact.telegram,
        simplex: temple.contact.simplex,
        matrix: temple.contact.matrix,
        website: temple.contact.website,
        nostr: temple.contact.nostr,
        pgp: temple.contact.pgp,
        fingerprint: temple.contact.fingerprint,
        reddit: 'r/templeofsats',
        twitter: 'templeofsats',
      ),
    );

    /// What the user taps, in which section if any, and the sheet it opens: its title and the value copied.
    final links =
        <
          ({
            String name,
            Finder tap,
            String? section,
            String title,
            String value,
          })
        >[
          (
            name: 'Nostr',
            tap: find.byTooltip('Nostr'),
            section: null,
            title: 'Nostr',
            value:
                'npub1wsqpvgpfwq6a4fs5whqxn7gtd9gqsll2p5qnfdu4ltr43s6wwxgsgk4xtl',
          ),
          (
            name: 'PGP',
            tap: find.byTooltip('PGP Pubkey fingerprint'),
            section: null,
            title: 'PGP Pubkey fingerprint',
            value: '2579 1752 E966 1C1D E118 A8C6 F78C D3D6 471B 6789',
          ),
          (
            name: 'email',
            tap: find.byTooltip('Send Email'),
            section: null,
            title: 'Send Email',
            value: 'coordinator@templeofsats.org',
          ),
          (
            name: 'Telegram',
            tap: find.byTooltip('Telegram'),
            section: null,
            title: 'Telegram',
            value: 'https://t.me/templeofsats',
          ),
          (
            name: 'X',
            tap: find.byTooltip('X'),
            section: null,
            title: 'X',
            value: 'https://x.com/templeofsats',
          ),
          (
            name: 'Reddit',
            tap: find.byTooltip('Reddit'),
            section: null,
            title: 'Reddit',
            value: 'https://reddit.com/r/templeofsats',
          ),
          (
            name: 'website',
            tap: find.byTooltip('Website'),
            section: null,
            title: 'Website',
            value: 'https://templeofsats.org',
          ),
          (
            name: 'Matrix',
            tap: find.byTooltip('Matrix'),
            section: null,
            title: 'Matrix',
            value: '@venividivici13:matrix.org',
          ),
          (
            name: 'Simplex',
            tap: find.byTooltip('Simplex'),
            section: null,
            title: 'Simplex',
            value: temple.contact.simplex ?? '',
          ),
          (
            name: 'hosted web app',
            tap: find.text(templeOnion),
            section: null,
            title: 'Coordinator hosted web app',
            value: templeOnion,
          ),
          (
            name: 'Lightning node',
            tap: find.text('0226f31c5f3a... (AMBOSS)'),
            section: 'Stats for Nerds',
            // A title of the app, never the alias the coordinator chose.
            title: 'LN Node',
            value:
                'https://amboss.space/node/0226f31c5f3a8b48bbbb7aaa97a10effcfb445b5972a676955d5c095383d35a428',
          ),
          (
            name: 'commit',
            tap: find.text('9526aad5...'),
            section: 'Stats for Nerds',
            title: 'Coordinator commit hash',
            value: 'https://github.com/Robosats/robosats/tree/9526aad5',
          ),
        ];

    for (final link in links) {
      testWidgets(link.name, (tester) async {
        await open(
          tester,
          FakeTransport(
            infos: {'temple': recordedInfo('temple', RobosatsNetwork.mainnet)},
          ),
          of: linked,
        );
        if (link.section case final section?) {
          await openSection(tester, section);
        }
        await scrollTo(tester, link.tap);
        await tester.tap(link.tap);
        await settle(tester);

        final sheet = find.byType(CoordinatorLinkSheet);
        expect(
          find
              .descendant(of: sheet, matching: find.byType(Text))
              .evaluate()
              .map((element) => (element.widget as Text).data),
          [link.title, link.value],
        );
        await tester.tap(
          find.descendant(of: sheet, matching: find.byIcon(Icons.copy_sharp)),
        );
        await settle(tester);
        expect(copied, [link.value]);
        expect(find.text('Copied!'), findsOneWidget);
        // The toast goes away on its own.
        await tester.pump(const Duration(seconds: 4));
        await settle(tester);
      });
    }
  });

  testWidgets('a commit that is not a commit id is shown without a link', (
    tester,
  ) async {
    for (final commit in ['../../evil/repo', 'ABCDEF1', 'abc123', 'a' * 41]) {
      final info = recordedInfo('temple', RobosatsNetwork.mainnet)
        ..['robosats_running_commit_hash'] = commit;
      await open(tester, FakeTransport(infos: {'temple': info}));
      await openSection(tester, 'Stats for Nerds');
      final shown = find.text(
        '${String.fromCharCodes(commit.runes.take(12))}...',
      );
      await scrollTo(tester, shown);
      await tester.tap(shown);
      await settle(tester);
      expect(find.byType(CoordinatorLinkSheet), findsNothing, reason: commit);
      // The text of a row without a link is not in the colour of a link.
      expect(tester.widget<Text>(shown).style?.color, testBullTheme.text);
      await tester.tapAt(const Offset(4, 4));
      await settle(tester);
    }
  });

  testWidgets('invisible characters are neither shown nor copied', (
    tester,
  ) async {
    String hidden(String text) => text.replaceAll(
      '|',
      String.fromCharCodes([
        0x200B,
        0x2060,
        0xFEFF,
        0x00AD,
        0xFFF9,
        0xE0041,
        0x200D,
      ]),
    );
    final hostile = rewrite(
      coordinator('temple'),
      contact: CoordinatorContact(
        telegram: hidden('temple|ofsats'),
        website: hidden('https://templeofsats|.org'),
      ),
    );
    await open(
      tester,
      FakeTransport(
        infos: {'temple': recordedInfo('temple', RobosatsNetwork.mainnet)},
      ),
      of: hostile,
    );

    for (final (tooltip, value) in [
      ('Telegram', 'https://t.me/templeofsats'),
      ('Website', 'https://templeofsats.org'),
    ]) {
      await tester.tap(find.byTooltip(tooltip));
      await settle(tester);
      expect(
        find.descendant(
          of: find.byType(BullCopyField),
          matching: find.text(value),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byIcon(Icons.copy_sharp));
      await tester.pump(const Duration(seconds: 4));
      await settle(tester);
      await tester.tapAt(const Offset(4, 4));
      await settle(tester);
    }
    expect(copied, ['https://t.me/templeofsats', 'https://templeofsats.org']);
  });

  testWidgets('the hosted web app is shown and copied as it reads', (
    tester,
  ) async {
    final temple = coordinator('temple');
    final onion = temple.mainnet.onion ?? '';
    final known = await tester.runAsync(
      () => CoordinatorClient(
        FakeTransport(
          infos: {'temple': recordedInfo('temple', RobosatsNetwork.mainnet)},
        ),
      ).fetchInfo(temple, RobosatsNetwork.mainnet),
    );
    // An address with a zero width space: the info is already known, so nothing is asked of it.
    final hidden = rewrite(
      temple,
      mainnet: CoordinatorOrigins(
        onion:
            '${onion.substring(0, 20)}${String.fromCharCode(0x200B)}${onion.substring(20)}',
      ),
    );
    await open(
      tester,
      FakeTransport(),
      of: hidden,
      known: switch (known) {
        Ok(:final value) => value,
        _ => throw StateError('no info'),
      },
    );

    await scrollTo(tester, find.text(onion));
    await tester.tap(find.text(onion));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.copy_sharp));
    await tester.pump(const Duration(seconds: 4));
    await settle(tester);
    expect(copied, [onion]);
  });

  for (final (locale, label) in [
    (const Locale('en'), 'Copy'),
    (const Locale('fr'), 'Copier'),
  ]) {
    testWidgets('the copy button is labelled (${locale.languageCode})', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await open(
        tester,
        FakeTransport(
          infos: {'temple': recordedInfo('temple', RobosatsNetwork.mainnet)},
        ),
        locale: locale,
      );
      await tester.tap(find.byTooltip('Telegram'));
      await settle(tester);

      final copy = find.descendant(
        of: find.byType(CoordinatorLinkSheet),
        matching: find.byType(IconButton),
      );
      expect(find.byTooltip(label), findsOneWidget);
      // A screen reader announces the button with its label.
      expect(
        tester.getSemantics(copy),
        isSemantics(tooltip: label, isButton: true),
      );
      semantics.dispose();
    });
  }

  testWidgets(
    'a value that is not printable ASCII, or too long, is not offered for copy',
    (tester) async {
      // A Cyrillic letter that looks Latin, and a link longer than the bound of the embedded list.
      final lookalike =
          'https://templeofsats${String.fromCharCode(0x0456)}.org';
      final long =
          'https://templeofsats.org/${'a' * CoordinatorText.copyBound}';
      final hostile = rewrite(
        coordinator('temple'),
        contact: CoordinatorContact(website: lookalike, simplex: long),
      );
      await open(
        tester,
        FakeTransport(
          infos: {'temple': recordedInfo('temple', RobosatsNetwork.mainnet)},
        ),
        of: hostile,
      );

      await tester.tap(find.byTooltip('Website'));
      await settle(tester);
      expect(
        find.descendant(
          of: find.byType(BullCopyField),
          matching: find.text(lookalike),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.copy_sharp), findsNothing);
      await tester.tapAt(const Offset(4, 4));
      await settle(tester);

      await tester.tap(find.byTooltip('Simplex'));
      await settle(tester);
      final shown = tester.widget<Text>(
        find.descendant(
          of: find.byType(BullCopyField),
          matching: find.byType(Text),
        ),
      );
      // Shown cut, and a cut value is never copied.
      expect(shown.data?.endsWith('…'), isTrue);
      expect(find.byIcon(Icons.copy_sharp), findsNothing);
      expect(copied, isEmpty);
    },
  );

  testWidgets('a hosted web app that cannot be copied is shown without a link', (
    tester,
  ) async {
    final temple = coordinator('temple');
    final onion = temple.mainnet.onion ?? '';
    final known = await tester.runAsync(
      () => CoordinatorClient(
        FakeTransport(
          infos: {'temple': recordedInfo('temple', RobosatsNetwork.mainnet)},
        ),
      ).fetchInfo(temple, RobosatsNetwork.mainnet),
    );
    // A Cyrillic letter in the address: the info is already known, so nothing is asked of it.
    final lookalike =
        '${onion.substring(0, 20)}${String.fromCharCode(0x0430)}${onion.substring(21)}';
    await open(
      tester,
      FakeTransport(),
      of: rewrite(temple, mainnet: CoordinatorOrigins(onion: lookalike)),
      known: switch (known) {
        Ok(:final value) => value,
        _ => throw StateError('no info'),
      },
    );

    await scrollTo(tester, find.text(lookalike));
    expect(
      tester.widget<Text>(find.text(lookalike)).style?.color,
      testBullTheme.text,
    );
    await tester.tap(find.text(lookalike));
    await settle(tester);
    expect(find.byType(CoordinatorLinkSheet), findsNothing);
  });

  testWidgets(
    'the text of the coordinator answer is shown cleaned, the notice whole',
    (tester) async {
      String hidden(String text) =>
          text.replaceAll('|', String.fromCharCodes([0x200B, 0x3164, 0xFE0F]));
      // Longer than a line, shorter than the bound of a notice.
      final notice = 'Maintenance|${'n' * 2000}';
      final info = recordedInfo('temple', RobosatsNetwork.mainnet)
        ..['notice_severity'] = 'warning'
        ..['notice_message'] = hidden(notice)
        ..['market_price_apis'] = hidden('https://price|.example')
        ..['lnd_version'] = hidden('v0.21|.5-beta')
        ..['cln_version'] = hidden('v25|.09')
        ..['node_alias'] = hidden('Temple|Node');
      await open(tester, FakeTransport(infos: {'temple': info}));

      final shownNotice = tester.widget<Text>(
        find.textContaining('Maintenance'),
      );
      expect(shownNotice.data, 'Maintenance${'n' * 2000}');
      await openSection(tester, 'Summary');
      expect(find.text('https://price.example'), findsOneWidget);
      await openSection(tester, 'Stats for Nerds');
      expect(find.text('v0.21.5-beta'), findsOneWidget);
      expect(find.text('v25.09'), findsOneWidget);
      expect(find.text('TempleNode'), findsOneWidget);
    },
  );

  test('a fingerprint is grouped by characters, never inside one', () {
    expect(CoordinatorContacts.groupFingerprint('ABCDEFGHIJ'), 'ABCD EFGH IJ');
    expect(CoordinatorContacts.groupFingerprint('🔥🔥🔥🔥🔥'), '🔥🔥🔥🔥 🔥');
    expect(CoordinatorContacts.groupFingerprint(''), '');
  });

  testWidgets('on testnet: the testnet web app and the 1ML link', (
    tester,
  ) async {
    await open(
      tester,
      FakeTransport(
        network: RobosatsNetwork.testnet,
        infos: {'temple': recordedInfo('temple', RobosatsNetwork.testnet)},
      ),
      network: RobosatsNetwork.testnet,
    );

    expect(
      find.text(
        'http://jpp3w5tpxtyg6lifonisdszpriiapszzem4wod2zsdweyfenlsxeoxid.onion',
      ),
      findsOneWidget,
    );
    // The notice of temple on testnet holds HTML, shown as written.
    expect(
      find.text(
        'This is a coordinator message with <a href="http://duck.com">LINK</a>',
      ),
      findsOneWidget,
    );
    await openSection(tester, 'Stats for Nerds');
    await scrollTo(tester, find.textContaining('(1ML)'));
    expect(find.textContaining('LN Node: '), findsOneWidget);
  });

  testWidgets('badges are lit or greyed out as in the official client', (
    tester,
  ) async {
    // Gumpellite joined four days before the clock: not a founder, gives 20 %, good OpSec, small limits.
    await open(tester, FakeTransport(), of: coordinator('gumpellite'));

    final colors = [
      for (final badge in tester.widgetList<CoordinatorBadge>(
        find.byType(CoordinatorBadge),
      ))
        (badge.lit, badge.explanation),
    ];
    expect(colors, [
      (false, 'Not a federation founder'),
      (
        true,
        'Development fund supporter: donates 20% to make RoboSats better.',
      ),
      (
        true,
        'Good OpSec: the coordinator follows best practices to protect his and your privacy.',
      ),
      (false, 'Does not have large trade limits.'),
    ]);
    final icons = tester
        .widgetList<Icon>(
          find.descendant(
            of: find.byType(CoordinatorBadge),
            matching: find.byType(Icon),
          ),
        )
        .map((icon) => icon.color);
    expect(icons, [
      testBullTheme.outline,
      testBullTheme.primary,
      testBullTheme.primary,
      testBullTheme.outline,
    ]);
  });

  testWidgets('large limits come from the size limit, not from the list', (
    tester,
  ) async {
    // A coordinator four days old that the list says has large limits: the official client reads `size_limit` only.
    final young = rewrite(
      coordinator('gumpellite'),
      badges: const CoordinatorBadges(
        isFounder: false,
        donatesToDevFund: 20,
        hasGoodOpSec: true,
        hasLargeLimits: true,
      ),
    );
    await open(tester, FakeTransport(), of: young);
    expect(
      tester
          .widgetList<CoordinatorBadge>(find.byType(CoordinatorBadge))
          .last
          .lit,
      isFalse,
    );
    await tester.tapAt(const Offset(4, 4));
    await settle(tester);

    // A founder that the list says has no large limits: 21 BTC.
    final founder = rewrite(
      coordinator('temple'),
      badges: const CoordinatorBadges(
        isFounder: true,
        donatesToDevFund: 30,
        hasGoodOpSec: true,
        hasLargeLimits: false,
      ),
    );
    await open(tester, FakeTransport(), of: founder);
    expect(
      tester.widgetList<CoordinatorBadge>(find.byType(CoordinatorBadge)).last,
      isA<CoordinatorBadge>()
          .having((badge) => badge.lit, 'lit', isTrue)
          .having(
            (badge) => badge.explanation,
            'explanation',
            'Large limits: the coordinator has large trade limits.',
          ),
    );
  });

  testWidgets('a young coordinator: its size limit caps the order size', (
    tester,
  ) async {
    final info = recordedInfo('temple', RobosatsNetwork.mainnet)
      ..['node_id'] = coordinator('gumpellite').mainnetNodesPubkeys.first
      ..['swap_enabled'] = false;
    await open(
      tester,
      FakeTransport(infos: {'gumpellite': info}),
      of: coordinator('gumpellite'),
    );

    await openSection(tester, 'Summary');
    expect(find.text('250,000 Sats'), findsOneWidget);
    expect(find.text('Onchain payouts disabled'), findsOneWidget);
    expect(find.text('Current onchain payout status'), findsOneWidget);
    expect(find.text('Maximum onchain swap size'), findsNothing);
    expect(
      tester.widget<Text>(find.text('Onchain payouts disabled')).style?.color,
      testBullTheme.error,
    );
  });

  testWidgets('hostile and missing texts are shown bounded, as plain text', (
    tester,
  ) async {
    final hostile = rewrite(
      coordinator('temple'),
      longAlias: 'Temple\u202E${'W' * 500}',
      description: '<script>alert(1)</script>\n${'d' * 100000}',
      motto: 'line\u0000one\nline two 🔥',
      contact: CoordinatorContact(
        email: '${'e' * 5000}@example.org',
        website: 'javascript:alert(1)',
        pgp: '',
        fingerprint: 'ABCD',
        nostr: '   ',
      ),
      badges: const CoordinatorBadges(
        isFounder: false,
        donatesToDevFund: 0,
        hasGoodOpSec: false,
        hasLargeLimits: true,
      ),
      policies: {'R\u202Eule': 'p' * 100000},
    );
    final info = recordedInfo('lake', RobosatsNetwork.mainnet)
      ..['node_id'] = coordinator('temple').mainnetNodesPubkeys.first
      ..['node_alias'] = 'n' * 1024
      ..remove('current_swap_fee_rate')
      ..remove('lnd_version')
      ..remove('cln_version')
      ..remove('robosats_running_commit_hash')
      ..remove('market_price_apis');
    await open(tester, FakeTransport(infos: {'temple': info}), of: hostile);

    expect(tester.takeException(), isNull);
    expect(
      find.text('Temple${'W' * (CoordinatorText.name - 6)}…'),
      findsOneWidget,
    );
    expect(find.text('lineone line two 🔥'), findsOneWidget);
    final description = tester.widget<Text>(
      find.textContaining('<script>alert(1)</script>'),
    );
    expect(description.data?.runes.length, CoordinatorText.paragraph + 1);
    expect(description.data?.endsWith('…'), isTrue);
    // A blank Nostr key and a PGP key without its path show no button; the long email is cut.
    expect(find.byTooltip('Nostr'), findsNothing);
    expect(find.byTooltip('PGP Pubkey fingerprint'), findsNothing);
    await tester.tap(find.byTooltip('Send Email'));
    await settle(tester);
    final email = tester.widget<Text>(
      find.descendant(
        of: find.byType(BullCopyField),
        matching: find.byType(Text),
      ),
    );
    expect(email.data?.runes.length, CoordinatorText.line + 1);
    await tester.tapAt(const Offset(4, 4));
    await settle(tester);
    // A website that is a script is only text: nothing opens it.
    await tester.tap(find.byTooltip('Website'));
    await settle(tester);
    expect(find.text('javascript:alert(1)'), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await settle(tester);

    // The notice of TheBigLake is HTML, shown as written.
    expect(find.textContaining('<h1>Recomendações'), findsOneWidget);

    await openSection(tester, 'Policies');
    expect(find.text('Rule'), findsOneWidget);
    await openSection(tester, 'Summary');
    // A coordinator that does not give its on-chain fee leaves it unknown.
    expect(find.text('-'), findsOneWidget);
    expect(find.text('0% of profits'), findsOneWidget);
    await openSection(tester, 'Stats for Nerds');
    expect(find.text('LND version'), findsNothing);
    expect(find.text('CLN version'), findsNothing);
    expect(find.text('Coordinator commit hash'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a coordinator without policies, contacts nor notice', (
    tester,
  ) async {
    final bare = rewrite(
      coordinator('temple'),
      contact: const CoordinatorContact(),
      policies: const {},
    );
    // LibreBazaar announces the severity « none »: no notice box.
    final info = recordedInfo('bazaar', RobosatsNetwork.mainnet)
      ..['node_id'] = coordinator('temple').mainnetNodesPubkeys.first;
    await open(tester, FakeTransport(infos: {'temple': info}), of: bare);

    expect(find.byType(IconButton), findsNothing);
    expect(find.text('Coordinator Notice'), findsNothing);
    // The official client always shows the section, empty or not.
    await openSection(tester, 'Policies');
    expect(find.text('1'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
