// The Dart half of `tool/pgp_interop.sh`: it writes OpenPGP artefacts for GnuPG and OpenPGP.js to check, and checks the ones they wrote.
//
// Run it from `packages/robosats`: `fvm dart run tool/pgp_interop.dart <emit|encrypt|check> <directory>`.
// Every key here is test material derived from public tokens of the RoboSats repository.
import 'dart:io';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../test/support/pgp.dart';

late final Directory _directory;

String _read(String name) =>
    File('${_directory.path}/$name').readAsStringSync();

bool _has(String name) => File('${_directory.path}/$name').existsSync();

void _write(String name, String content) =>
    File('${_directory.path}/$name').writeAsStringSync(content);

void main(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln('usage: pgp_interop.dart <emit|encrypt|check> <directory>');
    exit(64);
  }
  _directory = Directory(arguments[1]);
  final key = generateInteropKey();
  final unlocked = _ok(key.unlock(interopIdentity), 'unlock the generated key');

  switch (arguments[0]) {
    case 'emit':
      _write('token', interopIdentity.token.reveal());
      _write('openpgpjs_token', interopOpenPgpJsIdentity.token.reveal());
      _write('troc_pub_key', key.publicKey.armored);
      _write('troc_enc_priv_key', key.encryptedPrivateKeyArmored);
      _write('invoice.txt', interopInvoice);
      _write(
        'troc_invoice_signed.asc',
        _ok(
          unlocked.signCleartext(interopInvoice, now: interopNow),
          'clear-sign the invoice',
        ),
      );
      _write('chat.txt', interopChatText);
      _write('chat_long.txt', interopLongChatText);
      _write('gpg_protected_token', interopPeerIdentity.token.reveal());
      _write('troc_chat_to_peer.asc', encryptInteropChatMessage(unlocked));
      stdout
        ..writeln('ok   dart: encrypt and sign the deterministic chat message')
        ..writeln('fingerprint ${key.publicKey.fingerprint}')
        ..writeln('user id     ${key.publicKey.userId}')
        ..writeln('created     ${key.publicKey.createdAt.toIso8601String()}');
    case 'encrypt':
      // The keys GnuPG and OpenPGP.js just generated are dated today: the real clock applies.
      final now = DateTime.now();
      for (final peerName in ['gpg', 'openpgpjs']) {
        if (!_has('${peerName}_peer_pub_key')) continue;
        final peer = _ok(
          PgpPublicKey.parse(_read('${peerName}_peer_pub_key')),
          'read the public key $peerName generated',
        );
        _write(
          'troc_chat_to_$peerName.asc',
          _ok(
            unlocked.encryptChatMessage(interopChatText, peer: peer, now: now),
            'encrypt and sign the chat message to $peerName',
          ),
        );
      }
      if (_has('openpgpjs_peer_enc_priv_key')) {
        final jsKey = _ok(
          RobotPgpKey.parse(
            publicKey: _read('openpgpjs_peer_pub_key'),
            encryptedPrivateKey: _read('openpgpjs_peer_enc_priv_key'),
          ),
          'read the key pair OpenPGP.js generated',
        );
        _check(
          jsKey.isNamedAfter(interopOpenPgpJsIdentity),
          'the key OpenPGP.js generated is named after its token',
        );
        final jsUnlocked = _ok(
          jsKey.unlock(interopOpenPgpJsIdentity),
          'unlock the key OpenPGP.js generated with its token',
        );
        _write(
          'troc_clearsigned_by_openpgpjs_key.asc',
          _ok(
            jsUnlocked.signCleartext(interopInvoice, now: now),
            'clear-sign with the key OpenPGP.js generated',
          ),
        );
      }
      stdout.writeln(
        'signed at   ${now.millisecondsSinceEpoch ~/ 1000 - 86400}',
      );
    case 'check':
      _checkGnuPg(key, unlocked);
      if (_has('openpgpjs_peer_pub_key')) _checkOpenPgpJs(key, unlocked);
    default:
      stderr.writeln('unknown command ${arguments[0]}');
      exit(64);
  }
}

