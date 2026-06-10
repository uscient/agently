#!/usr/bin/env bash
# shellcheck disable=SC2016
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

assert_no_file() {
  [[ ! -e "$1" ]] || fail "unexpected file: $1"
}

assert_dir() {
  [[ -d "$1" ]] || fail "missing dir: $1"
}

assert_no_dir() {
  [[ ! -d "$1" ]] || fail "unexpected dir: $1"
}

assert_contains() {
  local file="$1" needle="$2"
  grep -Fq -- "$needle" "$file" || fail "expected $file to contain: $needle"
}

assert_status_fails() {
  local status="$1" label="$2"
  [[ "$status" -ne 0 ]] || fail "$label should have failed"
}

export HOME="$TMP/home"
mkdir -p "$HOME"

AGENTLY=(env AGENTLY_HOME="$ROOT" "$ROOT/bin/agently")

new_repo() {
  local dir="$1"
  mkdir -p "$dir"
  cd "$dir"
  git init -q
  git config user.email serena-smoke@example.invalid
  git config user.name SerenaSmoke
  printf '# Serena Smoke Repo\n' > README.md
  git add README.md
  git commit -q -m init
}

BASE_PATH="$PATH"

new_repo "$TMP/plain"
"${AGENTLY[@]}" init --codex >/dev/null
assert_no_dir .agently/integrations/serena
assert_no_dir .agently/generated/serena
assert_no_dir .serena
[[ "$("${AGENTLY[@]}" profile get serena.enabled)" == "false" ]] || fail "plain init enabled Serena"
"${AGENTLY[@]}" doctor --serena > "$TMP/plain-doctor.md"
assert_contains "$TMP/plain-doctor.md" "## Serena"

mkdir -p "$TMP/bin"
cat > "$TMP/bin/serena" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  --version)
    printf 'serena 9.9.9\n'
    ;;
  start-mcp-server)
    printf 'fake serena server\n'
    ;;
  project)
    case "${2:-}" in
      generate-yml) printf 'generated_by: fake-serena\n' ;;
      index) printf 'indexed\n' ;;
      *) printf 'fake serena project %s\n' "${2:-}" ;;
    esac
    ;;
  *)
    printf 'fake serena %s\n' "$*"
    ;;
esac
SH
cat > "$TMP/bin/claude" <<'SH'
#!/usr/bin/env bash
printf 'claude %s\n' "$*" >> "$HOME/claude-mcp.log"
if [[ "${1:-} ${2:-}" == "mcp list" ]]; then
  printf 'no servers\n'
fi
SH
chmod +x "$TMP/bin/serena" "$TMP/bin/claude"
export PATH="$TMP/bin:$BASE_PATH"

new_repo "$TMP/serena"
"${AGENTLY[@]}" init --codex --serena --profile serena-review >/dev/null
assert_dir .agently/integrations/serena
assert_file .agently/integrations/serena/README.md
assert_file .agently/integrations/serena/lane-separation.md
assert_file .agently/integrations/serena/state.yml
assert_file .agently/generated/serena/onboard.codex.md
assert_file .agently/generated/serena/onboard.claude-code.md
assert_file .agently/generated/serena/codex.config.toml.example
assert_file .agently/generated/serena/claude-code.commands.sh
assert_file .agently/generated/serena/project.yml.example
assert_no_dir .serena
[[ "$("${AGENTLY[@]}" profile get serena.enabled)" == "true" ]] || fail "Serena not enabled"
[[ "$("${AGENTLY[@]}" profile get serena.profile)" == "review" ]] || fail "Serena profile not normalized"
assert_contains .agently/generated/serena/codex.config.toml.example "--context=codex"
assert_contains .agently/generated/serena/claude-code.commands.sh "--context claude-code"

printf '\nSENTINEL_SERENA_README\n' >> .agently/integrations/serena/README.md
"${AGENTLY[@]}" init --codex --serena >/dev/null
assert_contains .agently/integrations/serena/README.md "SENTINEL_SERENA_README"

"${AGENTLY[@]}" serena status > "$TMP/serena-status.md"
assert_contains "$TMP/serena-status.md" "# Agently Serena Status"
"${AGENTLY[@]}" serena status --json > "$TMP/serena-status.json"
assert_contains "$TMP/serena-status.json" "\"profile\":\"review\""
"${AGENTLY[@]}" doctor --serena > "$TMP/doctor-serena.md"
assert_contains "$TMP/doctor-serena.md" "Serena version"
"${AGENTLY[@]}" mcp status > "$TMP/mcp-status.md"
assert_contains "$TMP/mcp-status.md" "Codex MCP"
printf 'not toml\n[[bad]\n' > "$TMP/malformed.toml"
CODEX_HOME="$TMP" "${AGENTLY[@]}" mcp status --json > "$TMP/mcp-status.json"
assert_contains "$TMP/mcp-status.json" "\"codex\""

"${AGENTLY[@]}" mcp add serena --client codex > "$TMP/mcp-add-codex.md"
assert_contains "$TMP/mcp-add-codex.md" "Snippet"
assert_contains .agently/generated/serena/codex.config.toml.example "--context=codex"
assert_no_file "$HOME/.codex/config.toml"

