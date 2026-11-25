#!/usr/bin/env bash
# Tests of tools/test_shards.sh, with no SDK: each case copies the script into
# a fake workspace, with its own shard table, and puts a fake `fvm` first on
# PATH that answers `melos list` from a members file and records the
# `melos exec` commands instead of running them.
#
# Usage: tools/test_shards_test.sh   (CI: the `test-plan` job of Analyze and Test)
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_shards.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
passed=0
failed=0

# A fake workspace in $work/<case>: members "<name> <flutter|dart> <path>",
# each with a test/ directory and the test files given after the path.
make_workspace() {
  local root=$1
  shift
  mkdir -p "$root/tools" "$root/bin"
  : >"$root/members"
  : >"$root/fvm.log"
  local spec name flavor path file
  for spec in "$@"; do
    read -r name flavor path files <<<"$spec"
    printf '%s %s %s\n' "$name" "$flavor" "$path" >>"$root/members"
    mkdir -p "$root/$path/test"
    for file in $files; do
      mkdir -p "$(dirname "$root/$path/$file")"
      : >"$root/$path/$file"
    done
  done
  cat >"$root/bin/fvm" <<'FAKE'
#!/usr/bin/env bash
root=$(cd "$(dirname "$0")/.." && pwd)
printf '%s\n' "$*" >>"$root/fvm.log"
if [[ "$1 $2 $3 $4" == "dart run melos list" ]]; then
  flavor=
  for arg in "$@"; do
    case "$arg" in --flutter) flavor=flutter ;; --no-flutter) flavor=dart ;; esac
  done
  # A "fail-list" file names the lists that fail ("flutter", "dart"); a
  # "fail-from" file holds N: the N-th `melos list` and every later one fail.
  if [[ -f "$root/fail-list" ]] && grep -qx "$flavor" "$root/fail-list"; then
    echo "melos: simulated failure" >&2
    exit 1
  fi
  calls=$(grep -c "^dart run melos list" "$root/fvm.log")
  if [[ -f "$root/fail-from" ]] && ((calls >= $(cat "$root/fail-from"))); then
    echo "melos: simulated failure from call $(cat "$root/fail-from")" >&2
    exit 1
  fi
  while read -r name f path; do
    [[ "$f" == "$flavor" ]] || continue
    location=$root
    [[ "$path" == . ]] || location="$root/$path"
    printf '%s:%s:0.0.1:PRIVATE\n' "$location" "$name"
  done <"$root/members"
fi
FAKE
  chmod +x "$root/bin/fvm"
}

# Copies the script with the given table entries in place of its own.
set_table() {
  local root=$1
  shift
  {
    sed -n '1,/^SHARDS=($/p' "$script"
    local entry
    for entry in "$@"; do printf '  "%s"\n' "$entry"; done
    sed -n '/^SHARDS=($/,$p' "$script" | sed -n '/^)$/,$p'
  } >"$root/tools/test_shards.sh"
}

shards() {
  local root=$1
  shift
  PATH="$root/bin:$PATH" bash "$root/tools/test_shards.sh" "$@"
}

expect_pass() {
  local label=$1 root=$2
  shift 2
  local out
  if out=$(shards "$root" "$@" 2>&1); then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    printf '❌ %s: expected success, got:\n%s\n' "$label" "$out"
  fi
  last_output=$out
}

expect_fail() {
  local label=$1 root=$2 pattern=$3
  shift 3
  local out
  if out=$(shards "$root" "$@" 2>&1); then
    failed=$((failed + 1))
    printf '❌ %s: expected a failure, got success:\n%s\n' "$label" "$out"
  elif ! grep -qF -- "$pattern" <<<"$out"; then
    failed=$((failed + 1))
    printf '❌ %s: failed without "%s":\n%s\n' "$label" "$pattern" "$out"
  else
    passed=$((passed + 1))
  fi
}

expect_output() {
  local label=$1 pattern=$2
  if grep -qF -- "$pattern" <<<"$last_output"; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    printf '❌ %s: output lacks "%s":\n%s\n' "$label" "$pattern" "$last_output"
  fi
}

expect_log() {
  local label=$1 root=$2 pattern=$3
  if grep -qxF -- "$pattern" "$root/fvm.log"; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    printf '❌ %s: no command "%s" in:\n%s\n' "$label" "$pattern" "$(cat "$root/fvm.log")"
  fi
}

standard_members=(
  "bb_mobile flutter . test/app_test.dart"
  "p2p flutter features/p2p test/a_test.dart test/b_test.dart test/sub/c_test.dart test/d_test.dart test/e_test.dart test/helper.dart"
  "secrets flutter packages/secrets test/s_test.dart"
  "robosats dart packages/robosats test/r_test.dart"
)
standard_table=("app:bb_mobile" "p2p-1:p2p@1/2" "p2p-2:p2p@2/2" "packages:*")

