#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

assert_dir() {
  [[ -d "$1" ]] || fail "missing dir: $1"
}

assert_contains() {
  local file="$1" needle="$2"
  grep -Fq -- "$needle" "$file" || fail "expected $file to contain: $needle"
}

assert_not_contains() {
  local file="$1" needle="$2"
  ! grep -Fq -- "$needle" "$file" || fail "expected $file not to contain: $needle"
}

hash_file() {
  sha256sum "$1" | awk '{print $1}'
}

new_repo() {
  local dir="$1"
  mkdir -p "$dir"
  cd "$dir"
  git init -q
  git config user.email context-smoke@example.invalid
  git config user.name ContextSmoke
  printf '# Context Smoke\n' > README.md
  git add README.md
  git commit -q -m init
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" init --codex >/dev/null
}

AGENTLY=(env AGENTLY_HOME="$ROOT" "$ROOT/bin/agently")

new_repo "$TMP/repo"
"${AGENTLY[@]}" ws new ctx-ws >/dev/null
"${AGENTLY[@]}" task new context-task --workstream ctx-ws >/dev/null
cat <<'MD' | "${AGENTLY[@]}" doc replace requirements --workstream ctx-ws --task context-task >/dev/null
# Requirements

- Cache summaries must be sha-fresh.
- Source files must remain untouched by compaction.

This paragraph is raw source and should not be in normal packets.
MD
"${AGENTLY[@]}" task set-state requirements_ready --workstream ctx-ws --task context-task >/dev/null

REQ=".agently/workstreams/ctx-ws/tasks/context-task/REQUIREMENTS.md"
req_before="$(hash_file "$REQ")"
"${AGENTLY[@]}" context manifest --workstream ctx-ws --task context-task > "$TMP/manifest-before.md"
assert_contains "$TMP/manifest-before.md" "summary_fresh"
assert_contains "$TMP/manifest-before.md" "false"
assert_contains "$TMP/manifest-before.md" ".agently/doctrine"

"${AGENTLY[@]}" compact workstream ctx-ws > "$TMP/compact.md"
assert_contains "$TMP/compact.md" "# Compact Workstream"
assert_contains "$TMP/compact.md" "manifest:"
assert_dir .agently/cache/summaries/workstream
assert_file .agently/cache/manifests/workstream-ctx-ws.md
[[ "$(hash_file "$REQ")" == "$req_before" ]] || fail "compaction changed source requirements"
assert_contains .agently/.gitignore "cache/"
assert_contains .agently/.gitignore "doctrine/"

"${AGENTLY[@]}" context manifest --workstream ctx-ws --task context-task --json > "$TMP/manifest-after.json"
assert_contains "$TMP/manifest-after.json" '"summary_fresh": true'
assert_contains "$TMP/manifest-after.json" '"sha256"'

"${AGENTLY[@]}" context budget --workstream ctx-ws --task context-task --budget normal --json > "$TMP/budget.json"
assert_contains "$TMP/budget.json" '"est_tokens"'

cat <<'MD' | "${AGENTLY[@]}" doc replace requirements --workstream ctx-ws --task context-task >/dev/null
# Requirements

- Cache summaries must become stale after source edits.

Changed paragraph that should invalidate the previous summary.
MD
"${AGENTLY[@]}" context manifest --workstream ctx-ws --task context-task --json > "$TMP/manifest-stale.json"
assert_contains "$TMP/manifest-stale.json" '"summary_fresh": false'

"${AGENTLY[@]}" compact workstream ctx-ws > "$TMP/compact-refresh.md"
"${AGENTLY[@]}" context manifest --workstream ctx-ws --task context-task --json > "$TMP/manifest-refresh.json"
assert_contains "$TMP/manifest-refresh.json" '"summary_fresh": true'

"${AGENTLY[@]}" packet --profile codex --workstream ctx-ws --task context-task --budget normal > "$TMP/packet-normal.md"
assert_contains "$TMP/packet-normal.md" "agently_summary: structural"
assert_not_contains "$TMP/packet-normal.md" "Changed paragraph that should invalidate"

"${AGENTLY[@]}" compact doctrine > "$TMP/compact-doctrine.md"
assert_contains "$TMP/compact-doctrine.md" "# Compact Doctrine"
assert_file .agently/cache/manifests/doctrine.md

printf 'context smoke ok\n'