void _checkGnuPg(RobotPgpKey key, UnlockedRobotPgpKey unlocked) {
  final peer = _ok(
    PgpPublicKey.parse(_read('gpg_peer_pub_key')),
    'read the public key GnuPG generated',
  );
  final reexported = _ok(
    PgpPublicKey.parse(_read('troc_pub_key_reexported_by_gpg')),
    'read the public key as GnuPG exports it again',
  );
  _check(
    reexported == key.publicKey,
    'the key GnuPG exports again is the generated key',
  );
  _check(
    _ok(
          key.publicKey.verifyCleartext(
            _read('gpg_clearsigned_by_troc_key.asc'),
          ),
          'verify the text GnuPG clear-signed with the generated key',
        ) ==
        interopInvoice,
    'the text GnuPG clear-signed is the invoice',
  );
  final decrypted = _ok(
    unlocked.decryptChatMessage(_read('gpg_chat_to_troc.asc'), sender: peer),
    'decrypt the message GnuPG encrypted and signed',
  );
  _check(
    decrypted.text == interopChatText && decrypted.validSignature,
    'the message GnuPG encrypted is the chat text, signed by the peer',
  );
  final long = _ok(
    unlocked.decryptChatMessage(
      _read('gpg_chat_long_to_troc.asc'),
      sender: peer,
    ),
    'decrypt the long message GnuPG framed with partial lengths',
  );
  _check(
    long.text == interopLongChatText && long.validSignature,
    'the long message is the long chat text, signed by the peer',
  );
  final protected = _ok(
    RobotPgpKey.parse(
      publicKey: _read('gpg_protected_pub_key'),
      encryptedPrivateKey: _read('gpg_protected_enc_priv_key'),
    ),
    'read a key pair GnuPG generated and protected with a passphrase',
  );
  _ok(
    protected.unlock(interopPeerIdentity),
    'unlock the private key GnuPG protected (S2K count 255)',
  );
  final own = _ok(
    unlocked.decryptChatMessage(
      _read('troc_chat_to_gpg.asc'),
      sender: key.publicKey,
    ),
    'decrypt the own copy of the message sent to GnuPG',
  );
  _check(
    own.text == interopChatText && own.validSignature,
    'the own copy reads back, signature valid',
  );
}

void _checkOpenPgpJs(RobotPgpKey key, UnlockedRobotPgpKey unlocked) {
  final peer = _ok(
    PgpPublicKey.parse(_read('openpgpjs_peer_pub_key')),
    'read the public key OpenPGP.js generated',
  );
  for (final name in ['openpgpjs_clearsigned', 'openpgpjs_clearsigned_lines']) {
    _check(
      _ok(
            peer.verifyCleartext(_read('$name.asc')),
            'verify $name, clear-signed by OpenPGP.js',
          ) ==
          _read('$name.expected.txt'),
      '$name: the text returned is the text OpenPGP.js returns',
    );
  }
  final signed = _ok(
    unlocked.decryptChatMessage(
      _read('openpgpjs_chat_to_troc.asc'),
      sender: peer,
    ),
    'decrypt the message OpenPGP.js encrypted and signed',
  );
  _check(
    signed.text == interopChatText && signed.validSignature,
    'the message OpenPGP.js encrypted is the chat text, signed by the peer',
  );
  final unsigned = _ok(
    unlocked.decryptChatMessage(
      _read('openpgpjs_chat_unsigned.asc'),
      sender: peer,
    ),
    'decrypt the unsigned message OpenPGP.js encrypted',
  );
  _check(
    unsigned.text == interopChatText && !unsigned.validSignature,
    'the unsigned message is shown and flagged',
  );
}

T _ok<T, F extends Failure>(Result<T, F> result, String what) {
  switch (result) {
    case Ok(:final value):
      stdout.writeln('ok   dart: $what');
      return value;
    case Err(:final failure):
      stdout.writeln('FAIL dart: $what ($failure)');
      exit(1);
  }
}

void _check(bool condition, String what) {
  stdout.writeln('${condition ? 'ok  ' : 'FAIL'} dart: $what');
  if (!condition) exit(1);
}
