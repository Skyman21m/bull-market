// The coordinator images of the P2P feature, as the app bundles them: listed in the app's asset manifest under the feature's package, loaded through the app's own asset bundle, decoded by the engine, and byte for byte the RoboSats files their table pins.
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/testing.dart';

/// The Git blob id of [bytes], which `git rev-parse <commit>:<path>` prints for a file of a commit.
String _gitBlobId(List<int> bytes) => sha1.convert([
  ...ascii.encode('blob ${bytes.length}\x00'),
  ...bytes,
]).toString();

void main() {
  testWidgets(
    'every coordinator image is in the app bundle, decodes at 200 by 200, and is its pinned RoboSats file',
    (tester) async {
      await tester.runAsync(() async {
        final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
        expect(coordinatorImages, isNotEmpty);
        for (final MapEntry(key: alias, value: image)
            in coordinatorImages.entries) {
          // `Image.asset(…, package: 'p2p')` asks the bundle for this key.
          final key = 'packages/p2p/${image.asset}';
          expect(manifest.listAssets(), contains(key), reason: alias);
          final bytes = (await rootBundle.load(key)).buffer.asUint8List();
          expect(_gitBlobId(bytes), image.blob, reason: alias);
          final frame = await (await ui.instantiateImageCodec(
            bytes,
          )).getNextFrame();
          expect(
            (frame.image.width, frame.image.height),
            (200, 200),
            reason: alias,
          );
        }
      });
    },
  );
}
