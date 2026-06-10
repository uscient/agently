#!/usr/bin/env bash

cmd_ws() {
  local sub="${1:-help}"
  if [[ $# -gt 0 ]]; then
    shift
  fi
  case "$sub" in
    list) ws_list "$@" ;;
    new) ws_new "$@" ;;
    use) ws_use "$@" ;;
    current) ws_current "$@" ;;
    init) ws_init_spine "$@" ;;
    status) ws_status_spine "$@" ;;
    summary) ws_summary_spine "$@" ;;
    ingest) ws_ingest_spine "$@" ;;
    propose) ws_propose_spine "$@" ;;
    reject) ws_reject_spine "$@" ;;
    promote) ws_promote_spine "$@" ;;
    doctor) ws_doctor_spine "$@" ;;
    show) ws_show "$@" ;;
    path) ws_path "$@" ;;
    help|-h|--help|"") ws_help ;;
    *) die "unknown ws command: $sub" ;;
  esac
}

ws_help() {
  cat >&2 <<'EOF'
Usage:
  agently ws list
  agently ws new <slug> [--branch|--no-branch] [--branch-name NAME] [--branch-from REF] [--allow-dirty] [--checkout-existing]
  agently ws show --workstream <slug>
  agently ws show <ALIAS> [--json]
  agently ws path --workstream <slug>
  agently ws init <WS_ID> [--json]
  agently ws status <WS_ID> [--json]
  agently ws summary <WS_ID> [--json]
  agently ws ingest <WS_ID> --type <TYPE> --file <PATH> [--json]
  agently ws propose <ALIAS> [--json]
  agently ws reject <ALIAS> [--json]
  agently ws promote <ALIAS> [--json]
  agently ws doctor <WS_ID> [--verify-hashes] [--json]

Spine promote/reject use a /dev/tty typed-alias confirmation. This is a
friction gate, not a security boundary; same-user shell access can edit
.agently files directly.
EOF
}

workstream_branch_default() {
  case "$1" in
    mode) printf 'manual\n' ;;
    prefix) printf 'workstream/\n' ;;
    checkout_on_create) printf 'true\n' ;;
    require_clean_tree) printf 'true\n' ;;
    if_exists) printf 'fail\n' ;;
    base) printf 'current\n' ;;
    push_on_create|set_upstream|delete_on_close) printf 'false\n' ;;
    *) return 1 ;;
  esac
}

workstream_branch_config_file_for_root() {
  local root="$1"
  printf '%s/.agently/config.yml\n' "$root"
}

workstream_branch_config_get_for_root() {
  local root="$1" key="$2" file value
  workstream_branch_default "$key" >/dev/null || die "unknown workstream branch config key: $key"
  file="$(workstream_branch_config_file_for_root "$root")"
  if [[ -f "$file" ]]; then
    agently_config_validate_project_config_file "$file"
    value="$(awk -v key="$key" '
      /^[^[:space:]#][^:]*:/ {
        top = $1
        sub(":", "", top)
        in_workstreams = (top == "workstreams")
        in_branch = 0
      }
      in_workstreams && /^[[:space:]]{2}branch:[[:space:]]*($|#)/ {
        in_branch = 1
        next
      }
      in_workstreams && in_branch && /^[[:space:]]{2}[^[:space:]#][^:]*:/ {
        in_branch = 0
      }
      in_workstreams && in_branch {
        pattern = "^[[:space:]]{4}" key ":[[:space:]]*"
        if ($0 ~ pattern) {
          value = $0
          sub(pattern, "", value)
          sub(/[[:space:]]+#.*$/, "", value)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
          if (value ~ /^".*"$/) {
            value = substr(value, 2, length(value) - 2)
          }
          print value
          exit
        }
      }
    ' "$file")"
  else
    value=""
  fi
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
  else
    workstream_branch_default "$key"
  fi
}

workstream_branch_config_get() {
  local key="$1" root
  root="$(require_initialized)"
  workstream_branch_config_get_for_root "$root" "$key"
}

workstream_branch_normalize_mode() {
  case "$1" in
    off|manual|auto) printf '%s\n' "$1" ;;
    *) return 1 ;;
  esac
}

