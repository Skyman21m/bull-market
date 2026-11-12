import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/ui/widgets/coordinator_avatar.dart';
import 'package:p2p/src/ui/widgets/coordinator_images.dart';
import 'package:p2p/src/ui/widgets/coordinator_mark.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

/// [temple] under another short alias.
Coordinator aliased(String shortAlias) {
  final temple = coordinator('temple');
  return Coordinator(
    shortAlias: shortAlias,
    longAlias: temple.longAlias,
    identifier: temple.identifier,
    description: temple.description,
    motto: temple.motto,
    color: temple.color,
    established: temple.established,
    nostrHexPubkey: temple.nostrHexPubkey,
    contact: temple.contact,
    badges: temple.badges,
    policies: temple.policies,
    mainnet: temple.mainnet,
    testnet: temple.testnet,
    mainnetNodesPubkeys: temple.mainnetNodesPubkeys,
    testnetNodesPubkeys: temple.testnetNodesPubkeys,
    federated: temple.federated,
  );
}

/// The app's bundle, but without the coordinator images, as a build that lost them would be, or with bytes that are no image when [corrupt].
final class _BrokenImagesBundle extends CachingAssetBundle {
  final bool corrupt;

  _BrokenImagesBundle({this.corrupt = false});

  @override
  Future<ByteData> load(String key) {
    if (!key.contains('assets/coordinators/')) return rootBundle.load(key);
    if (corrupt) {
      return Future.value(ByteData.sublistView(Uint8List.fromList([1, 2, 3])));
    }
    return Future.error(FlutterError('no asset $key'));
  }
}

/// The width and height of the image in [bytes], once the engine decoded it.
Future<(int, int)?> decodedSize(WidgetTester tester, Uint8List bytes) =>
    tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return (frame.image.width, frame.image.height);
    });

