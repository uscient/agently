#!/usr/bin/env bash

resolve_claude_config() {
  local flag_model="${1:-}" flag_effort="${2:-}" cfg_model="" cfg_effort="" cfg_permission="" cfg_turns=""
  local source="config" cfg_root="" cfg_file=""

  cfg_root="$(project_dir_or_empty)"
  if [[ -n "$cfg_root" && -f "$cfg_root/.agently/config.yml" ]]; then
    cfg_file="$cfg_root/.agently/config.yml"
  fi

  if [[ -n "$cfg_file" ]]; then
    agently_config_validate_project_config_file "$cfg_file"
    cfg_model="$(config_get_profile_key_from_file "$cfg_file" claude.model)"
    cfg_effort="$(config_get_profile_key_from_file "$cfg_file" claude.reasoning)"
    cfg_permission="$(config_get_top "$cfg_file" claude_permission_mode)"
    cfg_turns="$(config_get_top "$cfg_file" claude_max_turns)"
  fi

  CLAUDE_MODEL="${cfg_model:-opus}"
  CLAUDE_EFFORT="${cfg_effort:-max}"
  CLAUDE_PERMISSION_MODE="${cfg_permission:-plan}"
  CLAUDE_MAX_TURNS="${cfg_turns:-6}"

  if [[ -n "${AGENTLY_CLAUDE_MODEL:-}" ]]; then
    agently_config_validate_env_override AGENTLY_CLAUDE_MODEL claude.model
    CLAUDE_MODEL="$AGENTLY_CLAUDE_MODEL"
    source="env"
  fi
  if [[ -n "${AGENTLY_CLAUDE_EFFORT:-}" ]]; then
    agently_config_validate_env_override AGENTLY_CLAUDE_EFFORT claude.reasoning
    CLAUDE_EFFORT="$AGENTLY_CLAUDE_EFFORT"
    source="env"
  fi
  if [[ -n "$flag_model" ]]; then
    CLAUDE_MODEL="$flag_model"
    source="flags"
  fi
  if [[ -n "$flag_effort" ]]; then
    CLAUDE_EFFORT="$flag_effort"
    source="flags"
  fi

  validate_claude_model "$CLAUDE_MODEL"
  validate_claude_effort "$CLAUDE_EFFORT"

  CLAUDE_COMMAND_SOURCE="$source"
  if [[ -n "${AGENTLY_CLAUDE_CMD:-}" ]]; then
    agently_config_validate_env_override AGENTLY_CLAUDE_CMD
    CLAUDE_COMMAND_SOURCE="AGENTLY_CLAUDE_CMD"
    CLAUDE_COMMAND_DISPLAY="$AGENTLY_CLAUDE_CMD"
  else
    CLAUDE_COMMAND_DISPLAY="$(join_command_display \
      claude -p \
      --model "$CLAUDE_MODEL" \
      --effort "$CLAUDE_EFFORT" \
      --permission-mode "$CLAUDE_PERMISSION_MODE" \
      --max-turns "$CLAUDE_MAX_TURNS" \
      --allowedTools Read Grep Glob \
      --append-system-prompt "Planning/review only. Do not modify files. Return one Markdown document.")"
  fi
}

cmd_claude() {
  local sub="${1:-help}"
  if [[ $# -gt 0 ]]; then
    shift
  fi
  case "$sub" in
    config) claude_config "$@" ;;
    plan) claude_plan_like plan "$@" ;;
    followup) claude_plan_like followup "$@" ;;
    help|-h|--help|"") claude_help ;;
    *) die "unknown claude command: $sub" ;;
  esac
}

claude_help() {
  cat >&2 <<'EOF'
Usage:
  agently claude config [--model <alias-or-model-name>] [--effort <auto|low|medium|high|xhigh|max>]
  agently claude plan --workstream <ws> --task <task> [--model <alias-or-model-name>] [--effort <level>]
  agently claude followup --workstream <ws> --task <task> [--note "..."] [--model <alias-or-model-name>] [--effort <level>]
EOF
}

claude_config() {
  local model="" effort="" changed=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --model)
        [[ $# -ge 2 ]] || die "--model requires a value"
        model="$2"; shift 2 ;;
      --effort)
        [[ $# -ge 2 ]] || die "--effort requires a value"
        effort="$2"; shift 2 ;;
      -h|--help) claude_help; return 0 ;;
      *) die "unknown claude config option: $1" ;;
    esac
  done
  if [[ -n "$model" ]]; then
    validate_claude_model "$model"
    profile_set claude.model "$model"
    changed=1
  fi
  if [[ -n "$effort" ]]; then
    validate_claude_effort "$effort"
    profile_set claude.reasoning "$effort"
    changed=1
  fi
  if [[ "$changed" -eq 1 ]]; then
    note "updated Claude config"
  fi
  resolve_claude_config "" ""
  cat <<EOF
# Agently Claude Config

- model: $CLAUDE_MODEL
- effort: $CLAUDE_EFFORT
- permission_mode: $CLAUDE_PERMISSION_MODE
- max_turns: $CLAUDE_MAX_TURNS
- command_source: $CLAUDE_COMMAND_SOURCE
- command: $CLAUDE_COMMAND_DISPLAY
EOF
}

