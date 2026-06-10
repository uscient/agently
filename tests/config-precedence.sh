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
mkdir -p "$HOME" "$TMP/repo"

AGENTLY=(env AGENTLY_HOME="$ROOT" "$ROOT/bin/agently")

cd "$TMP/repo"
git init -q
git config user.email config-precedence@example.invalid
git config user.name ConfigPrecedence
printf '# Config Precedence\n' > README.md
git add README.md
git commit -q -m init

"${AGENTLY[@]}" init --codex >/dev/null
"${AGENTLY[@]}" profile set claude.reasoning low >/dev/null

"${AGENTLY[@]}" claude config > "$TMP/config.md"
assert_contains "$TMP/config.md" "effort: low"

AGENTLY_CLAUDE_EFFORT=high "${AGENTLY[@]}" claude config > "$TMP/env.md"
assert_contains "$TMP/env.md" "effort: high"

cat > "$TMP/fake-claude" <<'SH'
#!/usr/bin/env bash
printf '# Fake Claude\n'
SH
chmod +x "$TMP/fake-claude"

"${AGENTLY[@]}" ws new precedence >/dev/null
"${AGENTLY[@]}" task new check --workstream precedence >/dev/null
AGENTLY_CLAUDE_EFFORT=high AGENTLY_CLAUDE_CMD="$TMP/fake-claude" "${AGENTLY[@]}" claude plan --workstream precedence --task check --effort xhigh > "$TMP/flag.md"
assert_contains .agently/workstreams/precedence/tasks/check/handoffs/claude/001-receipt.md "effort: xhigh"

cat > .agently/local.yml <<'YAML'
agents:
  claude:
    model: sonnet
    reasoning: max
YAML

[[ "$("${AGENTLY[@]}" profile get claude.model)" == "sonnet" ]] || fail "local.yml did not affect profile display"
[[ "$("${AGENTLY[@]}" profile get claude.reasoning)" == "max" ]] || fail "local.yml did not affect profile reasoning display"

"${AGENTLY[@]}" claude config > "$TMP/local-not-invocation.md"
assert_contains "$TMP/local-not-invocation.md" "model: opus"
assert_contains "$TMP/local-not-invocation.md" "effort: low"

printf 'config precedence ok\n'
