/// Where a Garage Key is kept: one per network, so that tests on testnet never use the identity of real trades. Also the network of a Garage Key derived from a secret's words, `0'` for mainnet and `1'` for testnet in its BIP85 path.
///
/// The names written to the keystore belong to the data layer and are frozen there; renaming a value here does not move a stored key.
enum GarageKeySlot { mainnet, testnet }
