#!/usr/bin/env bash
# shellcheck disable=SC2016

cmd_context() {
  local sub="${1:-help}"
  if [[ $# -gt 0 ]]; then
    shift
  fi
  case "$sub" in
    budget) context_budget "$@" ;;
    manifest) context_manifest "$@" ;;
    help|-h|--help|"") context_help ;;
    *) die "unknown context command: $sub" ;;
  esac
}

cmd_compact() {
  local sub="${1:-help}"
  if [[ $# -gt 0 ]]; then
    shift
  fi
  case "$sub" in
    workstream) compact_workstream "$@" ;;
    doctrine) compact_doctrine "$@" ;;
    help|-h|--help|"") compact_help ;;
    *) die "unknown compact command: $sub" ;;
  esac
}

context_help() {
  cat >&2 <<'EOF'
Usage:
  agently context budget [--workstream <id> [--task <slug>]] [--budget <small|normal|full>] [--json]
  agently context manifest [--workstream <id> [--task <slug>]] [--json]
EOF
}

compact_help() {
  cat >&2 <<'EOF'
Usage:
  agently compact workstream <id> [--force]
  agently compact doctrine [--force]
EOF
}

context_hash_string() {
  if has_cmd sha256sum; then
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  else
    printf 'unavailable\n'
  fi
}

context_summary_path_for() {
  local root="$1" scope="$2" source="$3" rel hash base dir
  rel="$(rel_to_root "$root" "$source")"
  hash="$(context_hash_string "$rel")"
  hash="${hash:0:16}"
  base="$(basename "$rel")"
  base="$(slugify "${base%.*}")" || base="source"
  dir="$(agently_cache_subdir "$root" "summaries/$scope")"
  printf '%s/%s-%s.md\n' "$dir" "$base" "$hash"
}

context_summary_header_value() {
  local summary="$1" key="$2"
  [[ -f "$summary" ]] || return 0
  awk -v key="$key" '
    NR == 1 && $0 == "---" { in_header = 1; next }
    in_header && $0 == "---" { exit }
    in_header {
      pattern = "^" key ":[[:space:]]*"
      if ($0 ~ pattern) {
        value = $0
        sub(pattern, "", value)
        print value
        exit
      }
    }
  ' "$summary"
}

context_summary_fresh() {
  local source="$1" summary="$2" source_sha summary_sha
  [[ -f "$source" && -f "$summary" ]] || return 1
  source_sha="$(sha256_of "$source")"
  summary_sha="$(context_summary_header_value "$summary" source_sha256)"
  [[ -n "$summary_sha" && "$summary_sha" == "$source_sha" ]]
}

context_write_summary() {
  local root="$1" scope="$2" source="$3" budget="${4:-normal}" summary rel dir tmp
  rel="$(rel_to_root "$root" "$source")"
  summary="$(context_summary_path_for "$root" "$scope" "$source")"
  dir="$(dirname "$summary")"
  mkdir -p "$dir"
  ensure_under_agently "$dir" >/dev/null
  tmp="$(mktemp "$dir/.summary.tmp.XXXXXX")"
  {
    printf '%s\n' '---'
    printf 'agently_summary: structural\n'
    printf 'source_path: %s\n' "$rel"
    printf 'source_sha256: %s\n' "$(sha256_of "$source")"
    printf 'source_lines: %s\n' "$(line_count "$source")"
    printf 'generated_at: %s\n' "$(now)"
    printf 'generator: agently-compact/%s\n' "$(agently_version)"
    printf 'budget_hint: %s\n' "$budget"
    printf '%s\n\n' '---'
    structural_digest_for_file "$source" "$rel"
  } > "$tmp"
  mv "$tmp" "$summary"
  printf '%s\n' "$summary"
}

context_cached_digest() {
  local root="$1" source="$2" scope="${3:-workstream}" budget="${4:-normal}" summary
  summary="$(context_summary_path_for "$root" "$scope" "$source")"
  if ! context_summary_fresh "$source" "$summary"; then
    summary="$(context_write_summary "$root" "$scope" "$source" "$budget")"
  fi
  cat "$summary"
}

