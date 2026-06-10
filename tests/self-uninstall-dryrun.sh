#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_empty() { [[ ! -s "$1" ]] || fail "expected empty file: $1"; }
assert_json() { jq -e . "$1" >/dev/null || fail "invalid JSON: $1"; }

command -v jq >/dev/null 2>&1 || fail "jq required for self uninstall dry-run tests"

setup_env() {
  local name="$1"
  export HOME="$TMP/$name/home"
  export XDG_DATA_HOME="$TMP/$name/xdg-data"
  export XDG_STATE_HOME="$TMP/$name/xdg-state"
  export XDG_CONFIG_HOME="$TMP/$name/xdg-config"
  mkdir -p "$HOME"
}

snapshot_tree() {
  local path
  for path in "$HOME/.local" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME" "$TMP/project"; do
    if [[ -e "$path" ]]; then
      find "$path" -maxdepth 8 -print | sort
    fi
  done
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

setup_env managed
write_managed_shim
mkdir -p "$XDG_DATA_HOME/agently/lib" "$XDG_CONFIG_HOME/agently" "$XDG_STATE_HOME/agently" "$TMP/project/.agently"
printf 'version\n' > "$XDG_DATA_HOME/agently/VERSION"
printf 'config\n' > "$XDG_CONFIG_HOME/agently/config"
printf 'state\n' > "$XDG_STATE_HOME/agently/state"
printf 'project\n' > "$TMP/project/.agently/state"
before="$(snapshot_tree)"
(
  cd "$TMP/project"
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" self uninstall --user --dry-run --json > "$TMP/uninstall.json" 2> "$TMP/uninstall.err"
)
after="$(snapshot_tree)"
assert_json "$TMP/uninstall.json"
assert_empty "$TMP/uninstall.err"
[[ "$before" == "$after" ]] || fail "uninstall dry-run mutated files"
jq -e --arg shim "$HOME/.local/bin/agently" --arg share "$XDG_DATA_HOME/agently" --arg config "$XDG_CONFIG_HOME/agently" --arg state "$XDG_STATE_HOME/agently" '
  .ok == true and
  .command == "self_uninstall_dry_run" and
  .mutated == false and
  .installed == true and
  .shim_managed == true and
  (.remove[]? | select(.path == $shim and .reason == "managed_shim")) and
  (.remove[]? | select(.path == $share and .reason == "agently_share")) and
  (.keep[]? | select(.path == $config and .reason == "config_preserved")) and
  (.keep[]? | select(.path == $state and .reason == "state_preserved"))
' "$TMP/uninstall.json" >/dev/null || fail "bad uninstall dry-run plan"
grep -Fq "$TMP/project/.agently" "$TMP/uninstall.json" && fail "uninstall listed project .agently path"
[[ -f "$HOME/.local/bin/agently" ]] || fail "managed shim removed"
[[ -d "$XDG_DATA_HOME/agently" ]] || fail "share dir removed"
[[ -f "$XDG_CONFIG_HOME/agently/config" ]] || fail "config removed"
[[ -f "$XDG_STATE_HOME/agently/state" ]] || fail "state removed"
[[ -f "$TMP/project/.agently/state" ]] || fail "project state removed"

setup_env unmanaged
mkdir -p "$HOME/.local/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$HOME/.local/bin/agently"
chmod +x "$HOME/.local/bin/agently"
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" self uninstall --user --dry-run --json > "$TMP/unmanaged.json" 2> "$TMP/unmanaged.err"
assert_json "$TMP/unmanaged.json"
assert_empty "$TMP/unmanaged.err"
jq -e --arg shim "$HOME/.local/bin/agently" '
  .shim_action == "keep_unmanaged_shim" and
  ([.remove[]?.path] | index($shim) | not) and
  (.warnings[]? | select(.code == "UNMANAGED_SHIM"))
' "$TMP/unmanaged.json" >/dev/null || fail "unmanaged shim was not preserved"
[[ -f "$HOME/.local/bin/agently" ]] || fail "unmanaged shim removed"

setup_env not-installed
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" self uninstall --user --dry-run --json > "$TMP/not-installed.json" 2> "$TMP/not-installed.err"
assert_json "$TMP/not-installed.json"
assert_empty "$TMP/not-installed.err"
jq -e '.installed == false and .status == "NOT_INSTALLED" and (.remove | length == 0) and (.warnings[]? | select(.code == "NOT_INSTALLED"))' "$TMP/not-installed.json" >/dev/null || fail "not installed case unclear"

printf 'self uninstall dry-run ok\n'

