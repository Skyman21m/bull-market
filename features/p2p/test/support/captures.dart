import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures of the feature's own screen tests (#182), written only when `P2P_CAPTURE_DIR` names a folder, as the app's capture test (`test/features/p2p/p2p_screens_capture_test.dart`): the panels drawn from the state machine's statuses, which the app's test cannot build through the testing seam.
///
/// The app's font (`assets/fonts/GolosText.ttf` of the repository) stands in for the platform's, and the SDK's Material icons are loaded, so that the texts are read and looked at; the colours are those of the tests' theme, not the app's.
final String? captureDirectory = Platform.environment['P2P_CAPTURE_DIR'];

/// The key of the boundary [capture] draws.
const captureFrame = ValueKey('p2p-capture-frame');

bool _fontsLoaded = false;

/// Loads the fonts once, when captures are asked.
Future<void> loadCaptureFonts() async {
  if (captureDirectory == null || _fontsLoaded) return;
  _fontsLoaded = true;
  Future<void> load(String family, File file) async {
    if (!file.existsSync()) return;
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    await loader.load();
  }

  final golos = File('../../assets/fonts/GolosText.ttf');
  await load('Roboto', golos);
  await load('Golos Text', golos);
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(
        Platform.resolvedExecutable,
      ).parent.parent.parent.parent.parent.parent.path;
  await load(
    'MaterialIcons',
    File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ),
  );
}

/// Writes the frame under [captureFrame] as `<locale>-<name>.png`, when captures are asked.
Future<void> capture(WidgetTester tester, String name) async {
  final directory = captureDirectory;
  if (directory == null) return;
  await tester.pump(const Duration(milliseconds: 50));
  await tester.runAsync(() async {
    final boundary =
        tester.renderObject(find.byKey(captureFrame)) as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw StateError('no PNG for $name');
    Directory(directory).createSync(recursive: true);
    File('$directory/$name.png').writeAsBytesSync(png.buffer.asUint8List());
  });
}