context_workstream_sources() {
  local root="$1" ws="$2" task="${3:-}" ws_dir task_dir file rel
  ws="$(slugify "$ws")" || die "invalid workstream: $ws"
  ws_dir="$root/.agently/workstreams/$ws"
  [[ -d "$ws_dir" ]] || die "workstream not found: $ws"
  for rel in README.md PLAN.md TASKS.md DECISIONS.md HANDOFF.md CODEX.md CLAUDE.md LOG.md workstream.md status.md requirements.md decisions.md inbox.md state.yml; do
    file="$ws_dir/$rel"
    [[ -f "$file" ]] && printf '%s|workstream.%s\n' "$file" "$rel"
  done
  if [[ -n "$task" ]]; then
    task="$(slugify "$task")" || die "invalid task: $task"
    [[ -d "$ws_dir/tasks/$task" ]] || die "task not found: $task"
    task_dir="$ws_dir/tasks/$task"
    for rel in TASK.md REQUIREMENTS.md CONTEXT.md NOTES.md STATE.yaml ledger.md; do
      file="$task_dir/$rel"
      [[ -f "$file" ]] && printf '%s|task.%s\n' "$file" "$rel"
    done
  fi
}

context_doctrine_sources() {
  local root="$1" base file
  base="$(agently_doctrine_dir "$root")"
  [[ -n "$base" && -d "$base" ]] || return 0
  while IFS= read -r file; do
    printf '%s|doctrine\n' "$file"
  done < <(find "$base" -maxdepth 1 -type f -name '*.md' | sort)
}

context_manifest_sources() {
  local root="$1" ws="${2:-}" task="${3:-}" source
  [[ -f "$root/AGENTS.md" ]] && printf '%s|agent_rules\n' "$root/AGENTS.md"
  context_doctrine_sources "$root"
  if [[ -n "$ws" ]]; then
    context_workstream_sources "$root" "$ws" "$task"
  fi
}

context_manifest_line() {
  local root="$1" scope="$2" source="$3" role="$4" summary rel sha bytes lines tokens fresh
  rel="$(rel_to_root "$root" "$source")"
  sha="$(sha256_of "$source")"
  bytes="$(byte_count "$source")"
  lines="$(line_count "$source")"
  tokens="$(estimate_tokens "$bytes")"
  summary="$(context_summary_path_for "$root" "$scope" "$source")"
  if context_summary_fresh "$source" "$summary"; then
    fresh=true
  else
    fresh=false
  fi
  printf '%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "$rel" "$role" "$sha" "$bytes" "$lines" "$tokens" "$(rel_to_root "$root" "$summary")" "$fresh" "$summary"
}

context_emit_manifest_markdown() {
  local root="$1" scope="$2" ws="$3" task="${4:-}" rel role sha bytes lines tokens summary_rel fresh _summary_abs count=0
  printf '# Context Manifest\n\n'
  printf -- '- scope: %s\n' "$scope"
  [[ -n "$ws" ]] && printf -- '- workstream: %s\n' "$ws"
  [[ -n "$task" ]] && printf -- '- task: %s\n' "$task"
  printf '\n| Path | Role | SHA256 | Bytes | Lines | Est Tokens | Summary | summary_fresh |\n'
  printf '| --- | --- | --- | ---: | ---: | ---: | --- | --- |\n'
  while IFS='|' read -r rel role sha bytes lines tokens summary_rel fresh _summary_abs; do
    [[ -n "$rel" ]] || continue
    printf '| `%s` | %s | `%s` | %s | %s | %s | `%s` | %s |\n' "$rel" "$role" "$sha" "$bytes" "$lines" "$tokens" "$summary_rel" "$fresh"
    count=$((count + 1))
  done < <(context_manifest_collect "$root" "$scope" "$ws" "$task")
  [[ "$count" -gt 0 ]] || printf '| _(none)_ | none | pending | 0 | 0 | 0 | none | false |\n'
}

