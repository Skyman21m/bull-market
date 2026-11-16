import 'package:meta/meta.dart';

/// The Nostr keys of a trade pinned at its first Nostr copy (#94, review of #158), the peer's and this robot's, as the order gives them: kept with the trade's record with its PGP pin (#139, part of #159), so that after a restart a key the order changes is caught as within one run.
///
/// Not secret: public keys the coordinator publishes to both parties, 64 lowercase hexadecimal characters each.
@immutable
final class ChatNostrPin {
  final String peer;
  final String own;

  const ChatNostrPin({required this.peer, required this.own});

  @override
  bool operator ==(Object other) =>
      other is ChatNostrPin && other.peer == peer && other.own == own;

  @override
  int get hashCode => Object.hash(peer, own);

  @override
  String toString() => 'ChatNostrPin(${peer.substring(0, 8)}…)';
}
