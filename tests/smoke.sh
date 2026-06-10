#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

assert_not_exists() {
  [[ ! -e "$1" ]] || fail "unexpected path: $1"
}

assert_contains() {
  local file="$1" needle="$2"
  grep -Fq "$needle" "$file" || fail "expected $file to contain: $needle"
}

assert_not_contains() {
  local file="$1" needle="$2"
  if grep -Fq "$needle" "$file"; then
    fail "expected $file not to contain: $needle"
  fi
}

assert_no_ansi() {
  local file="$1"
  if LC_ALL=C grep -q "$(printf '\033')" "$file"; then
    fail "ANSI byte found in $file"
  fi
}

export HOME="$TMP/home"
export XDG_DATA_HOME="$TMP/xdg-data"
export XDG_STATE_HOME="$TMP/xdg-state"
export XDG_CONFIG_HOME="$TMP/xdg-config"
mkdir -p "$HOME"

cd "$ROOT"
bash -n bin/agently lib/*.sh tests/*.sh

AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" version >/dev/null
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" doctor >/dev/null
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" help > "$TMP/help-dev.out"
assert_contains "$TMP/help-dev.out" "agently status"
assert_contains "$TMP/help-dev.out" "agently workstream"
assert_contains "$TMP/help-dev.out" "agently profile"
assert_contains "$TMP/help-dev.out" "agently self"
assert_contains "$TMP/help-dev.out" "agently evidence"
assert_contains "$TMP/help-dev.out" "agently prompt"

AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" self install --user --from "$ROOT" --apply >/dev/null
export PATH="$HOME/.local/bin:$PATH"
agently version >/dev/null
agently doctor >/dev/null

mkdir -p "$TMP/repo"
cd "$TMP/repo"
git init -q
git config user.email smoke@example.invalid
git config user.name Smoke
printf '# Smoke Repo\n' > README.md
git add README.md
git commit -q -m 'init'

agently init --codex >/dev/null
assert_file AGENTS.md
assert_file .agently/config.yml
assert_file .agently/.gitignore
assert_not_exists .agently/current
assert_file .agently/templates/task/STATE.yaml
assert_file .agently/templates/packets/base/claude.md
assert_file .agently/templates/packets/context-menu.md
assert_not_exists .agently/templates/packets/claude.md
assert_not_exists .agently/templates/packets/codex.md
assert_not_exists .agently/templates/packets/status.md
assert_not_exists .agently/templates/packets/review.md
assert_file .agents/skills/agently-workstream-manager/SKILL.md
assert_file .codex/config.toml.example

agently doctor > "$TMP/doctor.md"
assert_contains "$TMP/doctor.md" "# Agently Doctor Report"
assert_contains "$TMP/doctor.md" "AGENTS.md: found"
agently doctor --codex --claude --serena --json > "$TMP/doctor.json"
assert_contains "$TMP/doctor.json" "\"repo\""
assert_contains "$TMP/doctor.json" "\"tools\""
agently doctor --fix > "$TMP/doctor-fix.md"
assert_contains "$TMP/doctor-fix.md" "Fix Suggestions"
assert_contains "$TMP/doctor-fix.md" "suggestions only"

printf '\nSENTINEL_CONFIG\n' >> .agently/config.yml
printf '\nSENTINEL_AGENTS\n' >> AGENTS.md
printf '\nSENTINEL_WORKSTREAMS\n' >> .agently/workstreams/.gitkeep
agently init --codex >/dev/null
assert_contains .agently/config.yml "SENTINEL_CONFIG"
assert_contains AGENTS.md "SENTINEL_AGENTS"
assert_contains .agently/workstreams/.gitkeep "SENTINEL_WORKSTREAMS"

agently ws new image-pipeline >/dev/null
assert_file .agently/workstreams/image-pipeline/README.md
assert_file .agently/workstreams/image-pipeline/PLAN.md
assert_file .agently/workstreams/image-pipeline/TASKS.md
assert_file .agently/workstreams/image-pipeline/DECISIONS.md
assert_file .agently/workstreams/image-pipeline/HANDOFF.md
assert_file .agently/workstreams/image-pipeline/CODEX.md
assert_file .agently/workstreams/image-pipeline/CLAUDE.md
assert_file .agently/workstreams/image-pipeline/LOG.md
agently ws list > "$TMP/ws-list.out"
assert_contains "$TMP/ws-list.out" "image-pipeline"
agently ws show --workstream image-pipeline > "$TMP/ws-show.md"
assert_contains "$TMP/ws-show.md" "# Workstream:"

agently workstream create agent-tooling >/dev/null
agently workstream list > "$TMP/workstream-list.out"
assert_contains "$TMP/workstream-list.out" "agent-tooling"
agently workstream status agent-tooling > "$TMP/workstream-status.md"
assert_contains "$TMP/workstream-status.md" "# Workstream Status: agent-tooling"
assert_contains "$TMP/workstream-status.md" "HANDOFF.md"
agently workstream open agent-tooling > "$TMP/workstream-open.md"
assert_contains "$TMP/workstream-open.md" "PLAN.md"

agently task new verify-signatures --workstream image-pipeline >/dev/null
agently task list --workstream image-pipeline > "$TMP/task-list.out"
assert_contains "$TMP/task-list.out" "verify-signatures draft"
agently task status --workstream image-pipeline --task verify-signatures > "$TMP/task-status.md"
assert_contains "$TMP/task-status.md" "status: draft"

printf 'Verify image signatures before deploy.\n' | agently doc replace requirements --workstream image-pipeline --task verify-signatures >/dev/null
agently doc show requirements --workstream image-pipeline --task verify-signatures > "$TMP/requirements.md"
assert_contains "$TMP/requirements.md" "Verify image signatures before deploy."
agently doc path requirements --workstream image-pipeline --task verify-signatures > "$TMP/requirements.path"
assert_contains "$TMP/requirements.path" ".agently/workstreams/image-pipeline/tasks/verify-signatures/REQUIREMENTS.md"

agently profile list > "$TMP/profile-list.out"
assert_contains "$TMP/profile-list.out" "codex.model"
agently profile get > "$TMP/profile-get.md"
assert_contains "$TMP/profile-get.md" "# Agently Profile"
agently profile set codex.model gpt-5.5 >/dev/null
agently profile set codex.reasoning xhigh >/dev/null
agently profile set codex.auto_edit true >/dev/null
agently profile set claude.reasoning max >/dev/null
[[ "$(agently profile get codex.model)" == "gpt-5.5" ]] || fail "wrong codex model"
assert_contains .agently/.gitignore "local.yml"

agently status > "$TMP/status.md"
assert_contains "$TMP/status.md" "# Agently Status"
agently status --workstream image-pipeline --json > "$TMP/status.json"
assert_contains "$TMP/status.json" "\"workstream\""
assert_contains "$TMP/status.json" "image-pipeline"

agently evidence > "$TMP/evidence.md"
assert_contains "$TMP/evidence.md" "# Evidence Pack"
assert_contains "$TMP/evidence.md" "## Git Status"
agently evidence --output "$TMP/evidence-output.md" >/dev/null
assert_file "$TMP/evidence-output.md"
agently evidence --json > "$TMP/evidence.json"
assert_contains "$TMP/evidence.json" "\"repo\""
set +e
agently evidence --since does-not-exist > "$TMP/evidence-missing-base.out" 2> "$TMP/evidence-missing-base.err"
missing_base_status=$?
set -e
[[ "$missing_base_status" -ne 0 ]] || fail "evidence should fail for missing base"
assert_contains "$TMP/evidence-missing-base.err" "FAIL: base not found"

agently prompt codex --workstream image-pipeline --task verify-signatures > "$TMP/prompt-codex.md"
assert_contains "$TMP/prompt-codex.md" "# Agently Codex Prompt"
assert_contains "$TMP/prompt-codex.md" "You may auto-edit freely within the requested scope"
agently prompt claude --workstream image-pipeline --objective "Review signature verification risks." > "$TMP/prompt-claude.md"
assert_contains "$TMP/prompt-claude.md" "# Agently Claude Prompt"
assert_contains "$TMP/prompt-claude.md" "Plan and review by default"
agently prompt review --from "$TMP/evidence.md" > "$TMP/prompt-review.md"
assert_contains "$TMP/prompt-review.md" "# Agently Review Prompt"
agently prompt --output .agently/workstreams/image-pipeline/prompts/codex.md codex --workstream image-pipeline --objective "Implement prompt output check." >/dev/null
assert_file .agently/workstreams/image-pipeline/prompts/codex.md
agently workstream prompt image-pipeline --for codex > "$TMP/workstream-prompt.md"
assert_contains "$TMP/workstream-prompt.md" "# Agently Codex Prompt"
agently workstream handoff image-pipeline --for claude > "$TMP/workstream-handoff.md"
assert_contains "$TMP/workstream-handoff.md" "Resume Instruction"

agently claude config > "$TMP/claude-config.md"
assert_contains "$TMP/claude-config.md" "model: opus"
agently claude config --model opus --effort xhigh > "$TMP/claude-config-updated.md"
assert_contains "$TMP/claude-config-updated.md" "effort: xhigh"
AGENTLY_CLAUDE_MODEL=sonnet AGENTLY_CLAUDE_EFFORT=high agently claude config > "$TMP/claude-config-env.md"
assert_contains "$TMP/claude-config-env.md" "model: sonnet"
assert_contains "$TMP/claude-config-env.md" "effort: high"

agently task set-state requirements_ready --workstream image-pipeline --task verify-signatures >/dev/null
for packet in claude codex status review; do
  agently packet "$packet" --workstream image-pipeline --task verify-signatures > "$TMP/packet-$packet.md"
  head -n 1 "$TMP/packet-$packet.md" | grep -q '^<base_contract profile=' || fail "packet $packet did not use compiler output"
  [[ -s "$TMP/packet-$packet.md" ]] || fail "empty packet: $packet"
  assert_contains "$TMP/packet-$packet.md" "<cache_breakpoint/>"
  assert_no_ansi "$TMP/packet-$packet.md"
done

cat > "$TMP/fake-claude" <<'SH'
#!/usr/bin/env bash
cat <<'MD'
# Plan
1. Read signature manifest.
2. Verify with cosign.
3. Gate deploy.
MD
SH
chmod +x "$TMP/fake-claude"

AGENTLY_CLAUDE_CMD="$TMP/fake-claude" agently claude plan --workstream image-pipeline --task verify-signatures > "$TMP/claude-request.md"
TASK_DIR=".agently/workstreams/image-pipeline/tasks/verify-signatures"
assert_file "$TASK_DIR/handoffs/claude/001-request.md"
assert_file "$TASK_DIR/handoffs/claude/001-response.md"
assert_file "$TASK_DIR/handoffs/claude/001-receipt.md"
assert_contains "$TASK_DIR/handoffs/claude/001-receipt.md" "command_source: AGENTLY_CLAUDE_CMD"
assert_not_contains "$TASK_DIR/STATE.yaml" "claude_model:"
assert_not_contains "$TASK_DIR/STATE.yaml" "claude_effort:"
assert_contains "$TASK_DIR/STATE.yaml" "last_handoff_agent: claude"
assert_contains "$TASK_DIR/STATE.yaml" "last_handoff_model: opus"
assert_contains "$TASK_DIR/STATE.yaml" "last_handoff_reasoning: xhigh"
assert_contains "$TASK_DIR/STATE.yaml" "last_handoff_path: handoffs/claude/001-receipt.md"
agently task status --workstream image-pipeline --task verify-signatures > "$TMP/status-after-claude.md"
assert_contains "$TMP/status-after-claude.md" "status: claude_response_ready"

AGENTLY_CLAUDE_CMD="/nonexistent/claude" agently claude followup --workstream image-pipeline --task verify-signatures > "$TMP/claude-followup.md"
assert_file "$TASK_DIR/handoffs/claude/002-request.md"
assert_file "$TASK_DIR/handoffs/claude/002-receipt.md"
assert_not_contains "$TASK_DIR/STATE.yaml" "claude_model:"
assert_not_contains "$TASK_DIR/STATE.yaml" "claude_effort:"
assert_contains "$TASK_DIR/STATE.yaml" "last_handoff_path: handoffs/claude/002-receipt.md"
agently task status --workstream image-pipeline --task verify-signatures > "$TMP/status-after-fallback.md"
assert_contains "$TMP/status-after-fallback.md" "status: claude_request_ready"

agently eval claude --workstream image-pipeline --task verify-signatures > "$TMP/review-packet.md"
agently report --workstream image-pipeline --task verify-signatures > "$TMP/decision-report.md"
agently decide accept --workstream image-pipeline --task verify-signatures --note "looks good" >/dev/null
assert_file "$TASK_DIR/handoffs/codex/001-eval.md"
assert_file "$TASK_DIR/handoffs/codex/001-decision-report.md"
assert_file "$TASK_DIR/decisions/001-decision.md"
agently task status --workstream image-pipeline --task verify-signatures > "$TMP/status-after-decision.md"
assert_contains "$TMP/status-after-decision.md" "status: accepted"

agently guard > "$TMP/guard.out"
agently guard scope > "$TMP/guard-scope.out"
assert_contains "$TMP/guard.out" "# Agently Guard Report"
assert_contains "$TMP/guard-scope.out" "# Agently Scope Guard"

mkdir -p "$TMP/not-git"
cd "$TMP/not-git"
set +e
agently status > "$TMP/not-git-status.out" 2> "$TMP/not-git-status.err"
not_git_status=$?
set -e
[[ "$not_git_status" -ne 0 ]] || fail "status should fail outside git repo"
assert_contains "$TMP/not-git-status.err" "FAIL:"
cd "$TMP/repo"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$ROOT/bin/agently" "$ROOT"/lib/*.sh "$ROOT"/tests/*.sh
fi

"$ROOT/tests/packet-compiler.sh"
"$ROOT/tests/context.sh"
"$ROOT/tests/directory-amnesia.sh"
"$ROOT/tests/handle-addressing.sh"
"$ROOT/tests/missing-handle.sh"
"$ROOT/tests/pointer-removal.sh"
"$ROOT/tests/inspect.sh"
"$ROOT/tests/patch.sh"
"$ROOT/tests/evidence.sh"
"$ROOT/tests/guard.sh"
"$ROOT/tests/eval.sh"
"$ROOT/tests/workstream-branch.sh"
"$ROOT/tests/ws-spine-json.sh"
"$ROOT/tests/ws-spine-ingest.sh"
"$ROOT/tests/ws-spine-escrow.sh"
"$ROOT/tests/ws-spine-promote.sh"
"$ROOT/tests/ws-spine-reject.sh"
"$ROOT/tests/ws-spine-doctor.sh"
"$ROOT/tests/ws-spine-concurrency.sh"
"$ROOT/tests/self-status.sh"
"$ROOT/tests/self-install-dryrun.sh"
"$ROOT/tests/self-uninstall-dryrun.sh"
"$ROOT/tests/self-ghost.sh"
"$ROOT/tests/self-install-apply.sh"
"$ROOT/tests/self-uninstall-confirm.sh"
"$ROOT/tests/launcher-resolution.sh"
"$ROOT/tests/config-modern-only.sh"
"$ROOT/tests/profile-flat-keys.sh"
"$ROOT/tests/config-allowlist.sh"
"$ROOT/tests/protected-surfaces.sh"
"$ROOT/tests/security-adversarial.sh"
"$ROOT/tests/config-precedence.sh"
"$ROOT/tests/profile-set-preserves-sections.sh"
"$ROOT/tests/config-get-top.sh"
"$ROOT/tests/serena.sh"

git status --short
find .agently -type f | sort
printf 'smoke ok\n'
