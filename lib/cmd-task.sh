#!/usr/bin/env bash

cmd_task() {
  local sub="${1:-help}"
  if [[ $# -gt 0 ]]; then
    shift
  fi
  case "$sub" in
    list) task_list "$@" ;;
    new) task_new "$@" ;;
    use) task_use "$@" ;;
    current) task_current "$@" ;;
    show) task_show "$@" ;;
    path) task_path "$@" ;;
    status) task_status "$@" ;;
    docs) task_docs "$@" ;;
    set-state) task_set_state "$@" ;;
    help|-h|--help|"") task_help ;;
    *) die "unknown task command: $sub" ;;
  esac
}

task_help() {
  cat >&2 <<'EOF'
Usage:
  agently task list --workstream <ws>
  agently task new <slug> --workstream <ws>
  agently task show --workstream <ws> --task <task>
  agently task path --workstream <ws> --task <task>
  agently task status --workstream <ws> --task <task>
  agently task docs
  agently task set-state <state> --workstream <ws> --task <task>
EOF
}

task_parse_ws_only() {
  local usage="$1"
  shift
  TASK_WS=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workstream)
        option_has_value "$@" || die "--workstream requires a value"
        TASK_WS="$2"; shift 2 ;;
      -h|--help) task_help; exit 0 ;;
      *) die "unknown option: $1" ;;
    esac
  done
  [[ -n "$TASK_WS" ]] || die "$usage"
  TASK_WS="$(require_workstream_handle "$TASK_WS")"
}

task_parse_slug_ws() {
  local usage="$1"
  shift
  TASK_SLUG=""
  TASK_WS=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workstream)
        option_has_value "$@" || die "--workstream requires a value"
        TASK_WS="$2"; shift 2 ;;
      -h|--help) task_help; exit 0 ;;
      --*) die "unknown option: $1" ;;
      *)
        [[ -z "$TASK_SLUG" ]] || die "$usage"
        TASK_SLUG="$1"; shift ;;
    esac
  done
  [[ -n "$TASK_SLUG" && -n "$TASK_WS" ]] || die "$usage"
  TASK_WS="$(require_workstream_handle "$TASK_WS")"
  TASK_SLUG="$(slugify "$TASK_SLUG")" || die "invalid task slug: $TASK_SLUG"
}

task_parse_ws_task() {
  local usage="$1"
  shift
  TASK_WS=""
  TASK_TASK=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workstream)
        option_has_value "$@" || die "--workstream requires a value"
        TASK_WS="$2"; shift 2 ;;
      --task)
        option_has_value "$@" || die "--task requires a value"
        TASK_TASK="$2"; shift 2 ;;
      -h|--help) task_help; exit 0 ;;
      *) die "unknown option: $1" ;;
    esac
  done
  [[ -n "$TASK_WS" ]] || die "--workstream is required"
  TASK_WS="$(require_workstream_handle "$TASK_WS")"
  TASK_TASK="$(require_task_handle "$TASK_WS" "$TASK_TASK")"
}

task_parse_state_ws_task() {
  local usage="$1"
  shift
  TASK_STATE=""
  TASK_WS=""
  TASK_TASK=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workstream)
        option_has_value "$@" || die "--workstream requires a value"
        TASK_WS="$2"; shift 2 ;;
      --task)
        option_has_value "$@" || die "--task requires a value"
        TASK_TASK="$2"; shift 2 ;;
      -h|--help) task_help; exit 0 ;;
      --*) die "unknown option: $1" ;;
      *)
        [[ -z "$TASK_STATE" ]] || die "$usage"
        TASK_STATE="$1"; shift ;;
    esac
  done
  [[ -n "$TASK_STATE" ]] || die "$usage"
  [[ -n "$TASK_WS" ]] || die "--workstream is required"
  TASK_WS="$(require_workstream_handle "$TASK_WS")"
  TASK_TASK="$(require_task_handle "$TASK_WS" "$TASK_TASK")"
}

