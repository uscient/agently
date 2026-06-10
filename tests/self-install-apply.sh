#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_empty() { [[ ! -s "$1" ]] || fail "expected empty file: $1"; }
assert_json() { jq -e . "$1" >/dev/null || fail "invalid JSON: $1"; }
assert_code() { [[ "$(jq -r '.error.code' "$1")" == "$2" ]] || fail "expected code $2 in $1"; }
assert_file() { [[ -f "$1" ]] || fail "missing file: $1"; }
assert_dir() { [[ -d "$1" ]] || fail "missing directory: $1"; }
assert_not_exists() { [[ ! -e "$1" ]] || fail "unexpected path: $1"; }
assert_contains() { grep -Fq "$2" "$1" || fail "expected $1 to contain: $2"; }

command -v jq >/dev/null 2>&1 || fail "jq required for self install apply tests"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum required for self install apply tests"
command -v flock >/dev/null 2>&1 || fail "flock required for self install apply tests"

setup_env() {
  local name="$1"
  export HOME="$TMP/$name/home"
  export XDG_DATA_HOME="$TMP/$name/xdg-data"
  export XDG_STATE_HOME="$TMP/$name/xdg-state"
  export XDG_CONFIG_HOME="$TMP/$name/xdg-config"
  mkdir -p "$HOME"
}

setup_env apply
mkdir -p "$HOME/project/.agently"
printf 'sentinel: keep\n' > "$HOME/project/.agently/config.yml"
project_before="$(find "$HOME/project/.agently" -type f -print -exec sha256sum {} \; | sort)"
root_status_before="$(git -C "$ROOT" status --short)"
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" self install --user --from "$ROOT" --apply --json > "$TMP/apply.json" 2> "$TMP/apply.err"
root_status_after="$(git -C "$ROOT" status --short)"
project_after="$(find "$HOME/project/.agently" -type f -print -exec sha256sum {} \; | sort)"
assert_json "$TMP/apply.json"
assert_empty "$TMP/apply.err"
[[ "$root_status_before" == "$root_status_after" ]] || fail "install apply mutated source repo"
[[ "$project_before" == "$project_after" ]] || fail "install apply mutated project .agently state"
jq -e '.ok == true and .command == "self_install" and .dry_run == false and .mutated == true' "$TMP/apply.json" >/dev/null || fail "bad apply success JSON"

release_dir="$(jq -r '.release_dir' "$TMP/apply.json")"
release_id="$(jq -r '.release_id' "$TMP/apply.json")"
share_dir="$XDG_DATA_HOME/agently"
assert_dir "$release_dir"
assert_dir "$release_dir/bin"
assert_dir "$release_dir/lib"
assert_dir "$release_dir/templates"
assert_dir "$release_dir/docs"
assert_file "$release_dir/VERSION"
assert_file "$release_dir/INSTALL-MANIFEST.json"
assert_not_exists "$release_dir/tests"
assert_not_exists "$release_dir/install.sh"
assert_not_exists "$release_dir/.git"
assert_not_exists "$release_dir/docs/tmp"
assert_not_exists "$share_dir/lib"
assert_not_exists "$share_dir/VERSION"
assert_json "$release_dir/INSTALL-MANIFEST.json"
jq -e --arg release_id "$release_id" --arg root "$ROOT" '
  .schema_version == 1 and
  .release_id == $release_id and
  .source_repo == $root and
  (.files | length > 0) and
  all(.files[]; (.bytes | type == "number") and (.sha256 | test("^[0-9a-f]{64}$")))
' "$release_dir/INSTALL-MANIFEST.json" >/dev/null || fail "bad install manifest"
manifest_sha="$(jq -r '.files[] | select(.path == "bin/agently").sha256' "$release_dir/INSTALL-MANIFEST.json")"
actual_sha="$(sha256sum "$release_dir/bin/agently" | awk '{ print $1 }')"
[[ "$manifest_sha" == "$actual_sha" ]] || fail "manifest hash mismatch for bin/agently"

[[ -L "$share_dir/current" ]] || fail "current is not a symlink"
[[ "$(readlink "$share_dir/current")" == "releases/$release_id" ]] || fail "current does not point to release"
if find "$share_dir/releases" -name '.stage.*' -print | grep -q .; then
  fail "stage directory left behind"
