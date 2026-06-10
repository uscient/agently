#!/usr/bin/env bash
# shellcheck disable=SC2016

json_string_array() {
  local first=1 item
  printf '['
  for item in "$@"; do
    if [[ "$first" -eq 0 ]]; then
      printf ','
    fi
    json_string "$item"
    first=0
  done
  printf ']'
}

git_root_or_empty() {
  project_dir_or_empty
}

git_branch_for() {
  local root="$1" branch
  branch="$(git -C "$root" branch --show-current 2>/dev/null || true)"
  if [[ -z "$branch" ]]; then
    branch="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || true)"
    [[ -n "$branch" ]] && branch="detached:$branch"
  fi
  printf '%s\n' "${branch:-unknown}"
}

git_status_short_for() {
  local root="$1"
  git -C "$root" status --short 2>/dev/null || true
}

git_dirty_count_for() {
  local status="$1"
  printf '%s' "$status" | awk 'END { print NR + 0 }'
}

agently_config_path_for_root() {
  local root="$1"
  if [[ -f "$root/.agently/config.yml" ]]; then
    printf '%s/.agently/config.yml\n' "$root"
  fi
}

profile_supported_keys() {
  cat <<'EOF'
codex.model
codex.reasoning
codex.auto_edit
claude.model
claude.reasoning
serena.enabled
serena.profile
EOF
}

profile_default_value() {
  case "$1" in
    codex.model) printf 'gpt-5.5\n' ;;
    codex.reasoning) printf 'xhigh\n' ;;
    codex.auto_edit) printf 'true\n' ;;
    claude.model) printf 'opus\n' ;;
    claude.reasoning) printf 'max\n' ;;
    serena.enabled) printf 'false\n' ;;
    serena.profile) printf 'lite\n' ;;
    *) return 1 ;;
  esac
}

profile_key_supported() {
  case "$1" in
    codex.model|codex.reasoning|codex.auto_edit|claude.model|claude.reasoning|serena.enabled|serena.profile) return 0 ;;
    *) return 1 ;;
  esac
}

normalize_bool_value() {
  case "$1" in
    true|TRUE|True|yes|YES|Yes|1|on|ON|On) printf 'true\n' ;;
    false|FALSE|False|no|NO|No|0|off|OFF|Off) printf 'false\n' ;;
    *) return 1 ;;
  esac
}

profile_validate_value() {
  local key="$1" value="$2"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || die "profile values must be single-line"
  case "$key" in
    codex.auto_edit|serena.enabled)
      normalize_bool_value "$value" >/dev/null || die "$key must be true or false"
      ;;
    serena.profile)
      serena_profile_normalize "$value" >/dev/null || die "$key must be lite, review, or edit"
      ;;
  esac
}

profile_value_from_file_or_default() {
  local file="$1" key="$2" value
  [[ -f "$file" ]] && agently_config_validate_project_config_file "$file"
  value="$(config_get_profile_key_from_file "$file" "$key")"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
  else
    profile_default_value "$key"
  fi
}

profile_ensure_gitignore() {
  local root="$1" file tmp
  file="$root/.agently/.gitignore"
  mkdir -p "$root/.agently"
  if [[ ! -f "$file" ]]; then
    printf 'local.yml\ncache/\n' > "$file"
    return 0
  fi
  if ! grep -Fxq 'local.yml' "$file" || ! grep -Fxq 'cache/' "$file"; then
    tmp="$(mktemp "$root/.agently/.gitignore.tmp.XXXXXX")"
    cat "$file" > "$tmp"
    grep -Fxq 'local.yml' "$file" || printf 'local.yml\n' >> "$tmp"
    grep -Fxq 'cache/' "$file" || printf 'cache/\n' >> "$tmp"
    mv "$tmp" "$file"
  fi
}

profile_set_config_key_for_root() {
  local root="$1" key="$2" value="$3" file agent field dir tmp
  profile_key_supported "$key" || die "unknown profile key: $key"
  agently_config_reject_authority_key "$key"
  agently_config_key_allowed "$key" || die "unknown config key: $key"
  file="$root/.agently/config.yml"
  [[ -f "$file" ]] || die "Agently is not initialized here. Run: agently init --codex"
  agently_config_validate_project_config_file "$file"
  agent="${key%%.*}"
  field="${key#*.}"
  dir="$(dirname "$file")"
  tmp="$(mktemp "$dir/.config.yml.tmp.XXXXXX")"
  awk -v agent="$agent" -v field="$field" -v value="$value" '
    function emit_field() {
      print "    " field ": " value
      done = 1
    }
    function emit_agent_block() {
      print "  " agent ":"
      emit_field()
      agent_seen = 1
    }
    function leading_indent(text, prefix) {
      prefix = text
      sub(/[^ ].*$/, "", prefix)
      return length(prefix)
    }
    {
      line = $0
      indent = leading_indent(line)
      is_agents_line = (indent == 0 && line ~ /^agents:[[:space:]]*($|#)/)

      if (indent == 0 && !is_agents_line && in_agents) {
        if (current == agent && !done) {
          emit_field()
        }
        if (!agent_seen) {
          emit_agent_block()
        }
        in_agents = 0
        current = ""
      }

      if (is_agents_line) {
        agents_seen = 1
        in_agents = 1
        current = ""
        print
        next
      }

      if (in_agents && indent == 2 && line ~ /^[[:space:]]{2}[A-Za-z0-9_.-]+:[[:space:]]*($|#)/) {
        if (current == agent && !done) {
          emit_field()
        }
        current = line
        sub(/^[[:space:]]*/, "", current)
        sub(/:.*/, "", current)
        if (current == agent) {
          agent_seen = 1
        }
        print
        next
      }

      if (in_agents && current == agent && indent == 4) {
        pattern = "^[[:space:]]{4}" field ":[[:space:]]*"
        if (line ~ pattern) {
          emit_field()
          next
        }
      }

      print
    }
    END {
      if (in_agents) {
        if (current == agent && !done) {
          emit_field()
        }
        if (!agent_seen) {
          emit_agent_block()
        }
      }
      if (!agents_seen) {
        print ""
        print "agents:"
        emit_agent_block()
      }
    }
  ' "$file" > "$tmp" || {
    rm -f "$tmp"
    return 1
  }
  mv "$tmp" "$file"
}

profile_ensure_config() {
  local root dest
  root="$(require_initialized)"
  dest="$root/.agently/config.yml"
  profile_ensure_gitignore "$root"
  printf '%s\n' "$dest"
}

profile_get_value() {
  local key="$1" root file value local_file local_value
  root="$(require_initialized)"
  file="$(agently_config_path_for_root "$root")"
  local_file="$root/.agently/local.yml"
  agently_config_reject_authority_key "$key"
  if [[ -f "$local_file" ]]; then
    agently_config_validate_local_config_file "$local_file"
    local_value="$(config_get_profile_key_from_file "$local_file" "$key")"
    if [[ -n "$local_value" ]]; then
      printf '%s\n' "$local_value"
      return 0
    fi
  fi
  agently_config_validate_project_config_file "$file"
  value="$(config_get_profile_key_from_file "$file" "$key")"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
  else
    profile_default_value "$key"
  fi
}

cmd_profile() {
  local sub="${1:-help}"
  if [[ $# -gt 0 ]]; then
    shift
  fi
  case "$sub" in
    list) profile_list "$@" ;;
    get) profile_get "$@" ;;
    set) profile_set "$@" ;;
    help|-h|--help|"") profile_help ;;
    *) die "unknown profile command: $sub" ;;
  esac
}

