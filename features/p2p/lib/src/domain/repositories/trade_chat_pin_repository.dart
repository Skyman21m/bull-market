import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../p2p_failure.dart';
import '../trade/trade_chat_pin.dart';
import '../trade_record.dart';

/// The peer's public key each trade's chat pinned (#139, design note § 3.5, § 4.3), and the Nostr keys of its first Nostr copy (part of #159): the only things of the chat that are stored, so that a restart compares the keys served with them instead of trusting new ones.
///
/// One pin per trade, written once and never changed nor deleted: the database's triggers refuse anything else, and a pin is written only for an open trade.
/// Each method is one statement that commits on its own; never call it inside a database transaction.
/// It holds no secret: a public key and its two fingerprints, and two Nostr public keys.
abstract interface class TradeChatPinRepository {
  /// The peer key pinned for [trade]'s chat, `null` when its chat never pinned a key on this device (a trade of an older version of the app included).
  ///
  /// The key read back is parsed by the package's bounded parser and must give the two fingerprints stored with it. A database that cannot be read, a row this code never writes, or a key that does not parse or gives other fingerprints is a [P2pStorageFailure].
  Future<Result<PgpPublicKey?, P2pFailure>> pinOf(TradeRecord trade);

  /// Records [key] as [trade]'s pin, and gives the key pinned once the call is done: [key], whether this call wrote it or an earlier one did, or another key stored already, which is kept.
  ///
  /// A pin of a closed trade is refused by the database ([P2pStorageFailure]).
  Future<Result<PgpPublicKey, P2pFailure>> keep(
    TradeRecord trade,
    PgpPublicKey key,
  );

  /// The Nostr keys of [trade] pinned at its first Nostr copy, `null` when none was kept (part of #159).
  ///
  /// A database that cannot be read, or a row this code never writes, is a [P2pStorageFailure].
  Future<Result<ChatNostrPin?, P2pFailure>> nostrPinOf(TradeRecord trade);

  /// Records [pin] as [trade]'s Nostr pin: `true` once the pin stored is [pin], `false` when another is stored already, which is kept. A pin of a closed trade is refused by the database ([P2pStorageFailure]).
  Future<Result<bool, P2pFailure>> keepNostr(
    TradeRecord trade,
    ChatNostrPin pin,
  );
}
