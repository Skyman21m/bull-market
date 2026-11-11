import 'dart:convert';
import 'dart:io';

import 'package:bull_ui/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/presentation/coordinator_details_cubit.dart';
import 'package:p2p/src/presentation/coordinator_text.dart';
import 'package:p2p/src/ui/coordinator_details_dialog.dart';
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
  mainnet: base.mainnet,
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
                CoordinatorDetailsRequest(of ?? coordinator('temple'), network),
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
    expect(find.text('3,44 %'), findsOneWidget);
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

  testWidgets('a link is shown in full and copied, never opened', (
    tester,
  ) async {
    await open(
      tester,
      FakeTransport(
        infos: {'temple': recordedInfo('temple', RobosatsNetwork.mainnet)},
      ),
    );

    await tester.tap(find.byTooltip('Telegram'));
    await settle(tester);
    expect(find.text('https://t.me/templeofsats'), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await settle(tester);
    expect(copied, ['https://t.me/templeofsats']);
    expect(find.text('Copied!'), findsOneWidget);
    // The toast goes away on its own.
    await tester.pump(const Duration(seconds: 4));
    await settle(tester);

    await tester.tap(find.byTooltip('PGP Pubkey fingerprint'));
    await settle(tester);
    expect(
      find.text('2579 1752 E966 1C1D E118 A8C6 F78C D3D6 471B 6789'),
      findsOneWidget,
    );
    await tester.tap(find.text('Copy'));
    await tester.pump(const Duration(seconds: 4));
    await settle(tester);

    await tester.tap(find.byTooltip('Send Email'));
    await settle(tester);
    expect(find.text('coordinator@templeofsats.org'), findsNWidgets(1));
    await tester.tap(find.text('Copy'));
    await tester.pump(const Duration(seconds: 4));
    await settle(tester);

    await openSection(tester, 'Stats for Nerds');
    await scrollTo(tester, find.text('0226f31c5f3a... (AMBOSS)'));
    await tester.tap(find.text('0226f31c5f3a... (AMBOSS)'));
    await settle(tester);
    expect(
      find.text(
        'https://amboss.space/node/0226f31c5f3a8b48bbbb7aaa97a10effcfb445b5972a676955d5c095383d35a428',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Copy'));
    await tester.pump(const Duration(seconds: 4));
    await settle(tester);

    expect(copied, [
      'https://t.me/templeofsats',
      '2579 1752 E966 1C1D E118 A8C6 F78C D3D6 471B 6789',
      'coordinator@templeofsats.org',
      'https://amboss.space/node/0226f31c5f3a8b48bbbb7aaa97a10effcfb445b5972a676955d5c095383d35a428',
    ]);
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
    final email = tester.widget<SelectableText>(find.byType(SelectableText));
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

  testWidgets('a coordinator without policies nor contacts', (tester) async {
    final bare = rewrite(
      coordinator('temple'),
      contact: const CoordinatorContact(),
      policies: const {},
    );
    await open(
      tester,
      FakeTransport(
        infos: {'temple': recordedInfo('temple', RobosatsNetwork.mainnet)},
      ),
      of: bare,
    );

    expect(find.byType(IconButton), findsNothing);
    // The official client always shows the section, empty or not.
    await openSection(tester, 'Policies');
    expect(find.text('1'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
