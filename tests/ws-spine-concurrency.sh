#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_code() { [[ "$(jq -r '.error.code' "$1")" == "$2" ]] || fail "expected code $2 in $1"; }

for tool in jq sha256sum flock; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool required for spine tests"
done

mkdir -p "$TMP/repo"
cd "$TMP/repo"
git init -q
git config user.email spine@example.invalid
git config user.name Spine
printf '# Concurrency\n' > README.md
git add README.md
git commit -q -m init
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" init --codex >/dev/null

AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws init WCON --json >/dev/null
printf 'parallel payload\n' > payload.md

for i in 1 2 3 4 5 6 7 8; do
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws ingest WCON --type plan --file payload.md --json > "$TMP/ingest-$i.out" 2> "$TMP/ingest-$i.err" &
done
wait

for i in 1 2 3 4 5 6 7 8; do
  [[ ! -s "$TMP/ingest-$i.err" ]] || fail "parallel ingest stderr not empty: $i"
  jq -e . "$TMP/ingest-$i.out" >/dev/null || fail "parallel ingest JSON invalid: $i"
done

jq -e '.candidates | length == 8' .agently/workstreams/WCON/manifest.json >/dev/null || fail "candidate count mismatch"
jq -e '.alias_counters.PLN == 8' .agently/workstreams/WCON/manifest.json >/dev/null || fail "counter mismatch"
aliases="$(jq -r '.candidates | keys[]' .agently/workstreams/WCON/manifest.json | sort)"
[[ "$(printf '%s\n' "$aliases" | uniq | wc -l | awk '{print $1}')" == "8" ]] || fail "alias collision"
while IFS= read -r alias; do
  [[ -f ".agently/workstreams/WCON/candidates/$alias.md" ]] || fail "missing candidate file: $alias"
  [[ -f ".agently/workstreams/WCON/raw/$alias.raw.md" ]] || fail "missing raw file: $alias"
done <<< "$aliases"
[[ "$(wc -l < .agently/workstreams/WCON/events.jsonl | awk '{print $1}')" == "9" ]] || fail "event count mismatch"
if find .agently/workstreams/WCON -name '.manifest.*.tmp' -print | grep -q .; then
  fail "manifest temp left behind"
fi
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws doctor WCON --verify-hashes --json >/dev/null

awk '{ if ($1 == "lock_timeout_seconds:") print "    lock_timeout_seconds: 1"; else print }' .agently/config.yml > .agently/config.tmp
mv .agently/config.tmp .agently/config.yml
(
  flock -x 200
  sleep 2
) 200>.agently/workstreams/WCON/.manifest.lock &
lock_pid=$!
sleep 0.2
set +e
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws ingest WCON --type review --file payload.md --json > "$TMP/locked.out" 2> "$TMP/locked.err"
locked_status=$?
set -e
wait "$lock_pid"
[[ "$locked_status" -ne 0 ]] || fail "locked ingest should fail"
assert_code "$TMP/locked.err" LOCK_FAILED
if find .agently/workstreams/WCON -name '.manifest.*.tmp' -print | grep -q .; then
  fail "manifest temp left after lock failure"
fi
