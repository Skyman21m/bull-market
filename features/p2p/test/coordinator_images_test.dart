import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bull_ui/testing.dart';
import 'package:crypto/crypto.dart';
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

/// The Git blob id of [bytes], which `git rev-parse <commit>:<path>` prints for a file of a commit.
String gitBlobId(List<int> bytes) => sha1.convert([
  ...ascii.encode('blob ${bytes.length}\x00'),
  ...bytes,
]).toString();

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

    test('each image is the avatar of its coordinator, at a pinned source', () {
      // Five come from the protocol reference, Gumpellite's from the commit of the federation list, which added it.
      // Each blob was checked against RoboSats when it was added: `git rev-parse ff1998c:<path>` in the reference clone, and the `sha` of `gh api 'repos/RoboSats/robosats/contents/<path>?ref=e56f9cf7c…'` for Gumpellite.
      // The files are checked against these blobs below, and `test/features/p2p/p2p_coordinator_images_test.dart` checks the bytes the app's bundle serves.
      expect(coordinatorImages, {
        for (final (alias, commit, blob) in [
          ('temple', reference, '01172a3738529ee58d554d92f57fd0e9085a22ee'),
          ('lake', reference, '8936c1cd93d8b0599c47522d5a83133c83cc0415'),
          ('bazaar', reference, '816a7c8478bcb72908f5bda2f104d468c222bb7f'),
          ('freeport', reference, '56b583ac77d992df27300cf0851d8e6d70439158'),
          ('ammanaya', reference, 'ebaa03a3cd2b923c07efc78a3dad4453afe51a3f'),
          (
            'gumpellite',
            federation,
            'b625b66c3052eb46260bb915ba4aca5e15a0d319',
          ),
        ])
          alias: (
            asset: 'assets/coordinators/$alias.webp',
            path: 'frontend/static/federation/avatars/$alias.webp',
            commit: commit,
            blob: blob,
          ),
      });
    });

    testWidgets(
      'each asset is on disk, is its pinned RoboSats file, decodes, and is 200 by 200 pixels',
      (tester) async {
        for (final MapEntry(key: alias, value: image)
            in coordinatorImages.entries) {
          final file = File(image.asset);
          expect(file.existsSync(), isTrue, reason: alias);
          expect(gitBlobId(file.readAsBytesSync()), image.blob, reason: alias);
          expect(await decodedSize(tester, file.readAsBytesSync()), (
            200,
            200,
          ), reason: alias);
        }
      },
    );

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
    /// Shows [avatar] at the pixel density [ratio], which the harness otherwise sets to 1, from [bundle] when given; with [decode], lets the asset load and decode, which happens outside the fake clock.
    Future<void> show(
      WidgetTester tester,
      Widget avatar, {
      AssetBundle? bundle,
      double ratio = 1,
      bool decode = true,
    }) async {
      await tester.pumpWidget(
        harness(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(devicePixelRatio: ratio),
              child: Center(
                child: bundle == null
                    ? avatar
                    : DefaultAssetBundle(bundle: bundle, child: avatar),
              ),
            ),
          ),
        ),
      );
      if (!decode) return;
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    /// The asset key and the size in pixels the image of the avatar shown is asked at.
    (String, int?, int?)? requested(WidgetTester tester) =>
        switch (tester.widget<Image>(find.byType(Image)).image) {
          ResizeImage(
            :final width,
            :final height,
            imageProvider: final AssetImage asset,
          ) =>
            (asset.keyName, width, height),
          _ => null,
        };

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
          (44, 44, 'packages/p2p/assets/coordinators/temple.webp'),
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

    testWidgets('each coordinator draws its own image', (tester) async {
      for (final coordinator in Federation.robosats.coordinators) {
        final alias = coordinator.shortAlias;
        await show(
          tester,
          CoordinatorAvatar(coordinator: coordinator, size: 44),
          decode: false,
        );

        expect(
          requested(tester)?.$1,
          'packages/p2p/${coordinatorImages[alias]?.asset}',
          reason: alias,
        );
        expect(requested(tester)?.$1, endsWith('/$alias.webp'), reason: alias);
      }
    });

    // The badge of a robot (16 points), the order page (44) and the coordinator dialog (96), on screens of density 1, 2, 2.625 and 3.
    for (final ratio in [1.0, 2.0, 2.625, 3.0]) {
      testWidgets(
        'is decoded at the size drawn in pixels at density $ratio, never above the file',
        (tester) async {
          for (final size in [16.0, 44.0, 96.0]) {
            imageCache
              ..clear()
              ..clearLiveImages();
            await show(
              tester,
              CoordinatorAvatar(coordinator: coordinator('lake'), size: size),
              ratio: ratio,
            );

            final pixels = (size * ratio).ceil();
            expect(requested(tester)?.$2, pixels, reason: '$size');
            expect(requested(tester)?.$3, pixels, reason: '$size');
            // Flutter's ResizeImage never enlarges: past the file's 200 pixels, the file's own size.
            final drawn = tester.widget<RawImage>(find.byType(RawImage)).image;
            final decoded = pixels < 200 ? pixels : 200;
            expect(
              (drawn?.width, drawn?.height),
              (decoded, decoded),
              reason: '$size',
            );
            expect(
              tester.getSize(find.byType(CoordinatorAvatar)),
              Size.square(size),
            );
          }
        },
      );
    }

    testWidgets(
      'until the image is decoded, a plain disc in its ring stands in, of the same size',
      (tester) async {
        await show(
          tester,
          CoordinatorAvatar(coordinator: coordinator('temple'), size: 44),
          decode: false,
        );

        final disc = tester.widget<Container>(
          find.descendant(
            of: find.byType(CoordinatorAvatar),
            matching: find.byType(Container),
          ),
        );
        expect(
          disc.decoration,
          BoxDecoration(
            color: testBullTheme.surfaceContainer,
            shape: BoxShape.circle,
          ),
        );
        expect(
          disc.foregroundDecoration,
          BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: testBullTheme.outlineVariant),
          ),
        );
        expect(
          tester.getSize(find.byType(CoordinatorAvatar)),
          const Size.square(44),
        );
        expect(find.byType(CoordinatorMark), findsNothing);
      },
    );

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
        // The mark takes the place at the size asked.
        expect(
          tester.getSize(find.byType(CoordinatorMark)),
          const Size.square(44),
        );
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
          'temple.webp',
          'assets/coordinators/temple.webp',
          'packages/p2p/assets/coordinators/temple.webp',
          '',
        ]) {
          await show(
            tester,
            CoordinatorAvatar(coordinator: aliased(alias), size: 30),
          );

          expect(find.byType(Image), findsNothing, reason: alias);
          expect(find.byType(CoordinatorMark), findsOneWidget, reason: alias);
          expect(
            tester.getSize(find.byType(CoordinatorMark)),
            const Size.square(30),
            reason: alias,
          );
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