# The repository's own table, as the CI's matrix reads it.
[[ "$(bash "$script" names)" == '["app-1","app-2","p2p-1","p2p-2","p2p-3","packages"]' ]] && passed=$((passed + 1)) || { failed=$((failed + 1)); echo "❌ the repository's shard names changed: update this test and the CI comments"; }

root=$work/standard
make_workspace "$root" "${standard_members[@]}"
set_table "$root" "${standard_table[@]}"
expect_pass "standard table: check" "$root" check
expect_output "standard table: summary" "✅ 4 shards cover the 4 workspace members"
expect_pass "standard table: p2p-1" "$root" plan p2p-1
expect_output "p2p-1 gets the first file" "test/a_test.dart"
expect_output "p2p-1 gets the third file" "test/d_test.dart"
expect_output "p2p-1 gets the fifth file" "test/sub/c_test.dart"
if grep -q "test/b_test.dart\|test/e_test.dart\|helper" <<<"$last_output"; then failed=$((failed + 1)); echo "❌ p2p-1 holds a file of p2p-2 or a non-test file"; else passed=$((passed + 1)); fi
expect_pass "standard table: packages" "$root" plan packages
expect_output "packages holds secrets" "secrets"
expect_output "packages holds robosats" "robosats"
if grep -q "bb_mobile\|p2p" <<<"$last_output"; then failed=$((failed + 1)); echo "❌ the default shard holds a named member"; else passed=$((passed + 1)); fi

expect_pass "run p2p-2" "$root" run p2p-2
expect_log "run p2p-2: one melos exec on p2p's files" "$root" "dart run melos exec --flutter --dir-exists=test --concurrency 1 --fail-fast --scope=p2p -- fvm flutter test --reporter=compact test/b_test.dart test/e_test.dart"
: >"$root/fvm.log"
expect_pass "run packages" "$root" run packages
expect_log "run packages: flutter members" "$root" "dart run melos exec --flutter --dir-exists=test --concurrency 1 --fail-fast --scope=secrets -- fvm flutter test --reporter=compact"
expect_log "run packages: dart members" "$root" "dart run melos exec --no-flutter --dir-exists=test --concurrency 1 --fail-fast --scope=robosats -- fvm dart test --reporter=compact"
expect_fail "run an unknown shard" "$root" "no shard is named 'nope'" run nope

# A new member, or a new test file of a split member, lands in a shard.
root=$work/new-member
make_workspace "$root" "${standard_members[@]}" "newpkg dart packages/newpkg test/n_test.dart" "dartonly dart packages/dartonly"
mkdir -p "$root/features/p2p/test/deep" && : >"$root/features/p2p/test/deep/z_test.dart"
set_table "$root" "${standard_table[@]}"
expect_pass "new member and new file: check" "$root" check
expect_pass "new member: in the default shard" "$root" plan packages
expect_output "the default shard holds the new member" "newpkg"
expect_pass "new file: in a part" "$root" plan p2p-2
expect_output "p2p-2 holds the new file" "test/deep/z_test.dart"

# The red cases.
root=$work/red
make_workspace "$root" "${standard_members[@]}"
set_table "$root" "app:bb_mobile" "p2p-1:p2p@1/2" "packages:*"
expect_fail "a part in no shard" "$root" "part 2/2 of p2p is in no shard" check
set_table "$root" "app:bb_mobile" "p2p-1:p2p@1/2" "p2p-2:p2p@1/2" "p2p-3:p2p@2/2" "packages:*"
expect_fail "a part in two shards" "$root" "part 1/2 of p2p is in two shards" check
set_table "$root" "app:bb_mobile robosats" "p2p-1:p2p@1/2" "p2p-2:p2p@2/2" "packages:* robosats"
expect_fail "a member in two shards" "$root" "robosats is in two shards" check
set_table "$root" "app:bb_mobile" "p2p-1:p2p@1/2" "p2p-2:p2p@2/2" "packages:secrets robosats"
expect_fail "no default shard" "$root" "exactly one shard must hold the default member" check
set_table "$root" "app:bb_mobile" "p2p-1:p2p@1/2" "p2p-2:p2p@2/2" "packages:*" "more:*"
expect_fail "two default shards" "$root" "exactly one shard must hold the default member" check
set_table "$root" "app:bb_mobil" "p2p-1:p2p@1/2" "p2p-2:p2p@2/2" "packages:*"
expect_fail "a member that does not exist" "$root" "names bb_mobil, which is not a workspace member" check
set_table "$root" "app:bb_mobile p2p" "p2p-1:p2p@1/2" "p2p-2:p2p@2/2" "packages:*"
expect_fail "a member whole and split" "$root" "p2p is both whole" check
set_table "$root" "app:bb_mobile" "p2p-1:p2p@1/2" "p2p-2:p2p@2/3" "packages:*"
expect_fail "parts of different counts" "$root" "split in 2 parts in one shard and in 3" check
set_table "$root" "app:bb_mobile" "app:secrets" "p2p-1:p2p@1/2" "p2p-2:p2p@2/2" "packages:*"
expect_fail "two shards of the same name" "$root" "two shards are named 'app'" check
set_table "$root" "app:bb_mobile" "p2p-1:p2p@1/2" "p2p-2:p2p@2/2" "packages:*" "Bad_Name:secrets"
expect_fail "a bad shard name" "$root" "shard name 'Bad_Name'" names
set_table "$root" "app:bb_mobile secrets robosats" "p2p-1:p2p@1/2" "p2p-2:p2p@2/2" "packages:*"
expect_fail "a default shard with nothing left" "$root" "shard 'packages' would run nothing" check
expect_fail "running a shard with nothing to run" "$root" "refusing to pass with no test run" run packages