workstream_branch_bool() {
  case "$1" in
    true|yes|1|on) printf 'true\n' ;;
    false|no|0|off|"") printf 'false\n' ;;
    *) return 1 ;;
  esac
}

workstream_branch_yaml_quote() {
  local value="$1" escaped
  escaped="$(printf '%s' "$value" | sed "s/'/''/g")"
  printf "'%s'" "$escaped"
}

workstream_branch_current() {
  local root="$1" branch commit
  branch="$(git -C "$root" branch --show-current 2>/dev/null || true)"
  if [[ -n "$branch" ]]; then
    printf '%s\n' "$branch"
    return 0
  fi
  commit="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || true)"
  if [[ -n "$commit" ]]; then
    printf 'detached:%s\n' "$commit"
  else
    printf 'unknown\n'
  fi
}

workstream_branch_exists() {
  local root="$1" branch="$2"
  git -C "$root" show-ref --verify --quiet "refs/heads/$branch"
}

workstream_branch_validate_name() {
  local root="$1" branch="$2"
  [[ -n "$branch" ]] || die "branch name cannot be empty"
  git -C "$root" check-ref-format --branch "$branch" >/dev/null 2>&1 || die "invalid Git branch name: $branch"
}

workstream_branch_slug_component() {
  local slug="$1" component
  component="$(printf '%s' "$slug" | sed -E 's/^[._-]+//; s/[._-]+$//')"
  [[ -n "$component" ]] || component="$slug"
  printf '%s\n' "$component"
}

workstream_branch_dirty_check() {
  local root="$1" allow_dirty="$2" dirty
  [[ "$allow_dirty" -eq 1 ]] && return 0
  dirty="$(git -C "$root" status --porcelain)"
  if [[ -n "$dirty" ]]; then
    die "dirty git tree; commit/stash changes or rerun with --allow-dirty"
  fi
}

workstream_branch_repo_check() {
  local root="$1"
  git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "branch creation requires a Git repo"
}

workstream_branch_base_resolve() {
  local root="$1" base="$2"
  if [[ "$base" == "current" ]]; then
    WS_BRANCH_BASE_REF="HEAD"
    WS_BRANCH_BASE_BRANCH="$(workstream_branch_current "$root")"
  else
    git -C "$root" rev-parse --verify "$base^{commit}" >/dev/null 2>&1 || die "branch base not found: $base"
    WS_BRANCH_BASE_REF="$base"
    WS_BRANCH_BASE_BRANCH="$base"
  fi
  WS_BRANCH_BASE_COMMIT="$(git -C "$root" rev-parse "$WS_BRANCH_BASE_REF^{commit}" 2>/dev/null)" || die "could not resolve branch base: $base"
}

workstream_branch_switch_existing() {
  local root="$1" branch="$2"
  if git -C "$root" switch "$branch" >/dev/null 2>&1; then
    return 0
  fi
  git -C "$root" checkout "$branch" >/dev/null 2>&1 || die "failed to check out existing branch: $branch"
}

workstream_branch_create_or_checkout() {
  local root="$1" branch="$2" base_ref="$3" checkout_on_create="$4" checkout_existing="$5" current
  WS_BRANCH_CREATED=false
  WS_BRANCH_CHECKED_OUT=false
  current="$(git -C "$root" branch --show-current 2>/dev/null || true)"
  if workstream_branch_exists "$root" "$branch"; then
    if [[ "$current" == "$branch" ]]; then
      WS_BRANCH_CHECKED_OUT=true
      return 0
    fi
    if [[ "$checkout_existing" -eq 1 ]]; then
      workstream_branch_switch_existing "$root" "$branch"
      WS_BRANCH_CHECKED_OUT=true
      return 0
    fi
    die "Git branch already exists: $branch. Use --checkout-existing to bind it."
  fi

  if [[ "$checkout_on_create" == "true" ]]; then
    if git -C "$root" switch -c "$branch" "$base_ref" >/dev/null 2>&1; then
      WS_BRANCH_CREATED=true
      WS_BRANCH_CHECKED_OUT=true
      return 0
    fi
    git -C "$root" checkout -b "$branch" "$base_ref" >/dev/null 2>&1 || die "failed to create branch: $branch"
    WS_BRANCH_CREATED=true
    WS_BRANCH_CHECKED_OUT=true
  else
    git -C "$root" branch "$branch" "$base_ref" >/dev/null 2>&1 || die "failed to create branch: $branch"
    WS_BRANCH_CREATED=true
    WS_BRANCH_CHECKED_OUT=false
  fi
}

