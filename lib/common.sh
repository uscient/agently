#!/usr/bin/env bash

die() {
  echo "FAIL: $*" >&2
  exit 1
}

note() {
  echo "$*" >&2
}

warn() {
  echo "WARN: $*" >&2
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

agently_version() {
  if [[ -f "${AGENTLY_SHARE:-}/VERSION" ]]; then
    sed -n '1p' "$AGENTLY_SHARE/VERSION"
  else
    printf 'unknown\n'
  fi
}

today() {
  date -u '+%Y-%m-%d'
}

now() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

slugify() {
  local raw="$1" s
  s="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:space:]]+/-/g')"
  [[ -n "$s" ]] || return 1
  [[ "$s" != "." && "$s" != ".." ]] || return 1
  [[ "$s" != *".."* ]] || return 1
  [[ "$s" != *"/"* ]] || return 1
  [[ "$s" =~ ^[a-z0-9._-]+$ ]] || return 1
  printf '%s\n' "$s"
}

titleize() {
  local raw="$1"
  printf '%s\n' "$raw" |
    sed -E 's/[-_.]+/ /g' |
    awk '{
      for (i = 1; i <= NF; i++) {
        $i = toupper(substr($i, 1, 1)) substr($i, 2)
      }
      print
    }'
}

shell_quote() {
  printf '%q' "$1"
}

repo_root() {
  local selected root
  selected="${AGENTLY_PROJECT:-}"
  if [[ -n "$selected" ]]; then
    [[ -d "$selected" ]] || die "project does not exist: $selected"
    root="$(git -C "$selected" rev-parse --show-toplevel 2>/dev/null || true)"
    [[ -n "$root" ]] || die "project is not a git repo: $selected"
    printf '%s\n' "$root"
    return 0
  fi
  git rev-parse --show-toplevel 2>/dev/null || die "not inside a git repo"
}

agently_dir() {
  printf '%s/.agently\n' "$(repo_root)"
}

require_initialized() {
  local root
  root="$(repo_root)"
  [[ -f "$root/.agently/config.yml" ]] || die "Agently is not initialized here. Run: agently init --codex"
  agently_config_validate_project_config_file "$root/.agently/config.yml"
  printf '%s\n' "$root"
}

project_dir_or_empty() {
  local selected root
  selected="${AGENTLY_PROJECT:-}"
  if [[ -n "$selected" ]]; then
    [[ -d "$selected" ]] || return 0
    root="$(git -C "$selected" rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -n "$root" ]]; then
      printf '%s\n' "$root"
    else
      (cd "$selected" && pwd)
    fi
    return 0
  fi
  git rev-parse --show-toplevel 2>/dev/null || true
}

fail_json() {
  local code="$1" message="$2"
  {
    printf '{"ok":false,"error":{"code":'
    json_string "$code"
    printf ',"message":'
    json_string "$message"
    printf '}}\n'
  } >&2
  exit 1
}

die_or_json() {
  local json="$1" code="$2" message="$3"
  if [[ "$json" -eq 1 ]]; then
    fail_json "$code" "$message"
  fi
  die "$message"
}

args_include_flag() {
  local needle="$1" arg
  shift
  for arg in "$@"; do
    [[ "$arg" == "$needle" ]] && return 0
  done
  return 1
}

option_has_value() {
  [[ $# -ge 2 && -n "${2:-}" && "${2:-}" != --* ]]
}

config_get_top() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 0
  awk -v key="$key" '
    $1 == key ":" {
      sub("^[^:]*:[[:space:]]*", "")
      print
      exit
    }
  ' "$file"
}

config_get_agent_key() {
  local file="$1" agent="$2" field="$3"
  [[ -f "$file" ]] || return 0
  awk -v agent="$agent" -v field="$field" '
    /^[^[:space:]#][^:]*:/ {
      top = $1
      sub(":", "", top)
      if (top != "agents") {
        in_agents = 0
        current = ""
      }
    }
    /^[[:space:]]*agents:[[:space:]]*$/ {
      in_agents = 1
      current = ""
      next
    }
    in_agents && $0 ~ "^[[:space:]]{2}" agent ":[[:space:]]*$" {
      current = agent
      next
    }
    in_agents && current == agent && $0 ~ "^[[:space:]]{4}" field ":[[:space:]]*" {
      sub("^[[:space:]]*" field ":[[:space:]]*", "")
      print
      exit
    }
  ' "$file"
}

config_get_profile_key_from_file() {
  local file="$1" key="$2" agent field value
  agently_config_reject_authority_key "$key"
  case "$key" in
    codex.model|codex.reasoning|codex.auto_edit|claude.model|claude.reasoning|serena.enabled|serena.profile)
      agent="${key%%.*}"
      field="${key#*.}"
      value="$(config_get_agent_key "$file" "$agent" "$field")"
      if [[ -n "$value" ]]; then
        printf '%s\n' "$value"
        return 0
      fi
      ;;
  esac
  return 0
}

