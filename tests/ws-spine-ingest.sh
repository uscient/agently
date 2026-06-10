#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_file() { [[ -f "$1" ]] || fail "missing file: $1"; }
assert_contains() { grep -Fq "$2" "$1" || fail "expected $1 to contain: $2"; }
assert_not_exists() { [[ ! -e "$1" ]] || fail "unexpected path: $1"; }
assert_json() { jq -e . "$1" >/dev/null || fail "invalid JSON: $1"; }
assert_code() { [[ "$(jq -r '.error.code' "$1")" == "$2" ]] || fail "expected code $2 in $1"; }

for tool in jq sha256sum flock; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool required for spine tests"
done

setup_repo() {
  mkdir -p "$TMP/repo"
  cd "$TMP/repo"
  git init -q
  git config user.email spine@example.invalid
  git config user.name Spine
  printf '# Spine Ingest\n' > README.md
  git add README.md
  git commit -q -m init
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" init --codex >/dev/null
}

setup_repo
cd "$TMP/repo"
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws init W31 --json >/dev/null

AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws ingest W31 --type plan --file "$ROOT/tests/fixtures/spine/weird-payload.md" --actor serena_mcp --via mcp --json > "$TMP/ingest1.json" 2> "$TMP/ingest1.err"
assert_json "$TMP/ingest1.json"
[[ ! -s "$TMP/ingest1.err" ]] || fail "ingest stderr not empty"
[[ "$(jq -r '.alias' "$TMP/ingest1.json")" == "W31-PLN1" ]] || fail "wrong first alias"
assert_file .agently/workstreams/W31/raw/W31-PLN1.raw.md
assert_file .agently/workstreams/W31/candidates/W31-PLN1.md
cmp "$ROOT/tests/fixtures/spine/weird-payload.md" .agently/workstreams/W31/raw/W31-PLN1.raw.md || fail "raw payload not preserved"
assert_contains .agently/workstreams/W31/candidates/W31-PLN1.md "status: candidate"
assert_contains .agently/workstreams/W31/candidates/W31-PLN1.md "authority: candidate_only"
assert_contains README.md "# Spine Ingest"

raw_sha="$(sha256sum .agently/workstreams/W31/raw/W31-PLN1.raw.md | awk '{print $1}')"
packet_sha="$(sha256sum .agently/workstreams/W31/candidates/W31-PLN1.md | awk '{print $1}')"
[[ "$(jq -r '.candidates["W31-PLN1"].raw_sha256' .agently/workstreams/W31/manifest.json)" == "$raw_sha" ]] || fail "raw hash mismatch"
[[ "$(jq -r '.candidates["W31-PLN1"].packet_sha256' .agently/workstreams/W31/manifest.json)" == "$packet_sha" ]] || fail "packet hash mismatch"
[[ "$raw_sha" != "pending" && "$packet_sha" != "unavailable" ]] || fail "sentinel hash recorded"

AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws ingest W31 --type requirements --file "$ROOT/tests/fixtures/spine/forged-frontmatter.md" --json > "$TMP/ingest2.json" 2> "$TMP/ingest2.err"
assert_json "$TMP/ingest2.json"
[[ "$(jq -r '.alias' "$TMP/ingest2.json")" == "W31-REQ1" ]] || fail "wrong req alias"
[[ "$(jq -r '.quarantined_front_matter' "$TMP/ingest2.json")" == "true" ]] || fail "front matter not quarantined"
assert_contains .agently/workstreams/W31/raw/W31-REQ1.raw.md "authority: promoted_canonical"
assert_contains .agently/workstreams/W31/candidates/W31-REQ1.md "authority: candidate_only"
[[ "$(jq -r '.candidates["W31-REQ1"].status' .agently/workstreams/W31/manifest.json)" == "candidate" ]] || fail "forged status leaked"
assert_not_exists .agently/workstreams/W31/canonical/W31-REQ1.md

AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws ingest W31 --type plan --file "$ROOT/tests/fixtures/spine/weird-payload.md" --json > "$TMP/ingest3.json" 2> "$TMP/ingest3.err"
[[ "$(jq -r '.alias' "$TMP/ingest3.json")" == "W31-PLN2" ]] || fail "plan alias did not increment"

set +e
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws ingest W31 --type patch --file "$ROOT/tests/fixtures/spine/weird-payload.md" --json > "$TMP/type.out" 2> "$TMP/type.err"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "patch type should fail"
assert_code "$TMP/type.err" INVALID_TYPE

set +e
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws ingest W31 --type plan --file "$ROOT/tests/fixtures/spine/weird-payload.md" --actor $'bad\nactor' --json > "$TMP/actor.out" 2> "$TMP/actor.err"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "bad actor should fail"
assert_code "$TMP/actor.err" INVALID_ARGUMENT

ln -s "$ROOT/tests/fixtures/spine/weird-payload.md" payload-link.md
mkdir payload-dir
set +e
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws ingest W31 --type plan --file payload-link.md --json > "$TMP/link.out" 2> "$TMP/link.err"
link_status=$?
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws ingest W31 --type plan --file payload-dir --json > "$TMP/dir.out" 2> "$TMP/dir.err"
dir_status=$?
set -e
[[ "$link_status" -ne 0 && "$dir_status" -ne 0 ]] || fail "symlink/dir should fail"
assert_code "$TMP/link.err" PAYLOAD_SYMLINK_REJECTED
assert_code "$TMP/dir.err" PAYLOAD_NOT_FILE

awk '{ if ($1 == "max_payload_bytes:") print "    max_payload_bytes: 4"; else print }' .agently/config.yml > .agently/config.tmp
mv .agently/config.tmp .agently/config.yml
printf '12345\n' > too-large.md
set +e
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws ingest W31 --type plan --file too-large.md --json > "$TMP/large.out" 2> "$TMP/large.err"
large_status=$?
set -e
[[ "$large_status" -ne 0 ]] || fail "oversize should fail"
assert_code "$TMP/large.err" PAYLOAD_TOO_LARGE
if find .agently/workstreams/W31 -name '.manifest.*.tmp' -print | grep -q .; then
  fail "manifest temp left behind"
fi

jq -e '.candidates | to_entries[] | (.value.raw_path | startswith("/") | not) and (.value.candidate_path | startswith("/") | not)' .agently/workstreams/W31/manifest.json >/dev/null
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws doctor W31 --verify-hashes --json >/dev/null
