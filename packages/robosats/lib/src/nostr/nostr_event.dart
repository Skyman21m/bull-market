import 'dart:convert';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// A Nostr event (NIP-01), unsigned (a NIP-59 rumor) or signed.
///
/// Serialized as `nostr-tools` 2.25.2 serializes it, byte for byte: the id is the SHA-256 of `JSON.stringify([0, pubkey, created_at, kind, tags, content])` (`serializeEvent` of `pure.ts`), and the JSON of an event keeps the order in which `nostr-tools` builds its fields, so that what this package sends reads as what the official client sends.
@immutable
final class NostrEvent {
  final int kind;
  final String content;
  final int createdAt;
  final List<List<String>> tags;
  final String pubkey;
  final String id;

  /// The BIP-340 signature, 128 lowercase hexadecimal characters, or `null` for a rumor, which NIP-59 never signs.
  final String? sig;

  /// The order of the fields in [toJson]: a rumor as `createRumor` builds it, a signed event as `finalizeEvent` completes its template.
  final List<String> _fieldOrder;

  NostrEvent._(
    this.kind,
    this.content,
    this.createdAt,
    this.tags,
    this.pubkey,
    this.id,
    this.sig,
    this._fieldOrder,
  );

  /// A rumor: an event of [pubkey] with its id and no signature (`createRumor` of `nip59.ts`).
  factory NostrEvent.rumor({
    required int kind,
    required String content,
    required int createdAt,
    required List<List<String>> tags,
    required String pubkey,
  }) => NostrEvent._(
    kind,
    content,
    createdAt,
    _frozen(tags),
    pubkey,
    idOf(pubkey, createdAt, kind, tags, content),
    null,
    const ['created_at', 'content', 'tags', 'kind', 'pubkey', 'id'],
  );

  /// A signed event: [signature] signs [id], which the caller computed with [idOf] for these very fields.
  @internal
  factory NostrEvent.signed({
    required int kind,
    required String content,
    required int createdAt,
    required List<List<String>> tags,
    required String pubkey,
    required String id,
    required String signature,
  }) => NostrEvent._(
    kind,
    content,
    createdAt,
    _frozen(tags),
    pubkey,
    id,
    signature,
    const ['kind', 'content', 'created_at', 'tags', 'pubkey', 'id', 'sig'],
  );

  /// The id of an event with these fields: lowercase hexadecimal SHA-256 of its NIP-01 serialization.
  static String idOf(
    String pubkey,
    int createdAt,
    int kind,
    List<List<String>> tags,
    String content,
  ) => hex.encode(
    sha256
        .convert(
          utf8.encode(stringify([0, pubkey, createdAt, kind, tags, content])),
        )
        .bytes,
  );

  /// The JSON object of the event, as `JSON.stringify` writes it in the official client.
  String toJson() => stringify({
    for (final field in _fieldOrder)
      field: switch (field) {
        'kind' => kind,
        'content' => content,
        'created_at' => createdAt,
        'tags' => tags,
        'pubkey' => pubkey,
        'id' => id,
        _ => sig,
      },
  });

  /// [value] as `JSON.stringify` of JavaScript writes it, for the values events are made of: strings, integers, lists and maps with string keys.
  ///
  /// Differs from `jsonEncode` where it matters for an id: a lone surrogate is written as a `\uXXXX` escape in lowercase hexadecimal (well-formed `JSON.stringify`, ES2019), the other control characters as `JSON.stringify` writes them, and nothing else is escaped.
  static String stringify(Object? value) {
    final out = StringBuffer();
    _write(out, value);
    return out.toString();
  }

  static void _write(StringBuffer out, Object? value) {
    switch (value) {
      case null:
        out.write('null');
      case final int number:
        out.write(number);
      case final String text:
        _writeString(out, text);
      case final List<Object?> list:
        out.write('[');
        for (var i = 0; i < list.length; i++) {
          if (i > 0) out.write(',');
          _write(out, list[i]);
        }
        out.write(']');
      case final Map<String, Object?> map:
        out.write('{');
        var first = true;
        for (final entry in map.entries) {
          if (!first) out.write(',');
          first = false;
          _writeString(out, entry.key);
          out.write(':');
          _write(out, entry.value);
        }
        out.write('}');
      default:
        throw ArgumentError('not a value of a Nostr event');
    }
  }

  static void _writeString(StringBuffer out, String text) {
    out.write('"');
    final units = text.codeUnits;
    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      switch (unit) {
        case 0x22:
          out.write(r'\"');
        case 0x5c:
          out.write(r'\\');
        case 0x08:
          out.write(r'\b');
        case 0x09:
          out.write(r'\t');
        case 0x0a:
          out.write(r'\n');
        case 0x0c:
          out.write(r'\f');
        case 0x0d:
          out.write(r'\r');
        default:
          if (unit < 0x20) {
            out.write(_unicodeEscape(unit));
          } else if (unit >= 0xd800 && unit <= 0xdbff) {
            final next = i + 1 < units.length ? units[i + 1] : 0;
            if (next >= 0xdc00 && next <= 0xdfff) {
              out.writeCharCode(unit);
              out.writeCharCode(next);
              i++;
            } else {
              out.write(_unicodeEscape(unit));
            }
          } else if (unit >= 0xdc00 && unit <= 0xdfff) {
            out.write(_unicodeEscape(unit));
          } else {
            out.writeCharCode(unit);
          }
      }
    }
    out.write('"');
  }

  static String _unicodeEscape(int unit) =>
      '\\u${unit.toRadixString(16).padLeft(4, '0')}';

  static List<List<String>> _frozen(List<List<String>> tags) =>
      List.unmodifiable([
        for (final tag in tags) List<String>.unmodifiable(tag),
      ]);

  /// Prints the kind and id only: never the content, which may be a message or a ciphertext.
  @override
  String toString() => 'NostrEvent(kind: $kind, id: $id)';
}