agently_config_keys_from_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  awk '
    /^[[:space:]]*($|#)/ { next }
    /^[[:space:]]*-/ { next }
    {
      raw = $0
      sub(/\r$/, "", raw)
      if (raw !~ /^[[:space:]]*[A-Za-z0-9_.-]+:[[:space:]]*/) {
        next
      }
      indent = match(raw, /[^ ]/) - 1
      line = raw
      sub(/[[:space:]]+#.*$/, "", line)
      key = line
      sub(/^[[:space:]]*/, "", key)
      sub(/:.*/, "", key)
      rest = line
      sub(/^[[:space:]]*[A-Za-z0-9_.-]+:[[:space:]]*/, "", rest)
      has_value = (rest != "")

      if (indent == 0) {
        top = key
        second = ""
        if (has_value) {
          print NR ":" key
        } else {
          print NR ":" key
        }
        next
      }

      if (indent == 2) {
        second = key
        if (top == "agents") {
          if (has_value) {
            print NR ":agents." key
          }
          next
        }
        if (top == "workstreams") {
          if (has_value) {
            print NR ":workstreams." key
          }
          next
        }
        if (top == "ws") {
          if (has_value) {
            print NR ":ws." key
          }
          next
        }
        print NR ":" top "." key
        next
      }

      if (indent == 4) {
        if (top == "agents") {
          print NR ":" second "." key
        } else {
          print NR ":" top "." second "." key
        }
        next
      }

      if (indent > 4) {
        print NR ":" top "." second "." key
      }
    }
  ' "$file"
}

agently_config_project_container_allowed() {
  case "$1" in
    agents|workstreams|ws|context|inspect|guard|eval|patch) return 0 ;;
    *) return 1 ;;
  esac
}

agently_config_validate_project_config_file() {
  local file="$1" line key
  [[ -f "$file" ]] || return 0
  while IFS=: read -r line key; do
    [[ -n "${key:-}" ]] || continue
    agently_config_reject_authority_key "$key"
    agently_config_project_container_allowed "$key" && continue
    agently_config_ignored_legacy_key "$key" && continue
    agently_config_key_allowed "$key" || die "unknown config key in .agently/config.yml line $line: $key"
  done < <(agently_config_keys_from_file "$file")
}

agently_config_validate_local_config_file() {
  local file="$1" line key
  [[ -f "$file" ]] || return 0
  while IFS=: read -r line key; do
    [[ -n "${key:-}" ]] || continue
    agently_config_reject_authority_key "$key"
    [[ "$key" == "agents" ]] && continue
    agently_config_local_key_allowed "$key" || die "unknown local config key in .agently/local.yml line $line: $key"
  done < <(agently_config_keys_from_file "$file")
}

ws_dir_for() {
  local slug="$1"
  printf '%s/workstreams/%s\n' "$(agently_dir)" "$slug"
}

task_dir_for() {
  local ws="$1" task="$2"
  printf '%s/tasks/%s\n' "$(ws_dir_for "$ws")" "$task"
}

require_workstream_handle() {
  local raw="${1:-}" root ws dir
  [[ -n "$raw" ]] || die "--workstream is required"
  ws="$(slugify "$raw")" || die "invalid workstream: $raw"
  root="$(require_initialized)"
  dir="$root/.agently/workstreams/$ws"
  [[ -d "$dir" ]] || die "workstream not found: $ws"
  printf '%s\n' "$ws"
}

