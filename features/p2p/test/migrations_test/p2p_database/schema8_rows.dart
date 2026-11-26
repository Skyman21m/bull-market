/// The rows of a file of schema 8 of `p2p.sqlite` that holds every shape of row a user's file of the APKs given out can hold (#204, #231, #233): the file `schema9_migration_test.dart` steps to schema 9, and `schema10_migration_test.dart` to schema 10 (#81, review of #292, C-mig). Fixed test text: no key, invoice or robot anyone holds.
library;

/// A key fingerprint of the rows: fixed test text, not a key anyone uses.
final schema8Key = 'ab' * 32;

/// A key fingerprint of a key acknowledged here.
final _otherKey = 'cd' * 32;

/// Payment hashes and hash ids of the rows: fixed test text, none an invoice anyone paid nor a robot anyone holds.
final _bondOfOne = '1b' * 32;
final _bondOfTwo = '2b' * 32;
final _escrowOfTwo = '2e' * 32;
final _bondOfSix = '6b' * 32;
final _bondOfSeven = '7b' * 32;
final _escrowOfSeven = '7e' * 32;
final schema8EscrowOfSevenNext = '7f' * 32;
final _takerA = 'a0' * 32;
final _takerB = 'b0' * 32;

const _armored = '-----BEGIN PGP PUBLIC KEY BLOCK-----\n\nnot a key';

const _trades =
    'INSERT INTO trades (network, key_fingerprint, robot_index, coordinator_alias, coordinator_onion, order_id, role, origin, taken_at, confirmed_at, closed_at) VALUES ';
const schema8Trails = 'INSERT INTO trade_trails VALUES ';
const schema8Payments =
    'INSERT INTO trade_payments (key_fingerprint, robot_index, step, payment_hash, started_at, wallet_payment_id, take) VALUES ';
const _makerTerms =
    'INSERT INTO maker_terms (key_fingerprint, robot_index, version, network, coordinator_alias, role, order_type, currency_id, amount, min_amount, max_amount, premium_percent, payment_method, bond_size_percent, public_seconds, escrow_seconds, description, has_password, latitude, longitude, created_price, maker_fee) VALUES ';

