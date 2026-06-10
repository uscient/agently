#!/usr/bin/env bash
# shellcheck disable=SC2016

cmd_packet() {
  local type="${1:-}"
  [[ -n "$type" ]] || die "usage: agently packet <claude|codex|status|review> OR agently packet --profile <profile>"
  case "$type" in
    inspect)
      shift
      packet_inspect "$@"
      ;;
    --profile|--budget|--workstream|--task|--objective)
      packet_compile_cli "$@"
      ;;
    claude|codex|status|review)
      shift || true
      packet_shortcut "$type" "$@"
      ;;
    -h|--help|help)
      packet_help
      ;;
    *)
      die "unknown packet type: $type"
      ;;
  esac
}

packet_help() {
  cat >&2 <<'EOF'
Usage:
  agently packet claude --workstream <id> [--task <slug>]
  agently packet codex --workstream <id> [--task <slug>]
  agently packet status --workstream <id> [--task <slug>]
  agently packet review --workstream <id> [--task <slug>]
  agently packet --profile <claude|codex|generic> --workstream <id> [--task <slug>] [--budget <small|normal|full>] [--objective "..."]
  agently packet --budget <small|normal|full> --workstream <id> [--task <slug>]
  agently packet inspect [--profile <profile>] [--workstream <id>] [--task <slug>] [--budget <budget>] [--json]
EOF
}

packet_profile_for_shortcut() {
  local type="$1"
  case "$type" in
    claude) printf 'claude\n' ;;
    codex|review) printf 'codex\n' ;;
    status) printf 'generic\n' ;;
    *) die "unknown packet shortcut: $type" ;;
  esac
}

packet_objective_for_shortcut() {
  local type="$1"
  case "$type" in
    claude) printf 'Plan or review the supplied task using the compiled Agently context.' ;;
    codex) printf 'Evaluate or execute the supplied task using the compiled Agently context after user approval.' ;;
    status) printf 'Summarize the supplied Agently workflow state using the compiled context.' ;;
    review) printf 'Review the latest Claude response using the compiled Agently context.' ;;
    *) die "unknown packet shortcut: $type" ;;
  esac
}

packet_shortcut() {
  local type="$1" ws="" task=""
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workstream)
        option_has_value "$@" || die "--workstream requires a value"
        ws="$2"; shift 2 ;;
      --task)
        option_has_value "$@" || die "--task requires a value"
        task="$2"; shift 2 ;;
      -h|--help) packet_help; return 0 ;;
      *) die "unknown packet $type option: $1" ;;
    esac
  done
  build_packet "$type" "" "" "$ws" "$task"
}

build_packet() {
  local type="$1" explicit_round="${2:-}" note_text="${3:-}" ws="${4:-}" task="${5:-}"
  local profile objective
  profile="$(packet_profile_for_shortcut "$type")"
  objective="$(packet_objective_for_shortcut "$type")"
  if [[ -n "$explicit_round" ]]; then
    objective+=$'\n\n'
    objective+="Requested round: $explicit_round"
  fi
  if [[ -n "$note_text" ]]; then
    objective+=$'\n\n'
    objective+="Follow-up note: $note_text"
  fi
  packet_compile_to_stdout "$profile" normal "$ws" "$task" "$objective"
}

packet_validate_profile() {
  case "$1" in
    claude|codex|generic) return 0 ;;
    *) die "invalid packet profile: $1" ;;
  esac
}

packet_validate_budget() {
  case "$1" in
    small|normal|full) return 0 ;;
    *) die "invalid packet budget: $1" ;;
  esac
}

packet_base_template() {
  local root="$1" profile="$2" project_template share_template
  project_template="$root/.agently/templates/packets/base/$profile.md"
  share_template="$AGENTLY_SHARE/templates/agently/templates/packets/base/$profile.md"
  if [[ -f "$project_template" ]]; then
    cat "$project_template"
  elif [[ -f "$share_template" ]]; then
    cat "$share_template"
  else
    case "$profile" in
      claude) printf 'You are Claude operating as planner/reviewer in an Agently-managed repository.\n' ;;
      codex) printf 'You are Codex operating in an Agently-managed repository.\n' ;;
      generic) printf 'You are operating in an Agently-managed repository.\n' ;;
    esac
  fi
}

