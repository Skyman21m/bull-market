import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;
import 'package:secrets/secrets.dart' show GarageKeyMaterial;

/// What the shell lends the P2P feature so that the Garage Key is the BIP85 child of the default wallet's words (#81, design note `docs/design/garage-key-from-the-words.md` § 1, § 2).
///
/// The shell implements it in `lib/features/p2p_garage_key/` and passes it to `P2pFeature.setup` in the foreground composition only, under the same flag as the vault's Garage Key handle; the custody gate names that implementation as the only caller of `secret.derive.garageKey` in the app.
/// The key is derived on each call and stored nowhere: the feature holds what it returns no longer than the vault's handle's reads, and only `GarageKeyRepositoryImpl` reads its bytes.
/// It never falls back to a key drawn at random: every case where the words cannot give the key is a [P2pGarageKeyRefusal].
abstract interface class P2pGarageKeyPort {
  /// The Garage Key of [index] on [network], from the words of the default Bitcoin wallet of that network's environment, or why it cannot be given.
  ///
  /// [index] is from 0 to 0x7fffffff; anything else is an [ArgumentError], before any keystore read.
  /// Nothing is written, logged or sent.
  Future<Result<GarageKeyMaterial, P2pGarageKeyRefusal>> garageKey(
    RobosatsNetwork network, {
    required int index,
  });
}

/// Why the words cannot give the Garage Key: a type with its [reason], never a text of the vault, and never a reason to draw a key at random.
final class P2pGarageKeyRefusal extends Failure {
  final P2pGarageKeyRefusalReason reason;

  const P2pGarageKeyRefusal(this.reason);

  @override
  bool operator ==(Object other) =>
      other is P2pGarageKeyRefusal && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;
}

/// What [P2pGarageKeyRefusal] says.
enum P2pGarageKeyRefusalReason {
  /// No default Bitcoin wallet on that network's environment.
  noDefaultWallet,

  /// The default wallet has a BIP39 passphrase: the words alone would not give the key back.
  passphrase,

  /// The default wallet's secret is a seed without words.
  noWords,

  /// The keystore is locked for now: the device must be unlocked.
  locked,

  /// The wallet or its secret could not be read.
  unreadable,
}