profile_help() {
  cat >&2 <<'EOF'
Usage:
  agently profile list
  agently profile get
  agently profile get <key>
  agently profile set <key> <value>
EOF
}

profile_list() {
  [[ $# -eq 0 ]] || die "profile list takes no arguments"
  local key
  require_initialized >/dev/null
  while IFS= read -r key; do
    printf '%s: %s\n' "$key" "$(profile_get_value "$key")"
  done < <(profile_supported_keys)
}

profile_get() {
  local key
  require_initialized >/dev/null
  case "$#" in
    0)
      cat <<EOF
# Agently Profile

- config: \`$(agently_config_path_for_root "$(repo_root)")\`
- local_override: \`$(repo_root)/.agently/local.yml\`

## Values

EOF
      while IFS= read -r key; do
        printf -- '- %s: %s\n' "$key" "$(profile_get_value "$key")"
      done < <(profile_supported_keys)
      ;;
    1)
      profile_key_supported "$1" || die "unknown profile key: $1"
      profile_get_value "$1"
      ;;
    *) die "usage: agently profile get [key]" ;;
  esac
}

profile_set() {
  [[ $# -eq 2 ]] || die "usage: agently profile set <key> <value>"
  local key="$1" value="$2" root
  profile_key_supported "$key" || die "unknown profile key: $key"
  profile_validate_value "$key" "$value"
  case "$key" in
    codex.auto_edit|serena.enabled) value="$(normalize_bool_value "$value")" ;;
    serena.profile) value="$(serena_profile_normalize "$value")" ;;
  esac
  root="$(require_initialized)"
  profile_ensure_config >/dev/null
  profile_set_config_key_for_root "$root" "$key" "$value"
  profile_ensure_gitignore "$root"
  note "updated profile: $key"
}

doctor_find_crlf_scripts() {
  local root="$1" file
  [[ -d "$root/.agently" || -d "$root/.agents" ]] || return 0
  while IFS= read -r file; do
    if LC_ALL=C grep -q "$(printf '\r')" "$file"; then
      printf '%s\n' "$(rel_to_root "$root" "$file")"
    fi
  done < <(find "$root/.agently" "$root/.agents" -type f -name '*.sh' 2>/dev/null | sort)
}

doctor_find_non_exec_scripts() {
  local root="$1" file
  [[ -d "$root/.agently" || -d "$root/.agents" ]] || return 0
  while IFS= read -r file; do
    [[ -x "$file" ]] || printf '%s\n' "$(rel_to_root "$root" "$file")"
  done < <(find "$root/.agently" "$root/.agents" -type f -name '*.sh' 2>/dev/null | sort)
}

doctor_serena_status() {
  local root="$1"
  if has_cmd serena; then
    printf 'installed\n'
  elif [[ -n "$root" && ( -d "$root/.serena" || -f "$root/serena.yml" || -f "$root/serena.yaml" ) ]]; then
    printf 'configured\n'
  elif [[ -n "$root" && -f "$root/.mcp.json" ]] && grep -qi 'serena' "$root/.mcp.json"; then
    printf 'configured\n'
  else
    printf 'not configured\n'
  fi
}

doctor_tool_names() {
  cat <<'EOF'
git
bash
jq
sha256sum
flock
ast-grep
rg
tree
shellcheck
bats
ruff
mypy
pytest
go
golangci-lint
php
phpstan
phpunit
pest
codex
claude
serena
EOF
}

doctor_tool_path() {
  local root="$1" tool="$2"
  case "$tool" in
    phpstan|phpunit|pest)
      detect_tool_path_for_root "$root" "$tool" 2>/dev/null || true
      ;;
    *)
      command -v "$tool" 2>/dev/null || true
      ;;
  esac
}

doctor_tool_state() {
  local root="$1" tool="$2" path
  path="$(doctor_tool_path "$root" "$tool")"
  if [[ -n "$path" ]]; then
    printf 'installed\n'
  else
    printf 'missing\n'
  fi
}

doctor_tool_table() {
  local root="$1" tool state path version
  printf '| Tool | Status | Path / Version |\n'
  printf '| --- | --- | --- |\n'
  while IFS= read -r tool; do
    [[ -n "$tool" ]] || continue
    state="$(doctor_tool_state "$root" "$tool")"
    path="$(doctor_tool_path "$root" "$tool")"
    version="$(tool_version_line "$tool" 2>/dev/null || true)"
    if [[ -n "$version" ]]; then
      printf '| %s | %s | %s |\n' "$tool" "$state" "$version"
    elif [[ -n "$path" ]]; then
      printf '| %s | %s | %s |\n' "$tool" "$state" "$path"
    else
      printf '| %s | %s | missing |\n' "$tool" "$state"
    fi
  done < <(doctor_tool_names)
}

doctor_tools_json() {
  local root="$1" tool first=1 state path
  printf '{'
  while IFS= read -r tool; do
    [[ -n "$tool" ]] || continue
    state="$(doctor_tool_state "$root" "$tool")"
    path="$(doctor_tool_path "$root" "$tool")"
    [[ "$first" -eq 0 ]] && printf ', '
    json_string "$tool"
    printf ': {"state": '
    json_string "$state"
    printf ', "path": '
    json_string "$path"
    printf '}'
    first=0
  done < <(doctor_tool_names)
  printf '}'
}

doctor_ready_if_tools() {
  local root="$1"
  shift
  local missing=() tool
  for tool in "$@"; do
    if [[ "$(doctor_tool_state "$root" "$tool")" != "installed" ]]; then
      missing+=("$tool")
    fi
  done
  if [[ "${#missing[@]}" -eq 0 ]]; then
    printf 'ready\n'
  else
    printf 'degraded: missing %s\n' "${missing[*]}"
  fi
}

doctor_readiness_report() {
  local root="$1"
  cat <<EOF
## Workflow Readiness

- Packet compiler: $(doctor_ready_if_tools "$root" git bash sha256sum)
- Context cache: $(doctor_ready_if_tools "$root" git bash sha256sum)
- Inspect: $(doctor_ready_if_tools "$root" bash)
- Inspect grep: $(doctor_ready_if_tools "$root" rg)
- Inspect tree: $(doctor_ready_if_tools "$root" tree)
- Inspect ast-grep: $(doctor_ready_if_tools "$root" ast-grep)
- Patch lane: $(doctor_ready_if_tools "$root" git bash)
- Workstream spine: $(doctor_ready_if_tools "$root" jq sha256sum flock)
- Guard Bash: $(doctor_ready_if_tools "$root" shellcheck)
- Guard Python: $(doctor_ready_if_tools "$root" ruff)
- Guard Go: $(doctor_ready_if_tools "$root" go)
- Guard PHP: $(doctor_ready_if_tools "$root" php)
- Eval patch: $(doctor_ready_if_tools "$root" git bash)
EOF
}

doctor_readiness_json() {
  local root="$1"
  printf '{'
  printf '"packet": '; json_string "$(doctor_ready_if_tools "$root" git bash sha256sum)"
  printf ', "context": '; json_string "$(doctor_ready_if_tools "$root" git bash sha256sum)"
  printf ', "inspect": '; json_string "$(doctor_ready_if_tools "$root" bash)"
  printf ', "inspect_grep": '; json_string "$(doctor_ready_if_tools "$root" rg)"
  printf ', "inspect_tree": '; json_string "$(doctor_ready_if_tools "$root" tree)"
  printf ', "inspect_ast_grep": '; json_string "$(doctor_ready_if_tools "$root" ast-grep)"
  printf ', "patch": '; json_string "$(doctor_ready_if_tools "$root" git bash)"
  printf ', "workstream_spine": '; json_string "$(doctor_ready_if_tools "$root" jq sha256sum flock)"
  printf ', "guard_bash": '; json_string "$(doctor_ready_if_tools "$root" shellcheck)"
  printf ', "guard_python": '; json_string "$(doctor_ready_if_tools "$root" ruff)"
  printf ', "guard_go": '; json_string "$(doctor_ready_if_tools "$root" go)"
  printf ', "guard_php": '; json_string "$(doctor_ready_if_tools "$root" php)"
  printf ', "eval_patch": '; json_string "$(doctor_ready_if_tools "$root" git bash)"
  printf '}'
}

doctor_install_suggestions() {
  local root="$1" tool
  printf 'Doctor --fix only prints suggestions; no files were changed and no tools were installed.\n\n'
  printf 'Suggested tool setup commands vary by platform. Install missing tools with your package manager, then rerun `agently doctor`.\n\n'
  printf '```bash\n'
  while IFS= read -r tool; do
    [[ -n "$tool" ]] || continue
    if [[ "$(doctor_tool_state "$root" "$tool")" == "installed" ]]; then
      continue
    fi
    case "$tool" in
      ast-grep) printf '# install ast-grep and ensure the command is named ast-grep\n' ;;
      rg) printf '# install ripgrep for bounded inspect grep\n' ;;
      tree) printf '# install tree for bounded inspect tree\n' ;;
      shellcheck) printf '# install shellcheck for Bash guard checks\n' ;;
      bats) printf '# install bats or bats-core if this project has .bats tests\n' ;;
      ruff) printf '# install ruff for Python guard checks\n' ;;
      mypy) printf '# install mypy if this project has mypy configuration\n' ;;
      pytest) printf '# install pytest if this project has pytest tests\n' ;;
      go) printf '# install Go for Go guard/eval checks\n' ;;
      golangci-lint) printf '# install golangci-lint if this project has golangci config\n' ;;
      php) printf '# install PHP for php -l guard checks\n' ;;
      phpstan) printf '# install phpstan or vendor/bin/phpstan if phpstan.neon is configured\n' ;;
      phpunit) printf '# install phpunit or vendor/bin/phpunit if phpunit.xml is configured\n' ;;
      pest) printf '# install pest or vendor/bin/pest if Pest is configured\n' ;;
      codex) printf '# install Codex CLI if you want Codex integration surfaces\n' ;;
      claude) printf '# install Claude Code if you want Claude handoff execution\n' ;;
      serena) printf '# install/configure Serena only if using the optional Serena capability pack\n' ;;
      jq) printf '# install jq for Agently ws spine JSON manifest mutation\n' ;;
      flock) printf '# install util-linux flock for Agently ws spine locking\n' ;;
      sha256sum) printf '# install coreutils sha256sum for content-hash cache staleness checks\n' ;;
    esac
  done < <(doctor_tool_names)
  printf '```\n'
}

