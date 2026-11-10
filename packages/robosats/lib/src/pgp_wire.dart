final RegExp _carriageReturn = RegExp(r'\r\n?');

/// Puts an ASCII-armored block on one line, as RoboSats carries it in HTTP headers and JSON bodies: every line break becomes a backslash.
///
/// It reproduces `key.replace(/\r\n?/g, '\n').split('\n').join('\\')` of `frontend/src/models/Robot.model.ts:82-83` and the `PGP_message` field of `frontend/src/components/TradeBox/EncryptedChat/index.tsx:263`.
String pgpArmorToWire(String armored) =>
    armored.replaceAll(_carriageReturn, '\n').split('\n').join(r'\');

/// Restores the line breaks of a block received on one line: `split('\\').join('\n')` in the official client.
///
/// A block that already has its line breaks comes back unchanged, because base64 and armor lines never contain a backslash.
String pgpArmorFromWire(String wire) =>
    wire.replaceAll(r'\', '\n').replaceAll(_carriageReturn, '\n');
