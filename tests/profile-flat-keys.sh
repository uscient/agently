#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

export HOME="$TMP/home"
export XDG_DATA_HOME="$TMP/xdg-data"
export XDG_STATE_HOME="$TMP/xdg-state"
export XDG_CONFIG_HOME="$TMP/xdg-config"
mkdir -p "$HOME" "$TMP/repo/.agently"

cd "$TMP/repo"
git init -q
git config user.email profile@example.invalid
git config user.name Profile
printf '# Profile Test\n' > README.md
git add README.md
git commit -q -m init

cat > .agently/config.yml <<'YAML'
project: profile-test
agents:
  claude:
    model: sonnet
    reasoning: high
YAML

[[ "$(AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" profile get claude.model)" == "sonnet" ]] || fail "nested claude.model did not resolve"
[[ "$(AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" profile get claude.reasoning)" == "high" ]] || fail "nested claude.reasoning did not resolve"

cat > .agently/config.yml <<'YAML'
project: profile-test
claude_model: forged-model
claude_effort: forged-effort
YAML

[[ "$(AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" profile get claude.model)" == "opus" ]] || fail "flat claude_model was resolved"
[[ "$(AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" profile get claude.reasoning)" == "max" ]] || fail "flat claude_effort was resolved"

cat > .agently/config.yml <<'YAML'
project: profile-test
agents:
  claude:
    model: opus
    reasoning: high
YAML

cat > .agently/local.yml <<'YAML'
agents:
  claude:
    model: sonnet
YAML

[[ "$(AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" profile get claude.model)" == "sonnet" ]] || fail "local.yml profile display override did not resolve"

cat > .agently/local.yml <<'YAML'
agents:
  claude:
    model: sonnet
review:
  required: false
YAML

set +e
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" profile get claude.model > "$TMP/local-authority.out" 2> "$TMP/local-authority.err"
local_authority_status=$?
set -e
[[ "$local_authority_status" -ne 0 ]] || fail "local.yml authority-shaped key should fail"
grep -Fq "authority-shaped config key" "$TMP/local-authority.err" || fail "local.yml authority rejection missing"

printf 'profile flat keys ok\n'