write_claude_receipt() {
  local task_dir="$1" round="$2" mode="$3" exit_code="$4" request="$5" response="$6" raw_json="$7"
  local receipt="$task_dir/handoffs/claude/$round-receipt.md"
  local request_rel response_rel raw_rel response_hash
  request_rel="$(rel_to_task "$task_dir" "$request")"
  response_rel="handoffs/claude/$round-response.md"
  if [[ -n "$raw_json" && -f "$raw_json" ]]; then
    raw_rel="$(rel_to_task "$task_dir" "$raw_json")"
  else
    raw_rel="none"
  fi
  if [[ -f "$response" ]]; then
    response_hash="$(sha256_of "$response")"
  else
    response_hash="pending"
  fi
  cat > "$receipt" <<EOF
# Claude Handoff Receipt — round $round

- generated: $(now)
- mode: $mode
- command_source: $CLAUDE_COMMAND_SOURCE
- model: $CLAUDE_MODEL
- effort: $CLAUDE_EFFORT
- permission_mode: $CLAUDE_PERMISSION_MODE
- max_turns: $CLAUDE_MAX_TURNS
- command: $CLAUDE_COMMAND_DISPLAY
- exit_code: $exit_code
- request: $request_rel
- response: $response_rel
- raw_json: $raw_rel
- request_sha256: $(sha256_of "$request")
- response_sha256: $response_hash
EOF
}

set_latest_claude_handoff_state() {
  local task_dir="$1" round="$2" receipt
  receipt="$task_dir/handoffs/claude/$round-receipt.md"
  state_set_in "$task_dir" last_handoff_role "PLANNER"
  state_set_in "$task_dir" last_handoff_agent "claude"
  state_set_in "$task_dir" last_handoff_model "$CLAUDE_MODEL"
  state_set_in "$task_dir" last_handoff_reasoning "$CLAUDE_EFFORT"
  state_set_in "$task_dir" last_handoff_path "$(rel_to_task "$task_dir" "$receipt")"
}

claude_plan_like() {
  local kind="$1" model="" effort="" note_text="" ws="" task="" task_dir status round request response raw_json tmp_response exit_code mode
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workstream)
        option_has_value "$@" || die "--workstream requires a value"
        ws="$2"; shift 2 ;;
      --task)
        option_has_value "$@" || die "--task requires a value"
        task="$2"; shift 2 ;;
      --model)
        [[ $# -ge 2 ]] || die "--model requires a value"
        model="$2"; shift 2 ;;
      --effort)
        [[ $# -ge 2 ]] || die "--effort requires a value"
        effort="$2"; shift 2 ;;
      --note)
        [[ $# -ge 2 ]] || die "--note requires a value"
        note_text="$2"; shift 2 ;;
      -h|--help) claude_help; return 0 ;;
      *) die "unknown claude $kind option: $1" ;;
    esac
  done

  task_dir="$(require_task_dir_for_handles "$ws" "$task")"
  ws="$(state_get_in "$task_dir" workstream)"
  task="$(state_get_in "$task_dir" slug)"
  status="$(state_get_in "$task_dir" status)"
  if [[ "$status" == "draft" ]]; then
    warn "task is still draft; continuing with Claude handoff"
  fi
  resolve_claude_config "$model" "$effort"
  if [[ "$CLAUDE_COMMAND_SOURCE" == "AGENTLY_CLAUDE_CMD" ]]; then
    warn "AGENTLY_CLAUDE_CMD is set; model/effort config is bypassed for command execution"
  fi

  round="$(next_round_in "$task_dir")"
  request="$task_dir/handoffs/claude/$round-request.md"
  response="$task_dir/handoffs/claude/$round-response.md"
  raw_json="$task_dir/handoffs/claude/$round-response.raw.json"
  mkdir -p "$(dirname "$request")"
  build_packet claude "$round" "$note_text" "$ws" "$task" > "$request"
  cat "$request"

  tmp_response="$(mktemp "$task_dir/handoffs/claude/.$round-response.tmp.XXXXXX")"
  exit_code="n/a"
  mode="manual"
  if [[ "$CLAUDE_COMMAND_SOURCE" == "AGENTLY_CLAUDE_CMD" ]]; then
    set +e
    bash -c "$AGENTLY_CLAUDE_CMD" < "$request" > "$tmp_response"
    exit_code=$?
    set -e
  elif has_cmd claude; then
    set +e
    claude -p \
      --model "$CLAUDE_MODEL" \
      --effort "$CLAUDE_EFFORT" \
      --permission-mode "$CLAUDE_PERMISSION_MODE" \
      --max-turns "$CLAUDE_MAX_TURNS" \
      --allowedTools Read Grep Glob \
      --append-system-prompt "Planning/review only. Do not modify files. Return one Markdown document." \
      < "$request" > "$tmp_response"
    exit_code=$?
    set -e
  else
    warn "Claude CLI not found"
  fi

  if [[ "$exit_code" != "n/a" && "$exit_code" -eq 0 && -s "$tmp_response" ]]; then
    mv "$tmp_response" "$response"
    mode="cli"
    state_set_in "$task_dir" current_claude_handoff "$round"
    state_set_in "$task_dir" round "$((10#$round))"
    state_set_in "$task_dir" status claude_response_ready
    set_latest_claude_handoff_state "$task_dir" "$round"
    ledger_append_in "$task_dir" "claude:$kind round=$round mode=cli"
  else
    rm -f "$tmp_response"
    state_set_in "$task_dir" current_claude_handoff "$round"
    state_set_in "$task_dir" round "$((10#$round))"
    state_set_in "$task_dir" status claude_request_ready
    set_latest_claude_handoff_state "$task_dir" "$round"
    ledger_append_in "$task_dir" "claude:$kind round=$round mode=manual"
    note "Claude manual mode:"
    note "  Request:  $(rel_to_task "$task_dir" "$request")"
    note "  Response: $(rel_to_task "$task_dir" "$response")"
    note "Run your planner with the request above, then save the reply to the response path."
    note "Command: $CLAUDE_COMMAND_DISPLAY"
  fi

  write_claude_receipt "$task_dir" "$round" "$mode" "$exit_code" "$request" "$response" "$raw_json"
}
