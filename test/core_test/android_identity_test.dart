import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Troc must install next to the official Bull Bitcoin app and must not present itself under Bull's name.
/// These settings are easy to lose in an upstream sync, so pin them.
void main() {
  test("applicationId is Troc's own, namespace stays upstream", () {
    final gradle = File('android/app/build.gradle').readAsStringSync();

    // Matches both `applicationId = '…'` and the Groovy form without `=`, and never `applicationIdSuffix`.
    final applicationIds = RegExp(
      r'''\bapplicationId\b\s*=?\s*['"]([^'"]+)['"]''',
    ).allMatches(gradle).map((m) => m.group(1)).toList();
    expect(applicationIds, ['io.github.skyman21m.troc']);

    // The namespace is the Kotlin package and R class, not the installed identity.
    // It stays aligned with upstream to keep syncs conflict-free.
    final namespace = RegExp(
      r'''namespace\s+['"]([^'"]+)['"]''',
    ).firstMatch(gradle)?.group(1);
    expect(namespace, 'com.bullbitcoin.mobile');
  });

  test('launcher labels do not use the Bull name', () {
    String? label(String path) {
      final manifest = File(path).readAsStringSync();
      return RegExp(r'android:label="([^"]+)"').firstMatch(manifest)?.group(1);
    }

    expect(label('android/app/src/main/AndroidManifest.xml'), 'Troc');
    expect(label('android/app/src/beta/AndroidManifest.xml'), 'Troc Beta');
  });
}
