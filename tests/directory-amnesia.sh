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

assert_contains() {
  local file="$1" needle="$2"
  grep -Fq -- "$needle" "$file" || fail "expected $file to contain: $needle"
}

assert_not_contains() {
  local file="$1" needle="$2"
  ! grep -Fq -- "$needle" "$file" || fail "expected $file not to contain: $needle"
}

assert_empty() {
  [[ ! -s "$1" ]] || fail "expected empty file: $1"
}

assert_status_fails() {
  local status="$1" label="$2"
  [[ "$status" -ne 0 ]] || fail "$label should have failed"
}

new_git_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email directory-amnesia@example.invalid
  git -C "$dir" config user.name DirectoryAmnesia
  printf '# Directory Amnesia\n' > "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -q -m init
}

export HOME="$TMP/home"
export XDG_DATA_HOME="$TMP/xdg-data"
export XDG_STATE_HOME="$TMP/xdg-state"
export XDG_CONFIG_HOME="$TMP/xdg-config"
mkdir -p "$HOME" "$TMP/outside"

AGENTLY=(env AGENTLY_HOME="$ROOT" "$ROOT/bin/agently")

REPO="$TMP/repo"
new_git_repo "$REPO"

cd "$TMP/outside"
"${AGENTLY[@]}" --project "$REPO" init --codex >/dev/null
assert_file "$REPO/.agently/config.yml"
"${AGENTLY[@]}" --project "$REPO" ws new alpha >/dev/null
"${AGENTLY[@]}" --project "$REPO" task new t1 --workstream alpha >/dev/null
"${AGENTLY[@]}" --project "$REPO" task status --workstream alpha --task t1 > "$TMP/project-task.md"
assert_contains "$TMP/project-task.md" "workstream: alpha"

AGENTLY_PROJECT="$REPO" "${AGENTLY[@]}" task status --workstream alpha --task t1 > "$TMP/env-task.md"
assert_contains "$TMP/env-task.md" "task: t1"

NEWDIR="$TMP/newdir"
new_git_repo "$NEWDIR"
"${AGENTLY[@]}" init --project "$NEWDIR" --codex >/dev/null
assert_file "$NEWDIR/.agently/config.yml"

set +e
"${AGENTLY[@]}" task list --workstream alpha > "$TMP/no-project.out" 2> "$TMP/no-project.err"
no_project_status=$?
set -e
assert_status_fails "$no_project_status" "task list outside repo without project"
assert_empty "$TMP/no-project.out"
assert_contains "$TMP/no-project.err" "FAIL:"

"${AGENTLY[@]}" --project "$REPO" ws init W31 --json > "$TMP/ws-init.json"
assert_contains "$TMP/ws-init.json" '"ws_id":"W31"'
set +e
"${AGENTLY[@]}" --project "$REPO" ws promote W31-PLN1 --json > "$TMP/promote.out" 2> "$TMP/promote.err"
promote_status=$?
set -e
assert_status_fails "$promote_status" "spine promote missing alias"
assert_empty "$TMP/promote.out"
assert_contains "$TMP/promote.err" '"code":'
assert_not_contains "$TMP/promote.err" "not inside a git repo"

printf 'directory amnesia ok\n'
