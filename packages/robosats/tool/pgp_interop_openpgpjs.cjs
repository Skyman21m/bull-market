// The OpenPGP.js half of `tool/pgp_interop.sh`: it checks what the Dart code wrote and writes artefacts for the Dart code to read.
//
// Usage: node pgp_interop_openpgpjs.cjs <path to openpgp.min.js> <make|read> <directory>
// The calls are those of `frontend/src/pgp/index.ts` in the RoboSats repository (commit ff1998c).
const fs = require('fs');
const crypto = require('crypto');

const openpgp = require(process.argv[2]);
const phase = process.argv[3];
const directory = process.argv[4];
const read = (name) => fs.readFileSync(`${directory}/${name}`, 'utf8');
const write = (name, content) => fs.writeFileSync(`${directory}/${name}`, content);
const sha256Hex = (text) => crypto.createHash('sha256').update(text).digest('hex');
const oneDayAgo = () => {
  const d = new Date();
  return new Date(d.setDate(d.getDate() - 1));
};

let failures = 0;
const check = (condition, what) => {
  console.log(`${condition ? 'ok  ' : 'FAIL'} js:   ${what}`);
  if (!condition) failures++;
};
const attempt = async (what, action) => {
  try {
    check(await action(), what);
  } catch (error) {
    check(false, `${what} (${error.message})`);
  }
};

const unlock = async (privateKeyArmored, passphrase) =>
  openpgp.decryptKey({
    privateKey: await openpgp.readPrivateKey({ armoredKey: privateKeyArmored }),
    passphrase,
  });

// `decryptMessage` of the frontend.
const decryptMessage = async (encryptedMessage, publicKeyArmored, privateKey) => {
  const publicKey = await openpgp.readKey({ armoredKey: publicKeyArmored });
  const message = await openpgp.readMessage({ armoredMessage: encryptedMessage });
  const { data, signatures } = await openpgp.decrypt({
    message,
    verificationKeys: publicKey,
    decryptionKeys: privateKey,
  });
  try {
    await signatures[0].verified;
    return { decryptedMessage: String(data), validSignature: true };
  } catch (error) {
    return { decryptedMessage: String(data), validSignature: false, error: error.message };
  }
};

const verifyCleartext = async (signed, publicKeyArmored) => {
  const result = await openpgp.verify({
    message: await openpgp.readCleartextMessage({ cleartextMessage: signed }),
    verificationKeys: await openpgp.readKey({ armoredKey: publicKeyArmored }),
  });
  await result.signatures[0].verified;
  return result.data;
};

