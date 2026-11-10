#!/usr/bin/env bash
# Cross-checks the OpenPGP code of this package against GnuPG, the engine of RoboSats coordinators.
#
# Run it on a host that has GnuPG 2.2 or later and the `bull-tools` container image:
#   packages/robosats/tool/pgp_interop.sh [--update-fixtures]
#
# It replays, with the command lines python-gnupg 0.5 builds, what `validate_pgp_keys` and `verify_signed_message` of `api/utils.py` do in the RoboSats repository (commit ff1998c), then lets GnuPG produce a clear-signed text and an encrypted message that the Dart code must read.
# GnuPG only ever touches throwaway home directories under a temporary directory: `--homedir` is on every call.
# With `--update-fixtures`, the artefacts and the transcript replace `test/fixtures/pgp_interop/`.
set -euo pipefail
# Stable, English output whatever the locale and time zone of the host.
export LC_ALL=C TZ=UTC

package=$(cd "$(dirname "$0")/.." && pwd)
root=$(cd "$package/../.." && pwd)
update_fixtures=false
[ "${1:-}" = "--update-fixtures" ] && update_fixtures=true

work=$(mktemp -d)
artefacts="$work/artefacts"
coordinator="$work/coordinator"
peer="$work/peer"
mkdir -p "$artefacts"
mkdir -m 700 "$coordinator" "$peer"
cleanup() {
  gpgconf --homedir "$coordinator" --kill gpg-agent 2>/dev/null || true
  gpgconf --homedir "$peer" --kill gpg-agent 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

transcript="$artefacts/gpg_transcript.txt"
say() { printf '%s\n' "${*//$work/<tmp>}" | tee -a "$transcript"; }
pass() { say "ok   gpg:  $*"; }
die() {
  say "FAIL gpg:  $*"
  exit 1
}

# The Dart half runs in the tools container, as every Dart command of this repository does.
dart_tool() {
  docker run --rm \
    -v "$root":/work -w /work/packages/robosats \
    -v "$artefacts":/artefacts \
    -v troc-pub-cache:/home/bull/.pub-cache \
    bull-tools bash -c "fvm dart run tool/pgp_interop.dart $1 /artefacts" | tee -a "$transcript"
}

# python-gnupg 0.5 starts every command with these options (`GPG.make_args`), and reads the status lines.
pygpg() {
  local home=$1
  shift
  gpg --status-fd 2 --no-tty --no-verbose --fixed-list-mode --batch --with-colons --homedir "$home" "$@"
}

# The same, with a passphrase on standard input ahead of the data, as python-gnupg passes it.
pygpg_passphrase() {
  local home=$1 passphrase=$2 input=$3
  shift 3
  { printf '%s\n' "$passphrase"; cat "$input"; } |
    gpg --status-fd 2 --no-tty --no-verbose --fixed-list-mode --batch --with-colons --homedir "$home" \
      --passphrase-fd 0 --pinentry-mode loopback "$@"
}

say "# $(gpg --version | head -n 1), libgcrypt $(gpg --version | sed -n 's/^libgcrypt //p'), $(date -u +%Y-%m-%dT%H:%M:%SZ)"
say "## 1. Dart writes a key, a clear-signed invoice and a chat text"
emitted=$(dart_tool emit)
printf '%s\n' "$emitted"
token=$(cat "$artefacts/token")
fingerprint=$(awk '$1 == "fingerprint" { print $2 }' <<<"$emitted")
hash_id=$(sed -n 's/^user id *RoboSats ID //p' <<<"$emitted")

say "## 2. validate_pgp_keys (api/utils.py:521-625)"
status=$(pygpg "$coordinator" --import <"$artefacts/troc_pub_key" 2>&1)
say "$status"
# IMPORT_RES: count, no_user_id, imported, ... (the third number is `imported`).
grep -q "^\[GNUPG:\] IMPORT_RES 1 0 1 " <<<"$status" || die "import_keys(pub_key).imported != 1"
grep -q "^\[GNUPG:\] IMPORT_OK 1 $fingerprint\$" <<<"$status" || die "import fingerprint is not $fingerprint"
pass "gpg.import_keys(pub_key): imported == 1, fingerprint $fingerprint"

listing=$(pygpg "$coordinator" --list-keys --fingerprint --fingerprint "$fingerprint" 2>/dev/null)
say "$listing"
created=$(awk -F: '$1 == "pub" { print $6 }' <<<"$listing")
[ "$created" = "1794139200" ] || die "creation time is $created, expected 1794139200 (2026-11-08T12:00:00Z)"
[ "$created" -le $(($(date +%s) - 43200)) ] || die "key is younger than 12 hours"
pass "gpg.list_keys: created $created, at least 12 hours old"
user_id=$(awk -F: '$1 == "uid" { print $10 }' <<<"$listing")
[ "$user_id" = "RoboSats ID $hash_id" ] || die "user ID is '$user_id'"
pass "user ID is 'RoboSats ID <hash id>'"
grep -q "^pub:[^:]*:255:22:" <<<"$listing" || die "primary key is not 255-bit EdDSA (algorithm 22)"
grep -q "^sub:[^:]*:255:18:" <<<"$listing" || die "subkey is not 255-bit ECDH (algorithm 18)"
pass "primary key ed25519 (algorithm 22), subkey cv25519 (algorithm 18)"

pygpg "$coordinator" --armor --export "$fingerprint" >"$artefacts/troc_pub_key_reexported_by_gpg" 2>/dev/null
grep -q "BEGIN PGP PUBLIC KEY BLOCK" "$artefacts/troc_pub_key_reexported_by_gpg" || die "export_keys returned nothing"
pass "gpg.export_keys: the public key a coordinator stores and hands to the peer"

status=$(pygpg "$coordinator" --import <"$artefacts/troc_enc_priv_key" 2>&1)
say "$status"
# IMPORT_RES: ..., secret_read, secret_imported, secret_unchanged, ... (fields 11 to 13).
grep -q "^\[GNUPG:\] IMPORT_RES 1 0 0 0 1 0 0 0 0 1 1 0 " <<<"$status" || die "import_keys(enc_priv_key).sec_imported != 1"
pass "gpg.import_keys(enc_priv_key), without passphrase: sec_imported == 1"

say "## 3. The key has the packets of a key made by the official client"
shape() {
  gpg --homedir "$coordinator" --batch --list-packets "$1" 2>/dev/null |
    grep -v '^# off' |
    sed -E 's/sig created [0-9-]+/sig created T/; s/created [0-9]+/created T/; s/keyid:? [0-9A-F]+/keyid K/;
            s/salt: [0-9A-F]+/salt: S/; s/protect IV: .*/protect IV: I/; s/(pkey\[1\]|data): .*/\1: D/;
            s/begin of digest .*/begin of digest B/; s/issuer key ID [0-9A-F]+/issuer key ID K/;
            s/issuer fpr v4 [0-9A-F]+/issuer fpr v4 F/; s/RoboSats ID [0-9a-f]{64}/RoboSats ID H/'
}
reference="$package/test/fixtures/robosats_tests_robot_3/enc_priv_key"
if diff <(shape "$reference") <(shape "$artefacts/troc_enc_priv_key") >>"$transcript"; then
  pass "gpg --list-packets: same as tests/robots/3/enc_priv_key but for key material, dates and identifiers"
else
  die "gpg --list-packets differs from tests/robots/3/enc_priv_key"
fi
shape "$artefacts/troc_enc_priv_key" >>"$transcript"

say "## 4. verify_signed_message (api/utils.py:628-648)"
pygpg "$coordinator" --import <"$artefacts/troc_pub_key" >/dev/null 2>&1
status=$(pygpg "$coordinator" --verify <"$artefacts/troc_invoice_signed.asc" 2>&1)
say "$status"
# VALIDSIG: signing key fingerprint, date, timestamp, expiry, version, reserved, public-key algorithm, hash algorithm, class, primary key fingerprint.
validsig=$(grep "^\[GNUPG:\] VALIDSIG " <<<"$status") || die "verify: no VALIDSIG"
[ "$(awk '{ print $3 }' <<<"$validsig")" = "$fingerprint" ] || die "verified.fingerprint is not the primary key fingerprint"
[ "$(awk '{ print $9 " " $10 " " $11 }' <<<"$validsig")" = "22 10 01" ] || die "signature is not EdDSA, SHA-512, text"
pass "gpg.verify: valid, fingerprint == import_result.fingerprints[0], EdDSA (22), SHA512 (10), text signature (01)"
header=$'-----BEGIN PGP SIGNED MESSAGE-----\nHash: SHA512\n\n'
[ "$(head -c ${#header} "$artefacts/troc_invoice_signed.asc"; printf x)" = "${header}x" ] || die "header is not the exact string the coordinator splits on"
extracted=$(python3 -c '
import sys
signed = open(sys.argv[1]).read()
header = "-----BEGIN PGP SIGNED MESSAGE-----\nHash: SHA512\n\n"
footer = "-----BEGIN PGP SIGNATURE-----"
print(signed.split(header)[1].split(footer)[0].strip(), end="")
' "$artefacts/troc_invoice_signed.asc")
[ "$extracted" = "$(cat "$artefacts/invoice.txt")" ] || die "the coordinator would extract '$extracted'"
pass "signed_message.split(header)[1].split(footer)[0].strip() == invoice"

say "## 5. GnuPG uses the generated private key with the token as passphrase (tests/utils/pgp.py:5-25)"
status=$(pygpg_passphrase "$coordinator" "$token" "$artefacts/invoice.txt" \
  -sa --clearsign --default-key "$fingerprint" --digest-algo SHA512 2>&1 >"$artefacts/gpg_clearsigned_by_troc_key.asc")
say "$status"
grep -q "^\[GNUPG:\] SIG_CREATED C 22 10 01 " <<<"$status" || die "gpg.sign with the token as passphrase failed"
pass "gpg.sign(passphrase=token, extra_args=['--digest-algo', 'SHA512']): the token unlocks the key in GnuPG"

say "## 6. GnuPG plays the peer: its own ed25519/cv25519 key, as api/oas_schemas.py:464-480 suggests"
gpg --homedir "$peer" --batch --quiet --passphrase '' --default-new-key-algo "ed25519/cert,sign+cv25519/encr" \
  --quick-gen-key "RoboSats ID gnupg-peer" default default never 2>>"$transcript"
peer_fingerprint=$(gpg --homedir "$peer" --batch --with-colons --list-keys | awk -F: '$1 == "fpr" { print $10; exit }')
gpg --homedir "$peer" --batch --armor --export "$peer_fingerprint" >"$artefacts/gpg_peer_pub_key"
gpg --homedir "$peer" --batch --quiet --import "$artefacts/troc_pub_key_reexported_by_gpg" 2>>"$transcript"
pass "peer key $peer_fingerprint generated, the robot key imported from the coordinator's export"

say "## 7. Dart encrypts and signs a chat message to itself and to the peer"
dart_tool encrypt

say "## 8. GnuPG decrypts it, as the peer and as the robot"
status=$(gpg --homedir "$peer" --batch --status-fd 2 --decrypt "$artefacts/troc_chat_to_gpg.asc" 2>&1 >"$work/peer_plain.txt")
say "$status"
cmp -s "$work/peer_plain.txt" "$artefacts/chat.txt" || die "the peer does not read the chat text"
grep -q "^\[GNUPG:\] DECRYPTION_OKAY" <<<"$status" || die "peer: no DECRYPTION_OKAY"
grep -q "^\[GNUPG:\] GOODMDC" <<<"$status" || die "peer: no GOODMDC"
validsig=$(grep "^\[GNUPG:\] VALIDSIG " <<<"$status") || die "peer: signature of the robot not valid"
[ "$(awk '{ print $3 }' <<<"$validsig")" = "$fingerprint" ] || die "peer: signer is not the robot key"
[ "$(awk '{ print $5 }' <<<"$validsig")" = "1794139200" ] || die "peer: signature is not dated 24 hours before"
pass "peer: decrypted (AES256, MDC good), text identical, good signature of the robot key dated 24 hours before"

status=$(pygpg_passphrase "$coordinator" "$token" "$artefacts/troc_chat_to_gpg.asc" --decrypt 2>&1 >"$work/own_plain.txt")
say "$status"
cmp -s "$work/own_plain.txt" "$artefacts/chat.txt" || die "the robot key in GnuPG does not read the chat text"
grep -q "^\[GNUPG:\] DECRYPTION_OKAY" <<<"$status" || die "robot key in GnuPG: no DECRYPTION_OKAY"
pass "robot key in GnuPG, unlocked by the token: decrypted its own copy, text identical"
gpg --homedir "$peer" --batch --list-packets "$artefacts/troc_chat_to_gpg.asc" 2>/dev/null |
  sed -E 's/keyid [0-9A-F]+/keyid K/; s/data: .*/data: D/; s/created [0-9]+/created T/' >>"$transcript"

say "## 9. GnuPG encrypts and signs a chat message to the robot and to itself"
gpg --homedir "$peer" --batch --quiet --armor --trust-model always --sign --encrypt \
  --recipient "$fingerprint" --recipient "$peer_fingerprint" \
  --output "$artefacts/gpg_chat_to_troc.asc" "$artefacts/chat.txt" 2>>"$transcript"
pass "peer: gpg --sign --encrypt to both keys"

say "## 10. Dart verifies and decrypts what GnuPG made"
dart_tool check

say "## All checks passed"
if $update_fixtures; then
  rm -f "$artefacts/token" "$artefacts/invoice.txt" "$artefacts/chat.txt"
  mkdir -p "$package/test/fixtures/pgp_interop"
  cp "$artefacts"/* "$package/test/fixtures/pgp_interop/"
  echo "fixtures updated in $package/test/fixtures/pgp_interop"
fi