void main() {
  const reference = 'ff1998caed30888b2fb60e15022c29063a60f1ba';
  const federation = 'e56f9cf7cd4e6b01aa78589922f7c648f262b6b6';

  group('the bundled images', () {
    test('every coordinator of the embedded list has its image', () {
      // No coordinator of the list falls back to its mark today: each has the image the official client shows.
      expect(coordinatorImages.keys.toSet(), {
        for (final c in Federation.robosats.coordinators) c.shortAlias,
      });
    });

    test('each image is the small avatar of its coordinator, at a pinned source', () {
      // Five come from the protocol reference, Gumpellite's from the commit of the federation list, which added it.
      // Each blob was checked against RoboSats when it was added: `git rev-parse ff1998c:<path>` in the reference clone, and the `sha` of `gh api 'repos/RoboSats/robosats/contents/<path>?ref=e56f9cf7c…'` for Gumpellite.
      // `test/features/p2p/p2p_coordinator_images_test.dart` checks each bundled asset against its blob.
      expect(coordinatorImages, {
        for (final (alias, commit, blob) in [
          ('temple', reference, '166ad7ed623aba45dc4cb84b71b36bd2dc8e111e'),
          ('lake', reference, 'c90d069fffa4f0dc0dc70d3e7f7341f5d40ecd76'),
          ('bazaar', reference, 'cbdaa1e17ba97eaf355905121990127a8eb57a9c'),
          ('freeport', reference, '13bd8f64d87ccd872eb4a0faaa8300f169edfec7'),
          ('ammanaya', reference, '041b4f19bae4d75b4a3e852ea92ad28a40bde06f'),
          (
            'gumpellite',
            federation,
            'def8359b4f8939b668bcb795082e552e98939329',
          ),
        ])
          alias: (
            asset: 'assets/coordinators/$alias.small.webp',
            path: 'frontend/static/federation/avatars/$alias.small.webp',
            commit: commit,
            blob: blob,
          ),
      });
    });

    testWidgets('each asset is on disk, decodes, and is 80 by 80 pixels', (
      tester,
    ) async {
      for (final MapEntry(key: alias, value: image)
          in coordinatorImages.entries) {
        final file = File(image.asset);
        expect(file.existsSync(), isTrue, reason: alias);
        expect(await decodedSize(tester, file.readAsBytesSync()), (
          80,
          80,
        ), reason: alias);
      }
    });

    test('the folder holds the images of the table and nothing else', () {
      expect(
        {
          for (final file in Directory('assets/coordinators').listSync())
            file.path,
        },
        {for (final image in coordinatorImages.values) image.asset},
      );
    });

    test('an asset is named only by an alias of the embedded list', () {
      // The aliases of the list are 1 to 20 lowercase letters and digits (`Federation.problems()`), and a path is a constant of the table, never built from text.
      for (final alias in coordinatorImages.keys) {
        expect(alias, matches(RegExp(r'^[a-z0-9]{1,20}$')));
        expect(Federation.robosats.byAlias(alias), isNotNull);
      }
      expect(Federation.robosats.problems(), isEmpty);
    });
  });

  group('the avatar of a coordinator', () {
    Future<void> show(
      WidgetTester tester,
      Widget avatar, {
      AssetBundle? bundle,
    }) async {
      await tester.pumpWidget(
        harness(
          Center(
            child: bundle == null
                ? avatar
                : DefaultAssetBundle(bundle: bundle, child: avatar),
          ),
        ),
      );
      // Lets the asset load and decode, which happens outside the fake clock.
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    testWidgets(
      'draws the coordinator image in a disc, decoded at the size drawn',
      (tester) async {
        await show(
          tester,
          CoordinatorAvatar(coordinator: coordinator('temple'), size: 44),
        );

        // The asset of the table, in the feature's package, asked at the size drawn.
        expect(
          switch (tester.widget<Image>(find.byType(Image)).image) {
            ResizeImage(
              :final width,
              :final height,
              imageProvider: final AssetImage asset,
            ) =>
              (width, height, asset.keyName),
            final other => other,
          },
          (44, 44, 'packages/p2p/assets/coordinators/temple.small.webp'),
        );
        expect(find.byType(ClipOval), findsOneWidget);
        expect(find.byType(CoordinatorMark), findsNothing);
        final drawn = tester.widget<RawImage>(find.byType(RawImage)).image;
        expect((drawn?.width, drawn?.height), (44, 44));
        expect(
          tester.getSize(find.byType(CoordinatorAvatar)),
          const Size.square(44),
        );
      },
    );

    testWidgets('is never decoded larger than the 80 pixels of its file', (
      tester,
    ) async {
      await show(
        tester,
        CoordinatorAvatar(coordinator: coordinator('gumpellite'), size: 96),
      );

      final drawn = tester.widget<RawImage>(find.byType(RawImage)).image;
      expect((drawn?.width, drawn?.height), (80, 80));
      expect(find.byType(CoordinatorMark), findsNothing);
    });

    for (final (name, corrupt) in [
      ('missing', false),
      ('not an image', true),
    ]) {
      testWidgets('shows the mark when the asset is $name', (tester) async {
        await show(
          tester,
          CoordinatorAvatar(coordinator: coordinator('temple'), size: 44),
          bundle: _BrokenImagesBundle(corrupt: corrupt),
        );

        expect(find.byType(CoordinatorMark), findsOneWidget);
        expect(find.text('TS'), findsOneWidget);
        expect(find.byType(RawImage), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'no other alias than one of the table reaches an asset: the mark is drawn instead',
      (tester) async {
        for (final alias in [
          'unknown',
          'Temple',
          'temple ',
          '../temple',
          'temple.small',
          'assets/coordinators/temple.small.webp',
          'packages/p2p/assets/coordinators/temple.small.webp',
          '',
        ]) {
          await show(tester, CoordinatorAvatar(coordinator: aliased(alias)));

          expect(find.byType(Image), findsNothing, reason: alias);
          expect(find.byType(CoordinatorMark), findsOneWidget, reason: alias);
        }
      },
    );

    testWidgets('stays out of the semantics tree, as the mark does', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await show(
        tester,
        CoordinatorAvatar(coordinator: coordinator('temple'), size: 44),
      );

      expect(find.byType(RawImage), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CoordinatorAvatar),
          matching: find.bySemanticsLabel(RegExp('.')),
        ),
        findsNothing,
      );
      semantics.dispose();
    });
  });
}
