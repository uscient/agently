#!/usr/bin/env bash
# shellcheck disable=SC2016

cmd_eval() {
  local sub="${1:-}"
  if [[ -z "$sub" || "$sub" == --* ]]; then
    eval_project "$@"
    return $?
  fi
  shift || true
  case "$sub" in
    -h|--help|help) eval_help ;;
    claude) eval_claude "$@" ;;
    patch) eval_patch "$@" ;;
    *) die "unknown eval command: $sub" ;;
  esac
}

eval_help() {
  cat >&2 <<'EOF'
Usage:
  agently eval [--changed] [--lang bash|python|go|php] [--file <file>] [--strict]
  agently eval patch <patch-id> --workstream <ws> [--strict]
  agently eval claude --workstream <ws> --task <task> [--exec]
EOF
}

eval_merge_status() {
  guard_merge_status "$@"
}

eval_project() {
  local root mode="all" strict="" strict_value status=0 next
  local -a guard_args=()
  root="$(require_initialized)"
  strict_value="$(agently_config_get "$root" guard strict_missing_tools)"
  strict="$(agently_bool "$strict_value")" || die "invalid guard.strict_missing_tools value: $strict_value"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --changed)
        mode="changed"
        shift
        ;;
      --lang)
        [[ $# -ge 2 ]] || die "--lang requires a value"
        guard_validate_lang "$2"
        guard_args+=(--lang "$2")
        shift 2
        ;;
      --file)
        [[ $# -ge 2 ]] || die "--file requires a value"
        resolve_repo_file "$root" "$2" >/dev/null
        guard_args+=(--file "$2")
        shift 2
        ;;
      --strict)
        strict="true"
        shift
        ;;
      -h|--help)
        eval_help
        return 0
        ;;
      *) die "unknown eval option: $1" ;;
    esac
  done
  printf '# Agently Eval Report\n\n'
  printf -- '- root: `%s`\n' "$root"
  printf -- '- live_tree_mutated: false\n\n'
  set +e
  guard_run_for_root "$root" "$mode" "$strict" "${guard_args[@]}"
  next=$?
  set -e
  status="$(eval_merge_status "$status" "$next")"
  printf '\n## Diff Check\n\n'
  set +e
  guard_diff
  next=$?
  set -e
  status="$(eval_merge_status "$status" "$next")"
  printf '\n## Eval Summary\n\n'
  printf -- '- status: %s\n' "$status"
  printf -- '- project_tests: covered by detected language guard runners\n'
  return "$status"
}

