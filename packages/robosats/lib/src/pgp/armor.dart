import 'dart:convert';
import 'dart:typed_data';

/// The kinds of ASCII-armored OpenPGP block RoboSats exchanges.
enum ArmorBlock {
  publicKey('PGP PUBLIC KEY BLOCK'),
  privateKey('PGP PRIVATE KEY BLOCK'),
  message('PGP MESSAGE'),
  signature('PGP SIGNATURE');

  final String label;

  const ArmorBlock(this.label);

  String get begin => '-----BEGIN $label-----';

  String get end => '-----END $label-----';
}

/// The first line of a cleartext-signed message.
const cleartextBegin = '-----BEGIN PGP SIGNED MESSAGE-----';

const _lineLength = 60;

final RegExp _lineBreak = RegExp(r'\r\n?');
final RegExp _armorHeader = RegExp(r'^[A-Za-z0-9-]+: ');
final RegExp _trailingWhitespace = RegExp(r'[ \t\r]+$');

/// Armors [data] exactly as OpenPGP.js 5 does: no `Version` or `Comment` header, 60-character lines, a CRC-24 line, line feeds only.
///
/// The layout is the one of `tests/robots/*/enc_priv_key` in the RoboSats repository, so a coordinator cannot tell this client from the official one by the armor.
String armorEncode(ArmorBlock block, List<int> data) {
  final encoded = base64.encode(data);
  final buffer = StringBuffer()
    ..write(block.begin)
    ..write('\n\n');
  for (var start = 0; start < encoded.length; start += _lineLength) {
    final end = start + _lineLength;
    buffer
      ..write(
        encoded.substring(start, end > encoded.length ? encoded.length : end),
      )
      ..write('\n');
  }
  buffer
    ..write('=')
    ..write(base64.encode(_crc24(data)))
    ..write('\n')
    ..write(block.end)
    ..write('\n');
  return buffer.toString();
}

/// Decodes one armored block of kind [block], or returns `null` when [armored] is not exactly one such block.
///
/// Armor headers are skipped, the blank line after them is required as the RoboSats coordinator requires it (`api/utils.py:496-518`), and a CRC-24 line is checked when present.
Uint8List? armorDecode(ArmorBlock block, String armored) {
  final lines = armored.replaceAll(_lineBreak, '\n').trim().split('\n');
  if (lines.length < 4) return null;
  if (lines.first.trimRight() != block.begin) return null;
  if (lines.last.trimRight() != block.end) return null;
  var index = 1;
  while (index < lines.length - 1 && _armorHeader.hasMatch(lines[index])) {
    index++;
  }
  if (lines[index].trim().isNotEmpty) return null;
  index++;
  final body = StringBuffer();
  String? checksum;
  for (; index < lines.length - 1; index++) {
    final line = lines[index].trimRight();
    if (checksum != null) return null;
    if (line.startsWith('=') && line.length == 5) {
      checksum = line.substring(1);
    } else {
      body.write(line);
    }
  }
  final Uint8List data;
  try {
    data = base64.decode(body.toString());
  } on FormatException {
    return null;
  }
  if (data.isEmpty) return null;
  if (checksum != null && checksum != base64.encode(_crc24(data))) return null;
  return data;
}

/// A cleartext-signed message taken apart.
typedef CleartextParts = ({
  List<String> hashes,
  String text,
  Uint8List signature,
});

/// Frames [text] and its armored [signature] packet as a cleartext-signed message.
///
/// The first three lines are exactly `-----BEGIN PGP SIGNED MESSAGE-----`, `Hash: <hashName>` and an empty line, separated by line feeds: the RoboSats coordinator splits on that literal string (`api/utils.py:642-644`).
String cleartextEncode({
  required String text,
  required String hashName,
  required List<int> signature,
}) {
  final escaped = text
      .split('\n')
      .map((line) => line.startsWith('-') ? '- $line' : line)
      .join('\n');
  return '$cleartextBegin\n'
      'Hash: $hashName\n'
      '\n'
      '$escaped\n'
      '${armorEncode(ArmorBlock.signature, signature)}';
}

/// Takes a cleartext-signed message apart, or returns `null` when [signed] is not one.
CleartextParts? cleartextDecode(String signed) {
  final lines = signed.replaceAll(_lineBreak, '\n').trim().split('\n');
  if (lines.first.trimRight() != cleartextBegin) return null;
  final hashes = <String>[];
  var index = 1;
  for (; index < lines.length && lines[index].trim().isNotEmpty; index++) {
    final line = lines[index].trimRight();
    if (!line.startsWith('Hash: ')) return null;
    hashes.addAll(
      line.substring('Hash: '.length).split(',').map((name) => name.trim()),
    );
  }
  index++;
  final textLines = <String>[];
  for (; index < lines.length; index++) {
    final line = lines[index];
    if (line.trimRight() == ArmorBlock.signature.begin) break;
    textLines.add(line.startsWith('- ') ? line.substring(2) : line);
  }
  if (index >= lines.length) return null;
  final signature = armorDecode(
    ArmorBlock.signature,
    lines.sublist(index).join('\n'),
  );
  if (signature == null) return null;
  return (hashes: hashes, text: textLines.join('\n'), signature: signature);
}

/// The text a cleartext signature really covers: each line without its trailing spaces and tabs, lines separated by line feeds.
String canonicalLines(String text) => text
    .replaceAll(_lineBreak, '\n')
    .split('\n')
    .map((line) => line.replaceFirst(_trailingWhitespace, ''))
    .join('\n');

/// The bytes a cleartext signature covers: [canonicalLines], with CR LF between lines.
Uint8List canonicalText(String text) =>
    utf8.encode(canonicalLines(text).replaceAll('\n', '\r\n'));

/// The CRC-24 of RFC 4880 section 6.1, as three bytes.
Uint8List _crc24(List<int> data) {
  var crc = 0xb704ce;
  for (final byte in data) {
    crc ^= byte << 16;
    for (var bit = 0; bit < 8; bit++) {
      crc <<= 1;
      if (crc & 0x1000000 != 0) crc ^= 0x1864cfb;
    }
  }
  return Uint8List.fromList([crc >> 16 & 0xff, crc >> 8 & 0xff, crc & 0xff]);
}