require_task_handle() {
  local ws="${1:-}" raw="${2:-}" root task dir
  [[ -n "$raw" ]] || die "--task is required"
  task="$(slugify "$raw")" || die "invalid task: $raw"
  root="$(require_initialized)"
  dir="$root/.agently/workstreams/$ws/tasks/$task"
  [[ -d "$dir" ]] || die "task not found: $task"
  printf '%s\n' "$task"
}

require_task_dir_for_handles() {
  local ws raw_task task
  ws="$(require_workstream_handle "${1:-}")"
  raw_task="${2:-}"
  task="$(require_task_handle "$ws" "$raw_task")"
  task_dir_for "$ws" "$task"
}

render_content() {
  local content="$1"
  shift
  local pair key value
  for pair in "$@"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    content="${content//\{\{$key\}\}/$value}"
  done
  printf '%s\n' "$content"
}

render_file_to_stdout() {
  local src="$1" content
  shift
  content="$(cat "$src")"
  render_content "$content" "$@"
}

write_text_file() {
  local dst="$1" mode="$2" content="$3" force="$4" dry_run="$5" label="$6"
  local dir tmp
  AGENTLY_WRITES_DONE="${AGENTLY_WRITES_DONE:-0}"
  AGENTLY_WRITES_SKIPPED="${AGENTLY_WRITES_SKIPPED:-0}"
  dir="$(dirname "$dst")"
  if [[ "$dry_run" -eq 1 ]]; then
    note "DRY write $label"
    return 0
  fi
  mkdir -p "$dir"
  if [[ -s "$dst" && "$force" -ne 1 ]]; then
    note "keep existing non-empty: $label"
    AGENTLY_WRITES_SKIPPED=$((AGENTLY_WRITES_SKIPPED + 1))
    return 0
  fi
  tmp="$(mktemp "$dir/.agently-write.tmp.XXXXXX")"
  printf '%s' "$content" > "$tmp"
  mv "$tmp" "$dst"
  chmod "$mode" "$dst"
  note "wrote: $label"
  AGENTLY_WRITES_DONE=$((AGENTLY_WRITES_DONE + 1))
}

file_or_empty() {
  local path="$1"
  if [[ -s "$path" ]]; then
    cat "$path"
  else
    printf '_(empty)_\n'
  fi
}

json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

json_string() {
  printf '"%s"' "$(json_escape "${1:-}")"
}

json_bool() {
  case "${1:-}" in
    1|true|yes|ok|found|installed|enabled) printf 'true' ;;
    *) printf 'false' ;;
  esac
}

line_count() {
  awk 'END { print NR + 0 }' "$1" 2>/dev/null || printf '0\n'
}

byte_count() {
  wc -c < "$1" 2>/dev/null | awk '{ print $1 + 0 }'
}