root=$work/red-yaml
make_workspace "$root" "${standard_members[@]}"
set_table "$root" "${standard_table[@]}"
printf 'paths: [test/a_test.dart]\n' >"$root/features/p2p/dart_test.yaml"
expect_fail "a split member whose dart_test.yaml selects files" "$root" "sets filename: or paths:" check

root=$work/red-empty
make_workspace "$root"
set_table "$root" "${standard_table[@]}"
expect_fail "melos lists no member" "$root" "melos lists no workspace member" check

# melos list failing, for either list, or answering nothing: never green,
# whatever the command (a failure once printed ❌ and still exited 0).
root=$work/red-list
make_workspace "$root" "${standard_members[@]}"
set_table "$root" "${standard_table[@]}"
echo flutter >"$root/fail-list"
expect_fail "melos list --flutter fails: check" "$root" "melos list --flutter failed" check
expect_fail "melos list --flutter fails: plan" "$root" "melos list --flutter failed" plan packages
expect_fail "melos list --flutter fails: run" "$root" "melos list --flutter failed" run p2p-1
echo dart >"$root/fail-list"
expect_fail "melos list --no-flutter fails: check" "$root" "melos list --no-flutter failed" check
expect_fail "melos list --no-flutter fails: run" "$root" "melos list --no-flutter failed" run app
if grep -q "melos exec" "$root/fvm.log"; then failed=$((failed + 1)); echo "❌ a shard ran although melos list failed"; else passed=$((passed + 1)); fi

# The members are listed once per command, both lists at the top level: a
# failure from the N-th call on can only be one of those two, and fails.
rm -f "$root/fail-list"
for from in 1 2; do
  echo "$from" >"$root/fail-from"
  : >"$root/fvm.log"
  expect_fail "melos list failing from call $from: check" "$root" "failed: the workspace members cannot be read" check
done
rm -f "$root/fail-from"
: >"$root/fvm.log"
expect_pass "check lists the members" "$root" check
[[ "$(grep -c "^dart run melos list" "$root/fvm.log")" == 2 ]] && passed=$((passed + 1)) || { failed=$((failed + 1)); echo "❌ check called melos list $(grep -c "^dart run melos list" "$root/fvm.log") times, not twice"; }

root=$work/red-list-empty
make_workspace "$root"
set_table "$root" "${standard_table[@]}"
expect_fail "melos lists nothing: plan" "$root" "melos lists no workspace member" plan packages
expect_fail "melos lists nothing: run" "$root" "melos lists no workspace member" run packages

# A split member whose test files cannot all be listed.
if [[ "$(id -u)" != 0 ]]; then
  root=$work/red-unreadable
  make_workspace "$root" "${standard_members[@]}"
  set_table "$root" "${standard_table[@]}"
  mkdir -p "$root/features/p2p/test/locked" && : >"$root/features/p2p/test/locked/x_test.dart"
  chmod 000 "$root/features/p2p/test/locked"
  expect_fail "unreadable test files: check" "$root" "cannot list the test files of p2p" check
  expect_fail "unreadable test files: run" "$root" "cannot list the test files of p2p" run p2p-1
  chmod 755 "$root/features/p2p/test/locked"
fi

root=$work/red-split-empty
make_workspace "$root" "bb_mobile flutter . test/app_test.dart" "p2p flutter features/p2p test/a_test.dart" "secrets flutter packages/secrets test/s_test.dart"
set_table "$root" "${standard_table[@]}"
expect_fail "a part with no file" "$root" "shard 'p2p-2' would run nothing" check

echo "test_shards.sh: $passed passed, $failed failed"
((failed == 0))
