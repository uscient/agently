#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_contains() { grep -Fq "$2" "$1" || fail "expected $1 to contain: $2"; }

export HOME="$TMP/home"
export XDG_DATA_HOME="$TMP/xdg-data"
export XDG_STATE_HOME="$TMP/xdg-state"
export XDG_CONFIG_HOME="$TMP/xdg-config"
mkdir -p "$HOME"

orphan="$TMP/orphan/bin/agently"
mkdir -p "$(dirname "$orphan")" "$XDG_DATA_HOME/agently/lib"
cp "$ROOT/bin/agently" "$orphan"
chmod +x "$orphan"
cat > "$XDG_DATA_HOME/agently/lib/agently.sh" <<'SH'
#!/usr/bin/env bash
printf 'flat launched\n'
SH
printf '0.0.flat\n' > "$XDG_DATA_HOME/agently/VERSION"

set +e
"$orphan" version > "$TMP/orphan.out" 2> "$TMP/orphan.err"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "orphan launcher should fail without AGENTLY_HOME or sibling lib"
assert_contains "$TMP/orphan.err" "FAIL: cannot locate agently lib"
if grep -Fq "flat launched" "$TMP/orphan.out"; then
  fail "launcher used removed XDG fallback"
fi

AGENTLY_HOME="$ROOT" "$orphan" version > "$TMP/agently-home.out" 2> "$TMP/agently-home.err"
assert_contains "$TMP/agently-home.out" "Agently"

unset AGENTLY_HOME
"$ROOT/bin/agently" version > "$TMP/checkout.out" 2> "$TMP/checkout.err"
assert_contains "$TMP/checkout.out" "Agently"

AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" self install --user --from "$ROOT" --apply --json > "$TMP/install.json" 2> "$TMP/install.err"
"$XDG_DATA_HOME/agently/current/bin/agently" version > "$TMP/release.out" 2> "$TMP/release.err"
assert_contains "$TMP/release.out" "Agently"

printf 'launcher resolution ok\n'