estimate_tokens() {
  local bytes="${1:-0}"
  [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
  awk -v bytes="$bytes" 'BEGIN { print int((bytes + 3) / 4) }'
}

rel_to_root() {
  local root="$1" path="$2"
  realpath --relative-to="$root" "$path" 2>/dev/null || printf '%s\n' "$path"
}

agently_is_source_repo() {
  local root="$1" share="${AGENTLY_SHARE:-}"
  [[ -d "$root/docs/doctrine" ]] || return 1
  if [[ -n "$share" && "$root" -ef "$share" ]]; then
    return 0
  fi
  [[ -f "$root/lib/agently.sh" && -x "$root/bin/agently" && -f "$root/VERSION" ]]
}

agently_doctrine_dir() {
  local root="$1" share="${AGENTLY_SHARE:-}"

  if agently_is_source_repo "$root"; then
    printf '%s/docs/doctrine\n' "$root"
    return 0
  fi

  if [[ -d "$root/.agently/doctrine" ]]; then
    printf '%s/.agently/doctrine\n' "$root"
    return 0
  fi

  if [[ -n "$share" && -d "$share/docs/doctrine" ]]; then
    printf '%s/docs/doctrine\n' "$share"
    return 0
  fi

  return 0
}

agently_doctrine_provenance() {
  local root="$1" dir="$2" share="${AGENTLY_SHARE:-}"
  if [[ -z "$dir" ]]; then
    printf 'none\n'
  elif agently_is_source_repo "$root" && [[ "$dir" == "$root/docs/doctrine" ]]; then
    printf 'source\n'
  elif [[ "$dir" == "$root/.agently/doctrine" ]]; then
    printf 'runtime-snapshot\n'
  elif [[ -n "$share" && "$dir" == "$share/docs/doctrine" ]]; then
    printf 'installed-fallback\n'
  else
    printf 'unknown\n'
  fi
}

is_protected_authority_path() {
  local rel="${1:-}"

  rel="${rel#./}"

  case "$rel" in
    AGENTS.md) return 0 ;;
    docs/doctrine/*) return 0 ;;
    .agently/doctrine|.agently/doctrine/*) return 0 ;;
  esac

  return 1
}

config_file_for_root() {
  local root="$1"
  printf '%s/.agently/config.yml\n' "$root"
}

config_get_subtree_key_for_root() {
  local root="$1" section="$2" key="$3" file value
  file="$(config_file_for_root "$root")"
  [[ -f "$file" ]] || return 0
  agently_config_validate_project_config_file "$file"
  value="$(awk -v section="$section" -v key="$key" '
    /^[^[:space:]#][^:]*:/ {
      top = $1
      sub(":", "", top)
      in_section = (top == section)
    }
    in_section {
      pattern = "^[[:space:]]{2}" key ":[[:space:]]*"
      if ($0 ~ pattern) {
        value = $0
        sub(pattern, "", value)
        sub(/[[:space:]]+#.*$/, "", value)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        if (value ~ /^'\''.*'\''$/ || value ~ /^".*"$/) {
          value = substr(value, 2, length(value) - 2)
          gsub(/'\'''\''/, "'\''", value)
        }
        print value
        exit
      }
    }
  ' "$file")"
  printf '%s\n' "$value"
}

agently_config_default() {
  local section="$1" key="$2"
  case "$section.$key" in
    context.default_budget) printf 'normal\n' ;;
    context.log_tail_lines) printf '20\n' ;;
    context.ledger_tail_lines) printf '10\n' ;;
    context.doctrine_mode) printf 'manifest\n' ;;
    context.cache_dir) printf '.agently/cache\n' ;;
    inspect.prefer_ripgrep) printf 'true\n' ;;
    inspect.max_grep_matches) printf '100\n' ;;
    inspect.max_full_lines) printf '2000\n' ;;
    inspect.tree_depth) printf '3\n' ;;
    guard.strict_missing_tools) printf 'false\n' ;;
    guard.languages) printf 'auto\n' ;;
    eval.use_worktree) printf 'true\n' ;;
    patch.dir) printf 'artifacts/patches\n' ;;
    patch.require_reviewed) printf 'true\n' ;;
    *) return 1 ;;
  esac
}

agently_config_get() {
  local root="$1" section="$2" key="$3" value
  agently_config_reject_authority_key "$section.$key"
  agently_config_key_allowed "$section.$key" || die "unknown config key: $section.$key"
  agently_config_default "$section" "$key" >/dev/null || die "unknown config key: $section.$key"
  value="$(config_get_subtree_key_for_root "$root" "$section" "$key")"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
  else
    agently_config_default "$section" "$key"
  fi
}

agently_bool() {
  case "${1:-}" in
    true|TRUE|True|yes|YES|Yes|1|on|ON|On) printf 'true\n' ;;
    false|FALSE|False|no|NO|No|0|off|OFF|Off|"") printf 'false\n' ;;
    *) return 1 ;;
  esac
}

agently_cache_dir_for_root() {
  local root="$1" rel
  rel="$(agently_config_get "$root" context cache_dir)"
  case "$rel" in
    .agently/cache|.agently/cache/*) printf '%s/%s\n' "$root" "$rel" ;;
    *) die "context.cache_dir must stay under .agently/cache: $rel" ;;
  esac
}

agently_cache_dir() {
  agently_cache_dir_for_root "$(require_initialized)"
}

agently_cache_subdir() {
  local root="$1" sub="$2" dir resolved ag_dir
  case "$sub" in
    summaries|summaries/*|manifests|manifests/*|logs|logs/*) ;;
    *) die "invalid cache subdir: $sub" ;;
  esac
  dir="$(agently_cache_dir_for_root "$root")/$sub"
  ag_dir="$(realpath -m "$root/.agently")"
  resolved="$(realpath -m "$dir")"
  case "$resolved" in
    "$ag_dir"/*) ;;
    *) die "cache path escapes .agently: $dir" ;;
  esac
  mkdir -p "$dir"
  printf '%s\n' "$resolved"
}

agently_log_file() {
  local root="$1" group="$2" name="${3:-run}" ts safe_group safe_name dir
  safe_group="$(slugify "$group")" || safe_group="run"
  safe_name="$(slugify "$name")" || safe_name="run"
  ts="$(date -u '+%Y%m%dT%H%M%SZ')"
  if [[ -n "${AGENTLY_LOG_ROOT:-}" ]]; then
    dir="$AGENTLY_LOG_ROOT/$safe_group"
    mkdir -p "$dir"
  else
    dir="$(agently_cache_subdir "$root" "logs/$safe_group")"
  fi
  printf '%s/%s-%s.log\n' "$dir" "$ts" "$safe_name"
}

run_and_truncate() {
  local logfile="$1" max_lines="${AGENTLY_TRUNCATE_LINES:-60}" head_lines="${AGENTLY_TRUNCATE_HEAD:-25}" tail_lines="${AGENTLY_TRUNCATE_TAIL:-25}"
  local status lines omitted errexit_was_set=0
  shift
  [[ "${1:-}" == "--" ]] && shift
  [[ $# -gt 0 ]] || die "run_and_truncate requires a command"
  mkdir -p "$(dirname "$logfile")"
  case "$-" in
    *e*) errexit_was_set=1 ;;
  esac
  set +e
  "$@" >"$logfile" 2>&1
  status=$?
  lines="$(awk 'END { print NR + 0 }' "$logfile")"
  if (( lines > max_lines )); then
    head -n "$head_lines" "$logfile"
    omitted=$((lines - head_lines - tail_lines))
    (( omitted < 0 )) && omitted=0
    printf '\n... [TRUNCATED %s LINES - full log: %s] ...\n\n' "$omitted" "$logfile"
    tail -n "$tail_lines" "$logfile"
    warn "full output logged at $logfile"
  else
    cat "$logfile"
  fi
  if [[ "$errexit_was_set" -eq 1 ]]; then
    set -e
  fi
  return "$status"
}

emit_bounded_log() {
  local logfile="$1" max_lines="${2:-${AGENTLY_TRUNCATE_LINES:-60}}" status="${3:-0}" head_lines="${AGENTLY_TRUNCATE_HEAD:-25}" tail_lines="${AGENTLY_TRUNCATE_TAIL:-25}"
  local lines omitted
  [[ -f "$logfile" ]] || die "bounded log file not found: $logfile"
  [[ "$max_lines" =~ ^[0-9]+$ && "$max_lines" -gt 0 ]] || die "max lines must be a positive integer"
  lines="$(awk 'END { print NR + 0 }' "$logfile")"
  if (( lines > max_lines )); then
    head -n "$head_lines" "$logfile"
    omitted=$((lines - head_lines - tail_lines))
    (( omitted < 0 )) && omitted=0
    printf '\n... [TRUNCATED %s LINES - full log: %s] ...\n\n' "$omitted" "$logfile"
    tail -n "$tail_lines" "$logfile"
    warn "full output logged at $logfile"
  else
    cat "$logfile"
  fi
  return "$status"
}

resolve_repo_file() {
  local root="$1" path="$2" abs resolved_root
  resolved_root="$(realpath "$root")"
  case "$path" in
    /*) abs="$(realpath -m "$path")" ;;
    *) abs="$(realpath -m "$root/$path")" ;;
  esac
  case "$abs" in
    "$resolved_root"|"$resolved_root"/*) ;;
    *) die "path escapes repository: $path" ;;
  esac
  [[ -f "$abs" ]] || die "file not found: $path"
  printf '%s\n' "$abs"
}

resolve_repo_path() {
  local root="$1" path="${2:-.}" abs resolved_root
  resolved_root="$(realpath "$root")"
  case "$path" in
    /*) abs="$(realpath -m "$path")" ;;
    *) abs="$(realpath -m "$root/$path")" ;;
  esac
  case "$abs" in
    "$resolved_root"|"$resolved_root"/*) ;;
    *) die "path escapes repository: $path" ;;
  esac
  [[ -e "$abs" ]] || die "path not found: $path"
  printf '%s\n' "$abs"
}

changed_files_for_root() {
  local root="$1" ref="${2:-}" file
  if [[ -n "$ref" ]]; then
    git -C "$root" rev-parse --verify "$ref^{commit}" >/dev/null 2>&1 || die "base not found: $ref"
    git -C "$root" diff --name-only "$ref"...HEAD
    return 0
  fi
  {
    git -C "$root" diff --name-only
    git -C "$root" diff --name-only --cached
    git -C "$root" ls-files --others --exclude-standard
  } 2>/dev/null | sort -u | while IFS= read -r file; do
    [[ -n "$file" ]] && printf '%s\n' "$file"
  done
}

detect_language_for_file() {
  local file="$1" first
  case "$file" in
    *.sh|*.bash|*/bash/*) printf 'bash\n'; return 0 ;;
    *.py|*/python/*) printf 'python\n'; return 0 ;;
    *.go|*/go/*) printf 'go\n'; return 0 ;;
    *.php|*/php/*) printf 'php\n'; return 0 ;;
    *.md|*.markdown) printf 'markdown\n'; return 0 ;;
    *.yml|*.yaml) printf 'yaml\n'; return 0 ;;
  esac
  first="$(sed -n '1p' "$file" 2>/dev/null || true)"
  case "$first" in
    '#!'*bash*|'#!'*'/sh') printf 'bash\n' ;;
    '#!'*python*) printf 'python\n' ;;
    *) printf 'text\n' ;;
  esac
}

extract_symbols_for_file() {
  local file="$1" lang="${2:-}"
  [[ -n "$lang" ]] || lang="$(detect_language_for_file "$file")"
  case "$lang" in
    bash)
      awk '
        /^[[:space:]]*function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(\(\))?[[:space:]]*\{/ { print FILENAME ":" FNR ": " $0 }
        /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)[[:space:]]*\{/ { print FILENAME ":" FNR ": " $0 }
      ' "$file"
      ;;
    python)
      awk '/^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+/ || /^[[:space:]]*class[[:space:]]+/ { print FILENAME ":" FNR ": " $0 }' "$file"
      ;;
    go)
      awk '/^(package|func|type|var|const)[[:space:]]+/ { print FILENAME ":" FNR ": " $0 }' "$file"
      ;;
    php)
      awk '/(function|class|trait|interface|enum)[[:space:]]+/ { print FILENAME ":" FNR ": " $0 }' "$file"
      ;;
    markdown)
      awk '/^#{1,6}[[:space:]]+/ { print FILENAME ":" FNR ": " $0 }' "$file"
      ;;
    yaml)
      awk '/^[A-Za-z0-9_.-]+:[[:space:]]*/ { print FILENAME ":" FNR ": " $0 }' "$file"
      ;;
    *)
      awk '/^[[:space:]]*($|#)/ { next } { print FILENAME ":" FNR ": " $0; count++; if (count >= 40) exit }' "$file"
      ;;
  esac
}

