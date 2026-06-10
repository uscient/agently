#!/usr/bin/env bash

cmd_self_help() {
  cat <<'EOF'
Agently self lifecycle commands

Usage:
  agently self status [--json]
  agently self install --user --from <repo> --dry-run [--json]
  agently self install --user --from <repo> --apply [--json]
  agently self uninstall --user --dry-run [--json]
  agently self uninstall --user --confirm [--json]

This lane installs and removes only the user-local Agently tool install.
It never mutates project .agently state.
Serena never administers Agently. Future MCP schemas must omit mutating
lifecycle commands. TTY friction is not a security boundary against same-user
shell bypass.
EOF
}

cmd_self() {
  self_json_scan "$@"
  local sub="${1:-help}"
  if [[ $# -gt 0 ]]; then
    shift
  fi
  case "$sub" in
    status) cmd_self_status "$@" ;;
    install) cmd_self_install "$@" ;;
    uninstall) cmd_self_uninstall "$@" ;;
    help|-h|--help|"") cmd_self_help ;;
    *) self_fail INVALID_ARGUMENT "unknown self command: $sub" true "Run agently self <status|install|uninstall>." ;;
  esac
}

cmd_self_status() {
  self_json_scan "$@"
  local arg
  for arg in "$@"; do
    case "$arg" in
      --json) ;;
      -h|--help)
        if self_json_active; then
          self_fail INVALID_ARGUMENT "help is not available in JSON mode for self status" true "Run agently self status --json."
        fi
        printf 'Usage: agently self status [--json]\n'
        return 0
        ;;
      *) self_fail INVALID_ARGUMENT "unknown self status option: $arg" true "Run agently self status [--json]." ;;
    esac
  done

  local expected share current path_active active active_resolved active_class release current_state version managed_shim
  local candidate candidate_json warning_json ghost_json classification resolved path_count=0
  local -a candidates_json warnings_json ghosts_json warnings_human ghosts_human

  expected="$(self_bin_path)"
  share="$(self_share_dir)"
  current="$(self_current_link)"
  path_active="$(command -v agently 2>/dev/null || true)"
  active="$path_active"
  if [[ -z "$active" && -n "${AGENTLY_SHARE:-}" && -x "$AGENTLY_SHARE/bin/agently" ]]; then
    active="$AGENTLY_SHARE/bin/agently"
  fi
  active_resolved=""
  active_class="not-installed"
  if [[ -n "$active" ]]; then
    active_resolved="$(self_resolve_path "$active")"
    active_class="$(self_classify_path "$active" "$active_resolved")"
  fi
  release="$(self_release_from_current 2>/dev/null || true)"
  current_state="$(self_current_link_state)"
  version="$(self_version_from_release "$release" 2>/dev/null || true)"
  managed_shim=false
  self_shim_is_managed "$expected" && managed_shim=true

  self_collect_path_candidates
  for candidate in "${SELF_UNIQUE_VALUES[@]:-}"; do
    [[ -n "$candidate" ]] || continue
    candidate_json="$(self_candidate_json "$candidate")"
    candidates_json+=("$candidate_json")
    path_count=$((path_count + 1))
    resolved="$(self_resolve_path "$candidate")"
    classification="$(self_classify_path "$candidate" "$resolved")"
    case "$classification" in
      global-stale)
        ghost_json="$(self_warning_json "GLOBAL_STALE" "PATH contains a global Agently candidate." "$candidate")"
        ghosts_json+=("$ghost_json")
        ghosts_human+=("$candidate: unmanaged global install on PATH")
        ;;
      home-bin)
        ghost_json="$(self_warning_json "HOME_BIN" "PATH contains a non-XDG user Agently candidate." "$candidate")"
        ghosts_json+=("$ghost_json")
        ghosts_human+=("$candidate: non-XDG user Agently candidate on PATH")
        ;;
      unknown)
        ghost_json="$(self_warning_json "UNKNOWN_CANDIDATE" "PATH contains an unclassified Agently candidate." "$candidate")"
        ghosts_json+=("$ghost_json")
        ghosts_human+=("$candidate: unclassified Agently candidate on PATH")
        ;;
    esac
  done

  if [[ -z "$path_active" ]]; then
    warning_json="$(self_warning_json "NOT_ON_PATH" "No agently command was found on PATH." "")"
    warnings_json+=("$warning_json")
    warnings_human+=("agently: no command found on PATH")
  elif [[ "$path_active" != "$expected" && "$managed_shim" == true ]]; then
    warning_json="$(self_warning_json "SHADOWED_ACTIVE_COMMAND" "The managed user shim is shadowed by another PATH candidate." "$path_active")"
    warnings_json+=("$warning_json")
    warnings_human+=("$path_active: managed user shim is shadowed by another PATH candidate")
  fi
  case "$current_state" in
    dangling)
      ghost_json="$(self_warning_json "DANGLING_CURRENT" "Agently current symlink does not resolve to a release." "$current")"
      ghosts_json+=("$ghost_json")
      ghosts_human+=("$current: broken current pointer")
      ;;
    not_symlink)
      ghost_json="$(self_warning_json "CURRENT_NOT_SYMLINK" "Agently current path exists but is not a symlink." "$current")"
      ghosts_json+=("$ghost_json")
      ghosts_human+=("$current: current path exists but is not a symlink")
      ;;
  esac

  if self_json_active; then
    {
      printf '{"ok":true,"command":"self_status","mutated":false'
      printf ',"active_command":'
      self_json_nullable_string "$active"
      printf ',"active_resolved":'
      self_json_nullable_string "$active_resolved"
      printf ',"active_classification":'
      json_string "$active_class"
      printf ',"install_state":'
      json_string "$active_class"
      printf ',"expected_shim_path":'
      json_string "$expected"
      printf ',"share_dir":'
      json_string "$share"
      printf ',"current_link":'
      json_string "$current"
      printf ',"current_link_state":'
      json_string "$current_state"
      printf ',"current_release":'
      self_json_nullable_string "$release"
      printf ',"version":'
      self_json_nullable_string "$version"
      printf ',"managed_shim_present":'
      json_bool "$managed_shim"
      printf ',"path_candidate_count":%s' "$path_count"
      printf ',"path_candidates":'
      self_json_raw_array "${candidates_json[@]:-}"
      printf ',"ghosts":'
      self_json_raw_array "${ghosts_json[@]:-}"
      printf ',"warnings":'
      self_json_raw_array "${warnings_json[@]:-}"
      printf '}\n'
    }
    return 0
  fi

  printf '# Agently Self Status\n\n'
  printf 'active_command: %s\n' "${active:-not-found}"
  printf 'active_classification: %s\n' "$active_class"
  printf 'expected_shim_path: %s\n' "$expected"
  printf 'share_dir: %s\n' "$share"
  printf 'current_link_state: %s\n' "$current_state"
  printf 'current_release: %s\n' "${release:-none}"
  printf 'version: %s\n' "${version:-unknown}"
  printf '\n## PATH Candidates\n'
  if [[ "$path_count" -eq 0 ]]; then
    printf '- none\n'
  else
    for candidate in "${SELF_UNIQUE_VALUES[@]:-}"; do
      [[ -n "$candidate" ]] || continue
      resolved="$(self_resolve_path "$candidate")"
      classification="$(self_classify_path "$candidate" "$resolved")"
      printf -- '- %s [%s]\n' "$candidate" "$classification"
    done
  fi
  printf '\nWarnings:\n'
  if [[ "${#ghosts_human[@]}" -eq 0 && "${#warnings_human[@]}" -eq 0 ]]; then
    printf '- none\n'
  else
    for candidate in "${ghosts_human[@]:-}" "${warnings_human[@]:-}"; do
      [[ -n "$candidate" ]] || continue
      printf -- '- %s\n' "$candidate"
    done
  fi
}