packet_context_menu() {
  local root="$1" project_template share_template
  project_template="$root/.agently/templates/packets/context-menu.md"
  share_template="$AGENTLY_SHARE/templates/agently/templates/packets/context-menu.md"
  if [[ -f "$project_template" ]]; then
    cat "$project_template"
  elif [[ -f "$share_template" ]]; then
    cat "$share_template"
  else
    cat <<'EOF'
Need more context? Use bounded Agently inspection commands:
- `agently inspect read <file> --start N --end M`
- `agently inspect skeleton <file>` / `agently inspect symbols <file>`
- `agently context manifest --workstream <id>`
EOF
  fi
}

packet_selected_doctrine_files() {
  local root="$1" base file
  base="$(agently_doctrine_dir "$root")"
  [[ -n "$base" ]] || return 0
  for file in \
    "$base/00-source-of-truth.md" \
    "$base/02-authority-model.md" \
    "$base/06-command-contract.md" \
    "$base/07-markdown-packets-and-copy-ux.md" \
    "$base/10-agent-boundaries.md" \
    "$base/11-security-and-guardrails.md" \
    "$base/12-testing-and-validation.md" \
    "$base/13-roadmap-and-deferred-work.md"; do
    [[ -f "$file" ]] && printf '%s\n' "$file"
  done
}

packet_markdown_digest() {
  local file="$1" max="${2:-30}"
  awk -v max="$max" '
    /^#{1,6}[[:space:]]+/ {
      print "- heading: " $0
      count++
    }
    /^[[:space:]]*[-*][[:space:]]+/ {
      print "- bullet: " $0
      count++
    }
    /TODO|FIXME|OPEN/ {
      print "- marker: " $0
      count++
    }
    count >= max { exit }
  ' "$file"
}

packet_file_view() {
  local root="$1" file="$2" budget="$3" label="$4"
  [[ -f "$file" ]] || { printf '### %s\n\n_(missing)_\n' "$label"; return 0; }
  case "$budget" in
    small)
      printf '### %s\n\n' "$label"
      printf -- '- path: `%s`\n' "$(rel_to_root "$root" "$file")"
      printf -- '- sha256: %s\n' "$(sha256_of "$file")"
      printf -- '- lines: %s\n' "$(line_count "$file")"
      ;;
    normal)
      if declare -F context_cached_digest >/dev/null 2>&1; then
        context_cached_digest "$root" "$file" workstream "$budget"
      else
        structural_digest_for_file "$file" "$(rel_to_root "$root" "$file")"
      fi
      ;;
    full)
      printf '### %s\n\n' "$label"
      printf -- '- path: `%s`\n' "$(rel_to_root "$root" "$file")"
      printf -- '- sha256: %s\n\n' "$(sha256_of "$file")"
      printf '```text\n'
      cat "$file"
      printf '\n```\n'
      ;;
  esac
}

packet_doctrine_manifest_section() {
  local root="$1" budget="$2" file rel count=0 base provenance
  base="$(agently_doctrine_dir "$root")"
  provenance="$(agently_doctrine_provenance "$root" "$base")"
  printf '<doctrine_manifest>\n'
  printf -- '- provenance: %s\n' "$provenance"
  [[ -n "$base" ]] && printf -- '- doctrine_dir: `%s`\n' "$(rel_to_root "$root" "$base")"
  while IFS= read -r file; do
    rel="$(rel_to_root "$root" "$file")"
    printf -- '- %s sha=%s bytes=%s lines=%s\n' "$rel" "$(sha256_of "$file")" "$(byte_count "$file")" "$(line_count "$file")"
    count=$((count + 1))
  done < <(packet_selected_doctrine_files "$root")
  if [[ "$count" -eq 0 ]]; then
    printf -- '- none found\n'
  fi
  printf '</doctrine_manifest>\n'
  case "$budget" in
    normal)
      while IFS= read -r file; do
        printf '\n<doctrine_digest path="%s">\n' "$(rel_to_root "$root" "$file")"
        packet_markdown_digest "$file" 20
        printf '</doctrine_digest>\n'
      done < <(packet_selected_doctrine_files "$root")
      ;;
    full)
      while IFS= read -r file; do
        printf '\n<doctrine path="%s">\n' "$(rel_to_root "$root" "$file")"
        cat "$file"
        printf '\n</doctrine>\n'
      done < <(packet_selected_doctrine_files "$root")
      ;;
  esac
}

