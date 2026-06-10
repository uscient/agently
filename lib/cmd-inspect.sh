#!/usr/bin/env bash

cmd_inspect() {
  local sub="${1:-help}"
  if [[ $# -gt 0 ]]; then
    shift
  fi
  case "$sub" in
    symbols) inspect_symbols "$@" ;;
    skeleton) inspect_skeleton "$@" ;;
    read) inspect_read "$@" ;;
    grep) inspect_grep "$@" ;;
    sg) inspect_sg "$@" ;;
    tree) inspect_tree "$@" ;;
    doc) inspect_doc "$@" ;;
    help|-h|--help|"") inspect_help ;;
    *) die "unknown inspect command: $sub" ;;
  esac
}

inspect_help() {
  cat >&2 <<'EOF'
Usage:
  agently inspect symbols <file>
  agently inspect skeleton <file>
  agently inspect read <file> --start <n> --end <m>
  agently inspect read <file> --full
  agently inspect grep <pattern> [path] [--lang <lang>] [--max <n>]
  agently inspect sg <pattern> --lang <lang> [path] [--max <n>] [--require]
  agently inspect tree [path] --depth <n>
  agently inspect doc go <package>
EOF
}

inspect_positive_int() {
  local value="$1" label="$2"
  [[ "$value" =~ ^[0-9]+$ && "$value" -gt 0 ]] || die "$label must be a positive integer"
}

inspect_emit_log_bounded() {
  local logfile="$1" max_lines="$2" status="${3:-0}" lines omitted
  inspect_positive_int "$max_lines" "--max"
  lines="$(line_count "$logfile")"
  if (( lines > max_lines )); then
    head -n "$max_lines" "$logfile"
    omitted=$((lines - max_lines))
    printf '\n[TRUNCATED %s LINES - full log: %s]\n' "$omitted" "$logfile"
    warn "full output logged at $logfile"
  else
    cat "$logfile"
  fi
  return "$status"
}

