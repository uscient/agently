#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_contains() { grep -Fq "$2" "$1" || fail "expected $1 to contain: $2"; }
assert_not_contains_line() {
  local file="$1" pattern="$2"
  if grep -Eq "$pattern" "$file"; then
    fail "expected $file not to match: $pattern"
  fi
}

export HOME="$TMP/home"
export XDG_DATA_HOME="$TMP/xdg-data"
export XDG_STATE_HOME="$TMP/xdg-state"
export XDG_CONFIG_HOME="$TMP/xdg-config"
mkdir -p "$HOME" "$TMP/repo"

AGENTLY=(env AGENTLY_HOME="$ROOT" "$ROOT/bin/agently")

cd "$TMP/repo"
git init -q
git config user.email profile-preserve@example.invalid
git config user.name ProfilePreserve
printf '# Profile Preserve\n' > README.md
git add README.md
git commit -q -m init

"${AGENTLY[@]}" init --codex >/dev/null
awk '
  $1 == "default_budget:" { print "  default_budget: full"; next }
  $1 == "dir:" { print "  dir: custom/patches"; next }
  { print }
' .agently/config.yml > "$TMP/config.yml"
mv "$TMP/config.yml" .agently/config.yml
printf '\n# preserve sentinel comment\n' >> .agently/config.yml
printf 'test_command: make test\n' >> .agently/config.yml
branch_prefix="$(grep -F '    prefix: workstream/' .agently/config.yml)"

"${AGENTLY[@]}" profile set claude.model sonnet >/dev/null

assert_contains .agently/config.yml "  default_budget: full"
assert_contains .agently/config.yml "  dir: custom/patches"
assert_contains .agently/config.yml "# preserve sentinel comment"
assert_contains .agently/config.yml "test_command: make test"
assert_contains .agently/config.yml "    model: sonnet"
assert_contains .agently/config.yml "$branch_prefix"
assert_not_contains_line .agently/config.yml '^claude:$'

printf 'profile set preserves sections ok\n'