context_emit_manifest_json() {
  local root="$1" scope="$2" ws="$3" task="${4:-}" rel role sha bytes lines tokens summary_rel fresh _summary_abs first=1
  printf '{\n'
  printf '  "scope": '; json_string "$scope"; printf ',\n'
  printf '  "workstream": '; json_string "$ws"; printf ',\n'
  printf '  "task": '; json_string "$task"; printf ',\n'
  printf '  "artifacts": ['
  while IFS='|' read -r rel role sha bytes lines tokens summary_rel fresh _summary_abs; do
    [[ -n "$rel" ]] || continue
    [[ "$first" -eq 0 ]] && printf ','
    printf '\n    {"path": '; json_string "$rel"
    printf ', "role": '; json_string "$role"
    printf ', "sha256": '; json_string "$sha"
    printf ', "bytes": %s, "lines": %s, "est_tokens": %s' "$bytes" "$lines" "$tokens"
    printf ', "summary_path": '; json_string "$summary_rel"
    printf ', "summary_fresh": '; json_bool "$fresh"
    printf '}'
    first=0
  done < <(context_manifest_collect "$root" "$scope" "$ws" "$task")
  printf '\n  ]\n'
  printf '}\n'
}

context_manifest_collect() {
  local root="$1" scope="$2" ws="$3" task="${4:-}" source role
  while IFS='|' read -r source role; do
    [[ -n "$source" ]] || continue
    context_manifest_line "$root" "$scope" "$source" "$role"
  done < <(context_manifest_sources "$root" "$ws" "$task")
}

context_manifest() {
  local ws="" task="" json=0 root scope json_requested=0
  args_include_flag --json "$@" && json_requested=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workstream)
        option_has_value "$@" || die_or_json "$json_requested" WORKSTREAM_REQUIRED "--workstream requires a value"
        ws="$2"; shift 2 ;;
      --task)
        option_has_value "$@" || die_or_json "$json_requested" TASK_REQUIRED "--task requires a value"
        task="$2"; shift 2 ;;
      --json) json=1; shift ;;
      -h|--help) context_help; return 0 ;;
      *) die "unknown context manifest option: $1" ;;
    esac
  done
  root="$(require_initialized)"
  if [[ -n "$task" && -z "$ws" ]]; then
    die_or_json "$json_requested" WORKSTREAM_REQUIRED "--workstream is required when --task is supplied"
  fi
  if [[ -n "$ws" ]]; then
    ws="$(require_workstream_handle "$ws")"
    if [[ -n "$task" ]]; then
      task="$(require_task_handle "$ws" "$task")"
    fi
  fi
  scope="$([[ -n "$ws" ]] && printf 'workstream' || printf 'doctrine')"
  if [[ "$json" -eq 1 ]]; then
    context_emit_manifest_json "$root" "$scope" "$ws" "$task"
  else
    context_emit_manifest_markdown "$root" "$scope" "$ws" "$task"
  fi
}

context_budget() {
  local ws="" task="" budget="" json=0 root scope total_bytes=0 total_tokens=0 rel _role _sha bytes _lines tokens _summary_rel _fresh _summary_abs json_requested=0
  args_include_flag --json "$@" && json_requested=1
  root="$(require_initialized)"
  budget="$(agently_config_get "$root" context default_budget)"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workstream)
        option_has_value "$@" || die_or_json "$json_requested" WORKSTREAM_REQUIRED "--workstream requires a value"
        ws="$2"; shift 2 ;;
      --task)
        option_has_value "$@" || die_or_json "$json_requested" TASK_REQUIRED "--task requires a value"
        task="$2"; shift 2 ;;
      --budget)
        [[ $# -ge 2 ]] || die "--budget requires a value"
        budget="$2"; shift 2 ;;
      --json) json=1; shift ;;
      -h|--help) context_help; return 0 ;;
      *) die "unknown context budget option: $1" ;;
    esac
  done
  packet_validate_budget "$budget"
  if [[ -n "$task" && -z "$ws" ]]; then
    die_or_json "$json_requested" WORKSTREAM_REQUIRED "--workstream is required when --task is supplied"
  fi
  if [[ -n "$ws" ]]; then
    ws="$(require_workstream_handle "$ws")"
    if [[ -n "$task" ]]; then
      task="$(require_task_handle "$ws" "$task")"
    fi
  fi
  scope="$([[ -n "$ws" ]] && printf 'workstream' || printf 'doctrine')"
  while IFS='|' read -r rel _role _sha bytes _lines tokens _summary_rel _fresh _summary_abs; do
    [[ -n "$rel" ]] || continue
    case "$budget" in
      small) tokens=$((tokens / 6 + 1)) ;;
      normal) tokens=$((tokens / 3 + 1)) ;;
      full) : ;;
    esac
    total_bytes=$((total_bytes + bytes))
    total_tokens=$((total_tokens + tokens))
  done < <(context_manifest_collect "$root" "$scope" "$ws" "$task")
  if [[ "$json" -eq 1 ]]; then
    printf '{"scope":'; json_string "$scope"
    printf ',"workstream":'; json_string "$ws"
    printf ',"task":'; json_string "$task"
    printf ',"budget":'; json_string "$budget"
    printf ',"source_bytes":%s,"est_tokens":%s}\n' "$total_bytes" "$total_tokens"
  else
    printf '# Context Budget\n\n'
    printf -- '- scope: %s\n' "$scope"
    [[ -n "$ws" ]] && printf -- '- workstream: %s\n' "$ws"
    [[ -n "$task" ]] && printf -- '- task: %s\n' "$task"
    printf -- '- budget: %s\n' "$budget"
    printf -- '- source_bytes: %s\n' "$total_bytes"
    printf -- '- est_tokens: %s\n' "$total_tokens"
  fi
}

