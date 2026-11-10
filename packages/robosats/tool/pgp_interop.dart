// The Dart half of `tool/pgp_interop.sh`: it writes OpenPGP artefacts for GnuPG to check, and checks the ones GnuPG wrote.
//
// Run it from `packages/robosats`: `fvm dart run tool/pgp_interop.dart <emit|encrypt|check> <directory>`.
// Every key here is test material derived from the public example Garage Key of the RoboSats repository.
import 'dart:io';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../test/support/pgp.dart';

void main(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln('usage: pgp_interop.dart <emit|encrypt|check> <directory>');
    exit(64);
  }
  final directory = Directory(arguments[1]);
  String read(String name) =>
      File('${directory.path}/$name').readAsStringSync();
  void write(String name, String content) =>
      File('${directory.path}/$name').writeAsStringSync(content);

  final key = generateInteropKey();
  final unlocked = _ok(key.unlock(interopIdentity), 'unlock the generated key');

  switch (arguments[0]) {
    case 'emit':
      write('token', interopIdentity.token.reveal());
      write('troc_pub_key', key.publicKey.armored);
      write('troc_enc_priv_key', key.encryptedPrivateKeyArmored);
      write('invoice.txt', interopInvoice);
      write(
        'troc_invoice_signed.asc',
        _ok(
          unlocked.signCleartext(interopInvoice, now: interopNow),
          'clear-sign the invoice',
        ),
      );
      write('chat.txt', interopChatText);
      stdout
        ..writeln('fingerprint ${key.publicKey.fingerprint}')
        ..writeln('user id     ${key.publicKey.userId}')
        ..writeln('created     ${key.publicKey.createdAt.toIso8601String()}');
    case 'encrypt':
      final peer = _ok(
        PgpPublicKey.parse(read('gpg_peer_pub_key')),
        'read the public key GnuPG generated',
      );
      write(
        'troc_chat_to_gpg.asc',
        _ok(
          unlocked.encryptChatMessage(
            interopChatText,
            peer: peer,
            now: interopNow,
          ),
          'encrypt and sign the chat message',
        ),
      );
      stdout.writeln('peer fingerprint ${peer.fingerprint}');
    case 'check':
      final peer = _ok(
        PgpPublicKey.parse(read('gpg_peer_pub_key')),
        'read the public key GnuPG generated',
      );
      final reexported = _ok(
        PgpPublicKey.parse(read('troc_pub_key_reexported_by_gpg')),
        'read the public key as GnuPG exports it again',
      );
      _check(
        reexported == key.publicKey,
        'the key GnuPG exports again is the generated key',
      );
      _check(
        _ok(
              key.publicKey.verifyCleartext(
                read('gpg_clearsigned_by_troc_key.asc'),
              ),
              'verify the text GnuPG clear-signed with the generated key',
            ) ==
            interopInvoice,
        'the text GnuPG clear-signed is the invoice',
      );
      final decrypted = _ok(
        unlocked.decryptChatMessage(read('gpg_chat_to_troc.asc'), sender: peer),
        'decrypt the message GnuPG encrypted and signed',
      );
      _check(
        decrypted.text == interopChatText,
        'the message GnuPG encrypted is the chat text',
      );
      _check(
        decrypted.validSignature,
        'the message GnuPG encrypted carries a valid signature of the peer',
      );
      final own = _ok(
        unlocked.decryptChatMessage(
          read('troc_chat_to_gpg.asc'),
          sender: key.publicKey,
        ),
        'decrypt the own copy of the message sent to GnuPG',
      );
      _check(
        own.text == interopChatText && own.validSignature,
        'the own copy reads back, signature valid',
      );
    default:
      stderr.writeln('unknown command ${arguments[0]}');
      exit(64);
  }
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
