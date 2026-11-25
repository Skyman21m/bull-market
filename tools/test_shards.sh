#!/usr/bin/env bash
# The unit tests in parallel shards: the CI's `tests` matrix of Analyze and
# Test runs one shard per job (`make unit-test-shard SHARD=<name>`), and the
# union of the shards is exactly what `make unit-test` runs, one package after
# another: every workspace member that has a test/ directory, as melos lists
# it, with the same tool (`flutter test` for a member that depends on the
# Flutter SDK, `dart test` otherwise).
#
# Usage:
#   tools/test_shards.sh names          the shard names, as a JSON array (no SDK needed)
#   tools/test_shards.sh check          fails unless every member and every split file is in exactly one shard
#   tools/test_shards.sh plan <shard>   what the shard runs
#   tools/test_shards.sh run <shard>    runs it
#
# A shard lists its members, separated by spaces:
#   <package>        the whole package, with its tool (as `make unit-test` runs it)
#   <package>@k/n    part k of n of the package's test files: the files under
#                    test/ named *_test.dart, sorted, the i-th (from 0) going to
#                    part (i mod n) + 1, so a new test file always lands in a part
#   *                the default: every member with a test/ directory that no
#                    shard names, so a new package always lands in a shard
#
# `check` runs in CI (the `checks` job) and fails when a member is in no shard
# or in two, when a file of a split package is in no part or in two, or when a
# shard would run nothing. melos lists the members (fvm dart run melos list),
# as `make unit-test` does through `melos exec`.
set -euo pipefail
# Command substitutions keep `set -e` (bash 4.4+), so a failure inside one is
# not ignored; the callers also check each substitution that can fail.
shopt -s inherit_errexit
# No pathname expansion: the default member is a literal '*'.
set -f

SHARDS=(
  # The app: 11 to 17 min of tests in one job on a CI runner (2026-11-25), so two parts.
  "app-1:bb_mobile@1/2"
  "app-2:bb_mobile@2/2"
  # features/p2p: 21 to 25 min in one job (2026-11-25), so three parts; its
  # slowest file, taken_price_route_test.dart, takes about 8 min alone.
  "p2p-1:p2p@1/3"
  "p2p-2:p2p@2/3"
  "p2p-3:p2p@3/3"
  # The other members: about 8 min (secrets 4 to 5 min, robosats about 1).
  "packages:*"
)

die() {
  echo "❌ $*" >&2
  exit 1
}