task_list() {
  task_parse_ws_only "usage: agently task list --workstream <ws>" "$@"
  local ws ws_dir dir slug status
  ws="$TASK_WS"
  ws_dir="$(ws_dir_for "$ws")"
  shopt -s nullglob
  for dir in "$ws_dir/tasks"/*; do
    [[ -d "$dir" ]] || continue
    slug="$(basename "$dir")"
    status="$(state_get_in "$dir" status)"
    printf '%s %s\n' "$slug" "${status:-unknown}"
  done
  shopt -u nullglob
}

task_next_id() {
  local ws_dir="$1" count=0 dir
  shopt -s nullglob
  for dir in "$ws_dir/tasks"/*; do
    [[ -d "$dir" ]] || continue
    count=$((count + 1))
  done
  shopt -u nullglob
  printf '%03d\n' "$((count + 1))"
}

task_new() {
  task_parse_slug_ws "usage: agently task new <slug> --workstream <ws>" "$@"
  local slug title ws ws_title root ws_dir template dest id date datetime src rel dst content
  slug="$TASK_SLUG"
  ws="$TASK_WS"
  ws_title="$(titleize "$ws")"
  root="$(require_initialized)"
  ws_dir="$(ws_dir_for "$ws")"
  template="$root/.agently/templates/task"
  [[ -d "$template" ]] || die "missing task template: $template"
  dest="$ws_dir/tasks/$slug"
  [[ ! -e "$dest" ]] || die "task already exists: $slug"
  title="$(titleize "$slug")"
  id="$(task_next_id "$ws_dir")"
  date="$(today)"
  datetime="$(now)"
  # shellcheck disable=SC2034
  AGENTLY_WRITES_DONE=0
  # shellcheck disable=SC2034
  AGENTLY_WRITES_SKIPPED=0
  while IFS= read -r src; do
    rel="${src#"$template"/}"
    dst="$dest/$rel"
    content="$(render_file_to_stdout "$src" \
      "ID=$id" \
      "SLUG=$slug" \
      "TITLE=$title" \
      "TASK_SLUG=$slug" \
      "TASK_TITLE=$title" \
      "WORKSTREAM_SLUG=$ws" \
      "WORKSTREAM_TITLE=$ws_title" \
      "DATE=$date" \
      "DATETIME=$datetime" \
      "PROJECT=$(basename "$root")")"
    write_text_file "$dst" 0644 "$content" 0 0 ".agently/workstreams/$ws/tasks/$slug/$rel"
  done < <(find "$template" -type f | sort)
  mkdir -p "$dest/handoffs/claude" "$dest/handoffs/codex" "$dest/artifacts" "$dest/decisions"
  ledger_append_in "$dest" "task:new slug=$slug"
  note "created task: $slug"
}

task_use() {
  die "agently task use is removed; pass --workstream <ws> --task <task> to the target command"
}

task_current() {
  die "agently task current is removed; pass --workstream <ws> --task <task> to the target command"
}

task_show() {
  task_parse_ws_task "usage: agently task show --workstream <ws> --task <task>" "$@"
  cat "$(task_dir_for "$TASK_WS" "$TASK_TASK")/TASK.md"
}

task_path() {
  task_parse_ws_task "usage: agently task path --workstream <ws> --task <task>" "$@"
  realpath "$(task_dir_for "$TASK_WS" "$TASK_TASK")"
}

task_status() {
  task_parse_ws_task "usage: agently task status --workstream <ws> --task <task>" "$@"
  local task_dir status round handoff eval created updated slug ws latest_decision
  task_dir="$(task_dir_for "$TASK_WS" "$TASK_TASK")"
  slug="$(state_get_in "$task_dir" slug)"
  ws="$(state_get_in "$task_dir" workstream)"
  status="$(state_get_in "$task_dir" status)"
  round="$(state_get_in "$task_dir" round)"
  handoff="$(state_get_in "$task_dir" current_claude_handoff)"
  eval="$(state_get_in "$task_dir" current_codex_eval)"
  created="$(state_get_in "$task_dir" created_at)"
  updated="$(state_get_in "$task_dir" updated_at)"
  latest_decision="$(find "$task_dir/decisions" -maxdepth 1 -type f -name '*-decision.md' 2>/dev/null | sort | tail -n 1 || true)"
  cat <<EOF
# Task Status

- workstream: ${ws:-unknown}
- task: ${slug:-unknown}
- status: ${status:-unknown}
- round: ${round:-0}
- current_claude_handoff: ${handoff:-none}
- current_codex_eval: ${eval:-none}
- latest_decision: ${latest_decision:-none}
- created_at: ${created:-unknown}
- updated_at: ${updated:-unknown}
EOF
}

task_docs() {
  [[ $# -eq 0 ]] || die "task docs takes no arguments"
  cat <<'EOF'
task
requirements
context
notes
ledger
state
ws:workstream
ws:status
ws:requirements
ws:decisions
ws:inbox
EOF
}

task_set_state() {
  task_parse_state_ws_task "usage: agently task set-state <state> --workstream <ws> --task <task>" "$@"
  local state="$1" task_dir
  state="$TASK_STATE"
  state_status_allowed "$state" || die "invalid task state: $state"
  task_dir="$(task_dir_for "$TASK_WS" "$TASK_TASK")"
  state_set_in "$task_dir" status "$state"
  ledger_append_in "$task_dir" "task:set-state status=$state"
  note "task state: $state"
}
