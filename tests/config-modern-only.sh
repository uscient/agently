#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_contains() { grep -Fq "$2" "$1" || fail "expected $1 to contain: $2"; }
assert_json() { jq -e . "$1" >/dev/null || fail "invalid JSON: $1"; }

command -v jq >/dev/null 2>&1 || fail "jq required for config-modern-only tests"

export HOME="$TMP/home"
export XDG_DATA_HOME="$TMP/xdg-data"
export XDG_STATE_HOME="$TMP/xdg-state"
export XDG_CONFIG_HOME="$TMP/xdg-config"
mkdir -p "$HOME" "$TMP/repo/.agently"

cd "$TMP/repo"
git init -q
git config user.email config@example.invalid
git config user.name Config
printf '# Config Test\n' > README.md
git add README.md
git commit -q -m init
printf 'project: old\n' > .agently/config.yaml

set +e
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws list > "$TMP/ws.out" 2> "$TMP/ws.err"
ws_status=$?
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" profile get claude.model > "$TMP/profile.out" 2> "$TMP/profile.err"
profile_status=$?
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" claude config --model opus > "$TMP/claude.out" 2> "$TMP/claude.err"
claude_status=$?
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws init W31 --json > "$TMP/spine.out" 2> "$TMP/spine.err"
spine_status=$?
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" serena profile get > "$TMP/serena.out" 2> "$TMP/serena.err"
serena_status=$?
set -e

for status in "$ws_status" "$profile_status" "$claude_status" "$spine_status" "$serena_status"; do
  [[ "$status" -ne 0 ]] || fail "config.yaml-only project should be treated as uninitialized"
done
assert_contains "$TMP/ws.err" "Agently is not initialized"
assert_contains "$TMP/profile.err" "Agently is not initialized"
assert_contains "$TMP/claude.err" "Agently is not initialized"
assert_json "$TMP/spine.err"
jq -e '.error.code == "INVALID_ARGUMENT" and (.error.message | contains("Agently is not initialized"))' "$TMP/spine.err" >/dev/null || fail "spine did not reject config.yaml-only project"
assert_contains "$TMP/serena.err" "Agently is not initialized"

AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" doctor > "$TMP/doctor.md"
assert_contains "$TMP/doctor.md" ".agently/config.yml is missing"

cat > .agently/config.yml <<'YAML'
project: config-test
review.required: false
YAML

set +e
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" profile get claude.model > "$TMP/authority.out" 2> "$TMP/authority.err"
authority_status=$?
set -e
[[ "$authority_status" -ne 0 ]] || fail "authority-shaped key in config.yml should fail"
assert_contains "$TMP/authority.err" "authority-shaped config key"

printf 'config modern-only ok\n'