eval_patch() {
  local id="${1:-}" root ws="" dir patch_file meta strict="" strict_value use_worktree
  local check_report guard_report eval_report wt="" status=0 next add_status apply_status remove_status
  [[ -n "$id" ]] || die "usage: agently eval patch <patch-id>"
  shift
  root="$(require_initialized)"
  strict_value="$(agently_config_get "$root" guard strict_missing_tools)"
  strict="$(agently_bool "$strict_value")" || die "invalid guard.strict_missing_tools value: $strict_value"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --strict)
        strict="true"
        shift
        ;;
      --workstream)
        option_has_value "$@" || die "--workstream requires a value"
        ws="$2"; shift 2 ;;
      -h|--help)
        eval_help
        return 0
        ;;
      *) die "unknown eval patch option: $1" ;;
    esac
  done
  ws="$(patch_workstream_required "$ws")"
  dir="$(patch_artifact_for_id "$root" "$ws" "$id")"
  patch_file="$dir/patch.diff"
  meta="$dir/meta.yml"
  check_report="$dir/eval-check.md"
  guard_report="$dir/eval-guard.md"
  eval_report="$dir/eval.md"
  printf '# Agently Patch Eval\n\n' > "$eval_report"
  {
    printf -- '- id: %s\n' "$id"
    printf -- '- artifact: `%s`\n' "$(rel_to_root "$root" "$dir")"
    printf -- '- live_tree_mutated: false\n'
  } >> "$eval_report"
  set +e
  patch_check_file "$root" "$patch_file" "$dir/eval-check.log" "$meta" > "$check_report"
  next=$?
  set -e
  status="$(eval_merge_status "$status" "$next")"
  cat "$check_report" >> "$eval_report"
  if [[ "$next" -ne 0 ]]; then
    patch_meta_set "$meta" eval_status failed_check
    cat "$eval_report"
    return "$status"
  fi
  use_worktree="$(agently_bool "$(agently_config_get "$root" eval use_worktree)")" || die "invalid eval.use_worktree value"
  if [[ "$use_worktree" != "true" ]]; then
    patch_meta_set "$meta" eval_status skipped_worktree_disabled
    {
      printf '\n## Worktree Eval\n\n'
      printf -- '- status: skipped\n'
      printf -- '- reason: eval.use_worktree is false; live tree was not touched\n'
    } >> "$eval_report"
    cat "$eval_report"
    return "$status"
  fi
  wt="$(mktemp -d "${TMPDIR:-/tmp}/agently-eval-patch-$id.XXXXXX")"
  rmdir "$wt"
  set +e
  run_and_truncate "$dir/eval-worktree-add.log" -- git -C "$root" worktree add --detach "$wt" HEAD
  add_status=$?
  set -e
  if [[ "$add_status" -ne 0 ]]; then
    patch_meta_set "$meta" eval_status failed_worktree
    {
      printf '\n## Worktree Eval\n\n'
      printf -- '- status: %s\n' "$add_status"
      printf -- '- log: `%s`\n' "$(rel_to_root "$root" "$dir/eval-worktree-add.log")"
    } >> "$eval_report"
    cat "$eval_report"
    return "$add_status"
  fi
  set +e
  run_and_truncate "$dir/eval-apply.log" -- git -C "$wt" apply --whitespace=error "$patch_file"
  apply_status=$?
  set -e
  if [[ "$apply_status" -ne 0 ]]; then
    status="$(eval_merge_status "$status" "$apply_status")"
    patch_meta_set "$meta" eval_status failed_apply
  else
    set +e
    AGENTLY_LOG_ROOT="$dir/eval-logs" guard_run_for_root "$wt" all "$strict" > "$guard_report"
    next=$?
    set -e
    status="$(eval_merge_status "$status" "$next")"
    patch_meta_set "$meta" eval_status "$([[ "$next" -eq 0 ]] && printf passed || printf failed)"
  fi
  {
    printf '\n## Worktree Eval\n\n'
    printf -- '- worktree: `%s`\n' "$wt"
    printf -- '- apply_status: %s\n' "$apply_status"
    printf -- '- apply_log: `%s`\n' "$(rel_to_root "$root" "$dir/eval-apply.log")"
    if [[ -f "$guard_report" ]]; then
      printf -- '- guard_report: `%s`\n' "$(rel_to_root "$root" "$guard_report")"
      printf '\n'
      cat "$guard_report"
    fi
    printf '\n## Eval Summary\n\n'
    printf -- '- status: %s\n' "$status"
    printf -- '- live_tree_mutated: false\n'
  } >> "$eval_report"
  set +e
  git -C "$root" worktree remove --force "$wt" > "$dir/eval-worktree-remove.log" 2>&1
  remove_status=$?
  set -e
  if [[ "$remove_status" -ne 0 ]]; then
    warn "failed to remove eval worktree; see $(rel_to_root "$root" "$dir/eval-worktree-remove.log")"
  fi
  patch_meta_set "$meta" eval_ran_at "$(now)"
  patch_meta_set "$meta" eval_report "$(rel_to_root "$root" "$eval_report")"
  cat "$eval_report"
  return "$status"
}

round_with_response() {
  local task_dir="$1" current="$2" file base
  if [[ -n "$current" && -f "$task_dir/handoffs/claude/$current-response.md" ]]; then
    printf '%s\n' "$current"
    return 0
  fi
  file="$(find "$task_dir/handoffs/claude" -maxdepth 1 -type f -name '*-response.md' 2>/dev/null | sort | tail -n 1 || true)"
  [[ -n "$file" ]] || return 1
  base="$(basename "$file")"
  printf '%s\n' "${base%%-*}"
}

eval_claude() {
  local exec_mode=0 ws="" task="" task_dir current round response eval_path packet
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --exec) exec_mode=1; shift ;;
      --workstream)
        option_has_value "$@" || die "--workstream requires a value"
        ws="$2"; shift 2 ;;
      --task)
        option_has_value "$@" || die "--task requires a value"
        task="$2"; shift 2 ;;
      -h|--help) echo "Usage: agently eval claude --workstream <ws> --task <task> [--exec]" >&2; return 0 ;;
      *) die "unknown eval claude option: $1" ;;
    esac
  done
  task_dir="$(require_task_dir_for_handles "$ws" "$task")"
  ws="$(state_get_in "$task_dir" workstream)"
  task="$(state_get_in "$task_dir" slug)"
  current="$(state_get_in "$task_dir" current_claude_handoff)"
  round="$(round_with_response "$task_dir" "$current")" || die "missing Claude response. Save it to: $task_dir/handoffs/claude/${current:-001}-response.md"
  response="$task_dir/handoffs/claude/$round-response.md"
  eval_path="$task_dir/handoffs/codex/$round-eval.md"
  mkdir -p "$(dirname "$eval_path")"
  packet="$(build_packet review "$round" "" "$ws" "$task")"
  printf '%s\n' "$packet"
  cat > "$eval_path" <<EOF
