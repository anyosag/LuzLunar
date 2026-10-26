#!/usr/bin/env bash
# LuzLunar's own version for a CI build, printed on one line (FORK.md, "Versions"):
#   1.16                   a master build: the update after LuzLunar 1.15
#   1.16-dev.ee5b3ba       any other build, toward that update
# The second number goes up by one with each published update: it's one more than the newest
# release from an earlier run (tag luzlunar-b<run>, titled "LuzLunar <major>.<n>"). Releases are
# pruned to the newest 15, so they can't be counted, but the newest is always there. A re-run of a
# published build skips its own release, so it keeps its number. The first number is MAJOR below,
# changed by hand for a big change; the second keeps counting.
#
# Usage: version.sh <run> <master|branch> <short commit>, with the releases on stdin as
# "<tag><TAB><title>" lines (gh release list --json tagName,name). Written for bash 3.2.
set -euo pipefail

MAJOR=1

run=$1
channel=$2
commit=$3

newest_run=-1
newest_title=
while IFS=$'\t' read -r tag title; do
  case "$tag" in
    luzlunar-b*) ;;
    *) continue ;;
  esac
  number=${tag#luzlunar-b}
  [[ "$number" =~ ^[0-9]+$ ]] || continue
  if [ "$number" -lt "$run" ] && [ "$number" -gt "$newest_run" ]; then
    newest_run=$number
    newest_title=$title
  fi
done

if [ "$newest_run" -lt 0 ]; then
  count=1
elif [[ "$newest_title" =~ ^LuzLunar\ [0-9]+\.([0-9]+)$ ]]; then
  count=$((BASH_REMATCH[1] + 1))
else
  echo "::error::The newest update, luzlunar-b$newest_run, is titled \"$newest_title\", not \"LuzLunar <major>.<n>\"; retitle it (FORK.md, \"Versions\")" >&2
  exit 1
fi

if [ "$channel" = master ]; then
  echo "$MAJOR.$count"
else
  echo "$MAJOR.$count-dev.$commit"
fi
