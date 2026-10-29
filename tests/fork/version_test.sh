#!/usr/bin/env bash
# Tests for scripts/fork/version.sh: LuzLunar's version from the releases published before a run.
# Run by .github/workflows/fork-macos.yml:
#   bash tests/fork/version_test.sh
set -uo pipefail

script="$(cd "$(dirname "$0")/../.." && pwd)/scripts/fork/version.sh"
failures=0

# expect <name> <expected output> <run> <channel> <releases, one "tag|title" per line>
expect() {
  local name=$1 expected=$2 run=$3 channel=$4 releases=$5 got
  got=$(printf '%s' "$releases" | tr '|' '\t' | bash "$script" "$run" "$channel" ee5b3ba 2> /dev/null) || got="(failed)"
  if [ "$got" != "$expected" ]; then
    echo "FAIL $name: expected \"$expected\", got \"$got\""
    failures=$((failures + 1))
  fi
}

published="luzlunar-b202|LuzLunar 1.15
luzlunar-b193|LuzLunar 1.14
luzlunar-b189|LuzLunar 1.13
luzlunar-b129|LuzLunar 1.1
"

expect "the next master build" "1.16" 205 master "$published"
expect "a branch build, toward it" "1.16-dev.ee5b3ba" 204 branch "$published"
expect "a local build, toward it" "1.16local" 2147483647 local "$published"
expect "a local build before any update" "1.1local" 2147483647 local ""
expect "a re-run keeps its number" "1.15" 202 master "$published"
expect "a re-run of an older one" "1.14" 193 master "$published"
expect "the newest earlier release, not the first listed" "1.16" 210 master "luzlunar-b129|LuzLunar 1.1
luzlunar-b202|LuzLunar 1.15
luzlunar-b193|LuzLunar 1.14
"
expect "pruning doesn't matter" "1.16" 205 master "luzlunar-b202|LuzLunar 1.15
"
expect "other releases are ignored" "1.16" 205 master "apollo-b300|Apollo 9
luzlunar-bx|LuzLunar 9.99
$published"
expect "the first update" "1.1" 5 master ""
expect "a later major keeps counting" "1.31" 400 master "luzlunar-b399|LuzLunar 2.30
"
expect "an old-style title fails" "(failed)" 205 master "luzlunar-b202|LuzLunar 6.2.0-fork.00a71d9
"

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All version checks passed"
