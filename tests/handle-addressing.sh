#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1" needle="$2"
  grep -Fq -- "$needle" "$file" || fail "expected $file to contain: $needle"
}

assert_not_contains() {
  local file="$1" needle="$2"
  ! grep -Fq -- "$needle" "$file" || fail "expected $file not to contain: $needle"
}

export HOME="$TMP/home"
export XDG_DATA_HOME="$TMP/xdg-data"
export XDG_STATE_HOME="$TMP/xdg-state"
export XDG_CONFIG_HOME="$TMP/xdg-config"
mkdir -p "$HOME" "$TMP/repo"

AGENTLY=(env AGENTLY_HOME="$ROOT" "$ROOT/bin/agently")

cd "$TMP/repo"
git init -q
git config user.email handle-addressing@example.invalid
git config user.name HandleAddressing
printf '# Handle Addressing\n' > README.md
git add README.md
git commit -q -m init

"${AGENTLY[@]}" init --codex >/dev/null
"${AGENTLY[@]}" ws new alpha >/dev/null
"${AGENTLY[@]}" ws new beta >/dev/null
"${AGENTLY[@]}" task new t1 --workstream alpha >/dev/null
"${AGENTLY[@]}" task new t1 --workstream beta >/dev/null

"${AGENTLY[@]}" task set-state requirements_ready --workstream alpha --task t1 >/dev/null
assert_contains .agently/workstreams/alpha/tasks/t1/STATE.yaml "status: requirements_ready"
assert_contains .agently/workstreams/beta/tasks/t1/STATE.yaml "status: draft"

printf 'alpha requirements only\n' | "${AGENTLY[@]}" doc replace requirements --workstream alpha --task t1 >/dev/null
assert_contains .agently/workstreams/alpha/tasks/t1/REQUIREMENTS.md "alpha requirements only"
assert_not_contains .agently/workstreams/beta/tasks/t1/REQUIREMENTS.md "alpha requirements only"
assert_contains .agently/workstreams/alpha/tasks/t1/ledger.md "doc:replace name=requirements"
assert_not_contains .agently/workstreams/beta/tasks/t1/ledger.md "doc:replace name=requirements"

"${AGENTLY[@]}" status --workstream alpha --json > "$TMP/status.json"
assert_contains "$TMP/status.json" '"root":'
assert_contains "$TMP/status.json" '"selected": "alpha"'

"${AGENTLY[@]}" context manifest --workstream alpha --task t1 --json > "$TMP/context.json"
assert_contains "$TMP/context.json" '"workstream": "alpha"'
assert_contains "$TMP/context.json" '"task": "t1"'

printf 'handle addressing ok\n'