extract_skeleton_for_file() {
  local file="$1" lang="${2:-}" prev_blank=1
  [[ -n "$lang" ]] || lang="$(detect_language_for_file "$file")"
  case "$lang" in
    markdown)
      awk '/^#{1,6}[[:space:]]+/ { print }' "$file"
      ;;
    yaml)
      awk '/^[A-Za-z0-9_.-]+:[[:space:]]*/ { print }' "$file"
      ;;
    bash|python|go|php)
      extract_symbols_for_file "$file" "$lang" | sed 's/^[^:]*:[0-9][0-9]*: //'
      printf '...\n'
      ;;
    *)
      while IFS= read -r line; do
        if [[ -z "$line" ]]; then
          if [[ "$prev_blank" -eq 0 ]]; then
            printf '\n'
          fi
          prev_blank=1
          continue
        fi
        printf '%s\n' "$line"
        prev_blank=0
      done < "$file" | head -n 120
      ;;
  esac
}

structural_digest_for_file() {
  local file="$1" rel="${2:-$file}" lang lines bytes sha
  lang="$(detect_language_for_file "$file")"
  lines="$(line_count "$file")"
  bytes="$(byte_count "$file")"
  sha="$(sha256_of "$file")"
  cat <<EOF
## $rel

- sha256: $sha
- bytes: $bytes
- lines: $lines
- language: $lang

EOF
  case "$lang" in
    markdown)
      printf '### Headings\n\n'
      awk '/^#{1,6}[[:space:]]+/ { print "- " $0; count++; if (count >= 40) exit }' "$file"
      printf '\n### Key Lines\n\n'
      awk '
        /^[[:space:]]*[-*][[:space:]]+/ || /TODO|FIXME|OPEN/ {
          print "- " $0
          count++
          if (count >= 40) exit
        }
      ' "$file"
      ;;
    yaml)
      printf '### Top-Level Keys\n\n'
      awk '/^[A-Za-z0-9_.-]+:[[:space:]]*/ { print "- " $0; count++; if (count >= 40) exit }' "$file"
      ;;
    *)
      printf '### Skeleton\n\n```text\n'
      extract_skeleton_for_file "$file" "$lang" | head -n 120
      printf '```\n'
      ;;
  esac
}

