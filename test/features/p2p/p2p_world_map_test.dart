// The world map of the « Map » view as the app bundles it: listed in the app's asset manifest under the feature's package, loaded through the app's own asset bundle, byte for byte the asset the feature pins, and read whole.
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/testing.dart';

void main() {
  testWidgets(
    'the world map is in the app bundle, is the pinned asset, and reads',
    (tester) async {
      await tester.runAsync(() async {
        // `MapChartView` asks the bundle for this key.
        const key =
            'packages/${WorldMapSource.package}/${WorldMapSource.asset}';
        final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
        expect(manifest.listAssets(), contains(key));
        final data = await rootBundle.load(key);
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        expect(sha256.convert(bytes).toString(), WorldMapSource.assetSha256);
        expect(WorldMap.parse(bytes)?.rings, hasLength(287));
      });
    },
  );
}