cmd_self_install() {
  self_json_scan "$@"
  local user=0 dry_run=0 apply=0 from="" arg repo release_id release_dir installed_at version commit dirty
  local current_action shim_action unmanaged_shim=false release_exists=false file_count
  local -a includes excludes

  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      --json) shift ;;
      --user) user=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      --apply) apply=1; shift ;;
      --from)
        [[ $# -ge 2 ]] || self_fail INVALID_ARGUMENT "--from requires a repository path" true "Run agently self install --user --from <repo> --dry-run."
        from="$2"
        shift 2
        ;;
      -h|--help)
        if self_json_active; then
          self_fail INVALID_ARGUMENT "help is not available in JSON mode for self install" true "Run agently self install --user --from <repo> <--dry-run|--apply> --json."
        fi
        printf 'Usage: agently self install --user --from <repo> <--dry-run|--apply> [--json]\n'
        return 0
        ;;
      *) self_fail INVALID_ARGUMENT "unknown self install option: $arg" true "Run agently self install --user --from <repo> <--dry-run|--apply>." ;;
    esac
  done

  [[ "$user" -eq 1 ]] || self_fail INVALID_ARGUMENT "self install requires --user" true "Run agently self install --user --from <repo> <--dry-run|--apply>."
  [[ $((dry_run + apply)) -eq 1 ]] || self_fail INVALID_ARGUMENT "self install requires exactly one of --dry-run or --apply" true "Run agently self install --user --from <repo> --dry-run or --apply."

  self_preflight
  repo="$(self_source_repo_from_args_or_git "$from")"
  release_id="$(self_release_id_for_repo "$repo")"
  release_dir="$(self_releases_dir)/$release_id"
  installed_at="$(now)"
  version="$(self_version_from_repo "$repo")"
  commit="$(self_git_commit_for_repo "$repo")"
  dirty="$(self_git_dirty_for_repo "$repo")"
  [[ -d "$release_dir" ]] && release_exists=true
  file_count="$(self_planned_file_count "$repo")"

  mapfile -t includes < <(self_include_rules)
  mapfile -t excludes < <(self_exclude_rules)

  if [[ -e "$(self_current_link)" ]]; then
    if [[ -L "$(self_current_link)" ]]; then
      current_action="replace_current_symlink"
    else
      current_action="would_refuse_non_symlink_current"
    fi
  else
    current_action="create_current_symlink"
  fi

  shim_action="$(self_shim_action_for_path "$(self_bin_path)")"
  if [[ "$shim_action" == "refuse_unmanaged_shim" ]]; then
    shim_action="would_refuse_unmanaged_shim"
    unmanaged_shim=true
  fi

  if [[ "$apply" -eq 1 ]]; then
    with_self_lock cmd_self_install_apply_locked "$repo" "$release_id" "$release_dir" "$installed_at" "$version" "$commit" "$dirty"
    return 0
  fi

  if self_json_active; then
    {
      printf '{"ok":true,"command":"self_install_dry_run","mutated":false'
      printf ',"release_id":'
      json_string "$release_id"
      printf ',"release_dir":'
      json_string "$release_dir"
      printf ',"release_dir_exists":'
      json_bool "$release_exists"
      printf ',"source_repo":'
      json_string "$repo"
      printf ',"source_git_commit":'
      self_json_nullable_string "$commit"
      printf ',"source_git_dirty":'
      json_bool "$dirty"
      printf ',"agently_version":'
      json_string "$version"
      printf ',"installed_at":'
      json_string "$installed_at"
      printf ',"install_mode":"user"'
      printf ',"share_dir":'
      json_string "$(self_share_dir)"
      printf ',"release_layout":{"current":'
      json_string "$(self_current_link)"
      printf ',"releases_dir":'
      json_string "$(self_releases_dir)"
      printf ',"release_dir":'
      json_string "$release_dir"
      printf ',"entries":'
      self_json_string_array "bin/" "lib/" "templates/" "docs/" "VERSION" "INSTALL-MANIFEST.json"
      printf '}'
      printf ',"current_link":'
      json_string "$(self_current_link)"
      printf ',"current_symlink_action":'
      json_string "$current_action"
      printf ',"shim_path":'
      json_string "$(self_bin_path)"
      printf ',"shim_action":'
      json_string "$shim_action"
      printf ',"would_refuse_unmanaged_shim":'
      json_bool "$unmanaged_shim"
      printf ',"includes":'
      self_json_string_array "${includes[@]}"
      printf ',"excludes":'
      self_json_string_array "${excludes[@]}"
      printf ',"planned_file_count":%s' "$file_count"
      printf ',"manifest_preview":{"schema_version":1,"release_id":'
      json_string "$release_id"
      printf ',"agently_version":'
      json_string "$version"
      printf ',"source_repo":'
      json_string "$repo"
      printf ',"source_git_commit":'
      self_json_nullable_string "$commit"
      printf ',"source_git_dirty":'
      json_bool "$dirty"
      printf ',"installed_at":'
      json_string "$installed_at"
      printf ',"install_mode":"user","installer":"agently self install","files":[]}'
      printf '}\n'
    }
    return 0
  fi

  printf '# Agently Self Install Dry Run\n\n'
  printf 'No changes made.\n\n'
  printf 'release_id: %s\n' "$release_id"
  printf 'source_repo: %s\n' "$repo"
  printf 'source_git_commit: %s\n' "${commit:-none}"
  printf 'source_git_dirty: %s\n' "$dirty"
  printf 'release_dir: %s\n' "$release_dir"
  printf 'current_symlink_action: %s\n' "$current_action"
  printf 'shim_action: %s\n' "$shim_action"
  printf 'planned_file_count: %s\n' "$file_count"
  printf '\n## Include\n'
  printf -- '- %s\n' "${includes[@]}"
  printf '\n## Exclude\n'
  printf -- '- %s\n' "${excludes[@]}"
}

