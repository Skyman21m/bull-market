/// The Bitcoin network a RoboSats federation trades on.
///
/// Every coordinator runs one instance per network, at a different onion address and with a different Lightning node.
enum RobosatsNetwork {
  mainnet,
  testnet;

  /// The value of the `network` field of `/api/info/`, or `null` for any other value.
  static RobosatsNetwork? fromWire(String value) => switch (value) {
    'mainnet' => mainnet,
    'testnet' => testnet,
    _ => null,
  };
}