fi

shim="$HOME/.local/bin/agently"
assert_file "$shim"
[[ -x "$shim" ]] || fail "shim is not executable"
assert_contains "$shim" "# AGENTLY-MANAGED-SHIM v1"
assert_contains "$shim" "exec \"\$TARGET\" \"\$@\""
PATH="$HOME/.local/bin:$PATH" agently version > "$TMP/version.out"
assert_contains "$TMP/version.out" "Agently $(sed -n '1p' "$ROOT/VERSION")"
PATH="$HOME/.local/bin:$PATH" agently doctor --json > "$TMP/doctor.json"
jq -e --arg release_dir "$release_dir" '.share == $release_dir' "$TMP/doctor.json" >/dev/null || fail "installed agently did not resolve release root"
assert_file "$XDG_STATE_HOME/agently/install.log"
grep -Fq "install success" "$XDG_STATE_HOME/agently/install.log" || fail "install success not logged"
[[ ! -e "$XDG_CONFIG_HOME" ]] || fail "install apply created XDG config"

setup_env unmanaged
mkdir -p "$HOME/.local/bin"
printf '#!/usr/bin/env bash\nprintf unmanaged\n' > "$HOME/.local/bin/agently"
chmod +x "$HOME/.local/bin/agently"
set +e
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" self install --user --from "$ROOT" --apply --json > "$TMP/unmanaged.out" 2> "$TMP/unmanaged.err"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "unmanaged shim should fail apply"
assert_empty "$TMP/unmanaged.out"
assert_json "$TMP/unmanaged.err"
assert_code "$TMP/unmanaged.err" REFUSE_UNMANAGED_SHIM
grep -Fq "unmanaged" "$HOME/.local/bin/agently" || fail "unmanaged shim was overwritten"
assert_not_exists "$XDG_DATA_HOME/agently"

setup_env lock
mkdir -p "$XDG_STATE_HOME/agently"
(
  flock -x 200
  sleep 2
) 200>"$XDG_STATE_HOME/agently/self.lock" &
lock_pid=$!
sleep 0.2
set +e
AGENTLY_SELF_LOCK_TIMEOUT_SECONDS=1 AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" self install --user --from "$ROOT" --apply --json > "$TMP/lock.out" 2> "$TMP/lock.err"
status=$?
set -e
wait "$lock_pid"
[[ "$status" -ne 0 ]] || fail "locked install should fail"
assert_empty "$TMP/lock.out"
assert_json "$TMP/lock.err"
assert_code "$TMP/lock.err" LOCK_FAILED
assert_not_exists "$XDG_DATA_HOME/agently"

setup_env current_not_symlink
mkdir -p "$XDG_DATA_HOME/agently" "$HOME/.local/bin"
printf 'not a symlink\n' > "$XDG_DATA_HOME/agently/current"
cat > "$HOME/.local/bin/agently" <<'SH'
#!/usr/bin/env bash
# AGENTLY-MANAGED-SHIM v1
printf 'old shim\n'
SH
chmod +x "$HOME/.local/bin/agently"
shim_before="$(sha256sum "$HOME/.local/bin/agently" | awk '{ print $1 }')"
set +e
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" self install --user --from "$ROOT" --apply --json > "$TMP/current-not-symlink.out" 2> "$TMP/current-not-symlink.err"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "non-symlink current should fail apply"
assert_empty "$TMP/current-not-symlink.out"
assert_json "$TMP/current-not-symlink.err"
assert_code "$TMP/current-not-symlink.err" STAGED_RELEASE_INVALID
[[ -f "$XDG_DATA_HOME/agently/current" ]] || fail "current marker disappeared"
[[ ! -L "$XDG_DATA_HOME/agently/current" ]] || fail "current marker was converted to symlink"
if [[ -d "$XDG_DATA_HOME/agently/releases" ]] && find "$XDG_DATA_HOME/agently/releases" -mindepth 1 -print | grep -q .; then
  fail "release activation occurred despite non-symlink current"
fi
shim_after="$(sha256sum "$HOME/.local/bin/agently" | awk '{ print $1 }')"
[[ "$shim_before" == "$shim_after" ]] || fail "shim was clobbered after non-symlink current failure"

printf 'self install apply ok\n'
