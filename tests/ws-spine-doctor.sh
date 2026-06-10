#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_json() { jq -e . "$1" >/dev/null || fail "invalid JSON: $1"; }
assert_code() { [[ "$(jq -r '.error.code' "$1")" == "$2" ]] || fail "expected code $2 in $1"; }
assert_error_contains() { jq -e --arg code "$2" '.errors[]? | select(.code == $code)' "$1" >/dev/null || fail "expected doctor error $2 in $1"; }

for tool in jq sha256sum flock; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool required for spine tests"
done

setup_case() {
  local repo="$1" ws="$2"
  mkdir -p "$repo"
  cd "$repo"
  git init -q
  git config user.email spine@example.invalid
  git config user.name Spine
  printf '# Doctor\n' > README.md
  git add README.md
  git commit -q -m init
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" init --codex >/dev/null
  printf 'doctor body\n' > payload.md
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws init "$ws" --json >/dev/null
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws ingest "$ws" --type plan --file payload.md --json >/dev/null
}

run_bad_doctor() {
  local ws="$1" expect="$2" out="$3" err="$4"
  set +e
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws doctor "$ws" --verify-hashes --json > "$out" 2> "$err"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail "doctor should fail for $expect"
  [[ ! -s "$out" ]] || fail "doctor failure stdout not empty"
  assert_json "$err"
  assert_error_contains "$err" "$expect"
}

setup_case "$TMP/valid" WDV
cd "$TMP/valid"
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws doctor WDV --verify-hashes --json > "$TMP/valid.json" 2> "$TMP/valid.err"
assert_json "$TMP/valid.json"
[[ ! -s "$TMP/valid.err" ]] || fail "valid doctor stderr not empty"

setup_case "$TMP/corrupt" WDC
cd "$TMP/corrupt"
printf '{bad\n' > .agently/workstreams/WDC/manifest.json
set +e
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws doctor WDC --json > "$TMP/corrupt.out" 2> "$TMP/corrupt.err"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "corrupt manifest should fail"
assert_code "$TMP/corrupt.err" MANIFEST_INVALID

setup_case "$TMP/badevent" WDE
cd "$TMP/badevent"
printf 'not-json\n' >> .agently/workstreams/WDE/events.jsonl
run_bad_doctor WDE EVENT_LOG_INVALID "$TMP/badevent.out" "$TMP/badevent.err"

setup_case "$TMP/missing" WDM
cd "$TMP/missing"
rm .agently/workstreams/WDM/candidates/WDM-PLN1.md
run_bad_doctor WDM PAYLOAD_NOT_FILE "$TMP/missing.out" "$TMP/missing.err"

setup_case "$TMP/escape" WDX
cd "$TMP/escape"
jq '.candidates["WDX-PLN1"].candidate_path = "../escape.md"' .agently/workstreams/WDX/manifest.json > .agently/workstreams/WDX/manifest.tmp
mv .agently/workstreams/WDX/manifest.tmp .agently/workstreams/WDX/manifest.json
run_bad_doctor WDX STATE_INCOHERENT "$TMP/escape.out" "$TMP/escape.err"

setup_case "$TMP/hash" WDH
cd "$TMP/hash"
printf 'tamper\n' >> .agently/workstreams/WDH/raw/WDH-PLN1.raw.md
run_bad_doctor WDH HASH_MISMATCH "$TMP/hash.out" "$TMP/hash.err"

setup_case "$TMP/openprop" WDO
cd "$TMP/openprop"
jq '.proposed = "WDO-PLN1"' .agently/workstreams/WDO/manifest.json > .agently/workstreams/WDO/manifest.tmp
mv .agently/workstreams/WDO/manifest.tmp .agently/workstreams/WDO/manifest.json
run_bad_doctor WDO STATE_INCOHERENT "$TMP/openprop.out" "$TMP/openprop.err"

setup_case "$TMP/escnull" WDN
cd "$TMP/escnull"
jq '.state = "escrowed"' .agently/workstreams/WDN/manifest.json > .agently/workstreams/WDN/manifest.tmp
mv .agently/workstreams/WDN/manifest.tmp .agently/workstreams/WDN/manifest.json
run_bad_doctor WDN STATE_INCOHERENT "$TMP/escnull.out" "$TMP/escnull.err"

setup_case "$TMP/escmissing" WDA
cd "$TMP/escmissing"
jq '.state = "escrowed" | .proposed = "WDA-REQ1"' .agently/workstreams/WDA/manifest.json > .agently/workstreams/WDA/manifest.tmp
mv .agently/workstreams/WDA/manifest.tmp .agently/workstreams/WDA/manifest.json
run_bad_doctor WDA STATE_INCOHERENT "$TMP/escmissing.out" "$TMP/escmissing.err"

setup_case "$TMP/canon" WDK
cd "$TMP/canon"
mkdir -p .agently/workstreams/WDK/canonical
cp .agently/workstreams/WDK/candidates/WDK-PLN1.md .agently/workstreams/WDK/canonical/WDK-PLN1.md
canon_sha="$(sha256sum .agently/workstreams/WDK/canonical/WDK-PLN1.md | awk '{print $1}')"
jq --arg sha "$canon_sha" '.canonical["WDK-PLN1"] = {type:"plan", canonical_path:"canonical/WDK-PLN1.md", canonical_sha256:$sha}' .agently/workstreams/WDK/manifest.json > .agently/workstreams/WDK/manifest.tmp
mv .agently/workstreams/WDK/manifest.tmp .agently/workstreams/WDK/manifest.json
run_bad_doctor WDK EVENT_LOG_INVALID "$TMP/canon.out" "$TMP/canon.err"

setup_case "$TMP/gap" WDG
cd "$TMP/gap"
jq '.event_seq += 1 | .version += 1' .agently/workstreams/WDG/manifest.json > .agently/workstreams/WDG/manifest.tmp
mv .agently/workstreams/WDG/manifest.tmp .agently/workstreams/WDG/manifest.json
run_bad_doctor WDG EVENT_LOG_INVALID "$TMP/gap.out" "$TMP/gap.err"
