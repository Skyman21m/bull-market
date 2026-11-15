import 'package:meta/meta.dart';
import 'package:robosats/robosats.dart';

/// The peer's key pinned for a trade's chat, by the two fingerprints that `PgpPublicKey` equality compares (#139): kept with the trade's record so that after a restart of the app the key served is compared with it instead of being trusted again.
///
/// Public data: the peer's key publishes both. It never holds the key, a message, or anything decrypted.
@immutable
final class ChatPinFingerprints {
  /// `PgpPublicKey.fingerprint`: 40 uppercase hexadecimal characters.
  final String primary;

  /// `PgpPublicKey.subkeyFingerprint`: 40 uppercase hexadecimal characters.
  final String subkey;

  const ChatPinFingerprints({required this.primary, required this.subkey});

  /// The fingerprints of [key].
  ChatPinFingerprints.of(PgpPublicKey key)
    : primary = key.fingerprint,
      subkey = key.subkeyFingerprint;

  /// Whether [key] is the key pinned: both its fingerprints are these.
  bool matches(PgpPublicKey key) =>
      key.fingerprint == primary && key.subkeyFingerprint == subkey;

  @override
  bool operator ==(Object other) =>
      other is ChatPinFingerprints &&
      other.primary == primary &&
      other.subkey == subkey;

  @override
  int get hashCode => Object.hash(primary, subkey);

  @override
  String toString() => 'ChatPinFingerprints($primary)';
}