cmd_self_install_apply_locked() {
  local repo="$1" release_id="$2" release_dir="$3" installed_at="$4" version="$5" commit="$6" dirty="$7"
  local share releases current shim_path stage
  share="$(self_share_dir)"
  releases="$(self_releases_dir)"
  current="$(self_current_link)"
  shim_path="$(self_bin_path)"

  if [[ -d "$release_dir" ]]; then
    self_fail ALREADY_EXISTS "release already exists: $release_dir" true "Rerun after a second or remove the stale release explicitly."
  fi
  self_current_path_allows_atomic_swap || self_fail STAGED_RELEASE_INVALID "current path exists but is not a symlink: $current" false "Inspect the Agently share directory."
  if [[ -e "$shim_path" ]] && ! self_shim_is_managed "$shim_path"; then
    self_fail REFUSE_UNMANAGED_SHIM "refusing to overwrite unmanaged Agently shim: $shim_path" true "Remove or rename the existing file, then rerun self install."
  fi

  mkdir -p "$releases" || self_fail STAGED_RELEASE_INVALID "failed to create releases directory: $releases" false "Check XDG_DATA_HOME permissions."
  stage="$(mktemp -d "$releases/.stage.XXXXXX")" || self_fail STAGED_RELEASE_INVALID "failed to create staged release directory" false "Check XDG_DATA_HOME permissions."
  trap 'rm -rf "$stage"' EXIT INT TERM
  self_stage_release "$repo" "$stage" "$release_id" "$version" "$commit" "$dirty" "$installed_at"
  self_validate_staged_release "$stage"
  [[ ! -d "$release_dir" ]] || self_fail ALREADY_EXISTS "release already exists: $release_dir" true "Rerun after a second or remove the stale release explicitly."
  mv "$stage" "$release_dir" || self_fail STAGED_RELEASE_INVALID "failed to move staged release into place" false "Check filesystem permissions."
  trap - EXIT INT TERM
  self_activate_release "$release_id"
  self_install_shim
  self_log "install success release_id=$release_id source=$repo dirty=$dirty"

  if self_json_active; then
    {
      printf '{"ok":true,"command":"self_install","dry_run":false,"mutated":true'
      printf ',"release_id":'
      json_string "$release_id"
      printf ',"release_dir":'
      json_string "$release_dir"
      printf ',"current":'
      json_string "$current"
      printf ',"shim":'
      json_string "$shim_path"
      printf ',"source_repo":'
      json_string "$repo"
      printf ',"source_git_commit":'
      self_json_nullable_string "$commit"
      printf ',"source_git_dirty":'
      json_bool "$dirty"
      printf ',"agently_version":'
      json_string "$version"
      printf '}\n'
    }
    return 0
  fi

  printf '# Agently Self Install\n\n'
  printf 'Installed release: %s\n' "$release_id"
  printf 'Release dir: %s\n' "$release_dir"
  printf 'Current: %s -> releases/%s\n' "$current" "$release_id"
  printf 'Shim: %s\n' "$shim_path"
}

