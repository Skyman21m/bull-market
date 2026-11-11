/// Where a Garage Key is kept: one per network, so that tests on testnet never use the identity of real trades.
///
/// The names written to the keystore belong to the data layer and are frozen there; renaming a value here does not move a stored key.
enum GarageKeySlot { mainnet, testnet }