workstream_branch_metadata_disabled() {
  local requested="$1" reason="$2" mode="$3"
  cat <<EOF
  enabled: false
  requested: $requested
  mode: $(workstream_branch_yaml_quote "$mode")
  reason: $(workstream_branch_yaml_quote "$reason")
EOF
}

workstream_branch_metadata_enabled() {
  local branch="$1" mode="$2" prefix="$3" base="$4" base_branch="$5" base_commit="$6" created="$7" checked_out="$8"
  cat <<EOF
  enabled: true
  requested: true
  name: $(workstream_branch_yaml_quote "$branch")
  mode: $(workstream_branch_yaml_quote "$mode")
  prefix: $(workstream_branch_yaml_quote "$prefix")
  base: $(workstream_branch_yaml_quote "$base")
  base_branch: $(workstream_branch_yaml_quote "$base_branch")
  base_commit: $(workstream_branch_yaml_quote "$base_commit")
  created: $created
  checked_out: $checked_out
  created_at: $(workstream_branch_yaml_quote "$(now)")
EOF
}

workstream_branch_prepare() {
  local root="$1" slug="$2" cli_branch="$3" cli_no_branch="$4" branch_name="$5" branch_from="$6" allow_dirty="$7" checkout_existing="$8"
  local mode prefix checkout_on_create require_clean_tree if_exists base requested reason branch branch_component
  mode="$(workstream_branch_config_get_for_root "$root" mode)"
  mode="$(workstream_branch_normalize_mode "$mode")" || die "invalid workstreams.branch.mode: $mode"
  prefix="$(workstream_branch_config_get_for_root "$root" prefix)"
  checkout_on_create="$(workstream_branch_bool "$(workstream_branch_config_get_for_root "$root" checkout_on_create)")" || die "invalid workstreams.branch.checkout_on_create"
  require_clean_tree="$(workstream_branch_bool "$(workstream_branch_config_get_for_root "$root" require_clean_tree)")" || die "invalid workstreams.branch.require_clean_tree"
  if_exists="$(workstream_branch_config_get_for_root "$root" if_exists)"
  [[ "$if_exists" == "fail" ]] || die "unsupported workstreams.branch.if_exists: $if_exists"
  base="${branch_from:-$(workstream_branch_config_get_for_root "$root" base)}"

  if [[ "$(workstream_branch_bool "$(workstream_branch_config_get_for_root "$root" push_on_create)")" == "true" ]]; then
    warn "workstreams.branch.push_on_create is ignored in v1"
  fi
  if [[ "$(workstream_branch_bool "$(workstream_branch_config_get_for_root "$root" set_upstream)")" == "true" ]]; then
    warn "workstreams.branch.set_upstream is ignored in v1"
  fi
  if [[ "$(workstream_branch_bool "$(workstream_branch_config_get_for_root "$root" delete_on_close)")" == "true" ]]; then
    warn "workstreams.branch.delete_on_close is ignored in v1"
  fi

  requested=0
  reason=""
  if [[ "$cli_no_branch" -eq 1 ]]; then
    reason="cli_no_branch"
  elif [[ "$cli_branch" -eq 1 || -n "$branch_name" || -n "$branch_from" || "$checkout_existing" -eq 1 ]]; then
    requested=1
  elif [[ "$mode" == "auto" ]]; then
    requested=1
  elif [[ "$mode" == "off" ]]; then
    reason="mode_off"
  else
    reason="mode_manual_without_cli_branch"
  fi

  if [[ "$requested" -eq 0 ]]; then
    workstream_branch_metadata_disabled false "$reason" "$mode"
    return 0
  fi

  workstream_branch_repo_check "$root"
  branch_component="$(workstream_branch_slug_component "$slug")"
  branch="${branch_name:-$prefix$branch_component}"
  workstream_branch_validate_name "$root" "$branch"
  if [[ "$require_clean_tree" == "true" ]]; then
    workstream_branch_dirty_check "$root" "$allow_dirty"
  fi
  workstream_branch_base_resolve "$root" "$base"
  workstream_branch_create_or_checkout "$root" "$branch" "$WS_BRANCH_BASE_REF" "$checkout_on_create" "$checkout_existing"
  workstream_branch_metadata_enabled "$branch" "$mode" "$prefix" "$base" "$WS_BRANCH_BASE_BRANCH" "$WS_BRANCH_BASE_COMMIT" "$WS_BRANCH_CREATED" "$WS_BRANCH_CHECKED_OUT"
}