cmd_self_uninstall() {
  self_json_scan "$@"
  local user=0 dry_run=0 confirm=0 arg installed=false shim_managed=false share_exists=false shim_action
  local shim_path share_dir config_dir state_dir
  local -a remove_json keep_json warnings_json

  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      --json) shift ;;
      --user) user=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      --confirm) confirm=1; shift ;;
      --apply) self_fail INVALID_ARGUMENT "self uninstall does not support --apply" true "Run agently self uninstall --user <--dry-run|--confirm>." ;;
      -h|--help)
        if self_json_active; then
          self_fail INVALID_ARGUMENT "help is not available in JSON mode for self uninstall" true "Run agently self uninstall --user <--dry-run|--confirm> --json."
        fi
        printf 'Usage: agently self uninstall --user <--dry-run|--confirm> [--json]\n'
        return 0
        ;;
      *) self_fail INVALID_ARGUMENT "unknown self uninstall option: $arg" true "Run agently self uninstall --user <--dry-run|--confirm>." ;;
    esac
  done

  [[ "$user" -eq 1 ]] || self_fail INVALID_ARGUMENT "self uninstall requires --user" true "Run agently self uninstall --user <--dry-run|--confirm>."
  [[ $((dry_run + confirm)) -eq 1 ]] || self_fail INVALID_ARGUMENT "self uninstall requires exactly one of --dry-run or --confirm" true "Run agently self uninstall --user --dry-run or --confirm."

  self_preflight

  shim_path="$(self_bin_path)"
  share_dir="$(self_share_dir)"
  config_dir="$(self_config_dir)"
  state_dir="$(self_state_dir)"

  if [[ "$confirm" -eq 1 ]]; then
    with_self_lock cmd_self_uninstall_confirm_locked "$shim_path" "$share_dir" "$config_dir" "$state_dir"
    return 0
  fi

  if self_shim_is_managed "$shim_path"; then
    shim_managed=true
    installed=true
    shim_action="would_remove_managed_shim"
    remove_json+=("{\"path\":$(json_string "$shim_path"),\"reason\":\"managed_shim\"}")
  elif [[ -e "$shim_path" ]]; then
    shim_action="keep_unmanaged_shim"
    warnings_json+=("$(self_warning_json "UNMANAGED_SHIM" "User bin agently exists but is not an Agently managed shim." "$shim_path")")
  else
    shim_action="not_present"
  fi

  if [[ -e "$share_dir" ]]; then
    share_exists=true
    installed=true
    remove_json+=("{\"path\":$(json_string "$share_dir"),\"reason\":\"agently_share\"}")
  fi

  keep_json+=("{\"path\":$(json_string "$config_dir"),\"reason\":\"config_preserved\"}")
  keep_json+=("{\"path\":$(json_string "$state_dir"),\"reason\":\"state_preserved\"}")
  keep_json+=("{\"path\":null,\"reason\":\"project .agently state is not searched or removed\"}")

  if [[ "$installed" == false ]]; then
    warnings_json+=("$(self_warning_json "NOT_INSTALLED" "No managed user install was found." "")")
  fi

  if self_json_active; then
    {
      printf '{"ok":true,"command":"self_uninstall_dry_run","mutated":false'
      printf ',"installed":'
      json_bool "$installed"
      printf ',"status":'
      if [[ "$installed" == true ]]; then json_string "PLANNED"; else json_string "NOT_INSTALLED"; fi
      printf ',"shim_path":'
      json_string "$shim_path"
      printf ',"shim_managed":'
      json_bool "$shim_managed"
      printf ',"shim_action":'
      json_string "$shim_action"
      printf ',"share_dir":'
      json_string "$share_dir"
      printf ',"share_exists":'
      json_bool "$share_exists"
      printf ',"remove":'
      self_json_raw_array "${remove_json[@]:-}"
      printf ',"keep":'
      self_json_raw_array "${keep_json[@]:-}"
      printf ',"warnings":'
      self_json_raw_array "${warnings_json[@]:-}"
      printf '}\n'
    }
    return 0
  fi

  printf '# Agently Self Uninstall Dry Run\n\n'
  printf 'No changes made.\n\n'
  printf 'shim_action: %s\n' "$shim_action"
  printf 'share_dir: %s\n' "$share_dir"
  printf '\n## Would Remove\n'
  if [[ "${#remove_json[@]}" -eq 0 ]]; then
    printf '- none\n'
  else
    if [[ "$shim_managed" == true ]]; then
      printf -- '- %s\n' "$shim_path"
    fi
    if [[ "$share_exists" == true ]]; then
      printf -- '- %s\n' "$share_dir"
    fi
  fi
  printf '\n## Would Keep\n'
  printf -- '- %s\n' "$config_dir"
  printf -- '- %s\n' "$state_dir"
  printf -- '- project .agently state (not searched)\n'
}

