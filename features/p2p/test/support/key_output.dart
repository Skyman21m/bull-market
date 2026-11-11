import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bull_logger/bull_logger.dart';
import 'package:robosats/robosats.dart' show GarageKey;
import 'package:test/test.dart';

/// Everything [body] prints and everything the project logger writes while it runs, as one text.
///
/// The logger is pointed at a fresh temporary folder for the call, and its file is read back once flushed; it prints every line it handles to the console in debug mode, which the zone captures too.
/// A line printed and a line logged by the capture itself show that both are seen.
Future<String> captureKeyOutput(Future<void> Function() body) async {
  final printed = <String>[];
  final directory = Directory.systemTemp.createTempSync('p2p_key_output');
  log = Logger.replace(directory: directory);
  try {
    await runZoned(
      () async {
        Zone.current.print('print capture works');
        log.fine('logger capture works');
        await body();
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => printed.add(line),
      ),
    );
    await log.flush();
  } finally {
    // Back to a folder of its own, as `flutter_test_config.dart` sets it up: the replaced logger no longer listens.
    log = Logger.replace(
      directory: Directory.systemTemp.createTempSync('p2p_test_logs'),
    );
  }
  final written = [
    for (final file in directory.listSync().whereType<File>())
      file.readAsStringSync(),
  ].join('\n');
  directory.deleteSync(recursive: true);
  expect(printed, contains('print capture works'));
  expect(written, contains('logger capture works'));
  return '${printed.join('\n')}\n$written';
}

/// Fails if [output] holds any usual form of any of [keys]: hexadecimal, a list of bytes, base64 or the `robo1…` text.
///
/// The check is a boolean per form, so that a failure never prints the key it found.
void expectNoKeyIn(String output, Iterable<GarageKey> keys) {
  for (final key in keys) {
    final bytes = key.revealBytes();
    final forms = [
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
      '$bytes',
      bytes.join(','),
      base64Encode(bytes),
      key.revealBech32(),
      key.revealBech32().substring(5, 30),
    ];
    for (final (index, form) in forms.indexed) {
      expect(output.contains(form), isFalse, reason: 'form $index');
    }
  }
}
