#!/usr/bin/env bash

agently_config_fail() {
  if declare -F die >/dev/null 2>&1; then
    die "$*"
  fi
  echo "FAIL: $*" >&2
  exit 1
}

agently_config_key_allowed() {
  local key="$1"
  case "$key" in
    context.default_budget|context.log_tail_lines|context.ledger_tail_lines|context.doctrine_mode|context.cache_dir) return 0 ;;
    inspect.prefer_ripgrep|inspect.max_grep_matches|inspect.max_full_lines|inspect.tree_depth) return 0 ;;
    guard.strict_missing_tools|guard.languages) return 0 ;;
    eval.use_worktree) return 0 ;;
    patch.dir|patch.require_reviewed) return 0 ;;
    codex.model|codex.reasoning|codex.auto_edit) return 0 ;;
    claude.model|claude.reasoning) return 0 ;;
    serena.enabled|serena.profile) return 0 ;;
    test_command|claude_permission_mode|claude_max_turns) return 0 ;;
    project|profile|agently_version|created_at) return 0 ;;
    workstreams.branch.mode|workstreams.branch.prefix|workstreams.branch.checkout_on_create) return 0 ;;
    workstreams.branch.require_clean_tree|workstreams.branch.if_exists|workstreams.branch.base) return 0 ;;
    workstreams.branch.push_on_create|workstreams.branch.set_upstream|workstreams.branch.delete_on_close) return 0 ;;
    ws.spine.schema_version|ws.spine.max_payload_bytes|ws.spine.lock_timeout_seconds|ws.spine.confirm_timeout_seconds) return 0 ;;
    *) return 1 ;;
  esac
}

agently_config_ignored_legacy_key() {
  case "$1" in
    claude_model|claude_effort) return 0 ;;
    *) return 1 ;;
  esac
}

agently_config_local_key_allowed() {
  case "$1" in
    codex.model|codex.reasoning|codex.auto_edit|claude.model|claude.reasoning|serena.enabled|serena.profile) return 0 ;;
    *) return 1 ;;
  esac
}

agently_config_public_env_allowed() {
  case "$1" in
    AGENTLY_PROJECT|AGENTLY_CLAUDE_CMD|AGENTLY_CLAUDE_MODEL|AGENTLY_CLAUDE_EFFORT|AGENTLY_SERENA_CMD) return 0 ;;
    *) return 1 ;;
  esac
}

agently_config_authority_key_matches() {
  local raw="$1" lower dot
  lower="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  lower="${lower#ag_cfg_}"
  lower="${lower#ag_meta_}"
  dot="${lower//_/.}"
  case "$lower" in
    authority|authority.*|doctrine|doctrine.*) return 0 ;;
    guard.required|review|review.required|promotion|promotion.*) return 0 ;;
    source_of_truth|source_of_truth.*|agent|agent.write_boundary) return 0 ;;
    agents_may_write_doctrine|review_required|agent_write_boundary) return 0 ;;
  esac
  case "$dot" in
    authority|authority.*|doctrine|doctrine.*) return 0 ;;
    guard.required|review|review.required|promotion|promotion.*) return 0 ;;
    source.of.truth|source.of.truth.*|agent|agent.write.boundary|agents.may.write.doctrine) return 0 ;;
  esac
  return 1
}

agently_config_reject_authority_key() {
  local key="$1" lower
  lower="$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    ag_cfg_*|ag_meta_*|ag.cfg.*|ag.meta.*)
      agently_config_fail "reserved config namespace is not accepted: $key"
      ;;
  esac
  if agently_config_authority_key_matches "$key"; then
    agently_config_fail "authority-shaped config key is not accepted: $key"
  fi
}

agently_config_default_for() {
  local key="$1"
  case "$key" in
    context.*|inspect.*|guard.*|eval.*|patch.*)
      if declare -F agently_config_default >/dev/null 2>&1; then
        agently_config_default "${key%%.*}" "${key#*.}"
        return $?
      fi
      ;;
    codex.*|claude.*|serena.*)
      if declare -F profile_default_value >/dev/null 2>&1; then
        profile_default_value "$key"
        return $?
      fi
      ;;
    workstreams.branch.*)
      if declare -F workstream_branch_default >/dev/null 2>&1; then
        workstream_branch_default "${key#workstreams.branch.}"
        return $?
      fi
      ;;
    ws.spine.*)
      if declare -F ws_spine_config_default >/dev/null 2>&1; then
        ws_spine_config_default "${key#ws.spine.}"
        return $?
      fi
      ;;
    claude_permission_mode) printf 'plan\n'; return 0 ;;
    claude_max_turns) printf '6\n'; return 0 ;;
  esac
  return 1
}

agently_config_validate_env_override() {
  local env_name="$1" key="${2:-}"
  agently_config_public_env_allowed "$env_name" || agently_config_fail "unsupported Agently environment override: $env_name"
  if [[ -n "$key" ]]; then
    agently_config_reject_authority_key "$key"
    agently_config_key_allowed "$key" || agently_config_fail "unsupported Agently environment override key: $key"
  fi
}

agently_config_reserved_env_guard() {
  local name
  while IFS= read -r name; do
    case "$name" in
      AG_META_*|AG_CFG_*)
        agently_config_fail "reserved environment namespace is not accepted: $name"
        ;;
    esac
  done < <(compgen -e)
}
