#!/usr/bin/env bash

cmd_docs() {
  task_docs "$@"
}

cmd_doc() {
  local sub="${1:-help}"
  if [[ $# -gt 0 ]]; then
    shift
  fi
  case "$sub" in
    show) doc_show "$@" ;;
    path) doc_path "$@" ;;
    edit) doc_edit "$@" ;;
    replace) doc_replace "$@" ;;
    help|-h|--help|"") doc_help ;;
    *) die "unknown doc command: $sub" ;;
  esac
}

doc_help() {
  cat >&2 <<'EOF'
Usage:
  agently docs
  agently doc show <name> --workstream <ws> --task <task>
  agently doc path <name> --workstream <ws> --task <task>
  agently doc edit <name> --workstream <ws> --task <task>
  agently doc replace <name> --workstream <ws> --task <task> < file.md
EOF
}

doc_parse_name_ws_task() {
  local usage="$1"
  shift
  DOC_NAME=""
  DOC_WS=""
  DOC_TASK=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workstream)
        option_has_value "$@" || die "--workstream requires a value"
        DOC_WS="$2"; shift 2 ;;
      --task)
        option_has_value "$@" || die "--task requires a value"
        DOC_TASK="$2"; shift 2 ;;
      -h|--help) doc_help; exit 0 ;;
      --*) die "unknown option: $1" ;;
      *)
        [[ -z "$DOC_NAME" ]] || die "$usage"
        DOC_NAME="$1"; shift ;;
    esac
  done
  [[ -n "$DOC_NAME" ]] || die "$usage"
  [[ -n "$DOC_WS" ]] || die "--workstream is required"
  DOC_WS="$(require_workstream_handle "$DOC_WS")"
  DOC_TASK="$(require_task_handle "$DOC_WS" "$DOC_TASK")"
}

doc_show() {
  doc_parse_name_ws_task "usage: agently doc show <name> --workstream <ws> --task <task>" "$@"
  cat "$(resolve_doc_path "$DOC_WS" "$DOC_TASK" "$DOC_NAME")"
}

doc_path() {
  doc_parse_name_ws_task "usage: agently doc path <name> --workstream <ws> --task <task>" "$@"
  realpath "$(resolve_doc_path "$DOC_WS" "$DOC_TASK" "$DOC_NAME")"
}

doc_edit() {
  doc_parse_name_ws_task "usage: agently doc edit <name> --workstream <ws> --task <task>" "$@"
  local path editor
  path="$(resolve_doc_path "$DOC_WS" "$DOC_TASK" "$DOC_NAME")"
  editor="${VISUAL:-${EDITOR:-}}"
  if [[ -z "$editor" ]]; then
    note "No VISUAL or EDITOR set. Path: $path"
    return 0
  fi
  "$editor" "$path"
}

doc_replace() {
  doc_parse_name_ws_task "usage: agently doc replace <name> --workstream <ws> --task <task>" "$@"
  local path name content dir tmp task_dir
  name="$(normalize_doc_name "$DOC_NAME")"
  [[ "$name" != "state" ]] || die "STATE.yaml is workflow state; use agently task set-state for status updates"
  path="$(resolve_doc_path "$DOC_WS" "$DOC_TASK" "$DOC_NAME")"
  content="$(cat)"
  [[ -n "$content" ]] || die "refusing to replace $DOC_NAME with empty stdin"
  dir="$(dirname "$path")"
  tmp="$(mktemp "$dir/.doc-replace.tmp.XXXXXX")"
  printf '%s\n' "$content" > "$tmp"
  mv "$tmp" "$path"
  task_dir="$(task_dir_for "$DOC_WS" "$DOC_TASK")"
  ledger_append_in "$task_dir" "doc:replace name=$DOC_NAME"
  note "replaced doc: $DOC_NAME"
}
