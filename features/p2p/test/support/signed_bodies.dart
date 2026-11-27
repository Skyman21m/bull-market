import 'dart:convert';

import 'package:test/test.dart';

/// The JSON text of [body], the body of a request of a robot that changes a state, before its signature (GHSA-22q8-9ghc-jg3h): the signature must be its last field, a cleartext signature, `,"signature":"…"}` byte for byte; what it signs is checked by the scripted coordinators, which refuse the request otherwise.
String unsignedBodyOf(List<int>? body) {
  final raw = utf8.decode(body ?? const []);
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, Object?>) fail('not a JSON object: $raw');
  expect(decoded.keys.last, 'signature');
  final signature = decoded['signature'];
  if (signature is! String) fail('no signature');
  expect(
    signature,
    startsWith('-----BEGIN PGP SIGNED MESSAGE-----\nHash: SHA512\n\n'),
  );
  final suffix = ',"signature":${jsonEncode(signature)}}';
  expect(raw, endsWith(suffix));
  return '${raw.substring(0, raw.length - suffix.length)}}';
}