cmd_self_uninstall_confirm_locked() {
  local shim_path="$1" share_dir="$2" config_dir="$3" state_dir="$4"
  local phrase shim_managed=false share_exists=false mutated=false
  local -a removed kept warnings_json
  phrase="$(realpath -m "$share_dir")"

  self_confirm_uninstall_gate "$phrase"

  if self_shim_is_managed "$shim_path"; then
    shim_managed=true
  fi
  [[ -e "$share_dir" ]] && share_exists=true

  if [[ "$shim_managed" == true ]]; then
    rm -f "$shim_path" || self_fail REFUSE_UNMANAGED_SHIM "failed to remove managed shim: $shim_path" false "Check HOME permissions."
    removed+=("$shim_path")
    mutated=true
  elif [[ -e "$shim_path" ]]; then
    warnings_json+=("$(self_warning_json "UNMANAGED_SHIM" "User bin agently exists but is not an Agently managed shim." "$shim_path")")
  fi

  if [[ "$share_exists" == true ]]; then
    [[ "$(realpath -m "$share_dir")" == "$phrase" ]] || self_fail INVALID_ARGUMENT "share path changed during uninstall" false "Rerun self status and inspect XDG paths."
    rm -rf "$share_dir" || self_fail INVALID_ARGUMENT "failed to remove Agently share directory: $share_dir" false "Check XDG_DATA_HOME permissions."
    removed+=("$share_dir")
    mutated=true
  fi

  kept+=("$config_dir" "$state_dir" "project .agently state")
  self_log "uninstall success removed=${#removed[@]} kept_config_state=true"

  if self_json_active; then
    {
      printf '{"ok":true,"command":"self_uninstall","dry_run":false,"mutated":'
      json_bool "$mutated"
      printf ',"removed":'
      self_uninstall_removed_json "${removed[@]:-}"
      printf ',"kept":'
      self_uninstall_removed_json "${kept[@]}"
      printf ',"warnings":'
      self_json_raw_array "${warnings_json[@]:-}"
      printf '}\n'
    }
    return 0
  fi

  printf '# Agently Self Uninstall\n\n'
  printf 'Removed:\n'
  if [[ "${#removed[@]}" -eq 0 ]]; then
    printf '- none\n'
  else
    printf -- '- %s\n' "${removed[@]}"
  fi
  printf '\nKept:\n'
  printf -- '- %s\n' "${kept[@]}"
}
