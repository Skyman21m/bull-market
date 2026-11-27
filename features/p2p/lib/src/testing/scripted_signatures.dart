import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

/// The text a scripted coordinator expects a robot to have signed for one request (GHSA-22q8-9ghc-jg3h, RoboSats pull request 2955, head `0943c97`).
sealed class ScriptedSignedText {
  const ScriptedSignedText();
}

/// A text with no time, compared as a whole: `{action}:{order_id}:{shortAlias}` for an action on an order, `review:{pubkey}` for the token to rate the coordinator (`validate_action_signature`, `api/utils.py`).
final class ScriptedExactText extends ScriptedSignedText {
  final String text;

  const ScriptedExactText(this.text);
}

/// A timed text, `{action}:{shortAlias}:{unix_ts}`, read as `validate_signed_action_timestamp` reads it (`api/utils.py`): the prefix of [action], then the alias, compared with [shortAlias] (1061), then the time, within 300 seconds of the coordinator's clock (1060).
final class ScriptedTimedText extends ScriptedSignedText {
  final String action;
  final String shortAlias;

  const ScriptedTimedText(this.action, this.shortAlias);
}

/// The code with which a coordinator running the fix of GHSA-22q8-9ghc-jg3h refuses the signature of a request whose JSON body is [fields], or `null` when the signature holds: 1059 when the body carries none, 1048 when it does not verify with [publicKey] (the key the coordinator holds for the robot) or signs another text than [expected], 1061 when a timed text names another coordinator, 1060 when its time is more than 300 seconds from [now], the coordinator's clock.
///
/// The text is read back as `verify_signed_message` reads it (`api/utils.py`): split on the exact header `-----BEGIN PGP SIGNED MESSAGE-----\nHash: SHA512\n\n`, cut at the signature's armor, and stripped.
/// The signature itself is checked on the device's clock, as a coordinator's GnuPG checks it on its own: the tests' key pairs are dated by it, not by [now].
int? scriptedSignatureRefusal(
  Map<String, Object?> fields, {
  required String? publicKey,
  required ScriptedSignedText expected,
  required DateTime now,
}) {
  final signature = fields['signature'];
  if (signature is! String || signature.isEmpty) return 1059;
  if (publicKey == null) return 1048;
  final verified = switch (PgpPublicKey.parse(publicKey)) {
    Ok(:final value) => value.verifyCleartext(signature),
    Err(:final failure) => Err<String, PgpFailure>(failure),
  };
  if (verified is Err) return 1048;
  const header = '-----BEGIN PGP SIGNED MESSAGE-----\nHash: SHA512\n\n';
  const footer = '-----BEGIN PGP SIGNATURE-----';
  final parts = signature.split(header);
  if (parts.length < 2) return 1048;
  final content = parts[1].split(footer).first.trim();
  switch (expected) {
    case ScriptedExactText(:final text):
      return content == text ? null : 1048;
    case ScriptedTimedText(:final action, :final shortAlias):
      final prefix = '$action:';
      if (!content.startsWith(prefix)) return 1048;
      final rest = content.substring(prefix.length);
      final colon = rest.indexOf(':');
      if (colon < 0) return 1048;
      final signedAt = int.tryParse(rest.substring(colon + 1));
      if (signedAt == null) return 1048;
      if (rest.substring(0, colon) != shortAlias) return 1061;
      final skew = unixSeconds(now) - signedAt;
      return skew.abs() > actionSignatureWindow.inSeconds ? 1060 : null;
  }
}

/// The message the reference sends with [code], one of [scriptedSignatureRefusal]'s: the app never shows it.
String scriptedSignatureMessage(int code) => switch (code) {
  1059 =>
    'This action needs a signature which your client did not provide because you are using an outdated client.',
  1060 =>
    "The signed request timestamp is too far from this coordinator's clock.",
  1061 => 'This action was signed for another coordinator.',
  _ => 'The PGP signed cleartext message is not valid.',
};