packet_agent_rules_section() {
  local root="$1" budget="$2" file="$root/AGENTS.md"
  printf '<agent_rules>\n'
  if [[ ! -f "$file" ]]; then
    printf '_(AGENTS.md missing)_\n'
  elif [[ "$budget" == "full" ]]; then
    cat "$file"
  elif [[ "$budget" == "small" ]]; then
    awk '/^#{1,6}[[:space:]]+/ { print "- " $0; count++; if (count >= 12) exit }' "$file"
  else
    packet_markdown_digest "$file" 40
  fi
  printf '</agent_rules>\n'
}

packet_patch_list() {
  local root="$1" ws="$2" dir id status files
  dir="$root/.agently/workstreams/$ws/artifacts/patches"
  [[ -d "$dir" ]] || { printf -- '- patches: none\n'; return 0; }
  shopt -s nullglob
  for meta in "$dir"/*/meta.yml; do
    id="$(basename "$(dirname "$meta")")"
    status="$(config_get_top "$meta" status)"
    files="$(config_get_top "$meta" files)"
    printf -- '- patch %s: status=%s files=%s\n' "$id" "${status:-unknown}" "${files:-unknown}"
  done
  shopt -u nullglob
}

packet_write_compiled_sections() {
  local outdir="$1" profile="$2" budget="$3" ws="${4:-}" task="${5:-}" objective="${6:-}"
  local root ws_dir="" task_dir="" branch status dirty_count generated round log_tail_lines ledger_tail_lines
  root="$(require_initialized)"
  packet_validate_profile "$profile"
  packet_validate_budget "$budget"
  ws="$(require_workstream_handle "$ws")"
  ws_dir="$root/.agently/workstreams/$ws"
  if [[ -n "$task" ]]; then
    task="$(require_task_handle "$ws" "$task")"
    task_dir="$ws_dir/tasks/$task"
  fi
  branch="$(git_branch_for "$root")"
  status="$(git_status_short_for "$root")"
  dirty_count="$(git_dirty_count_for "$status")"
  generated="$(now)"
  log_tail_lines="$(agently_config_get "$root" context log_tail_lines)"
  ledger_tail_lines="$(agently_config_get "$root" context ledger_tail_lines)"

  {
    printf '<base_contract profile="%s" agently="%s">\n' "$profile" "$(agently_version)"
    packet_base_template "$root" "$profile"
    printf '\n</base_contract>\n'
  } > "$outdir/01-base_contract.md"

  packet_doctrine_manifest_section "$root" "$budget" > "$outdir/02-doctrine_manifest.md"
  packet_agent_rules_section "$root" "$budget" > "$outdir/03-agent_rules.md"

  {
    printf '<workstream_state>\n'
    printf -- '- workstream: %s\n' "$ws"
    printf -- '- task: %s\n' "${task:-none}"
    if [[ -n "$task_dir" ]]; then
      printf -- '- task_status: %s\n' "$(state_get_in "$task_dir" status)"
      round="$(state_get_in "$task_dir" round)"
      printf -- '- round: %s\n' "${round:-0}"
    fi
    printf -- '- branch: %s\n' "$branch"
    printf -- '- dirty_count: %s\n' "$dirty_count"
    printf -- '- generated: %s\n' "$generated"
    printf '</workstream_state>\n'
  } > "$outdir/04-workstream_state.md"

  {
    printf '<log_tail lines="%s">\n' "$log_tail_lines"
    if [[ -f "$ws_dir/LOG.md" ]]; then
      tail -n "$log_tail_lines" "$ws_dir/LOG.md"
    else
      printf '_(no workstream log)_\n'
    fi
    if [[ -n "$task_dir" && -f "$task_dir/ledger.md" && "$budget" != "small" ]]; then
      printf '\n## Task Ledger Tail\n\n'
      tail -n "$ledger_tail_lines" "$task_dir/ledger.md"
    fi
    printf '\n</log_tail>\n'
  } > "$outdir/05-log_tail.md"

  {
    printf '<handoff_summary>\n'
    case "$budget" in
      small)
        sed -n '1,8p' "$ws_dir/HANDOFF.md" 2>/dev/null || printf '_(none)_\n'
        ;;
      normal)
        [[ -f "$ws_dir/HANDOFF.md" ]] && packet_markdown_digest "$ws_dir/HANDOFF.md" 30 || printf '_(none)_\n'
        ;;
      full)
        [[ -f "$ws_dir/HANDOFF.md" ]] && cat "$ws_dir/HANDOFF.md" || printf '_(none)_\n'
        ;;
    esac
    printf '\n</handoff_summary>\n'
  } > "$outdir/06-handoff_summary.md"

  {
    printf '<artifacts>\n'
    printf -- '- workstream_dir: `%s`\n' "$(rel_to_root "$root" "$ws_dir")"
    if [[ -n "$task_dir" ]]; then
      printf -- '- task_dir: `%s`\n' "$(rel_to_root "$root" "$task_dir")"
    fi
    packet_patch_list "$root" "$ws"
    printf '</artifacts>\n'
  } > "$outdir/07-artifacts.md"

  {
    printf '<task>\n'
    if [[ -n "$objective" ]]; then
      printf '## Objective\n\n%s\n\n' "$objective"
    fi
    if [[ -n "$task_dir" ]]; then
      packet_file_view "$root" "$task_dir/TASK.md" "$budget" "Task"
      printf '\n'
      packet_file_view "$root" "$task_dir/REQUIREMENTS.md" "$budget" "Requirements"
      if [[ "$budget" != "small" ]]; then
        printf '\n'
        packet_file_view "$root" "$task_dir/CONTEXT.md" "$budget" "Context"
      fi
      if [[ "$budget" == "full" ]]; then
        printf '\n'
        packet_file_view "$root" "$task_dir/NOTES.md" "$budget" "Notes"
      fi
    else
      printf 'No task supplied for workstream `%s`.\n' "$ws"
    fi
    printf '</task>\n'
  } > "$outdir/08-task.md"

  {
    printf '<context_menu>\n'
    packet_context_menu "$root"
    printf '\n</context_menu>\n'
  } > "$outdir/09-context_menu.md"
}

packet_emit_compiled_from_dir() {
  local dir="$1" file total_bytes total_tokens
  for file in "$dir"/01-*.md "$dir"/02-*.md "$dir"/03-*.md; do
    cat "$file"
    printf '\n'
  done
  printf '<cache_breakpoint/>\n\n'
  for file in "$dir"/04-*.md "$dir"/05-*.md "$dir"/06-*.md "$dir"/07-*.md "$dir"/08-*.md "$dir"/09-*.md; do
    cat "$file"
    printf '\n'
  done
  total_bytes="$(cat "$dir"/*.md | wc -c | awk '{ print $1 + 0 }')"
  total_tokens="$(estimate_tokens "$total_bytes")"
  if (( total_tokens > 25000 )); then
    warn "packet estimate is high: ${total_tokens} tokens"
  fi
}

packet_compile_to_stdout() {
  local profile="$1" budget="$2" ws="$3" task="$4" objective="$5" tmp
  packet_validate_profile "$profile"
  packet_validate_budget "$budget"
  tmp="$(mktemp -d)"
  packet_write_compiled_sections "$tmp" "$profile" "$budget" "$ws" "$task" "$objective"
  packet_emit_compiled_from_dir "$tmp"
  rm -rf "$tmp"
}

packet_compile_cli() {
  local profile="generic" budget="" ws="" task="" objective="" root
  root="$(require_initialized)"
  budget="$(agently_config_get "$root" context default_budget)"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile)
        [[ $# -ge 2 ]] || die "--profile requires a value"
        profile="$2"; shift 2 ;;
      --budget)
        [[ $# -ge 2 ]] || die "--budget requires a value"
        budget="$2"; shift 2 ;;
      --workstream)
        [[ $# -ge 2 ]] || die "--workstream requires a value"
        ws="$2"; shift 2 ;;
      --task)
        [[ $# -ge 2 ]] || die "--task requires a value"
        task="$2"; shift 2 ;;
      --objective)
        [[ $# -ge 2 ]] || die "--objective requires a value"
        objective="$2"; shift 2 ;;
      -h|--help) packet_help; return 0 ;;
      *) die "unknown packet compiler option: $1" ;;
    esac
  done
  packet_compile_to_stdout "$profile" "$budget" "$ws" "$task" "$objective"
}

packet_inspect() {
  local profile="generic" budget="" ws="" task="" objective="" json=0 root tmp file name bytes lines tokens first=1
  root="$(require_initialized)"
  budget="$(agently_config_get "$root" context default_budget)"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile)
        [[ $# -ge 2 ]] || die "--profile requires a value"
        profile="$2"; shift 2 ;;
      --budget)
        [[ $# -ge 2 ]] || die "--budget requires a value"
        budget="$2"; shift 2 ;;
      --workstream)
        [[ $# -ge 2 ]] || die "--workstream requires a value"
        ws="$2"; shift 2 ;;
      --task)
        [[ $# -ge 2 ]] || die "--task requires a value"
        task="$2"; shift 2 ;;
      --objective)
        [[ $# -ge 2 ]] || die "--objective requires a value"
        objective="$2"; shift 2 ;;
      --json) json=1; shift ;;
      -h|--help) packet_help; return 0 ;;
      *) die "unknown packet inspect option: $1" ;;
    esac
  done
  packet_validate_profile "$profile"
  packet_validate_budget "$budget"
  tmp="$(mktemp -d)"
  packet_write_compiled_sections "$tmp" "$profile" "$budget" "$ws" "$task" "$objective"
  if [[ "$json" -eq 1 ]]; then
    printf '{\n'
    printf '  "profile": '; json_string "$profile"; printf ',\n'
    printf '  "budget": '; json_string "$budget"; printf ',\n'
    printf '  "sections": ['
    for file in "$tmp"/*.md; do
      name="$(basename "$file")"
      name="${name#??-}"
      name="${name%.md}"
      bytes="$(byte_count "$file")"
      lines="$(line_count "$file")"
      tokens="$(estimate_tokens "$bytes")"
      [[ "$first" -eq 0 ]] && printf ','
      printf '\n    {"name": '; json_string "$name"; printf ', "bytes": %s, "lines": %s, "est_tokens": %s}' "$bytes" "$lines" "$tokens"
      first=0
    done
    printf '\n  ]\n'
    printf '}\n'
  else
    printf '# Packet Inspect\n\n'
    printf -- '- profile: %s\n' "$profile"
    printf -- '- budget: %s\n\n' "$budget"
    printf '| Section | Bytes | Lines | Est Tokens |\n'
    printf '| --- | ---: | ---: | ---: |\n'
    for file in "$tmp"/*.md; do
      name="$(basename "$file")"
      name="${name#??-}"
      name="${name%.md}"
      bytes="$(byte_count "$file")"
      lines="$(line_count "$file")"
      tokens="$(estimate_tokens "$bytes")"
      printf '| %s | %s | %s | %s |\n' "$name" "$bytes" "$lines" "$tokens"
    done
  fi
  rm -rf "$tmp"
}