CODEX_HOME="$TMP/codex-home" "${AGENTLY[@]}" mcp add serena --client codex --apply > "$TMP/mcp-add-codex-apply.md"
assert_file "$TMP/codex-home/config.toml"
assert_contains "$TMP/codex-home/config.toml" "[mcp_servers.serena]"
compgen -G "$TMP/codex-home/config.toml.agently-backup-*" >/dev/null || fail "missing Codex backup"
assert_contains "$TMP/mcp-add-codex-apply.md" "Rollback"
set +e
CODEX_HOME="$TMP/codex-home" "${AGENTLY[@]}" mcp add serena --client codex --apply > "$TMP/mcp-add-existing.out" 2> "$TMP/mcp-add-existing.err"
existing_status=$?
set -e
assert_status_fails "$existing_status" "Codex add existing block"
assert_contains "$TMP/mcp-add-existing.err" "FAIL:"

"${AGENTLY[@]}" mcp add serena --client claude-code > "$TMP/mcp-add-claude.md"
assert_contains "$TMP/mcp-add-claude.md" "claude-code.commands.sh"
assert_contains .agently/generated/serena/claude-code.commands.sh "--context claude-code"
"${AGENTLY[@]}" mcp add serena --client claude-code --apply --scope user >/dev/null
assert_contains "$HOME/claude-mcp.log" "mcp add --scope user serena -- serena start-mcp-server --context claude-code --project-from-cwd"

"${AGENTLY[@]}" serena create-project > "$TMP/create-project.md"
assert_file .agently/generated/serena/project.yml.example
assert_no_file .serena/project.yml
set +e
"${AGENTLY[@]}" serena onboard --client codex --output .serena/onboard.md > "$TMP/onboard-serena-output.out" 2> "$TMP/onboard-serena-output.err"
onboard_serena_output_status=$?
set -e
assert_status_fails "$onboard_serena_output_status" "onboard output under .serena"
assert_contains "$TMP/onboard-serena-output.err" "refusing to write Agently output under .serena"
assert_no_dir .serena
set +e
"${AGENTLY[@]}" serena smoke --output .serena/smoke.md > "$TMP/smoke-serena-output.out" 2> "$TMP/smoke-serena-output.err"
smoke_serena_output_status=$?
set -e
assert_status_fails "$smoke_serena_output_status" "smoke output under .serena"
assert_contains "$TMP/smoke-serena-output.err" "refusing to write Agently output under .serena"
assert_no_dir .serena
"${AGENTLY[@]}" serena create-project --apply --index > "$TMP/create-project-apply.md"
assert_file .serena/project.yml
assert_contains .serena/project.yml "generated_by: fake-serena"

"${AGENTLY[@]}" serena onboard --client codex --dry-run > "$TMP/onboard-dry.md"
assert_contains "$TMP/onboard-dry.md" "Agently did not create memories"
assert_no_dir .serena/memories
"${AGENTLY[@]}" serena onboard --client codex > "$TMP/onboard.md"
assert_contains "$TMP/onboard.md" "Prepared Serena onboarding prompt"
assert_file .agently/reports/serena-onboarding-summary.md
assert_no_dir .serena/memories

mkdir -p .serena/memories
printf 'facts\n' > .serena/memories/project.md
"${AGENTLY[@]}" serena memories list > "$TMP/memories-list.md"
assert_contains "$TMP/memories-list.md" ".serena/memories/project.md"
"${AGENTLY[@]}" serena memories check --mark-reviewed > "$TMP/memories-check.md"
assert_contains "$TMP/memories-check.md" 'Review `.serena/memories/`'
assert_contains .agently/integrations/serena/state.yml "memories_reviewed: true"

before_git="$(git status --short)"
before_mem="$(find .serena/memories -type f -print -exec wc -c {} \; | sort)"
"${AGENTLY[@]}" serena smoke --output "$TMP/serena-smoke.md" >/dev/null
after_git="$(git status --short)"
after_mem="$(find .serena/memories -type f -print -exec wc -c {} \; | sort)"
[[ "$before_git" == "$after_git" ]] || fail "serena smoke changed git status"
[[ "$before_mem" == "$after_mem" ]] || fail "serena smoke changed memories"
"${AGENTLY[@]}" serena smoke --json > "$TMP/serena-smoke.json"
assert_contains "$TMP/serena-smoke.json" "\"ok\":true"

"${AGENTLY[@]}" serena profile set serena-edit >/dev/null
[[ "$("${AGENTLY[@]}" serena profile get)" == "edit" ]] || fail "profile alias did not normalize"
set +e
"${AGENTLY[@]}" serena profile set invalid > "$TMP/profile-invalid.out" 2> "$TMP/profile-invalid.err"
profile_status=$?
set -e
assert_status_fails "$profile_status" "invalid profile"
assert_contains "$TMP/profile-invalid.err" "FAIL:"

AGENTLY_SERENA_CMD="$TMP/bin/serena" "${AGENTLY[@]}" serena status --json > "$TMP/serena-cmd.json"
assert_contains "$TMP/serena-cmd.json" "serena 9.9.9"
AGENTLY_SERENA_CMD="serena --version" "${AGENTLY[@]}" serena status --json > "$TMP/serena-cmd-unsafe.json"
assert_contains "$TMP/serena-cmd-unsafe.json" "\"command_status\""

printf 'serena smoke ok\n'
