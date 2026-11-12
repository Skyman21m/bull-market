import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The P2P database, `p2p.sqlite`, lives in the documents directory the shell passes to `P2pFeature.setup` (`background_tasks_keystore_test.dart` pins that argument): these pin that the platforms keep that directory out of cloud backups.
///
/// The database holds no secret, but it tells which coordinators this device used, when, and for how many robots.
/// What these do not cover: Android's device-to-device transfer, which `allowBackup="false"` does not stop from Android 12, for the wallet's databases as for this one.
void main() {
  test('Android backs up nothing of the app', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:allowBackup="false"'));
  });

  test('iOS excludes the whole documents directory from backups', () {
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(delegate, contains('excludeSensitiveFilesFromBackup()'));
    expect(delegate, contains('fileManager.urls(for: .documentDirectory'));
    expect(delegate, contains('resourceValues.isExcludedFromBackup = true'));
    expect(
      delegate,
      contains('documentsURL.setResourceValues(resourceValues)'),
    );
  });
}