detect_test_command() {
  local root="$1" cfg="" configured=""
  if [[ -f "$root/.agently/config.yml" ]]; then
    cfg="$root/.agently/config.yml"
  fi
  if [[ -n "$cfg" ]]; then
    agently_config_validate_project_config_file "$cfg"
    configured="$(config_get_top "$cfg" test_command)"
    if [[ -n "$configured" ]]; then
      printf '%s\n' "$configured"
      return 0
    fi
  fi
  if [[ -x "$root/tests/smoke.sh" ]]; then
    printf './tests/smoke.sh\n'
  elif [[ -f "$root/go.mod" ]]; then
    printf 'go test ./...\n'
  elif [[ -f "$root/package.json" ]]; then
    printf 'npm test\n'
  fi
  return 0
}

state_file_for() {
  printf '%s/STATE.yaml\n' "$1"
}

state_require_in() {
  local task_dir="$1" file
  file="$(state_file_for "$task_dir")"
  [[ -f "$file" ]] || die "missing task state: $file"
}

state_get_in() {
  local task_dir="$1" key="$2" file
  file="$(state_file_for "$task_dir")"
  [[ -f "$file" ]] || return 0
  awk -v key="$key" '
    $1 == key ":" {
      sub("^[^:]*:[[:space:]]*", "")
      print
      exit
    }
  ' "$file"
}