cmd_doctor() {
  local check_codex=0 check_claude=0 check_serena=0 fix=0 json=0 arg
  local root inside_git branch status dirty_count dirty_state agents_state claude_state claude_defers
  local codex_state claude_dir_state serena_state config_state local_state git_state bash_state issues=() fixes=()
  local non_exec_scripts crlf_scripts branch_warnings doctrine_marker doctrine_marker_hash doctrine_installed_dir doctrine_installed_hash

  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      --codex) check_codex=1; shift ;;
      --claude) check_claude=1; shift ;;
      --serena) check_serena=1; shift ;;
      --fix) fix=1; shift ;;
      --json) json=1; shift ;;
      -h|--help)
        cat >&2 <<'EOF'
Usage:
  agently doctor [--codex] [--claude] [--serena] [--fix] [--json]
EOF
        return 0
        ;;
      *) die "unknown doctor option: $arg" ;;
    esac
  done

  [[ -d "$AGENTLY_SHARE/templates" ]] || die "missing templates at $AGENTLY_SHARE/templates. Reinstall Agently or set AGENTLY_HOME."

  root="$(git_root_or_empty)"
  if [[ -n "$root" ]]; then
    inside_git="true"
    branch="$(git_branch_for "$root")"
    status="$(git_status_short_for "$root")"
    dirty_count="$(git_dirty_count_for "$status")"
    if [[ "$dirty_count" -gt 0 ]]; then
      dirty_state="dirty"
    else
      dirty_state="clean"
    fi
  else
    inside_git="false"
    branch="none"
    status=""
    dirty_count=0
    dirty_state="not a git repo"
    issues+=("Current directory is not inside a git repo.")
  fi

  git_state="$(has_cmd git && printf 'installed' || printf 'missing')"
  bash_state="$(has_cmd bash && printf 'installed' || printf 'missing')"
  [[ "$git_state" == "installed" ]] || issues+=("Required tool missing: git.")
  [[ "$bash_state" == "installed" ]] || issues+=("Required tool missing: bash.")

  agents_state="missing"
  claude_state="missing"
  claude_defers="unknown"
  codex_state="missing"
  claude_dir_state="missing"
  config_state="missing"
  local_state="missing"
  non_exec_scripts=""
  crlf_scripts=""
  branch_warnings=""

  if [[ -n "$root" ]]; then
    [[ -f "$root/AGENTS.md" ]] && agents_state="found" || issues+=("AGENTS.md is missing.")
    if [[ -f "$root/CLAUDE.md" ]]; then
      claude_state="found"
      if grep -Eq 'AGENTS\.md|Agently|agently' "$root/CLAUDE.md"; then
        claude_defers="defers to AGENTS.md"
      else
        claude_defers="does not clearly defer to AGENTS.md"
        issues+=("CLAUDE.md does not clearly point to AGENTS.md.")
      fi
    else
      claude_state="missing"
    fi
    if [[ -d "$root/.codex" ]]; then
      if [[ -f "$root/.codex/config.toml.example" ]]; then
        codex_state="found Agently example"
      else
        codex_state="directory found"
      fi
    fi
    [[ -d "$root/.claude" ]] && claude_dir_state="directory found"
    if [[ -f "$root/.agently/config.yml" ]]; then
      config_state="found"
    else
      issues+=(".agently/config.yml is missing.")
    fi
    if [[ -f "$root/.agently/config.yml" ]]; then
      if ! agently_is_source_repo "$root"; then
        doctrine_marker="$root/.agently/doctrine/.agently-doctrine-snapshot.yml"
        doctrine_installed_dir="${AGENTLY_SHARE:-}/docs/doctrine"
        doctrine_installed_hash=""
        [[ -d "$doctrine_installed_dir" ]] && doctrine_installed_hash="$(agently_doctrine_manifest_hash "$doctrine_installed_dir")"
        if [[ -L "$root/.agently/doctrine" ]]; then
          issues+=("Doctrine snapshot path is a symlink; remove it and run: agently doctrine refresh.")
        elif [[ ! -d "$root/.agently/doctrine" ]]; then
          issues+=("Doctrine snapshot is missing; run: agently doctrine refresh or agently init --force.")
        elif [[ -n "$doctrine_installed_hash" ]]; then
          doctrine_marker_hash="$(config_get_top "$doctrine_marker" manifest_hash)"
          if [[ -z "$doctrine_marker_hash" || "$doctrine_marker_hash" != "$doctrine_installed_hash" ]]; then
            issues+=("Doctrine snapshot is stale; run: agently doctrine refresh.")
          fi
        fi
      fi
    fi
    [[ -f "$root/.agently/local.yml" ]] && local_state="found"
    non_exec_scripts="$(doctor_find_non_exec_scripts "$root")"
    crlf_scripts="$(doctor_find_crlf_scripts "$root")"
    if [[ -n "$non_exec_scripts" ]]; then
      issues+=("Generated shell scripts are not executable.")
    fi
    if [[ -n "$crlf_scripts" ]]; then
      issues+=("Generated shell scripts contain CRLF line endings.")
    fi
    if [[ -f "$root/.agently/current" ]]; then
      issues+=("Removed workflow pointer file is present and ignored: .agently/current.")
    fi
  fi

  serena_state="$(doctor_serena_status "$root")"

  if [[ "$fix" -eq 1 ]]; then
    fixes+=("No changes applied; doctor --fix prints suggestions only.")
  fi

  if [[ "$json" -eq 1 ]]; then
    printf '{\n'
    printf '  "version": '; json_string "$(agently_version)"; printf ',\n'
    printf '  "share": '; json_string "$AGENTLY_SHARE"; printf ',\n'
    printf '  "repo": {"inside": '; json_bool "$inside_git"; printf ', "root": '; json_string "${root:-}"; printf ', "branch": '; json_string "$branch"; printf ', "git_state": '; json_string "$dirty_state"; printf ', "dirty_count": %s},\n' "$dirty_count"
    printf '  "tools": '; doctor_tools_json "${root:-}"; printf ',\n'
    printf '  "checks": {"AGENTS.md": '; json_string "$agents_state"; printf ', "CLAUDE.md": '; json_string "$claude_state"; printf ', "claude_defers": '; json_string "$claude_defers"; printf ', "codex_config": '; json_string "$codex_state"; printf ', "claude_config": '; json_string "$claude_dir_state"; printf ', "agently_config": '; json_string "$config_state"; printf ', "local_override": '; json_string "$local_state"; printf '},\n'
    printf '  "readiness": '; doctor_readiness_json "${root:-}"; printf ',\n'
    if [[ "$check_serena" -eq 1 && -n "$root" ]]; then
      serena_collect_state "$root"
      printf '  "serena": '; serena_state_json; printf ',\n'
    fi
    printf '  "workstream_branch_warnings": '; json_string "$branch_warnings"; printf ',\n'
    printf '  "issues": '; json_string_array "${issues[@]}"; printf ',\n'
    printf '  "fixes": '; json_string_array "${fixes[@]}"; printf '\n'
    printf '}\n'
    return 0
  fi

  cat <<EOF
