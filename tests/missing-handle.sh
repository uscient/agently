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

assert_empty() {
  [[ ! -s "$1" ]] || fail "expected empty file: $1"
}

assert_no_ansi() {
  local file="$1"
  if LC_ALL=C grep -q "$(printf '\033')" "$file"; then
    fail "ANSI byte found in $file"
  fi
}

run_fail() {
  local label="$1"
  shift
  set +e
  "$@" > "$TMP/$label.out" 2> "$TMP/$label.err"
  local status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail "$label should have failed"
  assert_empty "$TMP/$label.out"
  assert_contains "$TMP/$label.err" "FAIL:"
}

run_fail_json() {
  local label="$1"
  shift
  command -v jq >/dev/null 2>&1 || fail "jq required for JSON missing-handle checks"
  set +e
  "$@" > "$TMP/$label.out" 2> "$TMP/$label.err"
  local status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail "$label should have failed"
  assert_empty "$TMP/$label.out"
  jq -e . "$TMP/$label.err" >/dev/null || fail "invalid JSON error for $label"
  assert_no_ansi "$TMP/$label.err"
}

export HOME="$TMP/home"
export XDG_DATA_HOME="$TMP/xdg-data"
export XDG_STATE_HOME="$TMP/xdg-state"
export XDG_CONFIG_HOME="$TMP/xdg-config"
mkdir -p "$HOME" "$TMP/repo"

AGENTLY=(env AGENTLY_HOME="$ROOT" "$ROOT/bin/agently")

cd "$TMP/repo"
git init -q
git config user.email missing-handle@example.invalid
git config user.name MissingHandle
printf '# Missing Handle\n' > README.md
git add README.md
git commit -q -m init

"${AGENTLY[@]}" init --codex >/dev/null
"${AGENTLY[@]}" ws new alpha >/dev/null
"${AGENTLY[@]}" task new t1 --workstream alpha >/dev/null

cat > "$TMP/change.diff" <<'DIFF'
diff --git a/README.md b/README.md
--- a/README.md
+++ b/README.md
@@ -1 +1 @@
-# Missing Handle
+# Missing Handle Updated
DIFF

run_fail task-set-state "${AGENTLY[@]}" task set-state "done" --task t1
run_fail task-status "${AGENTLY[@]}" task status --workstream alpha

set +e
printf 'requirements\n' | "${AGENTLY[@]}" doc replace requirements --workstream alpha > "$TMP/doc-replace.out" 2> "$TMP/doc-replace.err"
doc_status=${PIPESTATUS[1]}
set -e
[[ "$doc_status" -ne 0 ]] || fail "doc replace should have failed"
assert_empty "$TMP/doc-replace.out"
assert_contains "$TMP/doc-replace.err" "FAIL:"

run_fail decide "${AGENTLY[@]}" decide accept --workstream alpha
run_fail report "${AGENTLY[@]}" report --workstream alpha
run_fail eval-claude "${AGENTLY[@]}" eval claude --workstream alpha
run_fail claude-plan "${AGENTLY[@]}" claude plan --workstream alpha
run_fail patch-propose "${AGENTLY[@]}" patch propose "$TMP/change.diff"
run_fail patch-list "${AGENTLY[@]}" patch list
run_fail patch-apply "${AGENTLY[@]}" patch apply 001 --reviewed
run_fail context-missing-value "${AGENTLY[@]}" context manifest --workstream

run_fail_json patch-list-json "${AGENTLY[@]}" patch list --json
run_fail_json context-missing-value-json "${AGENTLY[@]}" context manifest --workstream --json

printf 'missing handle ok\n'