state_set_raw_in() {
  local task_dir="$1" key="$2" value="$3" file dir tmp
  file="$(state_file_for "$task_dir")"
  dir="$(dirname "$file")"
  tmp="$(mktemp "$dir/.STATE.yaml.tmp.XXXXXX")"
  awk -v key="$key" -v value="$value" '
    BEGIN { done = 0 }
    $0 ~ "^" key ":[[:space:]]*" {
      print key ": " value
      done = 1
      next
    }
    { print }
    END {
      if (!done) {
        print key ": " value
      }
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

state_set_in() {
  local task_dir="$1" key="$2" value="$3"
  state_require_in "$task_dir"
  state_set_raw_in "$task_dir" "$key" "$value"
  if [[ "$key" != "updated_at" ]]; then
    state_set_raw_in "$task_dir" updated_at "$(now)"
  fi
}

state_status_allowed() {
  case "$1" in
    draft|requirements_ready|claude_request_ready|claude_response_ready|codex_eval_ready|user_decision_needed|accepted|needs_revision|rejected|execution_ready|done)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

ledger_append_in() {
  local task_dir="$1" event="$2" file
  file="$task_dir/ledger.md"
  mkdir -p "$(dirname "$file")"
  printf -- '- %s %s\n' "$(now)" "$event" >> "$file"
}

next_round_in() {
  local task_dir="$1" max=0 file base n
  shopt -s nullglob
  for file in "$task_dir"/handoffs/claude/*-request.md; do
    base="$(basename "$file")"
    n="${base%%-*}"
    if [[ "$n" =~ ^[0-9][0-9][0-9]$ ]]; then
      if (( 10#$n > max )); then
        max=$((10#$n))
      fi
    fi
  done
  shopt -u nullglob
  printf '%03d\n' "$((max + 1))"
}

sha256_of() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    printf 'pending\n'
  elif has_cmd sha256sum; then
    sha256sum "$path" | awk '{print $1}'
  else
    printf 'unavailable\n'
  fi
}

agently_doctrine_manifest_hash() {
  local dir="$1" f rel
  [[ -d "$dir" ]] || { printf 'pending\n'; return 0; }
  has_cmd sha256sum || { printf 'unavailable\n'; return 0; }
  {
    while IFS= read -r f; do
      rel="${f#"$dir"/}"
      printf '%s  %s\n' "$(sha256_of "$f")" "$rel"
    done < <(find "$dir" -type f -name '*.md' | sort)
  } | sha256sum | awk '{print $1}'
}

rel_to_task() {
  local task_dir="$1" path="$2"
  realpath --relative-to="$task_dir" "$path" 2>/dev/null || printf '%s\n' "$path"
}

ensure_under_agently() {
  local path="$1" root resolved ag_dir
  root="$(require_initialized)"
  ag_dir="$root/.agently"
  resolved="$(realpath "$path")"
  case "$resolved" in
    "$ag_dir"/*) printf '%s\n' "$resolved" ;;
    *) die "resolved path escapes .agently: $path" ;;
  esac
}

normalize_doc_name() {
  local name="$1"
  [[ "$name" != *"/"* && "$name" != *".."* ]] || die "invalid doc name: $name"
  name="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
  name="${name%.md}"
  printf '%s\n' "$name"
}

resolve_doc_path() {
  local ws="$1" task="$2" raw="$3" name task_dir ws_dir prefix=""
  name="$(normalize_doc_name "$raw")"
  if [[ "$name" == ws:* ]]; then
    prefix="ws"
    name="${name#ws:}"
  fi
  ws="$(require_workstream_handle "$ws")"
  ws_dir="$(ws_dir_for "$ws")"
  task="$(require_task_handle "$ws" "$task")"
  if [[ "$prefix" != "ws" && -n "$task" ]]; then
    task_dir="$(task_dir_for "$ws" "$task")"
    case "$name" in
      task) ensure_under_agently "$task_dir/TASK.md"; return ;;
      requirements) ensure_under_agently "$task_dir/REQUIREMENTS.md"; return ;;
      context) ensure_under_agently "$task_dir/CONTEXT.md"; return ;;
      notes) ensure_under_agently "$task_dir/NOTES.md"; return ;;
      ledger) ensure_under_agently "$task_dir/ledger.md"; return ;;
      state) ensure_under_agently "$task_dir/STATE.yaml"; return ;;
    esac
  fi
  case "$name" in
    workstream|ws) ensure_under_agently "$ws_dir/workstream.md" ;;
    status) ensure_under_agently "$ws_dir/status.md" ;;
    requirements) ensure_under_agently "$ws_dir/requirements.md" ;;
    decisions) ensure_under_agently "$ws_dir/decisions.md" ;;
    inbox) ensure_under_agently "$ws_dir/inbox.md" ;;
    *) die "unknown doc name: $raw" ;;
  esac
}

validate_claude_effort() {
  case "$1" in
    auto|low|medium|high|xhigh|max) return 0 ;;
    *) die "invalid Claude effort: $1" ;;
  esac
}

validate_claude_model() {
  local model="$1" backtick
  backtick='`'
  [[ -n "$model" ]] || die "Claude model cannot be empty"
  if [[ "$model" == *$'\n'* ||
        "$model" == *$'\r'* ||
        "$model" == *$'\t'* ||
        "$model" == *" "* ||
        "$model" == *";"* ||
        "$model" == *"&"* ||
        "$model" == *"|"* ||
        "$model" == *"<"* ||
        "$model" == *">"* ||
        "$model" == *"$backtick"* ||
        "$model" == *"\""* ||
        "$model" == *"\\"* ||
        "$model" == *"'"* ]]; then
    die "Claude model contains unsafe shell characters: $model"
  fi
}

join_command_display() {
  local out="" arg
  for arg in "$@"; do
    if [[ -n "$out" ]]; then
      out+=" "
    fi
    out+="$(shell_quote "$arg")"
  done
  printf '%s\n' "$out"
}