# Agently Doctor Report

## Status

- Repo: $([[ "$inside_git" == "true" ]] && printf 'ok' || printf 'not found')
- Root: \`${root:-none}\`
- Git state: $dirty_state
- Branch: $branch
- Codex: $(has_cmd codex && printf 'installed' || printf 'missing')
- Claude Code: $(has_cmd claude && printf 'installed' || printf 'missing')
- Serena: $serena_state
- AGENTS.md: $agents_state
- CLAUDE.md: $claude_state$([[ "$claude_state" == "found" ]] && printf ', %s' "$claude_defers")
- .codex/: $codex_state
- .claude/: $claude_dir_state
- Config: $config_state
- Local override: $local_state
- Required tools: git=$git_state, bash=$bash_state
EOF

  cat <<'EOF'

## Tool Readiness

EOF
  doctor_tool_table "${root:-}"
  printf '\n'
  doctor_readiness_report "${root:-}"

  if [[ "$check_codex" -eq 1 || "$check_claude" -eq 1 || "$check_serena" -eq 1 ]]; then
    cat <<EOF

## Requested Agent Checks

- Codex command: $(has_cmd codex && command -v codex || printf 'missing')
- Claude command: $(has_cmd claude && command -v claude || printf 'missing')
- Serena status: $serena_state
EOF
  fi

  if [[ "$check_serena" -eq 1 && -n "$root" ]]; then
    serena_doctor_report "$root"
  fi

  if [[ -n "$branch_warnings" ]]; then
    cat <<EOF

## Workstream Branch Checks

$branch_warnings
EOF
  fi

  cat <<'EOF'

## Issues

EOF
  if [[ "${#issues[@]}" -eq 0 ]]; then
    printf -- '- None detected.\n'
  else
    printf -- '- %s\n' "${issues[@]}"
  fi

  if [[ -n "$non_exec_scripts" || -n "$crlf_scripts" ]]; then
    cat <<'EOF'

## Generated Script Checks

EOF
    if [[ -n "$non_exec_scripts" ]]; then
      printf 'Non-executable scripts:\n\n```text\n%s\n```\n' "$non_exec_scripts"
    fi
    if [[ -n "$crlf_scripts" ]]; then
      printf 'CRLF scripts:\n\n```text\n%s\n```\n' "$crlf_scripts"
    fi
  fi

  cat <<'EOF'

## Recommended Fixes

```bash
agently doctor --fix   # print suggestions only
agently profile set codex.model gpt-5.5
agently profile set codex.reasoning xhigh
```
EOF

  if [[ "$fix" -eq 1 ]]; then
    cat <<'EOF'

## Fix Suggestions

EOF
    printf -- '- %s\n\n' "${fixes[@]}"
    doctor_install_suggestions "${root:-}"
  fi
}

workstream_tooling_files() {
  cat <<'EOF'
README.md
PLAN.md
TASKS.md
DECISIONS.md
HANDOFF.md
CODEX.md
CLAUDE.md
LOG.md
state.yml
EOF
}

workstream_template_dir() {
  local root="$1"
  printf '%s/.agently/templates/workstream\n' "$root"
}

workstream_ensure_tooling_files() {
  local root="$1" slug="$2" title date datetime template dest src rel content branch_metadata
  template="$(workstream_template_dir "$root")"
  dest="$root/.agently/workstreams/$slug"
  title="$(titleize "$slug")"
  date="$(today)"
  datetime="$(now)"
  branch_metadata="$(workstream_branch_metadata_disabled false legacy_backfill manual)"
  while IFS= read -r rel; do
    src="$template/$rel"
    [[ -f "$src" ]] || continue
    if [[ -e "$dest/$rel" ]]; then
      continue
    fi
    content="$(render_file_to_stdout "$src" \
      "SLUG=$slug" \
      "TITLE=$title" \
      "WORKSTREAM_SLUG=$slug" \
      "WORKSTREAM_TITLE=$title" \
      "DATE=$date" \
      "DATETIME=$datetime" \
      "BRANCH_METADATA=$branch_metadata" \
      "PROJECT=$(basename "$root")")"
    write_text_file "$dest/$rel" 0644 "$content" 0 0 ".agently/workstreams/$slug/$rel"
  done < <(workstream_tooling_files)
}

cmd_workstream() {
  local sub="${1:-help}"
  if [[ $# -gt 0 ]]; then
    shift
  fi
  case "$sub" in
    list) workstream_list "$@" ;;
    create|new) workstream_create "$@" ;;
    open) workstream_open "$@" ;;
    status) workstream_status "$@" ;;
    prompt) workstream_prompt "$@" ;;
    handoff) workstream_handoff "$@" ;;
    help|-h|--help|"") workstream_help ;;
    *) die "unknown workstream command: $sub" ;;
  esac
}

workstream_help() {
  cat >&2 <<'EOF'
Usage:
  agently workstream list
  agently workstream create <name> [--branch|--no-branch] [--branch-name NAME] [--branch-from REF] [--allow-dirty] [--checkout-existing]
  agently workstream new <name> [--branch|--no-branch] [--branch-name NAME] [--branch-from REF] [--allow-dirty] [--checkout-existing]
  agently workstream open <name>
  agently workstream status <name>
  agently workstream prompt <name> --for <codex|claude>
  agently workstream handoff <name> --for <codex|claude>
EOF
}

workstream_list() {
  ws_list "$@"
}

workstream_create() {
  [[ $# -ge 1 ]] || die "usage: agently workstream create <name> [--branch|--no-branch] [--branch-name NAME] [--branch-from REF] [--allow-dirty] [--checkout-existing]"
  local slug root
  slug="$(slugify "$1")" || die "invalid workstream name: $1"
  root="$(require_initialized)"
  ws_new "$@"
  workstream_ensure_tooling_files "$root" "$slug"
}

workstream_open() {
  [[ $# -eq 1 ]] || die "usage: agently workstream open <name>"
  local slug root dir file
  slug="$(slugify "$1")" || die "invalid workstream name: $1"
  root="$(require_initialized)"
  dir="$root/.agently/workstreams/$slug"
  [[ -d "$dir" ]] || die "workstream not found: $slug"
  cat <<EOF
# Workstream Files: $slug

- Directory: \`$dir\`
EOF
  while IFS= read -r file; do
    [[ -f "$dir/$file" ]] && printf -- '- %s: `%s`\n' "$file" "$dir/$file"
  done < <(workstream_tooling_files)
  cat <<'EOF'

## Editor Hint

EOF
  if [[ -n "${VISUAL:-${EDITOR:-}}" ]]; then
    printf 'Run: `%s %s`\n' "${VISUAL:-${EDITOR:-}}" "$dir"
  elif has_cmd code; then
    printf 'Run: `code %s`\n' "$dir"
  else
    printf 'Set `VISUAL` or `EDITOR`, or open the files above in your editor.\n'
  fi
}

workstream_status() {
  [[ $# -eq 1 ]] || die "usage: agently workstream status <name>"
  local slug root dir task_count latest_handoff latest_log
  slug="$(slugify "$1")" || die "invalid workstream name: $1"
  root="$(require_initialized)"
  dir="$root/.agently/workstreams/$slug"
  [[ -d "$dir" ]] || die "workstream not found: $slug"
  task_count="$(find "$dir/tasks" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | awk 'END { print NR + 0 }')"
  latest_handoff="$dir/HANDOFF.md"
  latest_log="$dir/LOG.md"
  cat <<EOF
# Workstream Status: $slug

- Directory: \`$dir\`
- Tasks: $task_count
- README: \`$dir/README.md\`
- Plan: \`$dir/PLAN.md\`
- Tasks: \`$dir/TASKS.md\`
- Decisions: \`$dir/DECISIONS.md\`
- Handoff: \`$latest_handoff\`
- Codex notes: \`$dir/CODEX.md\`
- Claude notes: \`$dir/CLAUDE.md\`
- Log: \`$latest_log\`
$(workstream_branch_status_markdown "$root" "$dir")

## Current Handoff

$(file_or_empty "$latest_handoff")
EOF
}

workstream_parse_for() {
  [[ $# -eq 2 && "$1" == "--for" ]] || die "usage: agently workstream prompt <name> --for <codex|claude>"
  case "$2" in
    codex|claude) printf '%s\n' "$2" ;;
    *) die "--for must be codex or claude" ;;
  esac
}

workstream_prompt() {
  [[ $# -eq 3 ]] || die "usage: agently workstream prompt <name> --for <codex|claude>"
  local slug agent
  slug="$(slugify "$1")" || die "invalid workstream name: $1"
  agent="$(workstream_parse_for "$2" "$3")"
  prompt_generate_agent "$agent" "$slug" "" "Continue the $slug workstream using the workstream files as the source of truth." ""
}

workstream_handoff() {
  [[ $# -eq 3 ]] || die "usage: agently workstream handoff <name> --for <codex|claude>"
  local slug agent
  slug="$(slugify "$1")" || die "invalid workstream name: $1"
  agent="$(workstream_parse_for "$2" "$3")"
  prompt_generate_agent "$agent" "$slug" "" "Resume from the latest handoff for the $slug workstream." "handoff"
}

latest_file_under() {
  local dir="$1" pattern="$2"
  find "$dir" -type f -name "$pattern" 2>/dev/null | sort | tail -n 1 || true
}

cmd_status() {
  local ws_arg="" json=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workstream)
        [[ $# -ge 2 ]] || die "--workstream requires a value"
        ws_arg="$(slugify "$2")" || die "invalid workstream name: $2"
        shift 2 ;;
      --json) json=1; shift ;;
      -h|--help)
        cat >&2 <<'EOF'
Usage:
  agently status [--workstream <name>] [--json]
EOF
        return 0
        ;;
      *) die "unknown status option: $1" ;;
    esac
  done

  local root branch status dirty_count dirty_state ws dir task_dir handoff prompt test_cmd next_action
  local ws_branch_name ws_branch_status
  root="$(repo_root)"
  branch="$(git_branch_for "$root")"
  status="$(git_status_short_for "$root")"
  dirty_count="$(git_dirty_count_for "$status")"
  dirty_state="$([[ "$dirty_count" -gt 0 ]] && printf 'dirty' || printf 'clean')"
  ws="$ws_arg"
  if [[ -n "$ws" ]]; then
    [[ -f "$root/.agently/config.yml" ]] || die "Agently is not initialized here. Run: agently init --codex"
    dir="$root/.agently/workstreams/$ws"
    [[ -d "$dir" ]] || die "workstream not found: $ws"
  else
    dir=""
  fi
  if [[ -n "$dir" ]]; then
    task_dir=""
    handoff="$dir/HANDOFF.md"
  else
    task_dir=""
    handoff=""
  fi
  if [[ -n "$dir" ]]; then
    prompt="$(latest_file_under "$dir/prompts" '*.md')"
    workstream_branch_collect_status "$root" "$dir"
    ws_branch_name="$WS_BRANCH_STATUS_NAME"
    ws_branch_status="$WS_BRANCH_STATUS_SUMMARY"
  else
    prompt=""
    ws_branch_name=""
    ws_branch_status=""
  fi
  test_cmd="$(detect_test_command "$root")"
  if [[ -n "$ws" ]]; then
    next_action="agently prompt codex --workstream $ws --task implement"
  else
    next_action="agently workstream create <name>"
  fi

  if [[ "$json" -eq 1 ]]; then
    printf '{\n'
    printf '  "repo": {"root": '; json_string "$root"; printf ', "branch": '; json_string "$branch"; printf ', "git_state": '; json_string "$dirty_state"; printf ', "dirty_count": %s},\n' "$dirty_count"
    printf '  "workstream": {"selected": '; json_string "${ws:-}"; printf ', "path": '; json_string "${dir:-}"; printf ', "branch": '; json_string "${ws_branch_name:-}"; printf ', "branch_status": '; json_string "${ws_branch_status:-}"; printf '},\n'
    printf '  "task": {"path": '; json_string "${task_dir:-}"; printf '},\n'
    printf '  "last_handoff": '; json_string "${handoff:-}"; printf ',\n'
    printf '  "last_prompt": '; json_string "${prompt:-}"; printf ',\n'
    printf '  "test_command": '; json_string "${test_cmd:-}"; printf ',\n'
    printf '  "next_action": '; json_string "$next_action"; printf '\n'
    printf '}\n'
    return 0
  fi

  cat <<EOF
# Agently Status

## Repo

- Root: \`$root\`
- Branch: \`$branch\`
- Git state: $dirty_state
- Dirty files: $dirty_count

## Workstream

- Selected: \`${ws:-none}\`
EOF
  if [[ -n "$dir" ]]; then
    cat <<EOF
- Plan: \`$dir/PLAN.md\`
- Tasks: \`$dir/TASKS.md\`
- Handoff: \`$dir/HANDOFF.md\`
$(workstream_branch_status_markdown "$root" "$dir")
EOF
  fi
  cat <<EOF

## Handoff And Prompts

- Last handoff: \`${handoff:-none}\`
- Last generated prompt: \`${prompt:-none}\`
- Test command: \`${test_cmd:-none configured}\`

## Suggested Next Action

Run:

\`\`\`bash
$next_action
\`\`\`
EOF
}

evidence_usage() {
  cat >&2 <<'EOF'
Usage:
  agently evidence [--since <base>] [--tests] [--output <path>] [--json]
EOF
}

evidence_build_markdown() {
  local root="$1" base="$2" run_tests="$3"
  local branch status dirty_count diff_summary changed_files recent_commits test_cmd test_output test_exit test_runner test_log log max_lines
  branch="$(git_branch_for "$root")"
  status="$(git_status_short_for "$root")"
  dirty_count="$(git_dirty_count_for "$status")"
  if [[ -n "$base" ]]; then
    git -C "$root" rev-parse --verify "$base^{commit}" >/dev/null 2>&1 || die "base not found: $base"
    diff_summary="$(git -C "$root" diff --stat "$base"...HEAD 2>/dev/null || true)"
    changed_files="$(git -C "$root" diff --name-status "$base"...HEAD 2>/dev/null || true)"
  else
    diff_summary="$(git -C "$root" diff --stat HEAD 2>/dev/null || git -C "$root" diff --stat 2>/dev/null || true)"
    changed_files="$status"
  fi
  recent_commits="$(git -C "$root" log --oneline -5 2>/dev/null || true)"
  test_cmd="$(detect_test_command "$root")"
  test_output="No test command configured."
  test_exit="not run"
  test_runner="not run"
  test_log="none"
  if [[ "$run_tests" -eq 1 ]]; then
    if [[ -f "$root/.agently/config.yml" ]]; then
      log="$(agently_log_file "$root" evidence tests)"
      max_lines="${AGENTLY_EVIDENCE_TEST_LINES:-80}"
      set +e
      guard_run_for_root "$root" all false > "$log" 2>&1
      test_exit=$?
      test_output="$(emit_bounded_log "$log" "$max_lines" "$test_exit")"
      set -e
      test_runner="agently guard"
      test_log="$(rel_to_root "$root" "$log")"
    else
      test_output="Agently is not initialized; argv-safe guard/eval test evidence was not run."
      test_exit="not run"
      test_runner="not run"
    fi
  fi
  cat <<EOF
# Evidence Pack

## Repo

- Root: \`$root\`
- Branch: \`$branch\`
- Generated: $(now)
- Base: \`${base:-working tree}\`

## Git Status

\`\`\`text
${status:-clean}
\`\`\`

## Branch

\`\`\`text
$branch
\`\`\`

## Diff Summary

\`\`\`text
${diff_summary:-no diff}
\`\`\`

## Changed Files

\`\`\`text
${changed_files:-none}
\`\`\`

## Recent Commits

\`\`\`text
${recent_commits:-none}
\`\`\`

## Tests

- Configured command: \`${test_cmd:-none configured}\`
- Runner: \`$test_runner\`
- Exit: $test_exit
- Log: \`$test_log\`

\`\`\`text
${test_output:-not run}
\`\`\`

## Notes

- Dirty file count: $dirty_count
- This pack is generated from local repository state only.
EOF
}

cmd_evidence() {
  local base="" run_tests=0 output="" json=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --since)
        [[ $# -ge 2 ]] || die "--since requires a value"
        base="$2"; shift 2 ;;
      --tests) run_tests=1; shift ;;
      --output)
        [[ $# -ge 2 ]] || die "--output requires a value"
        output="$2"; shift 2 ;;
      --json) json=1; shift ;;
      -h|--help) evidence_usage; return 0 ;;
      *) die "unknown evidence option: $1" ;;
    esac
  done
  local root markdown branch status dirty_count
  root="$(repo_root)"
  if [[ -n "$base" ]]; then
    git -C "$root" rev-parse --verify "$base^{commit}" >/dev/null 2>&1 || die "base not found: $base"
  fi
  if [[ "$json" -eq 1 ]]; then
    branch="$(git_branch_for "$root")"
    status="$(git_status_short_for "$root")"
    dirty_count="$(git_dirty_count_for "$status")"
    printf '{\n'
    printf '  "repo": {"root": '; json_string "$root"; printf ', "branch": '; json_string "$branch"; printf ', "dirty_count": %s},\n' "$dirty_count"
    printf '  "base": '; json_string "${base:-}"; printf ',\n'
    printf '  "test_command": '; json_string "$(detect_test_command "$root")"; printf ',\n'
    printf '  "generated": '; json_string "$(now)"; printf '\n'
    printf '}\n'
    return 0
  fi
  markdown="$(evidence_build_markdown "$root" "$base" "$run_tests")"
  if [[ -n "$output" ]]; then
    mkdir -p "$(dirname "$output")"
    printf '%s\n' "$markdown" > "$output"
    note "wrote evidence: $output"
  else
    printf '%s\n' "$markdown"
  fi
}

prompt_usage() {
  cat >&2 <<'EOF'
Usage:
  agently prompt codex --workstream <name> (--task <task>|--objective <objective>)
  agently prompt claude --workstream <name> (--task <task>|--objective <objective>)
  agently prompt review --from <file>
  agently prompt review --workstream <name>
  agently prompt --output <path> ...
EOF
}

prompt_write_or_print() {
  local output="$1" content="$2"
  if [[ -n "$output" ]]; then
    mkdir -p "$(dirname "$output")"
    printf '%s\n' "$content" > "$output"
    note "wrote prompt: $output"
  else
    printf '%s\n' "$content"
  fi
}

prompt_file_list_for_workstream() {
  local dir="$1" file
  while IFS= read -r file; do
    [[ -f "$dir/$file" ]] && printf -- '- `%s`\n' "$dir/$file"
  done < <(workstream_tooling_files)
}

prompt_generate_agent() {
  local agent="$1" ws="$2" task="$3" objective="$4" mode="${5:-}"
  local root dir task_dir codex_model codex_reasoning codex_auto_edit claude_model claude_reasoning test_cmd role auto_line agent_model agent_reasoning
  root="$(require_initialized)"
  dir="$root/.agently/workstreams/$ws"
  [[ -d "$dir" ]] || die "workstream not found: $ws"
  task_dir=""
  if [[ -n "$task" ]]; then
    task_dir="$dir/tasks/$task"
    [[ -d "$task_dir" ]] || die "task not found in workstream $ws: $task"
  fi
  codex_model="$(profile_get_value codex.model)"
  codex_reasoning="$(profile_get_value codex.reasoning)"
  codex_auto_edit="$(profile_get_value codex.auto_edit)"
  claude_model="$(profile_get_value claude.model)"
  claude_reasoning="$(profile_get_value claude.reasoning)"
  test_cmd="$(detect_test_command "$root")"
  case "$agent" in
    codex)
      role="You are Codex operating in the Agently-managed repository."
      agent_model="$codex_model"
      agent_reasoning="$codex_reasoning"
      auto_line="You may auto-edit freely within the requested scope. Do not wait for permission."
      ;;
    claude)
      role="You are Claude acting as planner and reviewer for an Agently-managed repository."
      agent_model="$claude_model"
      agent_reasoning="$claude_reasoning"
      auto_line="Plan and review by default. Do not edit files unless the user explicitly asks for implementation."
      ;;
    *) die "unknown prompt agent: $agent" ;;
  esac
  cat <<EOF
# Agently ${agent^} Prompt

## Role

$role

## Objective

${objective:-Complete the requested work in workstream \`$ws\`.}

## Model Preference

- model: $agent_model
- reasoning: $agent_reasoning
- codex.auto_edit: $codex_auto_edit

## Source Of Truth

- Repository root: \`$root\`
- Workstream: \`$dir\`
$(prompt_file_list_for_workstream "$dir")
$([[ -n "$task_dir" ]] && printf -- '- Task capsule: `%s`\n- Task state: `%s`\n- Task requirements: `%s`\n' "$task_dir" "$task_dir/STATE.yaml" "$task_dir/REQUIREMENTS.md")

## Operating Instructions

- Inspect the current repository before editing or judging the work.
- Use Agently files as workflow state; do not rely on chat memory.
- $auto_line
- Keep edits within the requested scope.
- Do not make hidden global config changes.
- Do not run destructive commands.
- Do not make real model calls in tests.
- Show final git status and tests run in the handoff.

## Allowed Edits

- Source, tests, docs, and Agently workflow files directly relevant to the objective.
- Project-local \`.agently/\` handoff, prompt, evidence, and workstream files.

## Forbidden Edits

- Secrets, credentials, telemetry, background services, databases, web UIs, MCP servers, or global Codex/Claude/Serena config.
- Unrelated rewrites or broad architecture changes outside the objective.

## Acceptance Criteria

- The objective is satisfied.
- Relevant tests or smoke checks pass, or gaps are clearly explained.
- Evidence is grounded in local files, command output, or diffs.
- Final handoff includes summary, files changed, tests, known limitations, and git status.

## Test Command

\`\`\`bash
${test_cmd:-# no configured test command detected}
\`\`\`

## Expected Handoff Format

\`\`\`markdown
## Summary
## Files Changed
## Tests / Validation
## Known Limitations
## Final Git Status
\`\`\`

## Workstream README

$(file_or_empty "$dir/README.md")

## Plan

$(file_or_empty "$dir/PLAN.md")

## Tasks

$(file_or_empty "$dir/TASKS.md")

## Handoff

$(file_or_empty "$dir/HANDOFF.md")

## Agent Notes

$(file_or_empty "$dir/${agent^^}.md")
EOF
  if [[ -n "$task_dir" ]]; then
    cat <<EOF

## Task

$(file_or_empty "$task_dir/TASK.md")

## Task Requirements

$(file_or_empty "$task_dir/REQUIREMENTS.md")

## Task Context

$(file_or_empty "$task_dir/CONTEXT.md")
EOF
  fi
  if [[ "$mode" == "handoff" ]]; then
    cat <<EOF

## Resume Instruction

Start from the handoff section above. Identify stale assumptions, then produce the next useful planning, review, or implementation step for $agent.
EOF
  fi
}

prompt_codex_or_claude() {
  local agent="$1" output="$2"
  shift 2
  local ws="" task="" objective=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workstream)
        [[ $# -ge 2 ]] || die "--workstream requires a value"
        ws="$(slugify "$2")" || die "invalid workstream name: $2"
        shift 2 ;;
      --task)
        [[ $# -ge 2 ]] || die "--task requires a value"
        task="$(slugify "$2")" || die "invalid task name: $2"
        shift 2 ;;
      --objective)
        [[ $# -ge 2 ]] || die "--objective requires a value"
        objective="$2"
        shift 2 ;;
      -h|--help) prompt_usage; return 0 ;;
      *) die "unknown prompt $agent option: $1" ;;
    esac
  done
  [[ -n "$ws" ]] || die "--workstream is required"
  [[ -n "$task" || -n "$objective" ]] || die "provide --task or --objective"
  if [[ -n "$task" && -z "$objective" ]]; then
    objective="Complete task \`$task\` in workstream \`$ws\`."
  fi
  prompt_write_or_print "$output" "$(prompt_generate_agent "$agent" "$ws" "$task" "$objective" "")"
}

prompt_review() {
  local output="$1"
  shift
  local from="" ws="" root dir content
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from)
        [[ $# -ge 2 ]] || die "--from requires a value"
        from="$2"; shift 2 ;;
      --workstream)
        [[ $# -ge 2 ]] || die "--workstream requires a value"
        ws="$(slugify "$2")" || die "invalid workstream name: $2"
        shift 2 ;;
      -h|--help) prompt_usage; return 0 ;;
      *) die "unknown prompt review option: $1" ;;
    esac
  done
  if [[ -n "$from" ]]; then
    [[ -f "$from" ]] || die "review source not found: $from"
    content="$(cat "$from")"
    prompt_write_or_print "$output" "$(cat <<EOF
# Agently Review Prompt

## Role

You are reviewing an Agently evidence or handoff file. Prioritize bugs, risks, missing tests, authority-boundary issues, and unsupported claims.

## Instructions

- Ground every finding in the provided file.
- Separate blockers from non-blocking suggestions.
- Do not invent repository state that is not present in the evidence.
- Return concise Markdown with findings first.

## Review Source

\`\`\`markdown
$content
\`\`\`
EOF
)"
    return 0
  fi
  [[ -n "$ws" ]] || die "provide --from <file> or --workstream <name>"
  root="$(require_initialized)"
  dir="$root/.agently/workstreams/$ws"
  [[ -d "$dir" ]] || die "workstream not found: $ws"
  prompt_write_or_print "$output" "$(cat <<EOF
# Agently Workstream Review Prompt

## Role

You are reviewing the \`$ws\` workstream for planning quality, risks, missing acceptance criteria, and next-step clarity.

## Source Files

$(prompt_file_list_for_workstream "$dir")

## Plan

$(file_or_empty "$dir/PLAN.md")

## Tasks

$(file_or_empty "$dir/TASKS.md")

## Decisions

$(file_or_empty "$dir/DECISIONS.md")

## Handoff

$(file_or_empty "$dir/HANDOFF.md")
EOF
)"
}

cmd_prompt() {
  local output="" args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output)
        [[ $# -ge 2 ]] || die "--output requires a value"
        output="$2"; shift 2 ;;
      -h|--help) prompt_usage; return 0 ;;
      *)
        args+=("$1")
        shift ;;
    esac
  done
  [[ "${#args[@]}" -gt 0 ]] || die "usage: agently prompt <codex|claude|review> ..."
  local target="${args[0]}"
  case "$target" in
    codex|claude)
      prompt_codex_or_claude "$target" "$output" "${args[@]:1}"
      ;;
    review)
      prompt_review "$output" "${args[@]:1}"
      ;;
    *) die "unknown prompt target: $target" ;;
  esac
}
