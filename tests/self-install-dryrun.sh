#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_empty() { [[ ! -s "$1" ]] || fail "expected empty file: $1"; }
assert_json() { jq -e . "$1" >/dev/null || fail "invalid JSON: $1"; }
assert_code() { [[ "$(jq -r '.error.code' "$1")" == "$2" ]] || fail "expected code $2 in $1"; }

command -v jq >/dev/null 2>&1 || fail "jq required for self install dry-run tests"

setup_env() {
  local name="$1"
  export HOME="$TMP/$name/home"
  export XDG_DATA_HOME="$TMP/$name/xdg-data"
  export XDG_STATE_HOME="$TMP/$name/xdg-state"
  export XDG_CONFIG_HOME="$TMP/$name/xdg-config"
  mkdir -p "$HOME"
}

snapshot_xdg() {
  local path
  for path in "$HOME/.local" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME"; do
    if [[ -e "$path" ]]; then
      find "$path" -maxdepth 8 -print | sort
    fi
  done
}

assert_rule() {
  local file="$1" array="$2" rule="$3"
  jq -e --arg rule "$rule" ".$array | index(\$rule)" "$file" >/dev/null || fail "missing $array rule: $rule"
}

setup_env dryrun
before="$(snapshot_xdg)"
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" self install --user --from "$ROOT" --dry-run --json > "$TMP/install.json" 2> "$TMP/install.err"
after="$(snapshot_xdg)"
assert_json "$TMP/install.json"
assert_empty "$TMP/install.err"
[[ "$before" == "$after" ]] || fail "install dry-run mutated XDG paths"
jq -e --arg root "$ROOT" '
  .ok == true and
  .command == "self_install_dry_run" and
  .mutated == false and
  .source_repo == $root and
  (.release_id | test("^[0-9]{8}-[0-9]{6}-([0-9a-f]{12}|nogit)$")) and
  (.release_layout.entries | index("INSTALL-MANIFEST.json")) and
  (.source_git_dirty | type == "boolean") and
  (.source_git_commit == null or (.source_git_commit | test("^[0-9a-f]{40}$"))) and
  .manifest_preview.schema_version == 1 and
  .manifest_preview.installer == "agently self install" and
  (.manifest_preview.files | length == 0)
' "$TMP/install.json" >/dev/null || fail "bad install dry-run JSON"
for rule in "bin/" "lib/" "templates/" "docs/" "VERSION"; do
  assert_rule "$TMP/install.json" includes "$rule"
done
for rule in "tests/" ".git/" "docs/tmp/"; do
  assert_rule "$TMP/install.json" excludes "$rule"
done

mkdir -p "$HOME/.local/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$HOME/.local/bin/agently"
chmod +x "$HOME/.local/bin/agently"
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" self install --user --from "$ROOT" --dry-run --json > "$TMP/unmanaged.json" 2> "$TMP/unmanaged.err"
assert_json "$TMP/unmanaged.json"
assert_empty "$TMP/unmanaged.err"
jq -e '.would_refuse_unmanaged_shim == true and .shim_action == "would_refuse_unmanaged_shim"' "$TMP/unmanaged.json" >/dev/null || fail "unmanaged shim not reported"
[[ -f "$HOME/.local/bin/agently" ]] || fail "unmanaged shim changed"

setup_env missing-source
set +e
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" self install --user --from "$TMP/no-such-repo" --dry-run --json > "$TMP/source.out" 2> "$TMP/source.err"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "missing source should fail"
assert_empty "$TMP/source.out"
assert_json "$TMP/source.err"
assert_code "$TMP/source.err" SOURCE_NOT_FOUND

BASH_BIN="$(command -v bash)"
make_required_path() {
  local dir="$1" missing="${2:-}" tool real
  mkdir -p "$dir"
  for tool in git sha256sum flock realpath mktemp ln mv jq; do
    [[ "$tool" == "$missing" ]] && continue
    real="$(command -v "$tool")" || fail "missing host tool: $tool"
    ln -s "$real" "$dir/$tool"
  done
}

setup_env missing-deps
for missing in git sha256sum flock realpath mktemp ln mv jq; do
  shim="$TMP/path-missing-$missing"
  make_required_path "$shim" "$missing"
  set +e
  PATH="$shim" AGENTLY_SHARE="$ROOT" "$BASH_BIN" "$ROOT/lib/agently.sh" self install --user --from "$ROOT" --dry-run --json > "$TMP/missing-$missing.out" 2> "$TMP/missing-$missing.err"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail "$missing dependency should fail"
  assert_empty "$TMP/missing-$missing.out"
  assert_json "$TMP/missing-$missing.err"
  assert_code "$TMP/missing-$missing.err" DEPENDENCY_MISSING
  jq -e --arg missing "$missing" '.error.message | contains($missing)' "$TMP/missing-$missing.err" >/dev/null || fail "missing dependency message did not name $missing"
done

shim="$TMP/path-mv-no-T"
make_required_path "$shim" mv
cat > "$shim/mv" <<'SH'
#!/bin/sh
if [ "${1:-}" = "--help" ]; then
  printf 'Usage: mv SOURCE DEST\n'
  exit 0
fi
exit 1
SH
chmod +x "$shim/mv"
set +e
PATH="$shim" AGENTLY_SHARE="$ROOT" "$BASH_BIN" "$ROOT/lib/agently.sh" self install --user --from "$ROOT" --dry-run --json > "$TMP/mvT.out" 2> "$TMP/mvT.err"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "mv without -T should fail"
assert_empty "$TMP/mvT.out"
assert_json "$TMP/mvT.err"
assert_code "$TMP/mvT.err" DEPENDENCY_MISSING
jq -e '.error.message | contains("mv")' "$TMP/mvT.err" >/dev/null || fail "mv -T failure did not name mv"

printf 'self install dry-run ok\n'