/// The rows of the file of schema 8, written in the order the app writes them through schema 8's triggers.
final schema8Rows = [
  "INSERT INTO garage_key_histories VALUES ('testnet', '$schema8Key', 'generated', 1)",
  "INSERT INTO garage_key_histories VALUES ('testnet', '$_otherKey', 'acknowledged', 3)",
  for (var index = 0; index <= 10; index++)
    "INSERT INTO robot_bindings VALUES ('testnet', '$schema8Key', $index, 'temple', 'http://temple.onion', 'node1,node2', 'nostr$index', ${10 + index}, 'generated')",
  "INSERT INTO robot_bindings VALUES ('testnet', '$_otherKey', 0, 'lake', 'http://lake.onion', '', 'nostr', 30, 'acknowledged')",
  // Robot 0: a taker buyer's pending take, its terms and its first trail: no payout yet, no mark.
  "$_trades('testnet', '$schema8Key', 0, 'temple', 'http://temple.onion', 100, 'buyer', 'takenHere', 1000, NULL, NULL)",
  "INSERT INTO trade_terms VALUES ('$schema8Key', 0, 1, 'testnet', 'temple', 100, 'buyer', 1, 2, 100.0, 0, 2.0, NULL, 3.0, 10800, 93545.25, 0.00175)",
  "$schema8Trails('$schema8Key', 0, 1, 'testnet', 'temple', 100, 'buyer', 'start', 1000000, NULL, NULL, NULL, NULL, NULL, 0, 0, 0, NULL, NULL, NULL, '', 0)",
  // Robot 1: a taker buyer's trade at its payout, its bond paid from the wallet: marked.
  "$_trades('testnet', '$schema8Key', 1, 'temple', 'http://temple.onion', 101, 'buyer', 'takenHere', 1100, 1150, NULL)",
  "INSERT INTO trade_terms VALUES ('$schema8Key', 1, 1, 'testnet', 'temple', 101, 'buyer', 1, 3, 123.45, 1, -1.5, NULL, 3.5, 7200, 87654.321, 0.002)",
  "$schema8Trails('$schema8Key', 1, 1, 'testnet', 'temple', 101, 'buyer', 'bondStep', 1100000, '$_bondOfOne', NULL, 1400000000, 1100000, 1400000000, 0, 0, 0, NULL, NULL, NULL, '', 0)",
  "$schema8Payments('$schema8Key', 1, 'bond', '$_bondOfOne', 1120000, 'swap-1', 0)",
  "UPDATE trade_trails SET position = 'waitingForPayout', read_at = 1200000, deadline = 1900000000 WHERE robot_index = 1 AND key_fingerprint = '$schema8Key'",
  // Robot 2: a taker seller in its chat, bond and escrow paid, the peer's keys pinned: no mark.
  "$_trades('testnet', '$schema8Key', 2, 'temple', 'http://temple.onion', 102, 'seller', 'takenHere', 1200, 1250, NULL)",
  "INSERT INTO trade_terms VALUES ('$schema8Key', 2, 1, 'testnet', 'temple', 102, 'seller', 0, 1, 50.0, 0, 0.0, 21000, 2.0, 36000, 60000.5, 0.0)",
  "$schema8Trails('$schema8Key', 2, 1, 'testnet', 'temple', 102, 'seller', 'bondStep', 1250000, '$_bondOfTwo', NULL, NULL, 1250000, NULL, 0, 0, 0, NULL, NULL, NULL, '', 0)",
  "$schema8Payments('$schema8Key', 2, 'bond', '$_bondOfTwo', 1260000, NULL, 0)",
  "UPDATE trade_trails SET position = 'waitingForEscrow', read_at = 1300000, escrow_hash = '$_escrowOfTwo', deadline = 2000000000 WHERE robot_index = 2 AND key_fingerprint = '$schema8Key'",
  "$schema8Payments('$schema8Key', 2, 'escrow', '$_escrowOfTwo', 1310000, 'swap-2', 0)",
  "UPDATE trade_trails SET position = 'chatting', read_at = 1400000 WHERE robot_index = 2 AND key_fingerprint = '$schema8Key'",
  "INSERT INTO trade_chat_pins VALUES ('$schema8Key', 2, '${'A' * 40}', '${'B' * 40}', '$_armored')",
  "INSERT INTO trade_chat_nostr_pins VALUES ('$schema8Key', 2, '${'a' * 64}', '${'b' * 64}')",
  // Robot 3: a pending take that never left, closed with no terms and no trail.
  "$_trades('testnet', '$schema8Key', 3, 'temple', 'http://temple.onion', 103, 'buyer', 'takenHere', 1300, NULL, NULL)",
  "UPDATE trades SET closed_at = 1301 WHERE robot_index = 3 AND key_fingerprint = '$schema8Key'",
  // Robot 0 of the acknowledged key: a seller's trade recovered, a breach recorded: no mark.
  "$_trades('testnet', '$_otherKey', 0, 'lake', 'http://lake.onion', 105, 'seller', 'recovered', 1500, 1500, NULL)",
  "INSERT INTO trade_terms VALUES ('$_otherKey', 0, 1, 'testnet', 'lake', 105, 'seller', 0, 5, 1.0, 0, 5.25, NULL, 2.5, 3600, 1.5, 0.001)",
  "$schema8Trails('$_otherKey', 0, 1, 'testnet', 'lake', 105, 'seller', 'start', 1500000, NULL, NULL, NULL, NULL, NULL, 0, 1, 0, NULL, NULL, NULL, '', 0)",
  "UPDATE trade_trails SET position = 'waitingForBoth', read_at = 1600000, breached = 1 WHERE key_fingerprint = '$_otherKey'",
  // Robot 5: a pending make, its terms and no trail: no mark.
  "$_trades('testnet', '$schema8Key', 5, 'temple', 'http://temple.onion', NULL, 'buyer', 'madeHere', 1650, NULL, NULL)",
  "$_makerTerms('$schema8Key', 5, 1, 'testnet', 'temple', 'buyer', 0, 2, 100.0, NULL, NULL, 2.0, 'Revolut', 3.0, 86400, 10800, NULL, 0, NULL, NULL, 50000.0, 0.00025)",
  // Robot 6: a maker buyer's order taken, back in the book, taken again: contract 1 at its payout, marked at contract 1.
  "$_trades('testnet', '$schema8Key', 6, 'temple', 'http://temple.onion', NULL, 'buyer', 'madeHere', 1700, NULL, NULL)",
  "$_makerTerms('$schema8Key', 6, 1, 'testnet', 'temple', 'buyer', 0, 1, NULL, 20.0, 200.0, -1.25, 'SEPA Instant', 5.5, 3600, 7200, 'Fast', 1, 48.857, 2.352, 45000.5, 0.0)",
  "UPDATE trades SET order_id = 107, confirmed_at = 1750 WHERE robot_index = 6 AND key_fingerprint = '$schema8Key'",
  "$schema8Trails('$schema8Key', 6, 1, 'testnet', 'temple', 107, 'buyer', 'makerBondStep', 1750000, '$_bondOfSix', NULL, 1800000000, NULL, NULL, 0, 0, 0, NULL, NULL, NULL, '', 0)",
  "$schema8Payments('$schema8Key', 6, 'bond', '$_bondOfSix', 1760000, 'swap-6', 0)",
  "UPDATE trade_trails SET position = 'public', read_at = 1770000 WHERE robot_index = 6 AND key_fingerprint = '$schema8Key'",
  "UPDATE trade_trails SET position = 'waitingForBoth', read_at = 1780000, take_deadline = 1800000000, taker_hash_id = '$_takerA', taken_amount = 150.0 WHERE robot_index = 6 AND key_fingerprint = '$schema8Key'",
  "UPDATE trade_trails SET position = 'public', read_at = 1790000 WHERE robot_index = 6 AND key_fingerprint = '$schema8Key'",
  "UPDATE trade_trails SET position = 'waitingForPayout', read_at = 1795000, take = 1, take_deadline = 1900000000, taker_hash_id = '$_takerB', taken_amount = 50.0 WHERE robot_index = 6 AND key_fingerprint = '$schema8Key'",
  // Robot 7: a maker seller's order taken again, contract 0's escrow paid before schema 9, contract 1's too: no mark, its escrows' amounts unknown.
  "$_trades('testnet', '$schema8Key', 7, 'temple', 'http://temple.onion', NULL, 'seller', 'madeHere', 1800, NULL, NULL)",
  "$_makerTerms('$schema8Key', 7, 1, 'testnet', 'temple', 'seller', 1, 2, 100.0, NULL, NULL, 2.0, 'Revolut', 3.0, 86400, 10800, NULL, 0, NULL, NULL, 50000.0, 0.00025)",
  "UPDATE trades SET order_id = 108, confirmed_at = 1850 WHERE robot_index = 7 AND key_fingerprint = '$schema8Key'",
  "$schema8Trails('$schema8Key', 7, 1, 'testnet', 'temple', 108, 'seller', 'makerBondStep', 1850000, '$_bondOfSeven', NULL, 1800000000, NULL, NULL, 0, 0, 0, NULL, NULL, NULL, '', 0)",
  "$schema8Payments('$schema8Key', 7, 'bond', '$_bondOfSeven', 1860000, 'swap-7', 0)",
  "UPDATE trade_trails SET position = 'public', read_at = 1870000 WHERE robot_index = 7 AND key_fingerprint = '$schema8Key'",
  "UPDATE trade_trails SET position = 'waitingForEscrow', read_at = 1880000, escrow_hash = '$_escrowOfSeven', take_deadline = 1800000000, taker_hash_id = '$_takerA' WHERE robot_index = 7 AND key_fingerprint = '$schema8Key'",
  "$schema8Payments('$schema8Key', 7, 'escrow', '$_escrowOfSeven', 1885000, 'swap-7e', 0)",
  "UPDATE trade_trails SET position = 'public', read_at = 1890000 WHERE robot_index = 7 AND key_fingerprint = '$schema8Key'",
  "UPDATE trade_trails SET position = 'waitingForEscrow', read_at = 1895000, take = 1, escrow_hash = '$schema8EscrowOfSevenNext', take_deadline = 1900000000, taker_hash_id = '$_takerB', earlier_escrows = '$_escrowOfSeven;' WHERE robot_index = 7 AND key_fingerprint = '$schema8Key'",
  "$schema8Payments('$schema8Key', 7, 'escrow', '$schema8EscrowOfSevenNext', 1897000, NULL, 1)",
  // Robot 8: a maker buyer's order cancelled at its bond and closed: marked (its end says nothing of a payout).
  "$_trades('testnet', '$schema8Key', 8, 'temple', 'http://temple.onion', NULL, 'buyer', 'madeHere', 1900, NULL, NULL)",
  "$_makerTerms('$schema8Key', 8, 1, 'testnet', 'temple', 'buyer', 0, 2, 10.0, NULL, NULL, 0.0, 'Cash', 2.0, 600, 1800, NULL, 0, NULL, NULL, 0.0001, 0.01)",
  "UPDATE trades SET order_id = 109, confirmed_at = 1950 WHERE robot_index = 8 AND key_fingerprint = '$schema8Key'",
  "$schema8Trails('$schema8Key', 8, 1, 'testnet', 'temple', 109, 'buyer', 'makerBondStep', 1950000, NULL, NULL, 1960000000, NULL, NULL, 0, 0, 0, NULL, NULL, NULL, '', 0)",
  "UPDATE trade_trails SET position = 'cancelled', read_at = 1960000 WHERE robot_index = 8 AND key_fingerprint = '$schema8Key'",
  "UPDATE trades SET closed_at = 1960 WHERE robot_index = 8 AND key_fingerprint = '$schema8Key'",
  // Robot 9: a taker buyer's trade at « fiat sent »: marked.
  "$_trades('testnet', '$schema8Key', 9, 'temple', 'http://temple.onion', 110, 'buyer', 'takenHere', 2000, 2050, NULL)",
  "INSERT INTO trade_terms VALUES ('$schema8Key', 9, 1, 'testnet', 'temple', 110, 'buyer', 1, 2, 75.0, 0, 1.0, NULL, 3.0, 10800, 61000.0, 0.00175)",
  "$schema8Trails('$schema8Key', 9, 1, 'testnet', 'temple', 110, 'buyer', 'chatting', 2050000, NULL, NULL, 2100000000, NULL, NULL, 0, 0, 0, NULL, NULL, NULL, '', 0)",
  "UPDATE trade_trails SET position = 'fiatSent', read_at = 2060000 WHERE robot_index = 9 AND key_fingerprint = '$schema8Key'",
  // Robot 10: bound, no trade.
];