compact_sources() {
  local root="$1" scope="$2" ws="$3" force="$4" rebuilt=0 skipped=0 source _role summary
  while IFS='|' read -r source _role; do
    [[ -n "$source" ]] || continue
    summary="$(context_summary_path_for "$root" "$scope" "$source")"
    if [[ "$force" -eq 1 || ! -f "$summary" ]]; then
      context_write_summary "$root" "$scope" "$source" normal >/dev/null
      rebuilt=$((rebuilt + 1))
    elif ! context_summary_fresh "$source" "$summary"; then
      context_write_summary "$root" "$scope" "$source" normal >/dev/null
      rebuilt=$((rebuilt + 1))
    else
      skipped=$((skipped + 1))
    fi
  done < <(context_manifest_sources "$root" "$ws")
  COMPACT_REBUILT="$rebuilt"
  COMPACT_SKIPPED="$skipped"
}

compact_write_manifest_file() {
  local root="$1" scope="$2" ws="$3" file dir label
  dir="$(agently_cache_subdir "$root" manifests)"
  if [[ -n "$ws" ]]; then
    label="$(slugify "$ws")" || label="$ws"
    file="$dir/workstream-$label.md"
  else
    file="$dir/$scope.md"
  fi
  context_emit_manifest_markdown "$root" "$scope" "$ws" "" > "$file"
  printf '%s\n' "$file"
}

compact_workstream() {
  local ws="" force=0 root manifest
  [[ $# -ge 1 ]] || die "usage: agently compact workstream <id> [--force]"
  ws="$1"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force=1; shift ;;
      -h|--help) compact_help; return 0 ;;
      *) die "unknown compact workstream option: $1" ;;
    esac
  done
  root="$(require_initialized)"
  ws="$(slugify "$ws")" || die "invalid workstream: $ws"
  [[ -d "$root/.agently/workstreams/$ws" ]] || die "workstream not found: $ws"
  compact_sources "$root" workstream "$ws" "$force"
  manifest="$(compact_write_manifest_file "$root" workstream "$ws")"
  cat <<EOF
# Compact Workstream

- workstream: $ws
- rebuilt: $COMPACT_REBUILT
- fresh_skipped: $COMPACT_SKIPPED
- manifest: $(rel_to_root "$root" "$manifest")
EOF
}

compact_doctrine() {
  local force=0 root manifest
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force=1; shift ;;
      -h|--help) compact_help; return 0 ;;
      *) die "unknown compact doctrine option: $1" ;;
    esac
  done
  root="$(require_initialized)"
  compact_sources "$root" doctrine "" "$force"
  manifest="$(compact_write_manifest_file "$root" doctrine "")"
  cat <<EOF
# Compact Doctrine

- rebuilt: $COMPACT_REBUILT
- fresh_skipped: $COMPACT_SKIPPED
- manifest: $(rel_to_root "$root" "$manifest")
EOF
}