# Codex Evaluation - round $round

- generated: $(now)
- claude_response: handoffs/claude/$round-response.md
- requirements: REQUIREMENTS.md

## Meets Requirements?

TBD

## Missing Items

TBD

## Risk Flags

TBD

## Implementation Feasibility

TBD

## Recommendation

TBD: accept | revise | reject
EOF
  if [[ "$exec_mode" -eq 1 ]]; then
    note "headless codex eval is not implemented; scaffold written for Codex TUI evaluation"
  fi
  state_set_in "$task_dir" current_codex_eval "$round"
  state_set_in "$task_dir" status codex_eval_ready
  ledger_append_in "$task_dir" "codex:eval round=$round"
}

cmd_report() {
  local ws="" task="" task_dir round eval_path response report_path report
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workstream)
        option_has_value "$@" || die "--workstream requires a value"
        ws="$2"; shift 2 ;;
      --task)
        option_has_value "$@" || die "--task requires a value"
        task="$2"; shift 2 ;;
      -h|--help) echo "Usage: agently report --workstream <ws> --task <task>" >&2; return 0 ;;
      *) die "unknown report option: $1" ;;
    esac
  done
  task_dir="$(require_task_dir_for_handles "$ws" "$task")"
  round="$(state_get_in "$task_dir" current_codex_eval)"
  [[ -n "$round" ]] || round="$(state_get_in "$task_dir" current_claude_handoff)"
  [[ -n "$round" ]] || die "no current evaluation round"
  eval_path="$task_dir/handoffs/codex/$round-eval.md"
  response="$task_dir/handoffs/claude/$round-response.md"
  [[ -f "$eval_path" ]] || die "missing Codex eval: $eval_path"
  [[ -f "$response" ]] || die "missing Claude response: $response"
  report_path="$task_dir/handoffs/codex/$round-decision-report.md"
  report="$(render_file_to_stdout "$(require_initialized)/.agently/templates/packets/decision-report.md" \
    "ROUND=$round" \
    "DATETIME=$(now)" \
    "TASK_SLUG=$(state_get_in "$task_dir" slug)" \
    "STATUS=$(state_get_in "$task_dir" status)" \
    "CLAUDE_RESPONSE_MD=$(file_or_empty "$response")" \
    "CODEX_EVAL_MD=$(file_or_empty "$eval_path")")"
  printf '%s\n' "$report" > "$report_path"
  printf '%s\n' "$report"
  state_set_in "$task_dir" status user_decision_needed
  ledger_append_in "$task_dir" "codex:report round=$round"
}

cmd_decide() {
  local decision="${1:-}" note_text="" stdin_note="" task_dir round state decision_path ws="" task=""
  [[ -n "$decision" ]] || die "usage: agently decide <accept|revise|reject> [--note ...]"
  shift || true
  case "$decision" in
    accept) state="accepted" ;;
    revise) state="needs_revision" ;;
    reject) state="rejected" ;;
    *) die "unknown decision: $decision" ;;
  esac
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --note)
        [[ $# -ge 2 ]] || die "--note requires a value"
        note_text="$2"; shift 2 ;;
      --workstream)
        option_has_value "$@" || die "--workstream requires a value"
        ws="$2"; shift 2 ;;
      --task)
        option_has_value "$@" || die "--task requires a value"
        task="$2"; shift 2 ;;
      -h|--help) echo "Usage: agently decide <accept|revise|reject> --workstream <ws> --task <task> [--note ...]" >&2; return 0 ;;
      *) die "unknown decide option: $1" ;;
    esac
  done
  if [[ ! -t 0 ]]; then
    stdin_note="$(cat || true)"
  fi
  task_dir="$(require_task_dir_for_handles "$ws" "$task")"
  round="$(state_get_in "$task_dir" current_codex_eval)"
  [[ -n "$round" ]] || round="$(state_get_in "$task_dir" current_claude_handoff)"
  [[ -n "$round" ]] || die "no current decision round"
  decision_path="$task_dir/decisions/$round-decision.md"
  mkdir -p "$(dirname "$decision_path")"
  cat > "$decision_path" <<EOF
# Decision - round $round

- generated: $(now)
- decision: $decision
- state: $state
- round: $round
- claude_response: handoffs/claude/$round-response.md
- codex_eval: handoffs/codex/$round-eval.md
- decision_report: handoffs/codex/$round-decision-report.md

## Note

${note_text:-_(none)_}

## Stdin Reason

${stdin_note:-_(none)_}
EOF
  state_set_in "$task_dir" status "$state"
  ledger_append_in "$task_dir" "user:decide decision=$decision round=$round"
  note "recorded decision: $decision"
  if [[ "$decision" == "revise" ]]; then
    note "Next: agently claude followup --note \"...\""
  fi
}
