#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_empty() { [[ ! -s "$1" ]] || fail "expected empty file: $1"; }
assert_json() { jq -e . "$1" >/dev/null || fail "invalid JSON: $1"; }
assert_contains() { grep -Fq "$2" "$1" || fail "expected $1 to contain: $2"; }

command -v jq >/dev/null 2>&1 || fail "jq required for self status tests"

setup_env() {
  local name="$1"
  export HOME="$TMP/$name/home"
  export XDG_DATA_HOME="$TMP/$name/xdg-data"
  export XDG_STATE_HOME="$TMP/$name/xdg-state"
  export XDG_CONFIG_HOME="$TMP/$name/xdg-config"
  mkdir -p "$HOME"
}

assert_no_xdg_mutation() {
  [[ ! -e "$XDG_DATA_HOME" ]] || fail "status created XDG_DATA_HOME"
  [[ ! -e "$XDG_STATE_HOME" ]] || fail "status created XDG_STATE_HOME"
  [[ ! -e "$XDG_CONFIG_HOME" ]] || fail "status created XDG_CONFIG_HOME"
  [[ ! -e "$HOME/.local" ]] || fail "status created HOME/.local"
}

setup_env noinstall
PATH="$ROOT/bin:$PATH" AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" self status --json > "$TMP/status.json" 2> "$TMP/status.err"
assert_json "$TMP/status.json"
assert_empty "$TMP/status.err"
jq -e '.ok == true and .command == "self_status" and .mutated == false' "$TMP/status.json" >/dev/null || fail "bad status JSON"
jq -e '.active_classification == "dev-repo"' "$TMP/status.json" >/dev/null || fail "expected dev-repo classification"
jq -e '.path_candidates | length >= 1' "$TMP/status.json" >/dev/null || fail "expected PATH candidates"
assert_no_xdg_mutation

AGENTLY_SHARE="$ROOT" bash -c 'source "$AGENTLY_SHARE/lib/common.sh"; source "$AGENTLY_SHARE/lib/self.sh"; self_render_shim' > "$TMP/shim-rendered"
assert_contains "$TMP/shim-rendered" "# AGENTLY-MANAGED-SHIM v1"
assert_contains "$TMP/shim-rendered" "# Managed by \`agently self\`; do not edit by hand."
assert_contains "$TMP/shim-rendered" "ERROR: Agently current release not found at \$TARGET."
assert_contains "$TMP/shim-rendered" "exec \"\$TARGET\" \"\$@\""

mkdir -p "$TMP/sentinel"
printf '#!/usr/bin/env bash\n# AGENTLY-MANAGED-SHIM v1\n' > "$TMP/sentinel/managed"
printf '#!/usr/bin/env bash\n# AGENTLY-MANAGED-SHIM v2\n' > "$TMP/sentinel/altered"
AGENTLY_SHARE="$ROOT" bash -c 'source "$AGENTLY_SHARE/lib/common.sh"; source "$AGENTLY_SHARE/lib/self.sh"; self_shim_is_managed "$1"' _ "$TMP/sentinel/managed" || fail "managed sentinel not recognized"
if AGENTLY_SHARE="$ROOT" bash -c 'source "$AGENTLY_SHARE/lib/common.sh"; source "$AGENTLY_SHARE/lib/self.sh"; self_shim_is_managed "$1"' _ "$TMP/sentinel/altered"; then
  fail "altered sentinel should be unmanaged"
fi
if AGENTLY_SHARE="$ROOT" bash -c 'source "$AGENTLY_SHARE/lib/common.sh"; source "$AGENTLY_SHARE/lib/self.sh"; self_shim_is_managed "$1"' _ "$TMP/sentinel/missing"; then
  fail "missing sentinel file should be unmanaged"
fi

setup_env managed
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/agently" <<'SH'
#!/usr/bin/env bash
# AGENTLY-MANAGED-SHIM v1
exit 99
SH
chmod +x "$HOME/.local/bin/agently"
PATH="$HOME/.local/bin:$ROOT/bin:$PATH" AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" self status --json > "$TMP/managed.json" 2> "$TMP/managed.err"
assert_json "$TMP/managed.json"
assert_empty "$TMP/managed.err"
jq -e '.active_classification == "managed-shim"' "$TMP/managed.json" >/dev/null || fail "expected managed-shim"
jq -e '.managed_shim_present == true' "$TMP/managed.json" >/dev/null || fail "managed shim not reported"
jq -e '.path_candidates[] | select(.path == env.HOME + "/.local/bin/agently" and .managed_shim == true)' "$TMP/managed.json" >/dev/null || fail "managed candidate missing"

setup_env notpath
PATH="/usr/bin:/bin" AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" self status --json > "$TMP/notpath.json" 2> "$TMP/notpath.err"
assert_json "$TMP/notpath.json"
assert_empty "$TMP/notpath.err"
jq -e '.active_classification == "dev-repo"' "$TMP/notpath.json" >/dev/null || fail "expected dev-repo fallback classification"
jq -e '.warnings[]? | select(.code == "NOT_ON_PATH")' "$TMP/notpath.json" >/dev/null || fail "missing NOT_ON_PATH warning"

setup_env human
fake_global="$TMP/human/usr/local/bin/agently"
mkdir -p "$(dirname "$fake_global")"
printf '#!/bin/sh\nexit 0\n' > "$fake_global"
chmod +x "$fake_global"
PATH="$(dirname "$fake_global"):/usr/bin:/bin" AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" self status > "$TMP/human.out" 2> "$TMP/human.err"
assert_empty "$TMP/human.err"
assert_contains "$TMP/human.out" "Warnings:"
assert_contains "$TMP/human.out" "unmanaged global install on PATH"
if grep -Fq '{"code":' "$TMP/human.out"; then
  fail "human status printed raw JSON warning objects"
fi

printf 'self status ok\n'
