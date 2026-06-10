#!/usr/bin/env bash
# shellcheck disable=SC2016

cmd_guard() {
  local first="${1:-}"
  case "$first" in
    -h|--help|help)
      guard_help
      ;;
    scope)
      shift
      guard_scope "$@"
      ;;
    secret)
      shift
      guard_secret "$@"
      ;;
    artifact)
      shift
      guard_artifact "$@"
      ;;
    diff)
      shift
      guard_diff "$@"
      ;;
    doctrine)
      shift
      guard_doctrine "$@"
      ;;
    *)
      guard_cli "$@"
      ;;
  esac
}

guard_help() {
  cat >&2 <<'EOF'
Usage:
  agently guard [--changed] [--file <file>] [--lang bash|python|go|php] [--strict]
  agently guard scope
  agently guard secret
  agently guard artifact
  agently guard diff
  agently guard doctrine
EOF
}

guard_validate_lang() {
  case "$1" in
    bash|python|go|php) return 0 ;;
    *) die "unsupported guard language: $1" ;;
  esac
}

guard_display_command() {
  local first=1 arg
  for arg in "$@"; do
    [[ "$first" -eq 0 ]] && printf ' '
    shell_quote "$arg"
    first=0
  done
}

guard_log_label() {
  local root="$1" log="$2" resolved_root resolved_log
  resolved_root="$(realpath -m "$root")"
  resolved_log="$(realpath -m "$log")"
  case "$resolved_log" in
    "$resolved_root"/*) rel_to_root "$root" "$log" ;;
    *) printf '%s\n' "$log" ;;
  esac
}

guard_merge_status() {
  local current="$1" next="$2"
  if [[ "$current" -eq 0 && "$next" -ne 0 ]]; then
    printf '%s\n' "$next"
  else
    printf '%s\n' "$current"
  fi
}

guard_missing_tool() {
  local root="$1" label="$2" tool="$3" strict="$4"
  printf '\n### %s\n\n' "$label"
  printf -- '- status: skipped\n'
  printf -- '- reason: missing optional tool: %s\n' "$tool"
  warn "missing optional tool for $label: $tool"
  if [[ "$strict" == "true" ]]; then
    return 3
  fi
  return 0
}

guard_run_command() {
  local root="$1" label="$2" log_name="$3"
  local log status
  shift 3
  log="$(agently_log_file "$root" guard "$log_name")"
  printf '\n### %s\n\n' "$label"
  printf -- '- command: `%s`\n' "$(guard_display_command "$@")"
  printf -- '- log: `%s`\n\n' "$(guard_log_label "$root" "$log")"
  printf '```text\n'
  set +e
  (
    cd "$root" || exit 1
    run_and_truncate "$log" -- "$@"
  )
  status=$?
  set -e
  printf '```\n\n'
  printf -- '- status: %s\n' "$status"
  return "$status"
}

guard_collect_files_for_lang() {
  local root="$1" lang="$2" mode="$3"
  shift 3
  local file abs rel detected
  if [[ $# -gt 0 ]]; then
    for file in "$@"; do
      abs="$(resolve_repo_file "$root" "$file")"
      detected="$(detect_language_for_file "$abs")"
      if [[ "$detected" == "$lang" ]]; then
        rel="$(rel_to_root "$root" "$abs")"
        printf '%s\n' "$rel"
      fi
    done
    return 0
  fi
  detect_files_by_lang "$root" "$lang" "$mode"
}

guard_abs_files() {
  local root="$1" rel
  shift
  for rel in "$@"; do
    printf '%s\n' "$root/$rel"
  done
}

guard_bats_files() {
  local root="$1"
  find "$root" -type f -name '*.bats' -not -path "$root/.git/*" -not -path "$root/.agently/cache/*" | sort |
    while IFS= read -r file; do
      rel_to_root "$root" "$file"
    done
}

guard_run_bash() {
  local root="$1" mode="$2" strict="$3"
  shift 3
  local -a files=() abs_files=() bats_files=()
  local rel status=0 next shellcheck_path bats_path
  while IFS= read -r rel; do
    [[ -n "$rel" ]] && files+=("$rel")
  done < <(guard_collect_files_for_lang "$root" bash "$mode" "$@")
  printf '\n## Bash\n\n'
  if [[ "${#files[@]}" -eq 0 ]]; then
    printf -- '- files: none\n'
  else
    printf -- '- files: %s\n' "${#files[@]}"
  fi
  if [[ "${#files[@]}" -gt 0 ]]; then
    if shellcheck_path="$(detect_tool_path_for_root "$root" shellcheck)"; then
      while IFS= read -r rel; do
        [[ -n "$rel" ]] && abs_files+=("$rel")
      done < <(printf '%s\n' "${files[@]}")
      set +e
      guard_run_command "$root" "shellcheck" "bash-shellcheck" "$shellcheck_path" --format=gcc "${abs_files[@]}"
      next=$?
      set -e
      status="$(guard_merge_status "$status" "$next")"
    else
      set +e
      guard_missing_tool "$root" "shellcheck" shellcheck "$strict"
      next=$?
      set -e
      status="$(guard_merge_status "$status" "$next")"
    fi
  fi
  while IFS= read -r rel; do
    [[ -n "$rel" ]] && bats_files+=("$rel")
  done < <(guard_bats_files "$root")
  if [[ "${#bats_files[@]}" -gt 0 ]]; then
    if bats_path="$(detect_tool_path_for_root "$root" bats)"; then
      set +e
      guard_run_command "$root" "bats" "bash-bats" "$bats_path" "${bats_files[@]}"
      next=$?
      set -e
      status="$(guard_merge_status "$status" "$next")"
    else
      set +e
      guard_missing_tool "$root" "bats" bats "$strict"
      next=$?
      set -e
      status="$(guard_merge_status "$status" "$next")"
    fi
  fi
  return "$status"
}

guard_run_python() {
  local root="$1" mode="$2" strict="$3"
  shift 3
  local -a files=()
  local rel status=0 next tool
  while IFS= read -r rel; do
    [[ -n "$rel" ]] && files+=("$rel")
  done < <(guard_collect_files_for_lang "$root" python "$mode" "$@")
  printf '\n## Python\n\n'
  if [[ "${#files[@]}" -eq 0 ]]; then
    printf -- '- files: none\n'
  else
    printf -- '- files: %s\n' "${#files[@]}"
  fi
  if [[ "${#files[@]}" -gt 0 ]]; then
    if tool="$(detect_tool_path_for_root "$root" ruff)"; then
      set +e
      guard_run_command "$root" "ruff check" "python-ruff" "$tool" check --output-format=concise "${files[@]}"
      next=$?
      set -e
      status="$(guard_merge_status "$status" "$next")"
    else
      set +e
      guard_missing_tool "$root" "ruff check" ruff "$strict"
      next=$?
      set -e
      status="$(guard_merge_status "$status" "$next")"
    fi
  fi
  if detect_python_mypy_config "$root"; then
    if tool="$(detect_tool_path_for_root "$root" mypy)"; then
      set +e
      if [[ "${#files[@]}" -gt 0 ]]; then
        guard_run_command "$root" "mypy" "python-mypy" "$tool" "${files[@]}"
      else
        guard_run_command "$root" "mypy" "python-mypy" "$tool" .
      fi
      next=$?
      set -e
      status="$(guard_merge_status "$status" "$next")"
    else
      set +e
      guard_missing_tool "$root" "mypy" mypy "$strict"
      next=$?
      set -e
      status="$(guard_merge_status "$status" "$next")"
    fi
  fi
  if detect_python_tests "$root"; then
    if tool="$(detect_tool_path_for_root "$root" pytest)"; then
      set +e
      guard_run_command "$root" "pytest" "python-pytest" "$tool" -q --tb=short
      next=$?
      set -e
      status="$(guard_merge_status "$status" "$next")"
    else
      set +e
      guard_missing_tool "$root" "pytest" pytest "$strict"
      next=$?
      set -e
      status="$(guard_merge_status "$status" "$next")"
    fi
  fi
  return "$status"
}

guard_run_go() {
  local root="$1" mode="$2" strict="$3"
  shift 3
  local -a files=()
  local rel status=0 next tool
  while IFS= read -r rel; do
    [[ -n "$rel" ]] && files+=("$rel")
  done < <(guard_collect_files_for_lang "$root" go "$mode" "$@")
  printf '\n## Go\n\n'
  if [[ "${#files[@]}" -eq 0 ]]; then
    printf -- '- files: none\n'
  else
    printf -- '- files: %s\n' "${#files[@]}"
  fi
  if detect_go_project "$root" || [[ "${#files[@]}" -gt 0 ]]; then
    if tool="$(detect_tool_path_for_root "$root" go)"; then
      set +e
      guard_run_command "$root" "go test" "go-test" "$tool" test -short ./...
      next=$?
      set -e
      status="$(guard_merge_status "$status" "$next")"
      set +e
      guard_run_command "$root" "go vet" "go-vet" "$tool" vet ./...
      next=$?
      set -e
      status="$(guard_merge_status "$status" "$next")"
    else
      set +e
      guard_missing_tool "$root" "go" go "$strict"
      next=$?
      set -e
      status="$(guard_merge_status "$status" "$next")"
    fi
    if detect_golangci_config "$root"; then
      if tool="$(detect_tool_path_for_root "$root" golangci-lint)"; then
        set +e
        guard_run_command "$root" "golangci-lint" "go-golangci-lint" "$tool" run
        next=$?
        set -e
        status="$(guard_merge_status "$status" "$next")"
      else
        set +e
        guard_missing_tool "$root" "golangci-lint" golangci-lint "$strict"
        next=$?
        set -e
        status="$(guard_merge_status "$status" "$next")"
      fi
    fi
  fi
  return "$status"
}

guard_run_php() {
  local root="$1" mode="$2" strict="$3"
  shift 3
  local -a files=()
  local rel status=0 next tool
  while IFS= read -r rel; do
    [[ -n "$rel" ]] && files+=("$rel")
  done < <(guard_collect_files_for_lang "$root" php "$mode" "$@")
  printf '\n## PHP\n\n'
  if [[ "${#files[@]}" -eq 0 ]]; then
    printf -- '- files: none\n'
  else
    printf -- '- files: %s\n' "${#files[@]}"
  fi
  if [[ "${#files[@]}" -gt 0 ]]; then
    if tool="$(detect_tool_path_for_root "$root" php)"; then
      for rel in "${files[@]}"; do
        set +e
        guard_run_command "$root" "php -l $rel" "php-lint" "$tool" -l "$rel"
        next=$?
        set -e
        status="$(guard_merge_status "$status" "$next")"
      done
    else
      set +e
      guard_missing_tool "$root" "php -l" php "$strict"
      next=$?
      set -e
      status="$(guard_merge_status "$status" "$next")"
    fi
  fi
  if detect_phpstan_config "$root"; then
    if tool="$(detect_tool_path_for_root "$root" phpstan)"; then
      set +e
      guard_run_command "$root" "phpstan analyse" "php-phpstan" "$tool" analyse --error-format=raw
      next=$?
      set -e
      status="$(guard_merge_status "$status" "$next")"
    else
      set +e
      guard_missing_tool "$root" "phpstan analyse" phpstan "$strict"
      next=$?
      set -e
      status="$(guard_merge_status "$status" "$next")"
    fi
  fi
  if detect_pest_config "$root"; then
    if tool="$(detect_tool_path_for_root "$root" pest)"; then
      set +e
      guard_run_command "$root" "pest" "php-pest" "$tool"
      next=$?
      set -e
      status="$(guard_merge_status "$status" "$next")"
    else
      set +e
      guard_missing_tool "$root" "pest" pest "$strict"
      next=$?
      set -e
      status="$(guard_merge_status "$status" "$next")"
    fi
  elif detect_phpunit_config "$root"; then
    if tool="$(detect_tool_path_for_root "$root" phpunit)"; then
      set +e
      guard_run_command "$root" "phpunit" "php-phpunit" "$tool"
      next=$?
      set -e
      status="$(guard_merge_status "$status" "$next")"
    else
      set +e
      guard_missing_tool "$root" "phpunit" phpunit "$strict"
      next=$?
      set -e
      status="$(guard_merge_status "$status" "$next")"
    fi
  fi
  return "$status"
}

guard_configured_languages() {
  local root="$1" value
  value="$(agently_config_get "$root" guard languages)"
  if [[ -z "$value" || "$value" == "auto" ]]; then
    detect_project_languages "$root"
  else
    printf '%s\n' "$value" | tr ',' '\n' | awk '{ gsub(/^[[:space:]]+|[[:space:]]+$/, ""); if ($0 != "") print }'
  fi
}

guard_languages_for_files() {
  local root="$1" file abs lang
  shift
  for file in "$@"; do
    abs="$(resolve_repo_file "$root" "$file")"
    lang="$(detect_language_for_file "$abs")"
    case "$lang" in
      bash|python|go|php) printf '%s\n' "$lang" ;;
    esac
  done | sort -u
}

guard_run_for_root() {
  local root="$1" mode="${2:-all}" strict="${3:-false}"
  shift 3
  local -a langs=() files=()
  local status=0 next lang
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lang)
        [[ $# -ge 2 ]] || die "--lang requires a value"
        guard_validate_lang "$2"
        langs+=("$2")
        shift 2
        ;;
      --file)
        [[ $# -ge 2 ]] || die "--file requires a value"
        files+=("$2")
        shift 2
        ;;
      *) die "unknown guard core option: $1" ;;
    esac
  done
  if [[ "${#langs[@]}" -eq 0 ]]; then
    if [[ "${#files[@]}" -gt 0 ]]; then
      while IFS= read -r lang; do
        [[ -n "$lang" ]] && langs+=("$lang")
      done < <(guard_languages_for_files "$root" "${files[@]}")
    else
      while IFS= read -r lang; do
        [[ -n "$lang" ]] && langs+=("$lang")
      done < <(guard_configured_languages "$root")
    fi
  fi
  printf '# Agently Guard Report\n\n'
  printf -- '- root: `%s`\n' "$root"
  printf -- '- mode: %s\n' "$mode"
  printf -- '- strict_missing_tools: %s\n' "$strict"
  if [[ "${#langs[@]}" -eq 0 ]]; then
    printf -- '- languages: none detected\n'
    return 0
  fi
  printf -- '- languages: %s\n' "${langs[*]}"
  for lang in "${langs[@]}"; do
    guard_validate_lang "$lang"
    set +e
    case "$lang" in
      bash) guard_run_bash "$root" "$mode" "$strict" "${files[@]}" ;;
      python) guard_run_python "$root" "$mode" "$strict" "${files[@]}" ;;
      go) guard_run_go "$root" "$mode" "$strict" "${files[@]}" ;;
      php) guard_run_php "$root" "$mode" "$strict" "${files[@]}" ;;
    esac
    next=$?
    set -e
    status="$(guard_merge_status "$status" "$next")"
  done
  printf '\n## Summary\n\n'
  printf -- '- status: %s\n' "$status"
  return "$status"
}

guard_cli() {
  local root mode="all" strict="" strict_value
  local -a args=()
  root="$(require_initialized)"
  strict_value="$(agently_config_get "$root" guard strict_missing_tools)"
  strict="$(agently_bool "$strict_value")" || die "invalid guard.strict_missing_tools value: $strict_value"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --changed)
        mode="changed"
        shift
        ;;
      --file)
        [[ $# -ge 2 ]] || die "--file requires a value"
        resolve_repo_file "$root" "$2" >/dev/null
        args+=(--file "$2")
        shift 2
        ;;
      --lang)
        [[ $# -ge 2 ]] || die "--lang requires a value"
        guard_validate_lang "$2"
        args+=(--lang "$2")
        shift 2
        ;;
      --strict)
        strict="true"
        shift
        ;;
      -h|--help)
        guard_help
        return 0
        ;;
      *) die "unknown guard option: $1" ;;
    esac
  done
  guard_run_for_root "$root" "$mode" "$strict" "${args[@]}"
}

guard_diff() {
  [[ $# -eq 0 ]] || die "agently guard diff takes no arguments"
  local root log status
  root="$(require_initialized)"
  log="$(agently_log_file "$root" guard diff)"
  printf '# Agently Diff Guard\n\n'
  printf -- '- check: `git diff --check`\n'
  printf -- '- log: `%s`\n\n' "$(rel_to_root "$root" "$log")"
  printf '```text\n'
  set +e
  run_and_truncate "$log" -- git -C "$root" diff --check
  status=$?
  set -e
  printf '```\n\n'
  printf -- '- status: %s\n' "$status"
  return "$status"
}

guard_secret() {
  [[ $# -eq 0 ]] || die "agently guard secret takes no arguments"
  local root log status=0 file
  root="$(require_initialized)"
  log="$(agently_log_file "$root" guard secret)"
  printf '# Agently Secret Guard\n\n'
  : > "$log"
  while IFS= read -r file; do
    [[ -n "$file" && -f "$root/$file" ]] || continue
    if grep -En '((AWS|GCP|AZURE|OPENAI|ANTHROPIC|GITHUB)_[A-Z0-9_]*(KEY|TOKEN|SECRET)|private[ _-]?key|BEGIN [A-Z ]*PRIVATE KEY)' "$root/$file" >> "$log" 2>/dev/null; then
      status=1
    fi
  done < <(changed_files_for_root "$root")
  if [[ "$status" -eq 0 ]]; then
    printf 'No obvious secret patterns found in changed files.\n' > "$log"
  fi
  cat "$log"
  printf '\n- log: `%s`\n' "$(rel_to_root "$root" "$log")"
  printf -- '- status: %s\n' "$status"
  return "$status"
}

guard_scope() {
  [[ $# -eq 0 ]] || die "agently guard scope takes no arguments"
  local root changed count
  root="$(require_initialized)"
  changed="$(changed_files_for_root "$root")"
  count="$(printf '%s\n' "$changed" | awk 'NF { count++ } END { print count + 0 }')"
  printf '# Agently Scope Guard\n\n'
  printf -- '- changed_files: %s\n\n' "$count"
  if [[ "$count" -gt 0 ]]; then
    printf '```text\n%s\n```\n' "$changed"
  else
    printf 'No changed files detected.\n'
  fi
}

guard_artifact() {
  [[ $# -eq 0 ]] || die "agently guard artifact takes no arguments"
  local root cache_dir
  root="$(require_initialized)"
  cache_dir="$(agently_cache_dir_for_root "$root")"
  printf '# Agently Artifact Guard\n\n'
  printf -- '- cache_dir: `%s`\n' "$(rel_to_root "$root" "$cache_dir")"
  printf -- '- cache_is_source_authority: false\n'
  printf -- '- patch_artifacts: `.agently/workstreams/*/artifacts/patches/`\n'
}

guard_doctrine() {
  [[ $# -eq 0 ]] || die "agently guard doctrine takes no arguments"
  local root base provenance file
  root="$(require_initialized)"
  base="$(agently_doctrine_dir "$root")"
  provenance="$(agently_doctrine_provenance "$root" "$base")"
  printf '# Agently Doctrine Guard\n\n'
  if [[ -n "$base" && -d "$base" ]]; then
    printf -- '- doctrine_dir: `%s`\n' "$(rel_to_root "$root" "$base")"
    printf -- '- provenance: %s\n' "$provenance"
    printf -- '- manifest_hash: %s\n\n' "$(agently_doctrine_manifest_hash "$base")"
    printf '## Files\n\n'
    while IFS= read -r file; do
      printf -- '- `%s` sha=%s\n' "$(rel_to_root "$root" "$file")" "$(sha256_of "$file")"
    done < <(find "$base" -maxdepth 1 -type f -name '*.md' | sort)
  else
    printf 'No doctrine directory resolved for this repository.\n'
  fi
}
