#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_contains() { grep -Fq "$2" "$1" || fail "expected $1 to contain: $2"; }
regex_escape() { printf '%s' "$1" | sed 's/[][(){}.^$+*?|\\]/\\&/g'; }
assert_refusal() {
  local file="$1" regex="$2"
  grep -Eq -- "$regex" "$file" || fail "expected $file to match: $regex"
}
assert_no_mutation() {
  local file="$1" baseline="$2"
  cmp -s "$file" "$baseline" || fail "unexpected mutation in $file"
}
assert_status_fails() {
  local status="$1" label="$2"
  [[ "$status" -ne 0 ]] || fail "$label should have failed"
}

export HOME="$TMP/home"
export XDG_DATA_HOME="$TMP/xdg-data"
export XDG_STATE_HOME="$TMP/xdg-state"
export XDG_CONFIG_HOME="$TMP/xdg-config"
mkdir -p "$HOME" "$TMP/repo"

AGENTLY=(env AGENTLY_HOME="$ROOT" "$ROOT/bin/agently")

cd "$TMP/repo"
git init -q
git config user.email config-allowlist@example.invalid
git config user.name ConfigAllowlist
printf '# Config Allowlist\n' > README.md
git add README.md
git commit -q -m init

"${AGENTLY[@]}" init --codex >/dev/null
cp .agently/config.yml "$TMP/base-config.yml"
"${AGENTLY[@]}" ws new allowlist >/dev/null
"${AGENTLY[@]}" task new verify --workstream allowlist >/dev/null
state_file=".agently/workstreams/allowlist/tasks/verify/STATE.yaml"
cp "$state_file" "$TMP/state.before"

expect_config_rejected_contains() {
  local label="$1" payload="$2" needle="$3" status
  cp "$TMP/base-config.yml" .agently/config.yml
  printf '\n%s\n' "$payload" >> .agently/config.yml
  set +e
  "${AGENTLY[@]}" profile get claude.model > "$TMP/$label.out" 2> "$TMP/$label.err"
  status=$?
  set -e
  assert_status_fails "$status" "$label"
  assert_contains "$TMP/$label.err" "$needle"
}

expect_config_refused() {
  local label="$1" payload="$2" message="$3" status before
  before="$TMP/$label.config.before"
  cp "$TMP/base-config.yml" .agently/config.yml
  printf '\n%s\n' "$payload" >> .agently/config.yml
  cp .agently/config.yml "$before"
  set +e
  "${AGENTLY[@]}" profile get claude.model > "$TMP/$label.out" 2> "$TMP/$label.err"
  status=$?
  set -e
  assert_status_fails "$status" "$label"
  assert_refusal "$TMP/$label.err" "^FAIL: $(regex_escape "$message")$"
  assert_no_mutation .agently/config.yml "$before"
  assert_no_mutation "$state_file" "$TMP/state.before"
}

expect_config_rejected_contains unknown_key 'unknown_option: true' 'unknown config key'
expect_config_refused review_required 'review.required: false' 'authority-shaped config key is not accepted: review.required'
expect_config_refused authority_source 'authority.source_of_truth: chat' 'authority-shaped config key is not accepted: authority.source_of_truth'
expect_config_refused promotion_gate 'promotion.gate: auto' 'authority-shaped config key is not accepted: promotion.gate'
expect_config_refused source_of_truth 'source_of_truth: chat' 'authority-shaped config key is not accepted: source_of_truth'
expect_config_refused doctrine_rules 'doctrine.rules.locked: false' 'authority-shaped config key is not accepted: doctrine.rules.locked'
expect_config_refused reserved_ag_cfg 'ag.cfg.review_required: false' 'reserved config namespace is not accepted: ag.cfg.review_required'
expect_config_refused reserved_ag_meta 'ag.meta.doctrine_locked: false' 'reserved config namespace is not accepted: ag.meta.doctrine_locked'

cp "$TMP/base-config.yml" .agently/config.yml

set +e
env AG_META_DOCTRINE_LOCKED=false AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" doctor > "$TMP/ag-meta.out" 2> "$TMP/ag-meta.err"
ag_meta_status=$?
env AG_CFG_REVIEW_REQUIRED=false AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" doctor > "$TMP/ag-cfg-authority.out" 2> "$TMP/ag-cfg-authority.err"
ag_cfg_authority_status=$?
env AG_CFG_CONTEXT_DEFAULT_BUDGET=full AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" doctor > "$TMP/ag-cfg-arbitrary.out" 2> "$TMP/ag-cfg-arbitrary.err"
ag_cfg_arbitrary_status=$?
set -e
assert_status_fails "$ag_meta_status" "AG_META injection"
assert_status_fails "$ag_cfg_authority_status" "AG_CFG authority injection"
assert_status_fails "$ag_cfg_arbitrary_status" "AG_CFG arbitrary injection"
assert_refusal "$TMP/ag-meta.err" "^FAIL: reserved environment namespace is not accepted: AG_META_DOCTRINE_LOCKED$"
assert_refusal "$TMP/ag-cfg-authority.err" "^FAIL: reserved environment namespace is not accepted: AG_CFG_REVIEW_REQUIRED$"
assert_refusal "$TMP/ag-cfg-arbitrary.err" "^FAIL: reserved environment namespace is not accepted: AG_CFG_CONTEXT_DEFAULT_BUDGET$"
assert_no_mutation .agently/config.yml "$TMP/base-config.yml"
assert_no_mutation "$state_file" "$TMP/state.before"

AGENTLY_CLAUDE_MODEL=sonnet AGENTLY_CLAUDE_EFFORT=high "${AGENTLY[@]}" claude config > "$TMP/claude-env.md"
assert_contains "$TMP/claude-env.md" "model: sonnet"
assert_contains "$TMP/claude-env.md" "effort: high"

cp "$TMP/base-config.yml" .agently/config.yml
printf '\nstatus: done\nround: 99\n' >> .agently/config.yml
cp .agently/config.yml "$TMP/state-config.before"
set +e
"${AGENTLY[@]}" task status --workstream allowlist --task verify > "$TMP/state-config.out" 2> "$TMP/state-config.err"
state_config_status=$?
set -e
assert_status_fails "$state_config_status" "state-shaped config keys"
assert_refusal "$TMP/state-config.err" '^FAIL: unknown config key in \.agently/config\.yml line [0-9]+: status$'
assert_no_mutation .agently/config.yml "$TMP/state-config.before"
assert_no_mutation "$state_file" "$TMP/state.before"

cp "$TMP/base-config.yml" .agently/config.yml
set +e
env AG_CFG_STATUS=done AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" task status --workstream allowlist --task verify > "$TMP/state-env.out" 2> "$TMP/state-env.err"
state_env_status=$?
set -e
assert_status_fails "$state_env_status" "state-shaped AG_CFG"
assert_refusal "$TMP/state-env.err" '^FAIL: reserved environment namespace is not accepted: AG_CFG_STATUS$'
assert_no_mutation .agently/config.yml "$TMP/base-config.yml"
assert_no_mutation "$state_file" "$TMP/state.before"

printf 'config allowlist ok\n'
