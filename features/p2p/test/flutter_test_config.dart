import 'dart:async';
import 'dart:io';

import 'package:bull_logger/bull_logger.dart';

/// Auto-loaded by `flutter test`, once per test binary, before any test of the feature runs.
///
/// The global logger is anchored at the working directory, the package in the checkout, and the transport and the vault of `package:secrets` log as these tests drive them: this sends their lines to a fresh folder of the system's temporary directory instead, as the app's own test configuration does.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final logDir = Directory.systemTemp.createTempSync('p2p_test_logs');
  log = Logger.replace(directory: logDir);
  await testMain();
}