const make = async () => {
  const token = read('token');
  const publicArmored = read('troc_pub_key');
  const privateArmored = read('troc_enc_priv_key');
  const publicKey = await openpgp.readKey({ armoredKey: publicArmored });
  const locked = await openpgp.readPrivateKey({ armoredKey: privateArmored });
  let privateKey;
  await attempt('decryptKey: the token unlocks the private key', async () => {
    privateKey = await unlock(privateArmored, token);
    await privateKey.validate();
    return true;
  });
  await attempt('a wrong passphrase is refused', async () => {
    try {
      await unlock(privateArmored, `${token}x`);
      return false;
    } catch (error) {
      return true;
    }
  });
  check(
    publicKey.getUserIDs().join() === `RoboSats ID ${sha256Hex(sha256Hex(token))}`,
    'user ID is RoboSats ID <hash id>',
  );
  check(
    publicKey.getCreationTime().toISOString() === '2026-11-08T12:00:00.000Z',
    `creation time ${publicKey.getCreationTime().toISOString()}`,
  );
  await attempt('primary key, user and encryption subkey are valid', async () => {
    await publicKey.verifyPrimaryKey();
    await publicKey.getPrimaryUser();
    const encryptionKey = await publicKey.getEncryptionKey();
    return encryptionKey.getKeyID().toHex() === publicKey.getSubkeys()[0].getKeyID().toHex();
  });
  check(
    publicKey.armor().replace(/\r\n/g, '\n') === publicArmored &&
      locked.armor().replace(/\r\n/g, '\n') === privateArmored,
    'both blocks are byte-identical after a round trip through OpenPGP.js',
  );
  await attempt('the clear-signed invoice verifies, text identical', async () =>
    (await verifyCleartext(read('troc_invoice_signed.asc'), publicArmored)) === read('invoice.txt'));
  await attempt('the deterministic chat message decrypts as the sender, signature valid', async () => {
    const result = await decryptMessage(read('troc_chat_to_peer.asc'), publicArmored, privateKey);
    return result.decryptedMessage === read('chat.txt') && result.validSignature;
  });

  // `genKey` of the frontend, for a second robot.
  const peerToken = read('openpgpjs_token');
  const keyPair = await openpgp.generateKey({
    type: 'ecc',
    curve: 'curve25519',
    userIDs: [{ name: `RoboSats ID ${sha256Hex(sha256Hex(peerToken))}` }],
    passphrase: peerToken,
    format: 'armored',
    date: oneDayAgo(),
  });
  write('openpgpjs_peer_pub_key', String(keyPair.publicKey));
  write('openpgpjs_peer_enc_priv_key', String(keyPair.privateKey));
  const peerPrivateKey = await unlock(String(keyPair.privateKey), peerToken);
  const peerPublicKey = await openpgp.readKey({ armoredKey: String(keyPair.publicKey) });

  // `signCleartextMessage` of the frontend, then what OpenPGP.js itself returns as the signed text.
  const texts = {
    openpgpjs_clearsigned: read('invoice.txt'),
    openpgpjs_clearsigned_lines: 'première ligne\n-dash line\ntrailing space \t\n\nlast ⚡',
  };
  for (const [name, text] of Object.entries(texts)) {
    const signed = await openpgp.sign({
      message: await openpgp.createCleartextMessage({ text }),
      signingKeys: peerPrivateKey,
    });
    write(`${name}.asc`, signed);
    write(`${name}.expected.txt`, await verifyCleartext(signed, String(keyPair.publicKey)));
  }

  // `encryptMessage` of the frontend.
  const encrypt = async (signingKeys) =>
    String(
      await openpgp.encrypt({
        message: await openpgp.createMessage({ text: read('chat.txt') }),
        encryptionKeys: [peerPublicKey, publicKey],
        signingKeys,
        date: oneDayAgo(),
      }),
    );
  write('openpgpjs_chat_to_troc.asc', await encrypt(peerPrivateKey));
  write('openpgpjs_chat_unsigned.asc', await encrypt(undefined));
  console.log(`ok   js:   ${openpgp.config.versionString} wrote a key, two clear-signed texts and two chat messages`);
};

const readBack = async () => {
  const peerPrivateKey = await unlock(read('openpgpjs_peer_enc_priv_key'), read('openpgpjs_token'));
  await attempt('the chat message from the robot decrypts as the peer, signature valid', async () => {
    const result = await decryptMessage(read('troc_chat_to_openpgpjs.asc'), read('troc_pub_key'), peerPrivateKey);
    if (!result.validSignature) console.log(`     ${result.error}`);
    return result.decryptedMessage === read('chat.txt') && result.validSignature;
  });
  await attempt('checked against another key, the same message is flagged', async () => {
    const result = await decryptMessage(
      read('troc_chat_to_openpgpjs.asc'),
      read('openpgpjs_peer_pub_key'),
      peerPrivateKey,
    );
    return result.decryptedMessage === read('chat.txt') && !result.validSignature;
  });
  await attempt('a text the Dart code clear-signed with the OpenPGP.js key verifies', async () =>
    (await verifyCleartext(read('troc_clearsigned_by_openpgpjs_key.asc'), read('openpgpjs_peer_pub_key'))) ===
    read('invoice.txt'));
};

(phase === 'make' ? make() : readBack())
  .then(() => process.exit(failures ? 1 : 0))
  .catch((error) => {
    console.error('FAIL js:   crashed', error);
    process.exit(2);
  });