inspect_symbols() {
  [[ $# -eq 1 ]] || die "usage: agently inspect symbols <file>"
  local root file log status
  root="$(require_initialized)"
  file="$(resolve_repo_file "$root" "$1")"
  log="$(agently_log_file "$root" inspect symbols)"
  set +e
  extract_symbols_for_file "$file" > "$log" 2>&1
  status=$?
  set -e
  inspect_emit_log_bounded "$log" 200 "$status"
}

inspect_skeleton() {
  [[ $# -eq 1 ]] || die "usage: agently inspect skeleton <file>"
  local root file log status
  root="$(require_initialized)"
  file="$(resolve_repo_file "$root" "$1")"
  log="$(agently_log_file "$root" inspect skeleton)"
  set +e
  extract_skeleton_for_file "$file" > "$log" 2>&1
  status=$?
  set -e
  inspect_emit_log_bounded "$log" 240 "$status"
}

inspect_read() {
  local path="${1:-}" start="" end="" full=0 root file max_full lines log
  [[ -n "$path" ]] || die "usage: agently inspect read <file> --start <n> --end <m> OR --full"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --start)
        [[ $# -ge 2 ]] || die "--start requires a value"
        start="$2"; shift 2 ;;
      --end)
        [[ $# -ge 2 ]] || die "--end requires a value"
        end="$2"; shift 2 ;;
      --full) full=1; shift ;;
      -h|--help) inspect_help; return 0 ;;
      *) die "unknown inspect read option: $1" ;;
    esac
  done
  root="$(require_initialized)"
  file="$(resolve_repo_file "$root" "$path")"
  if [[ "$full" -eq 1 ]]; then
    [[ -z "$start" && -z "$end" ]] || die "--full cannot be combined with --start/--end"
    max_full="$(agently_config_get "$root" inspect max_full_lines)"
    inspect_positive_int "$max_full" "inspect.max_full_lines"
    log="$(agently_log_file "$root" inspect read-full)"
    cat "$file" > "$log"
    lines="$(line_count "$file")"
    if (( lines > max_full )); then
      warn "full read logged at $log"
      die "inspect read --full exceeds cap: $lines lines > $max_full. Use --start/--end."
    fi
    warn "full read logged at $log"
    cat "$log"
    return 0
  fi
  [[ -n "$start" && -n "$end" ]] || die "inspect read requires --start and --end unless --full is passed"
  inspect_positive_int "$start" "--start"
  inspect_positive_int "$end" "--end"
  (( start <= end )) || die "--start must be <= --end"
  awk -v start="$start" -v end="$end" 'NR >= start && NR <= end { print }' "$file"
}

inspect_grep_parse() {
  INSPECT_PATTERN=""
  INSPECT_PATH="."
  INSPECT_MAX=""
  [[ $# -ge 1 ]] || die "usage: agently inspect grep <pattern> [path] [--lang <lang>] [--max <n>]"
  INSPECT_PATTERN="$1"
  shift
  if [[ $# -gt 0 && "$1" != --* ]]; then
    INSPECT_PATH="$1"
    shift
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lang)
        [[ $# -ge 2 ]] || die "--lang requires a value"
        shift 2 ;;
      --max)
        [[ $# -ge 2 ]] || die "--max requires a value"
        INSPECT_MAX="$2"; shift 2 ;;
      -h|--help) inspect_help; return 2 ;;
      *) die "unknown inspect grep option: $1" ;;
    esac
  done
}

inspect_grep_run() {
  local root="$1" pattern="$2" path="$3" max="$4" target log status
  target="$(resolve_repo_path "$root" "$path")"
  if [[ -z "$max" ]]; then
    max="$(agently_config_get "$root" inspect max_grep_matches)"
  fi
  inspect_positive_int "$max" "--max"
  log="$(agently_log_file "$root" inspect grep)"
  set +e
  if has_cmd rg && [[ "$(agently_bool "$(agently_config_get "$root" inspect prefer_ripgrep)" 2>/dev/null || printf true)" == "true" ]]; then
    rg --line-number --no-heading --color never -- "$pattern" "$target" > "$log" 2>&1
  else
    grep -R -n -- "$pattern" "$target" > "$log" 2>&1
  fi
  status=$?
  set -e
  inspect_emit_log_bounded "$log" "$max" "$status"
}

inspect_grep() {
  local root
  inspect_grep_parse "$@"
  root="$(require_initialized)"
  inspect_grep_run "$root" "$INSPECT_PATTERN" "$INSPECT_PATH" "$INSPECT_MAX"
}

inspect_sg() {
  local pattern="" path="" lang="" max="" require_tool=0 root target log status
  [[ $# -ge 1 ]] || die "usage: agently inspect sg <pattern> --lang <lang> [path]"
  pattern="$1"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lang)
        [[ $# -ge 2 ]] || die "--lang requires a value"
        lang="$2"; shift 2 ;;
      --max)
        [[ $# -ge 2 ]] || die "--max requires a value"
        max="$2"; shift 2 ;;
      --require) require_tool=1; shift ;;
      -h|--help) inspect_help; return 0 ;;
      --*) die "unknown inspect sg option: $1" ;;
      *)
        [[ -z "$path" ]] || die "inspect sg accepts only one path"
        path="$1"; shift ;;
    esac
  done
  [[ -n "$lang" ]] || die "inspect sg requires --lang <lang>"
  root="$(require_initialized)"
  [[ -n "$path" ]] || path="."
  if [[ -z "$max" ]]; then
    max="$(agently_config_get "$root" inspect max_grep_matches)"
  fi
  inspect_positive_int "$max" "--max"
  target="$(resolve_repo_path "$root" "$path")"
  if ! has_cmd ast-grep; then
    warn "ast-grep not found; install https://ast-grep.github.io (degrading to grep)"
    if [[ "$require_tool" -eq 1 ]]; then
      return 3
    fi
    inspect_grep_run "$root" "$pattern" "$path" "$max"
    return $?
  fi
  log="$(agently_log_file "$root" inspect ast-grep)"
  set +e
  ast-grep --pattern "$pattern" --lang "$lang" "$target" > "$log" 2>&1
  status=$?
  set -e
  inspect_emit_log_bounded "$log" "$max" "$status"
}

inspect_tree() {
  local path="." depth="" root target log status max=200
  if [[ $# -gt 0 && "$1" != --* ]]; then
    path="$1"
    shift
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --depth)
        [[ $# -ge 2 ]] || die "--depth requires a value"
        depth="$2"; shift 2 ;;
      -h|--help) inspect_help; return 0 ;;
      *) die "unknown inspect tree option: $1" ;;
    esac
  done
  root="$(require_initialized)"
  if [[ -z "$depth" ]]; then
    depth="$(agently_config_get "$root" inspect tree_depth)"
  fi
  inspect_positive_int "$depth" "--depth"
  target="$(resolve_repo_path "$root" "$path")"
  log="$(agently_log_file "$root" inspect tree)"
  set +e
  if has_cmd tree; then
    tree -L "$depth" "$target" > "$log" 2>&1
  else
    find "$target" -maxdepth "$depth" -print | sed "s#^$target#.#" > "$log" 2>&1
  fi
  status=$?
  set -e
  inspect_emit_log_bounded "$log" "$max" "$status"
}

inspect_doc() {
  local lang="${1:-}" subject="${2:-}" root log status
  [[ -n "$lang" && -n "$subject" ]] || die "usage: agently inspect doc go <package>"
  shift 2 || true
  [[ $# -eq 0 ]] || die "inspect doc takes exactly two arguments"
  root="$(require_initialized)"
  case "$lang" in
    go)
      if ! has_cmd go; then
        warn "go not found; cannot run go doc"
        return 3
      fi
      log="$(agently_log_file "$root" inspect go-doc)"
      set +e
      go doc "$subject" > "$log" 2>&1
      status=$?
      set -e
      inspect_emit_log_bounded "$log" 160 "$status"
      ;;
    *) die "unsupported inspect doc language: $lang" ;;
  esac
}
