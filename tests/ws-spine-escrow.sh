#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_code() { [[ "$(jq -r '.error.code' "$1")" == "$2" ]] || fail "expected code $2 in $1"; }
assert_json() { jq -e . "$1" >/dev/null || fail "invalid JSON: $1"; }

for tool in jq sha256sum flock; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool required for spine tests"
done

mkdir -p "$TMP/repo"
cd "$TMP/repo"
git init -q
git config user.email spine@example.invalid
git config user.name Spine
printf '# Spine Escrow\n' > README.md
git add README.md
git commit -q -m init
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" init --codex >/dev/null
printf 'one\n' > one.md
printf 'two\n' > two.md

AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws init WESC --json >/dev/null
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws ingest WESC --type plan --file one.md --json >/dev/null
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws ingest WESC --type review --file two.md --json >/dev/null
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws propose WESC-PLN1 --json > "$TMP/propose.json" 2> "$TMP/propose.err"
assert_json "$TMP/propose.json"
[[ ! -s "$TMP/propose.err" ]] || fail "propose stderr not empty"

[[ "$(jq -r '.state' .agently/workstreams/WESC/manifest.json)" == "escrowed" ]] || fail "not escrowed"
[[ "$(jq -r '.proposed' .agently/workstreams/WESC/manifest.json)" == "WESC-PLN1" ]] || fail "wrong proposed alias"
[[ "$(jq -r '.candidates["WESC-PLN1"].status' .agently/workstreams/WESC/manifest.json)" == "proposed" ]] || fail "candidate not proposed"
[[ -f .agently/workstreams/WESC/proposed/WESC-PLN1.md ]] || fail "missing proposed evidence"

AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws status WESC --json > "$TMP/status.json" 2> "$TMP/status.err"
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws summary WESC --json > "$TMP/summary.json" 2> "$TMP/summary.err"
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws show WESC-PLN1 --json > "$TMP/show.json" 2> "$TMP/show.err"
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws doctor WESC --json > "$TMP/doctor.json" 2> "$TMP/doctor.err"
for f in "$TMP/status.json" "$TMP/summary.json" "$TMP/show.json" "$TMP/doctor.json"; do
  assert_json "$f"
done
for f in "$TMP/status.err" "$TMP/summary.err" "$TMP/show.err" "$TMP/doctor.err"; do
  [[ ! -s "$f" ]] || fail "read command stderr not empty: $f"
done

set +e
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws ingest WESC --type plan --file one.md --json > "$TMP/ing.out" 2> "$TMP/ing.err"
ing_status=$?
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws propose WESC-REV1 --json > "$TMP/prop2.out" 2> "$TMP/prop2.err"
prop2_status=$?
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws promote WESC-REV1 --json > "$TMP/promote-foreign.out" 2> "$TMP/promote-foreign.err"
foreign_status=$?
set -e
[[ "$ing_status" -ne 0 && "$prop2_status" -ne 0 && "$foreign_status" -ne 0 ]] || fail "escrowed writes should fail"
assert_code "$TMP/ing.err" WORKSTREAM_ESCROWED
assert_code "$TMP/prop2.err" WORKSTREAM_ESCROWED
assert_code "$TMP/promote-foreign.err" WORKSTREAM_ESCROWED

AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws list > "$TMP/ws-list.out"
grep -Fq "WESC [spine]" "$TMP/ws-list.out" || fail "spine list annotation missing"
