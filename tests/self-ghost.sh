#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_empty() { [[ ! -s "$1" ]] || fail "expected empty file: $1"; }
assert_json() { jq -e . "$1" >/dev/null || fail "invalid JSON: $1"; }

command -v jq >/dev/null 2>&1 || fail "jq required for self ghost tests"

setup_env() {
  local name="$1"
  export HOME="$TMP/$name/home"
  export XDG_DATA_HOME="$TMP/$name/xdg-data"
  export XDG_STATE_HOME="$TMP/$name/xdg-state"
  export XDG_CONFIG_HOME="$TMP/$name/xdg-config"
  mkdir -p "$HOME"
}

write_exe() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'SH'
#!/bin/sh
exit 0
SH
  chmod +x "$path"
}

write_managed_shim() {
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/agently" <<'SH'
#!/usr/bin/env bash
# AGENTLY-MANAGED-SHIM v1
exit 99
SH
  chmod +x "$HOME/.local/bin/agently"
}

setup_env global
fake_global="$TMP/global/usr/local/bin/agently"
write_exe "$fake_global"
PATH="$(dirname "$fake_global"):/usr/bin:/bin" AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" self status --json > "$TMP/global.json" 2> "$TMP/global.err"
assert_json "$TMP/global.json"
assert_empty "$TMP/global.err"
jq -e '.active_classification == "global-stale" and (.ghosts[]? | select(.code == "GLOBAL_STALE")) and (.ghosts | type == "array") and (.warnings | type == "array")' "$TMP/global.json" >/dev/null || fail "global stale ghost missing"

setup_env shadow
write_managed_shim
fake_shadow="$TMP/shadow/usr/local/bin/agently"
write_exe "$fake_shadow"
PATH="$(dirname "$fake_shadow"):$HOME/.local/bin:$ROOT/bin:/usr/bin:/bin" AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" self status --json > "$TMP/shadow.json" 2> "$TMP/shadow.err"
assert_json "$TMP/shadow.json"
assert_empty "$TMP/shadow.err"
jq -e '.managed_shim_present == true and .active_classification == "global-stale" and (.warnings[]? | select(.code == "SHADOWED_ACTIVE_COMMAND"))' "$TMP/shadow.json" >/dev/null || fail "shadow warning missing"

setup_env dangling
mkdir -p "$XDG_DATA_HOME/agently"
ln -s "$XDG_DATA_HOME/agently/releases/missing-release" "$XDG_DATA_HOME/agently/current"
PATH="$ROOT/bin:/usr/bin:/bin" AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" self status --json > "$TMP/dangling.json" 2> "$TMP/dangling.err"
assert_json "$TMP/dangling.json"
assert_empty "$TMP/dangling.err"
jq -e '.current_link_state == "dangling" and (.ghosts[]? | select(.code == "DANGLING_CURRENT"))' "$TMP/dangling.json" >/dev/null || fail "dangling current ghost missing"

setup_env current_not_symlink_reported
mkdir -p "$XDG_DATA_HOME/agently"
printf 'not a symlink\n' > "$XDG_DATA_HOME/agently/current"
current_before="$(find "$XDG_DATA_HOME" -maxdepth 5 -print | sort)"
PATH="$ROOT/bin:/usr/bin:/bin" AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" self status --json > "$TMP/current-not-symlink.json" 2> "$TMP/current-not-symlink.err"
current_after="$(find "$XDG_DATA_HOME" -maxdepth 5 -print | sort)"
assert_json "$TMP/current-not-symlink.json"
assert_empty "$TMP/current-not-symlink.err"
[[ "$current_before" == "$current_after" ]] || fail "status mutated current-not-symlink case"
jq -e '.current_link_state == "not_symlink" and (.ghosts[]? | select(.code == "CURRENT_NOT_SYMLINK"))' "$TMP/current-not-symlink.json" >/dev/null || fail "current-not-symlink ghost missing"

printf 'self ghost ok\n'
