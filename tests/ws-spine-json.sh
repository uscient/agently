#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_empty() { [[ ! -s "$1" ]] || fail "expected empty file: $1"; }
assert_json() { jq -e . "$1" >/dev/null || fail "invalid JSON: $1"; }
assert_no_ansi() { ! LC_ALL=C grep -q "$(printf '\033')" "$1" || fail "ANSI byte found: $1"; }
assert_code() { [[ "$(jq -r '.error.code' "$1")" == "$2" ]] || fail "expected code $2 in $1"; }

for tool in jq sha256sum flock; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool required for spine tests"
done

setup_repo() {
  local repo="$1"
  mkdir -p "$repo"
  cd "$repo"
  git init -q
  git config user.email spine@example.invalid
  git config user.name Spine
  printf '# Spine JSON\n' > README.md
  git add README.md
  git commit -q -m init
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" init --codex >/dev/null
}

setup_repo "$TMP/repo"
cd "$TMP/repo"
printf 'payload\n' > payload.md

AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws init WJSON --json > "$TMP/init.out" 2> "$TMP/init.err"
assert_json "$TMP/init.out"
assert_empty "$TMP/init.err"
[[ "$(jq -r '.ok' "$TMP/init.out")" == "true" ]] || fail "init ok false"
assert_no_ansi "$TMP/init.out"

set +e
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws init lowercase --json > "$TMP/lower.out" 2> "$TMP/lower.err"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "lowercase id should fail"
assert_empty "$TMP/lower.out"
assert_json "$TMP/lower.err"
assert_code "$TMP/lower.err" INVALID_WS_ID
assert_no_ansi "$TMP/lower.err"

set +e
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws ingest WJSON --type plan --file payload.md --authority canonical --json > "$TMP/auth.out" 2> "$TMP/auth.err"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "authority flag should fail"
assert_empty "$TMP/auth.out"
assert_json "$TMP/auth.err"
assert_code "$TMP/auth.err" INVALID_ARGUMENT

BASH_BIN="$(command -v bash)"
for missing in jq sha256sum flock; do
  shim="$TMP/path-$missing"
  mkdir -p "$shim"
  for tool in jq sha256sum flock; do
    [[ "$tool" == "$missing" ]] && continue
    ln -s "$(command -v "$tool")" "$shim/$tool"
  done
  set +e
  PATH="$shim" AGENTLY_SHARE="$ROOT" "$BASH_BIN" "$ROOT/lib/agently.sh" ws init WMISS --json > "$TMP/missing-$missing.out" 2> "$TMP/missing-$missing.err"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail "$missing dependency path should fail"
  assert_empty "$TMP/missing-$missing.out"
  assert_json "$TMP/missing-$missing.err"
  assert_code "$TMP/missing-$missing.err" DEPENDENCY_MISSING
done

AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws status WJSON --json > "$TMP/status.out" 2> "$TMP/status.err"
assert_json "$TMP/status.out"
assert_empty "$TMP/status.err"
[[ "$(jq -r '.command' "$TMP/status.out")" == "ws_status" ]] || fail "wrong status command"
