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

assert_not_exists() {
  [[ ! -e "$1" ]] || fail "unexpected path: $1"
}

assert_contains() {
  local file="$1" needle="$2"
  grep -Fq -- "$needle" "$file" || fail "expected $file to contain: $needle"
}

assert_no_project_current_files() {
  local found
  found="$(find .agently -name current -print)"
  [[ -z "$found" ]] || fail "unexpected workflow current files: $found"
}

assert_removed_command() {
  local label="$1"
  shift
  set +e
  "$@" > "$TMP/$label.out" 2> "$TMP/$label.err"
  local status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail "$label should have failed"
  [[ ! -s "$TMP/$label.out" ]] || fail "$label wrote stdout"
  assert_contains "$TMP/$label.err" "is removed"
  assert_no_project_current_files
}

export HOME="$TMP/home"
export XDG_DATA_HOME="$TMP/xdg-data"
export XDG_STATE_HOME="$TMP/xdg-state"
export XDG_CONFIG_HOME="$TMP/xdg-config"
mkdir -p "$HOME" "$XDG_DATA_HOME/agently/releases/demo" "$TMP/repo"
ln -s "$XDG_DATA_HOME/agently/releases/demo" "$XDG_DATA_HOME/agently/current"

AGENTLY=(env AGENTLY_HOME="$ROOT" "$ROOT/bin/agently")

cd "$TMP/repo"
git init -q
git config user.email pointer-removal@example.invalid
git config user.name PointerRemoval
printf '# Pointer Removal\n' > README.md
git add README.md
git commit -q -m init

"${AGENTLY[@]}" init --codex >/dev/null
assert_file .agently/config.yml
assert_not_exists .agently/current
assert_no_project_current_files

"${AGENTLY[@]}" ws new alpha >/dev/null
"${AGENTLY[@]}" task new t1 --workstream alpha >/dev/null
assert_no_project_current_files

assert_removed_command ws-use "${AGENTLY[@]}" ws use alpha
assert_removed_command ws-current "${AGENTLY[@]}" ws current
assert_removed_command task-use "${AGENTLY[@]}" task use t1
assert_removed_command task-current "${AGENTLY[@]}" task current

printf 'alpha\n' > .agently/current
"${AGENTLY[@]}" doctor > "$TMP/doctor.md"
assert_contains "$TMP/doctor.md" "Removed workflow pointer file is present and ignored"
rm -f .agently/current
assert_no_project_current_files

[[ -L "$XDG_DATA_HOME/agently/current" ]] || fail "self current symlink was removed"
[[ "$(readlink "$XDG_DATA_HOME/agently/current")" == "$XDG_DATA_HOME/agently/releases/demo" ]] ||
  fail "self current symlink target changed"

printf 'pointer removal ok\n'