usage() {
  sed -n '9,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

shard_names() {
  local entry
  for entry in "${SHARDS[@]}"; do
    printf '%s\n' "${entry%%:*}"
  done
}

shard_members() {
  local entry
  for entry in "${SHARDS[@]}"; do
    if [[ "${entry%%:*}" == "$1" ]]; then
      printf '%s\n' "${entry#*:}"
      return 0
    fi
  done
  die "no shard is named '$1' (shards: $(shard_names | tr '\n' ' '))"
}

# The table's own rules, checked before anything is listed: names, syntax, one
# default, no member named twice, the parts of a split package all present.
validate_table() {
  local entry name members member pkg part k n
  local -A seen_name=() whole=() split_n=() parts=()
  local defaults=0 errors=0

  ((${#SHARDS[@]} > 0)) || die "the shard table is empty"
  for entry in "${SHARDS[@]}"; do
    [[ "$entry" == *:* ]] || { echo "❌ shard entry '$entry' has no ':'" >&2; errors=$((errors + 1)); continue; }
    name=${entry%%:*}
    members=${entry#*:}
    [[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "❌ shard name '$name' must be lower-case letters, digits and dashes" >&2; errors=$((errors + 1)); }
    [[ -z "${seen_name[$name]:-}" ]] || { echo "❌ two shards are named '$name'" >&2; errors=$((errors + 1)); }
    seen_name[$name]=1
    [[ -n "${members// /}" ]] || { echo "❌ shard '$name' lists no member" >&2; errors=$((errors + 1)); }
    for member in $members; do
      if [[ "$member" == '*' ]]; then
        defaults=$((defaults + 1))
      elif [[ "$member" =~ ^([A-Za-z0-9_]+)@([0-9]+)/([0-9]+)$ ]]; then
        pkg=${BASH_REMATCH[1]}
        k=${BASH_REMATCH[2]}
        n=${BASH_REMATCH[3]}
        if ((n < 2 || k < 1 || k > n)); then
          echo "❌ shard '$name': '$member' is not a part k/n with 1 <= k <= n and n >= 2" >&2
          errors=$((errors + 1))
          continue
        fi
        if [[ -n "${split_n[$pkg]:-}" && "${split_n[$pkg]}" != "$n" ]]; then
          echo "❌ $pkg is split in ${split_n[$pkg]} parts in one shard and in $n in another" >&2
          errors=$((errors + 1))
        fi
        split_n[$pkg]=$n
        part="$pkg@$k"
        if [[ -n "${parts[$part]:-}" ]]; then
          echo "❌ part $k/$n of $pkg is in two shards: ${parts[$part]} and $name" >&2
          errors=$((errors + 1))
        fi
        parts[$part]=$name
      elif [[ "$member" =~ ^[A-Za-z0-9_]+$ ]]; then
        if [[ -n "${whole[$member]:-}" ]]; then
          echo "❌ $member is in two shards: ${whole[$member]} and $name" >&2
          errors=$((errors + 1))
        fi
        whole[$member]=$name
      else
        echo "❌ shard '$name': '$member' is neither a package name, <package>@k/n nor *" >&2
        errors=$((errors + 1))
      fi
    done
  done

  ((defaults == 1)) || { echo "❌ exactly one shard must hold the default member '*' (found $defaults): without it a new package would be in no shard" >&2; errors=$((errors + 1)); }
  for pkg in "${!split_n[@]}"; do
    [[ -z "${whole[$pkg]:-}" ]] || { echo "❌ $pkg is both whole (shard ${whole[$pkg]}) and split" >&2; errors=$((errors + 1)); }
    for ((k = 1; k <= split_n[$pkg]; k++)); do
      [[ -n "${parts[$pkg@$k]:-}" ]] || { echo "❌ part $k/${split_n[$pkg]} of $pkg is in no shard: its test files would never run" >&2; errors=$((errors + 1)); }
    done
  done
  ((errors == 0)) || die "the shard table has $errors error(s)"
}

# Every workspace member with a test/ directory, as `make unit-test` selects
# them: "<name>\t<flutter|dart>\t<location>" per line. The two lists are the two
# `melos exec` of `make unit-test` (--flutter, then --no-flutter).
# load_members runs once, at the top level of a command: a `die` inside a
# command substitution would only leave that subshell, and a failed
# substitution read by `<<<` never stops the script.
members_cache=""
members_loaded=0
load_members() {
  local flavor flag line out name location dupes
  for flavor in flutter dart; do
    flag=--flutter
    [[ "$flavor" == dart ]] && flag=--no-flutter
    out=$(fvm dart run melos list --dir-exists=test "$flag" --long --parsable) || die "melos list $flag failed: the workspace members cannot be read"
    # --long --parsable prints "<location>:<name>:<version>:<PRIVATE?>".
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      [[ "$line" == /*:*:* ]] || die "unexpected line from melos list: '$line'"
      name=$(awk -F: '{print $(NF-2)}' <<<"$line")
      location=${line%%:"$name":*}
      [[ -d "$location/test" ]] || die "melos lists $name at '$location', which has no test/ directory"
      members_cache+="$name"$'\t'"$flavor"$'\t'"$location"$'\n'
    done <<<"$out"
  done
  [[ -n "$members_cache" ]] || die "melos lists no workspace member with a test/ directory: an empty list must never read as green"
  dupes=$(cut -f1 <<<"$members_cache" | sort | uniq -d)
  [[ -z "$dupes" ]] || die "melos lists these members twice: $dupes"
  members_loaded=1
}

member_line() {
  awk -F'\t' -v n="$1" '$1 == n' <<<"$members_cache" | head -n 1
}

# Every member any shard names, whole or split.
named_members() {
  local entry member
  for entry in "${SHARDS[@]}"; do
    for member in ${entry#*:}; do
      [[ "$member" == '*' ]] && continue
      printf '%s\n' "${member%%@*}"
    done
  done | sort -u
}

# The package's *_test.dart files, sorted; fails (pipefail) if they cannot be
# listed. Callers check its status: `files=$(test_files …) || die …`.
test_files() {
  (cd "$1" && find test -type f -name '*_test.dart' | LC_ALL=C sort)
}

# What a shard runs, tab-separated: "whole <name> <flavor> <location>" and
# "file <name> <flavor> <location> <path from the package>" lines. Called as
# `plan=$(plan_shard …)`: every failure inside exits non-zero, which stops the
# caller (set -e sees a failed substitution in an assignment).
plan_shard() {
  local shard=$1 members member pkg k n line name flavor location i file files named
  ((members_loaded)) || die "internal error: the members were not loaded"
  members=$(shard_members "$shard") || exit 1
  for member in $members; do
    if [[ "$member" == '*' ]]; then
      named=$(named_members) || die "cannot list the named members"
      while IFS=$'\t' read -r name flavor location; do
        [[ -n "$name" ]] || continue
        grep -qxF "$name" <<<"$named" && continue
        printf 'whole\t%s\t%s\t%s\n' "$name" "$flavor" "$location"
      done <<<"$members_cache"
    elif [[ "$member" == *@* ]]; then
      pkg=${member%%@*}
      k=${member#*@}
      n=${k#*/}
      k=${k%/*}
      line=$(member_line "$pkg") || die "cannot read the member $pkg"
      [[ -n "$line" ]] || die "shard '$shard' names $pkg, which is not a workspace member with a test/ directory"
      IFS=$'\t' read -r name flavor location <<<"$line"
      files=$(test_files "$location") || die "cannot list the test files of $name in '$location'"
      i=0
      while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        if ((i % n == k - 1)); then
          printf 'file\t%s\t%s\t%s\t%s\n' "$name" "$flavor" "$location" "$file"
        fi
        i=$((i + 1))
      done <<<"$files"
    else
      line=$(member_line "$member") || die "cannot read the member $member"
      [[ -n "$line" ]] || die "shard '$shard' names $member, which is not a workspace member with a test/ directory"
      printf 'whole\t%s\n' "$line"
    fi
  done
}

cmd_names() {
  validate_table
  local first=1 name names
  names=$(shard_names)
  printf '['
  while IFS= read -r name; do
    ((first)) || printf ','
    printf '"%s"' "$name"
    first=0
  done <<<"$names"
  printf ']\n'
}

cmd_check() {
  validate_table
  load_members
  local -A member_count=() file_count=() split=() shard_of_member=()
  local shard kind name flavor location file files names errors=0 total_files=0
  names=$(shard_names)

  while IFS= read -r shard; do
    local plan
    plan=$(plan_shard "$shard")
    [[ -n "$plan" ]] || { echo "❌ shard '$shard' would run nothing" >&2; errors=$((errors + 1)); continue; }
    while IFS=$'\t' read -r kind name flavor location file; do
      case "$kind" in
        whole)
          member_count[$name]=$((${member_count[$name]:-0} + 1))
          shard_of_member[$name]="${shard_of_member[$name]:-}${shard_of_member[$name]:+ and }$shard"
          ;;
        file)
          split[$name]=1
          file_count["$name $file"]=$((${file_count["$name $file"]:-0} + 1))
          ;;
        *) die "unexpected plan line: $kind $name" ;;
      esac
    done <<<"$plan"
  done <<<"$names"

  local members=0 whole_members=0
  while IFS=$'\t' read -r name flavor location; do
    [[ -n "$name" ]] || continue
    members=$((members + 1))
    if [[ -n "${split[$name]:-}" ]]; then
      if [[ -n "${member_count[$name]:-}" ]]; then
        echo "❌ $name is split and also run whole by shard ${shard_of_member[$name]}" >&2
        errors=$((errors + 1))
      fi
      # `dart test` and `flutter test` read dart_test.yaml: a file pattern or
      # path list there would make the package's own selection differ from the
      # *_test.dart files listed here.
      if [[ -f "$location/dart_test.yaml" ]] && grep -Eq '^[[:space:]]*(filename|paths):' "$location/dart_test.yaml"; then
        echo "❌ $name is split but its dart_test.yaml sets filename: or paths:, which this script does not follow" >&2
        errors=$((errors + 1))
      fi
      local found=0
      files=$(test_files "$location") || die "cannot list the test files of $name in '$location'"
      while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        found=$((found + 1))
        case "${file_count["$name $file"]:-0}" in
          1) ;;
          0) echo "❌ $name: $file is in no shard" >&2; errors=$((errors + 1)) ;;
          *) echo "❌ $name: $file is in ${file_count["$name $file"]} shards" >&2; errors=$((errors + 1)) ;;
        esac
      done <<<"$files"
      ((found > 0)) || { echo "❌ $name is split but has no *_test.dart file" >&2; errors=$((errors + 1)); }
      total_files=$((total_files + found))
      echo "  $name ($flavor): $found test files, split across shards"
    else
      case "${member_count[$name]:-0}" in
        1) whole_members=$((whole_members + 1)); echo "  $name ($flavor): shard ${shard_of_member[$name]}" ;;
        0) echo "❌ $name ($location) is in no shard" >&2; errors=$((errors + 1)) ;;
        *) echo "❌ $name is in ${member_count[$name]} shards: ${shard_of_member[$name]}" >&2; errors=$((errors + 1)) ;;
      esac
    fi
  done <<<"$members_cache"

  ((members > 0)) || die "no workspace member was checked: an empty check must never read as green"
  ((errors == 0)) || die "the shards do not cover the unit tests exactly ($errors error(s))"
  echo "✅ $(shard_names | wc -l) shards cover the $members workspace members with a test/ directory exactly once ($whole_members whole, the others split file by file over $total_files test files)"
}

cmd_plan() {
  validate_table
  load_members
  local plan
  plan=$(plan_shard "$1")
  [[ -n "$plan" ]] || die "shard '$1' would run nothing"
  printf '%s\n' "$plan"
}

cmd_run() {
  local shard=$1
  validate_table
  load_members
  local plan
  plan=$(plan_shard "$shard")
  [[ -n "$plan" ]] || die "shard '$shard' would run nothing: refusing to pass with no test run"

  local kind name flavor location file
  local -a flutter_scopes=() dart_scopes=() split_names=()
  local -A split_flavor=() split_files=() split_seen=()
  while IFS=$'\t' read -r kind name flavor location file; do
    case "$kind" in
      whole)
        if [[ "$flavor" == flutter ]]; then flutter_scopes+=("--scope=$name"); else dart_scopes+=("--scope=$name"); fi
        ;;
      file)
        if [[ -z "${split_seen[$name]:-}" ]]; then
          split_names+=("$name")
          split_seen[$name]=1
          split_flavor[$name]=$flavor
        fi
        split_files[$name]+="$file"$'\n'
        ;;
    esac
  done <<<"$plan"

  echo "🏃‍ unit test shard '$shard': $(shard_members "$shard")"
  # The same `melos exec` as `make unit-test`, restricted to the shard's
  # members: melos exec with no member left still exits 0, hence the counts
  # above, and the explicit --scope per member.
  if ((${#flutter_scopes[@]} > 0)); then
    echo "  whole, flutter test: ${flutter_scopes[*]#--scope=}"
    fvm dart run melos exec --flutter --dir-exists=test --concurrency 1 --fail-fast "${flutter_scopes[@]}" -- fvm flutter test --reporter=compact
  fi
  if ((${#dart_scopes[@]} > 0)); then
    echo "  whole, dart test: ${dart_scopes[*]#--scope=}"
    fvm dart run melos exec --no-flutter --dir-exists=test --concurrency 1 --fail-fast "${dart_scopes[@]}" -- fvm dart test --reporter=compact
  fi
  for name in "${split_names[@]}"; do
    local -a files=()
    mapfile -t files < <(printf '%s' "${split_files[$name]}")
    echo "  $name, ${#files[@]} test files"
    if [[ "${split_flavor[$name]}" == flutter ]]; then
      fvm dart run melos exec --flutter --dir-exists=test --concurrency 1 --fail-fast "--scope=$name" -- fvm flutter test --reporter=compact "${files[@]}"
    else
      fvm dart run melos exec --no-flutter --dir-exists=test --concurrency 1 --fail-fast "--scope=$name" -- fvm dart test --reporter=compact "${files[@]}"
    fi
  done
}

case "${1:-}" in
  names) (($# == 1)) || usage; cmd_names ;;
  check) (($# == 1)) || usage; cmd_check ;;
  plan) (($# == 2)) && [[ -n "$2" ]] || usage; cmd_plan "$2" ;;
  run) (($# == 2)) && [[ -n "$2" ]] || usage; cmd_run "$2" ;;
  *) usage ;;
esac
