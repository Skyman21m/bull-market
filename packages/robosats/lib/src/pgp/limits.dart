/// Hard bounds on what this package reads, so that no input from a coordinator or a peer can cost more than a fixed amount of time and memory.
///
/// Every bound is far above what the official client and GnuPG produce for a robot.
abstract final class PgpLimits {
  /// Characters of an armored key block: a robot key takes about 1 000.
  static const keyArmorChars = 20000;

  /// Packets in a key block: a robot key has 5.
  static const keyPackets = 32;

  /// Characters of a cleartext signed message: a coordinator accepts at most 15 000 (`api/serializers.py:638-659`).
  static const cleartextChars = 20000;

  /// Characters of an armored chat message, and UTF-8 bytes of the text of one.
  static const messageArmorChars = 65536;
  static const messageTextBytes = 30000;

  /// Session key packets in a chat message: the official client writes 2.
  static const sessionKeyPackets = 8;

  /// Signature packets next to a text, and one-pass signature packets in a chat message: the official client writes 1.
  static const signatures = 8;

  /// Bytes a compressed chat message may inflate to.
  static const decompressedBytes = 262144;

  /// Bytes an iterated S2K can hash at most: the format itself stops at 65 011 712, the count GnuPG 2.4 writes, four times what OpenPGP.js 5 asks for.
  static const s2kBytes = 65011712;
}
