#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

export HOME="$TMP/home"
export XDG_DATA_HOME="$TMP/xdg-data"
export XDG_STATE_HOME="$TMP/xdg-state"
export XDG_CONFIG_HOME="$TMP/xdg-config"
export AGENTLY_SHARE="$ROOT"
mkdir -p "$HOME" "$TMP/repo"

source "$ROOT/lib/config-keys.sh"
source "$ROOT/lib/common.sh"

AGENTLY=(env AGENTLY_HOME="$ROOT" "$ROOT/bin/agently")

cd "$TMP/repo"
git init -q
git config user.email config-get-top@example.invalid
git config user.name ConfigGetTop
printf '# Config Get Top\n' > README.md
git add README.md
git commit -q -m init

"${AGENTLY[@]}" init --codex >/dev/null
"${AGENTLY[@]}" ws new top >/dev/null
"${AGENTLY[@]}" task new check --workstream top >/dev/null

marker=".agently/doctrine/.agently-doctrine-snapshot.yml"
marker_hash="$(config_get_top "$marker" manifest_hash)"
[[ -n "$marker_hash" ]] || fail "config_get_top did not read doctrine marker"

state=".agently/workstreams/top/tasks/check/STATE.yaml"
[[ "$(config_get_top "$state" status)" == "draft" ]] || fail "config_get_top did not read task STATE.yaml"

meta=".agently/workstreams/top/artifacts/patches/001/meta.yml"
mkdir -p "$(dirname "$meta")"
printf 'status: proposed\nfiles: 2\n' > "$meta"
[[ "$(config_get_top "$meta" status)" == "proposed" ]] || fail "config_get_top did not read patch meta status"
[[ "$(config_get_top "$meta" files)" == "2" ]] || fail "config_get_top did not read patch meta files"

printf 'config get top ok\n'
