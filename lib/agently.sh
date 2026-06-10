#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  echo "FAIL: agently lib must be executed, not sourced" >&2
  return 1 2>/dev/null || exit 1
fi

[[ -n "${AGENTLY_SHARE:-}" ]] || {
  echo "FAIL: AGENTLY_SHARE is not set" >&2
  exit 1
}

# shellcheck source=config-keys.sh
source "$AGENTLY_SHARE/lib/config-keys.sh"
# shellcheck source=common.sh
source "$AGENTLY_SHARE/lib/common.sh"

agently_config_reserved_env_guard

# shellcheck source=detect.sh
source "$AGENTLY_SHARE/lib/detect.sh"
# shellcheck source=cmd-init.sh
source "$AGENTLY_SHARE/lib/cmd-init.sh"
# shellcheck source=cmd-doctrine.sh
source "$AGENTLY_SHARE/lib/cmd-doctrine.sh"
# shellcheck source=cmd-ws.sh
source "$AGENTLY_SHARE/lib/cmd-ws.sh"
# shellcheck source=spine.sh
source "$AGENTLY_SHARE/lib/spine.sh"
# shellcheck source=cmd-ws-spine.sh
source "$AGENTLY_SHARE/lib/cmd-ws-spine.sh"
# shellcheck source=self.sh
source "$AGENTLY_SHARE/lib/self.sh"
# shellcheck source=cmd-self.sh
source "$AGENTLY_SHARE/lib/cmd-self.sh"
# shellcheck source=cmd-task.sh
source "$AGENTLY_SHARE/lib/cmd-task.sh"
# shellcheck source=cmd-docs.sh
source "$AGENTLY_SHARE/lib/cmd-docs.sh"
# shellcheck source=cmd-packet.sh
source "$AGENTLY_SHARE/lib/cmd-packet.sh"
# shellcheck source=cmd-context.sh
source "$AGENTLY_SHARE/lib/cmd-context.sh"
# shellcheck source=cmd-inspect.sh
source "$AGENTLY_SHARE/lib/cmd-inspect.sh"
# shellcheck source=cmd-patch.sh
source "$AGENTLY_SHARE/lib/cmd-patch.sh"
# shellcheck source=cmd-claude.sh
source "$AGENTLY_SHARE/lib/cmd-claude.sh"
# shellcheck source=cmd-guard.sh
source "$AGENTLY_SHARE/lib/cmd-guard.sh"
# shellcheck source=cmd-eval.sh
source "$AGENTLY_SHARE/lib/cmd-eval.sh"
# shellcheck source=cmd-tooling.sh
source "$AGENTLY_SHARE/lib/cmd-tooling.sh"
# shellcheck source=cmd-serena.sh
source "$AGENTLY_SHARE/lib/cmd-serena.sh"

agently_help() {
  cat <<'EOF'
Agently - deterministic workflow API for Codex-operated projects

Usage:
  agently [--project DIR] <command> ...
  agently init --codex [--serena] [--profile lite|review|edit] [--project DIR|--target DIR] [--name NAME] [--force] [--dry-run] [--allow-non-git]
  agently doctrine <status|refresh>
  agently doctor [--codex] [--claude] [--serena] [--fix] [--json]
  agently status [--workstream NAME] [--json]
  agently workstream <list|create|new|open|status|prompt|handoff>
  agently profile <list|get|set>
  agently serena <status|create-project|onboard|memories|profile|smoke>
  agently self <status|install|uninstall>
  agently mcp <status|add|remove>
  agently evidence [--since BASE] [--tests] [--output PATH] [--json]
  agently prompt <codex|claude|review> ...
  agently version
  agently ws <list|new|show|path|init|status|summary|ingest|propose|reject|promote|doctor>
  agently task <list|new|show|path|status|docs|set-state>
  agently docs
  agently doc <show|path|edit|replace> <name>
  agently packet <claude|codex|status|review> --workstream NAME [--task NAME]
  agently packet --profile <claude|codex|generic> [--workstream NAME] [--task NAME] [--budget small|normal|full]
  agently context <budget|manifest>
  agently compact <workstream|doctrine>
  agently inspect <symbols|skeleton|read|grep|sg|tree|doc>
  agently patch <propose|check|apply|list|show|reject|explain>
  agently claude <config|plan|followup>
  agently eval [claude|patch]
  agently report
  agently decide <accept|revise|reject>
  agently guard [--changed] [--file PATH] [--lang LANG] [--strict]

Agently writes workflow state as files, compiles bounded context packets, and
runs guard/eval checks through detected local tools.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      option_has_value "$@" || die "--project requires a value"
      export AGENTLY_PROJECT="$2"
      shift 2
      ;;
    --project=*)
      export AGENTLY_PROJECT="${1#--project=}"
      [[ -n "$AGENTLY_PROJECT" ]] || die "--project requires a value"
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

cmd="${1:-help}"
if [[ $# -gt 0 ]]; then
  shift
fi

case "$cmd" in
  init) cmd_init "$@" ;;
  doctrine) cmd_doctrine "$@" ;;
  doctor) cmd_doctor "$@" ;;
  status) cmd_status "$@" ;;
  workstream) cmd_workstream "$@" ;;
  profile) cmd_profile "$@" ;;
  serena) cmd_serena "$@" ;;
  self) cmd_self "$@" ;;
  mcp) cmd_mcp "$@" ;;
  evidence) cmd_evidence "$@" ;;
  prompt) cmd_prompt "$@" ;;
  version) printf 'Agently %s\n' "$(agently_version)" ;;
  help|-h|--help|"") agently_help ;;
  ws) cmd_ws "$@" ;;
  task) cmd_task "$@" ;;
  docs) cmd_docs "$@" ;;
  doc) cmd_doc "$@" ;;
  packet) cmd_packet "$@" ;;
  context) cmd_context "$@" ;;
  compact) cmd_compact "$@" ;;
  inspect) cmd_inspect "$@" ;;
  patch) cmd_patch "$@" ;;
  claude) cmd_claude "$@" ;;
  eval) cmd_eval "$@" ;;
  report) cmd_report "$@" ;;
  decide) cmd_decide "$@" ;;
  guard) cmd_guard "$@" ;;
  *) die "unknown command: $cmd" ;;
esac