workstream_state_branch_get() {
  local dir="$1" key="$2" file
  file="$dir/state.yml"
  [[ -f "$file" ]] || return 0
  awk -v key="$key" '
    /^[^[:space:]#][^:]*:/ {
      top = $1
      sub(":", "", top)
      in_branch = (top == "branch")
    }
    in_branch {
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
  ' "$file"
}

workstream_branch_collect_status() {
  local root="$1" dir="$2" enabled name current exists base_commit warning
  WS_BRANCH_STATUS_SUMMARY="no branch metadata"
  WS_BRANCH_STATUS_WARNINGS=""
  WS_BRANCH_STATUS_NAME=""
  enabled="$(workstream_state_branch_get "$dir" enabled)"
  if [[ "$enabled" != "true" ]]; then
    warning="$(workstream_state_branch_get "$dir" reason)"
    WS_BRANCH_STATUS_SUMMARY="not bound$([[ -n "$warning" ]] && printf ' (%s)' "$warning")"
    return 0
  fi
  name="$(workstream_state_branch_get "$dir" name)"
  WS_BRANCH_STATUS_NAME="$name"
  current="$(workstream_branch_current "$root")"
  exists="missing"
  if workstream_branch_exists "$root" "$name"; then
    exists="exists"
  else
    WS_BRANCH_STATUS_WARNINGS+="- workstream has branch metadata but branch no longer exists: $name"$'\n'
  fi
  if [[ "$exists" == "exists" && "$current" != "$name" ]]; then
    WS_BRANCH_STATUS_WARNINGS+="- current branch does not match active workstream branch: current=$current expected=$name"$'\n'
  fi
  base_commit="$(workstream_state_branch_get "$dir" base_commit)"
  if [[ -n "$base_commit" ]] && ! git -C "$root" rev-parse --verify "$base_commit^{commit}" >/dev/null 2>&1; then
    WS_BRANCH_STATUS_WARNINGS+="- branch metadata exists but cannot resolve base commit: $base_commit"$'\n'
  fi
  if [[ "$exists" == "exists" && "$current" == "$name" ]]; then
    WS_BRANCH_STATUS_SUMMARY="branch exists, checked out"
  elif [[ "$exists" == "exists" ]]; then
    WS_BRANCH_STATUS_SUMMARY="branch exists, not checked out"
  else
    WS_BRANCH_STATUS_SUMMARY="branch missing"
  fi
}

workstream_branch_status_markdown() {
  local root="$1" dir="$2" current
  workstream_branch_collect_status "$root" "$dir"
  current="$(workstream_branch_current "$root")"
  cat <<EOF
- Branch: \`${WS_BRANCH_STATUS_NAME:-none}\`
- Current branch: \`$current\`
- Branch status: $WS_BRANCH_STATUS_SUMMARY
EOF
  if [[ -n "$WS_BRANCH_STATUS_WARNINGS" ]]; then
    printf '\n## Branch Warnings\n\n%s' "$WS_BRANCH_STATUS_WARNINGS"
  fi
}

ws_list() {
  [[ $# -eq 0 ]] || die "ws list takes no arguments"
  local root dir slug
  root="$(require_initialized)"
  shopt -s nullglob
  for dir in "$root/.agently/workstreams"/*; do
    [[ -d "$dir" ]] || continue
    slug="$(basename "$dir")"
    if [[ -f "$dir/manifest.json" ]]; then
      printf '%s [spine]\n' "$slug"
    else
      printf '%s\n' "$slug"
    fi
  done
  shopt -u nullglob
}

ws_new() {
  [[ $# -ge 1 ]] || die "usage: agently ws new <slug> [--branch|--no-branch] [--branch-name NAME] [--branch-from REF] [--allow-dirty] [--checkout-existing]"
  local raw="$1" slug title root template dest date datetime content src rel dst
  local cli_branch=0 cli_no_branch=0 branch_name="" branch_from="" allow_dirty=0 checkout_existing=0 branch_metadata
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --branch) cli_branch=1; shift ;;
      --no-branch) cli_no_branch=1; shift ;;
      --branch-name)
        [[ $# -ge 2 ]] || die "--branch-name requires a value"
        branch_name="$2"; shift 2 ;;
      --branch-from)
        [[ $# -ge 2 ]] || die "--branch-from requires a value"
        branch_from="$2"; shift 2 ;;
      --allow-dirty) allow_dirty=1; shift ;;
      --checkout-existing) checkout_existing=1; shift ;;
      -h|--help) ws_help; return 0 ;;
      *) die "unknown ws new option: $1" ;;
    esac
  done
  if [[ "$cli_branch" -eq 1 && "$cli_no_branch" -eq 1 ]]; then
    die "--branch and --no-branch cannot be used together"
  fi
  if [[ "$cli_no_branch" -eq 1 && -n "$branch_name" ]]; then
    die "--branch-name cannot be used with --no-branch"
  fi
  if [[ "$cli_no_branch" -eq 1 && -n "$branch_from" ]]; then
    die "--branch-from cannot be used with --no-branch"
  fi
  if [[ "$cli_no_branch" -eq 1 && "$checkout_existing" -eq 1 ]]; then
    die "--checkout-existing cannot be used with --no-branch"
  fi
  slug="$(slugify "$raw")" || die "invalid workstream slug: $raw"
  root="$(require_initialized)"
  template="$root/.agently/templates/workstream"
  [[ -d "$template" ]] || die "missing workstream template: $template"
  dest="$root/.agently/workstreams/$slug"
  [[ ! -e "$dest" ]] || die "workstream already exists: $slug"
  branch_metadata="$(workstream_branch_prepare "$root" "$slug" "$cli_branch" "$cli_no_branch" "$branch_name" "$branch_from" "$allow_dirty" "$checkout_existing")"
  title="$(titleize "$slug")"
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
      "SLUG=$slug" \
      "TITLE=$title" \
      "WORKSTREAM_SLUG=$slug" \
      "WORKSTREAM_TITLE=$title" \
        "DATE=$date" \
        "DATETIME=$datetime" \
        "BRANCH_METADATA=$branch_metadata" \
        "PROJECT=$(basename "$root")")"
    write_text_file "$dst" 0644 "$content" 0 0 ".agently/workstreams/$slug/$rel"
  done < <(find "$template" -type f | sort)
  mkdir -p "$dest/tasks"
  note "created workstream: $slug"
}

ws_use() {
  die "agently ws use is removed; pass --workstream <ws> to the target command"
}

ws_current() {
  die "agently ws current is removed; pass --workstream <ws> to the target command"
}

ws_show() {
  if [[ $# -ge 1 ]] && spine_alias_regex "$1"; then
    ws_show_spine "$@"
    return 0
  fi
  local ws=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workstream)
        option_has_value "$@" || die "--workstream requires a value"
        ws="$2"; shift 2 ;;
      -h|--help) ws_help; return 0 ;;
      *) die "unknown ws show option: $1" ;;
    esac
  done
  ws="$(require_workstream_handle "$ws")"
  cat "$(ws_dir_for "$ws")/workstream.md"
}

ws_path() {
  local ws=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workstream)
        option_has_value "$@" || die "--workstream requires a value"
        ws="$2"; shift 2 ;;
      -h|--help) ws_help; return 0 ;;
      *) die "unknown ws path option: $1" ;;
    esac
  done
  ws="$(require_workstream_handle "$ws")"
  realpath "$(ws_dir_for "$ws")"
}
