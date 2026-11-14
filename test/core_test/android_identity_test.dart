import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Bull Market (« Troc » until #105) must install next to the official Bull Bitcoin app and must not present itself as that app.
/// These settings are easy to lose in an upstream sync, so pin them.
void main() {
  test("applicationId is the app's own, namespace stays upstream", () {
    final gradle = File('android/app/build.gradle').readAsStringSync();

    // Matches both `applicationId = '…'` and the Groovy form without `=`, and never `applicationIdSuffix`.
    final applicationIds = RegExp(
      r'''\bapplicationId\b\s*=?\s*['"]([^'"]+)['"]''',
    ).allMatches(gradle).map((m) => m.group(1)).toList();
    expect(applicationIds, ['io.github.skyman21m.bullmarket']);

    // The namespace is the Kotlin package and R class, not the installed identity.
    // It stays aligned with upstream to keep syncs conflict-free.
    final namespace = RegExp(
      r'''namespace\s+['"]([^'"]+)['"]''',
    ).firstMatch(gradle)?.group(1);
    expect(namespace, 'com.bullbitcoin.mobile');
  });

  test("launcher labels show the app's own name, not the official app's", () {
    String? label(String path) {
      final manifest = File(path).readAsStringSync();
      return RegExp(r'android:label="([^"]+)"').firstMatch(manifest)?.group(1);
    }

    expect(label('android/app/src/main/AndroidManifest.xml'), 'Bull Market');
    expect(
      label('android/app/src/beta/AndroidManifest.xml'),
      'Bull Market Beta',
    );
  });
}
