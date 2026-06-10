#!/usr/bin/env bash

self_json_active() {
  [[ "${AGENTLY_SELF_JSON:-0}" -eq 1 ]]
}

self_json_scan() {
  local arg
  for arg in "$@"; do
    if [[ "$arg" == "--json" ]]; then
      AGENTLY_SELF_JSON=1
      export AGENTLY_SELF_JSON
      return 0
    fi
  done
  return 0
}

self_json_value() {
  case "${1:-}" in
    true|false|null) printf '%s' "$1" ;;
    *) json_string "${1:-}" ;;
  esac
}

self_json_nullable_string() {
  if [[ -n "${1:-}" ]]; then
    json_string "$1"
  else
    printf 'null'
  fi
}

self_json_string_array() {
  local first=1 item
  printf '['
  for item in "$@"; do
    [[ "$first" -eq 0 ]] && printf ','
    json_string "$item"
    first=0
  done
  printf ']'
}

self_json_raw_array() {
  local first=1 item
  printf '['
  for item in "$@"; do
    [[ -n "$item" ]] || continue
    [[ "$first" -eq 0 ]] && printf ','
    printf '%s' "$item"
    first=0
  done
  printf ']'
}

self_required_actions_json() {
  self_json_string_array "$@"
}

self_emit() {
  local first=1 key value
  printf '{'
  while [[ $# -gt 0 ]]; do
    key="$1"
    value="${2:-}"
    shift 2
    [[ "$first" -eq 0 ]] && printf ','
    json_string "$key"
    printf ':'
    self_json_value "$value"
    first=0
  done
  printf '}\n'
}

self_emit_json() {
  printf '%s\n' "$1"
}

self_exit_code_for() {
  case "$1" in
    INVALID_ARGUMENT) printf '2\n' ;;
    DEPENDENCY_MISSING|SOURCE_NOT_FOUND|SOURCE_INVALID|ALREADY_EXISTS|UNMANAGED_SHIM) printf '1\n' ;;
    REFUSE_UNMANAGED_SHIM|UNINSTALL_REQUIRES_INTERACTIVE_PATH|UNINSTALL_CONFIRMATION_TIMEOUT|UNINSTALL_NOT_CONFIRMED) printf '2\n' ;;
    STAGED_RELEASE_INVALID|MANIFEST_INVALID) printf '3\n' ;;
    LOCK_FAILED) printf '75\n' ;;
    NOT_INSTALLED) printf '0\n' ;;
    *) printf '1\n' ;;
  esac
}

self_fail() {
  local code="$1" message="$2" recoverable="${3:-true}" exit_code
  shift 3 || true
  exit_code="$(self_exit_code_for "$code")"
  if self_json_active; then
    {
      printf '{"ok":false,"error":{"code":'
      json_string "$code"
      printf ',"message":'
      json_string "$message"
      printf ',"recoverable":'
      json_bool "$recoverable"
      printf ',"required_next_actions":'
      self_required_actions_json "$@"
      printf '}}\n'
    } >&2
  else
    printf 'FAIL: %s\n' "$message" >&2
  fi
  exit "$exit_code"
}

xdg_data_home() {
  printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}"
}

xdg_config_home() {
  printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

xdg_state_home() {
  printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}"
}

self_share_dir() {
  printf '%s/agently\n' "$(xdg_data_home)"
}

self_releases_dir() {
  printf '%s/releases\n' "$(self_share_dir)"
}

self_current_link() {
  printf '%s/current\n' "$(self_share_dir)"
}

self_bin_dir() {
  printf '%s/.local/bin\n' "$HOME"
}

self_bin_path() {
  printf '%s/agently\n' "$(self_bin_dir)"
}

self_config_dir() {
  printf '%s/agently\n' "$(xdg_config_home)"
}

self_state_dir() {
  printf '%s/agently\n' "$(xdg_state_home)"
}

self_log_file() {
  printf '%s/install.log\n' "$(self_state_dir)"
}

self_lock_path() {
  printf '%s/self.lock\n' "$(self_state_dir)"
}

self_dependency_missing() {
  local tool="$1" message action
  message="$tool is required for Agently self lifecycle commands."
  action="Install $tool and rerun the command."
  case "$tool" in
    jq) action="Install jq and rerun the command." ;;
    sha256sum) action="Install coreutils sha256sum and rerun the command." ;;
    flock) action="Install util-linux flock and rerun the command." ;;
    mv) action="Install a coreutils mv with -T support and rerun the command." ;;
  esac
  self_fail DEPENDENCY_MISSING "$message" true "$action"
}

self_mv_supports_T() {
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/agently-mv.XXXXXX" 2>/dev/null || true)"
  [[ -n "$dir" ]] || return 1
  printf 'a\n' > "$dir/a"
  printf 'b\n' > "$dir/b"
  if mv -T "$dir/a" "$dir/b" >/dev/null 2>&1; then
    if has_cmd rm; then rm -rf "$dir" 2>/dev/null || true; fi
    return 0
  fi
  if has_cmd rm; then rm -rf "$dir" 2>/dev/null || true; fi
  return 1
}

self_preflight() {
  local tool
  for tool in git sha256sum flock realpath mktemp ln mv jq; do
    has_cmd "$tool" || self_dependency_missing "$tool"
  done
  self_mv_supports_T || self_dependency_missing "mv"
}

self_render_shim() {
  cat <<'EOF'
#!/usr/bin/env bash
# AGENTLY-MANAGED-SHIM v1
# Managed by `agently self`; do not edit by hand.
TARGET="${XDG_DATA_HOME:-$HOME/.local/share}/agently/current/bin/agently"
if [ ! -x "$TARGET" ]; then
  echo "ERROR: Agently current release not found at $TARGET." >&2
  echo "Run 'agently self status' or reinstall with 'agently self install --user --from <repo>'." >&2
  exit 1
fi
exec "$TARGET" "$@"
EOF
}

self_shim_is_managed() {
  local path="$1"
  [ -f "$path" ] || return 1
  grep -q -F -- 'AGENTLY-MANAGED-SHIM v1' "$path" 2>/dev/null
}

with_self_lock() {
  local timeout="${AGENTLY_SELF_LOCK_TIMEOUT_SECONDS:-10}" lock
  mkdir -p "$(self_state_dir)" || self_fail LOCK_FAILED "failed to create Agently state directory for lifecycle lock" false "Check XDG_STATE_HOME permissions."
  lock="$(self_lock_path)"
  exec 201>"$lock" || self_fail LOCK_FAILED "failed to open Agently lifecycle lock" false "Check XDG_STATE_HOME permissions."
  flock -w "$timeout" -x 201 || self_fail LOCK_FAILED "another Agently self lifecycle command is running" true "Wait for the other command to finish and retry."
  "$@"
}

self_log() {
  local message="$1" dir file
  dir="$(self_state_dir)"
  file="$(self_log_file)"
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s %s\n' "$(now)" "$message" >> "$file" 2>/dev/null || return 0
}

self_resolve_path() {
  local path="$1" resolved=""
  if has_cmd readlink; then
    resolved="$(readlink -f "$path" 2>/dev/null || true)"
  fi
  if [[ -z "$resolved" ]] && has_cmd realpath; then
    resolved="$(realpath -m "$path" 2>/dev/null || true)"
  fi
  printf '%s\n' "${resolved:-$path}"
}

self_path_under() {
  local path="$1" root="$2"
  [[ "$path" == "$root" || "$path" == "$root"/* ]]
}

self_git_checkout_root_for_path() {
  local path="$1" dir
  [[ -n "$path" ]] || return 1
  if [[ -d "$path" ]]; then
    dir="$path"
  else
    dir="$(dirname "$path")"
  fi
  while [[ "$dir" != "/" && -n "$dir" ]]; do
    if [[ -e "$dir/.git" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

self_release_from_current() {
  local current resolved
  current="$(self_current_link)"
  [[ -L "$current" ]] || return 1
  resolved="$(self_resolve_path "$current")"
  [[ -d "$resolved" ]] || return 1
  basename "$resolved"
}

self_current_link_state() {
  local current resolved
  current="$(self_current_link)"
  if [[ -L "$current" ]]; then
    resolved="$(self_resolve_path "$current")"
    if [[ -d "$resolved" ]]; then
      printf 'valid\n'
    else
      printf 'dangling\n'
    fi
  elif [[ -e "$current" ]]; then
    printf 'not_symlink\n'
  else
    printf 'missing\n'
  fi
}

self_candidate_is_managed_release() {
  local resolved="$1" share release_dir current_res
  share="$(self_share_dir)"
  case "$resolved" in
    "$share/releases/"*/bin/agently)
      release_dir="${resolved%/bin/agently}"
      current_res="$(self_resolve_path "$(self_current_link)")"
      [[ "$current_res" == "$release_dir" ]]
      ;;
    *) return 1 ;;
  esac
}

self_path_is_dev_repo() {
  local resolved="$1" root share
  root="$(self_git_checkout_root_for_path "$resolved" 2>/dev/null || true)"
  [[ -n "$root" ]] || return 1
  [[ -f "$root/lib/agently.sh" && -f "$root/bin/agently" ]] || return 1
  share="$(self_share_dir)"
  case "$root" in
    "$share"|"$share"/*) return 1 ;;
  esac
  return 0
}

self_path_is_global_stale() {
  local path="$1" resolved="$2"
  case "$resolved" in
    /usr/local/bin/*|/usr/bin/*|/bin/*|/opt/*) return 0 ;;
    */usr/local/bin/*|*/usr/bin/*) return 0 ;;
  esac
  case "$path" in
    /usr/local/bin/*|/usr/bin/*|/bin/*|/opt/*) return 0 ;;
    */usr/local/bin/*|*/usr/bin/*) return 0 ;;
  esac
  return 1
}

self_path_is_home_bin() {
  local resolved="$1" expected
  expected="$(self_bin_path)"
  [[ "$resolved" != "$expected" ]] || return 1
  case "$resolved" in
    "$HOME/bin/"*|"$HOME/.local/bin/"*) return 0 ;;
  esac
  return 1
}

self_classify_path() {
  local path="$1" resolved="$2" expected
  expected="$(self_bin_path)"
  if [[ "$path" == "$expected" && -f "$path" ]] && self_shim_is_managed "$path"; then
    printf 'managed-shim\n'
  elif self_candidate_is_managed_release "$resolved"; then
    printf 'managed-release\n'
  elif self_path_is_dev_repo "$resolved"; then
    printf 'dev-repo\n'
  elif self_path_is_global_stale "$path" "$resolved"; then
    printf 'global-stale\n'
  elif self_path_is_home_bin "$resolved"; then
    printf 'home-bin\n'
  else
    printf 'unknown\n'
  fi
}

self_add_unique() {
  local value="$1" existing
  [[ -n "$value" ]] || return 0
  for existing in "${SELF_UNIQUE_VALUES[@]:-}"; do
    [[ "$existing" == "$value" ]] && return 0
  done
  SELF_UNIQUE_VALUES+=("$value")
}

self_collect_path_candidates() {
  local line path
  SELF_UNIQUE_VALUES=()
  path="$(command -v agently 2>/dev/null || true)"
  self_add_unique "$path"
  while IFS= read -r line; do
    case "$line" in
      *" is hashed ("*")")
        path="${line#* is hashed (}"
        path="${path%)}"
        self_add_unique "$path"
        ;;
      *" is "/*)
        path="${line##* is }"
        self_add_unique "$path"
        ;;
    esac
  done < <(type -a agently 2>/dev/null || true)
  if has_cmd which; then
    while IFS= read -r path; do
      self_add_unique "$path"
    done < <(which -a agently 2>/dev/null || true)
  fi
}

self_candidate_json() {
  local path="$1" resolved classification managed exists
  resolved="$(self_resolve_path "$path")"
  classification="$(self_classify_path "$path" "$resolved")"
  managed=false
  self_shim_is_managed "$path" && managed=true
  exists=false
  [[ -e "$path" ]] && exists=true
  printf '{"path":'
  json_string "$path"
  printf ',"resolved":'
  json_string "$resolved"
  printf ',"classification":'
  json_string "$classification"
  printf ',"exists":'
  json_bool "$exists"
  printf ',"managed_shim":'
  json_bool "$managed"
  printf '}'
}

self_warning_json() {
  local code="$1" message="$2" path="${3:-}"
  printf '{"code":'
  json_string "$code"
  printf ',"message":'
  json_string "$message"
  printf ',"path":'
  self_json_nullable_string "$path"
  printf '}'
}

self_version_from_release() {
  local release="${1:-}" share
  share="$(self_share_dir)"
  if [[ -n "$release" && -f "$share/releases/$release/VERSION" ]]; then
    sed -n '1p' "$share/releases/$release/VERSION"
  else
    return 0
  fi
}

self_source_repo_from_args_or_git() {
  local from="${1:-}" root
  if [[ -n "$from" ]]; then
    [[ -d "$from" ]] || self_fail SOURCE_NOT_FOUND "source repo not found: $from" true "Pass --from with an Agently checkout path."
    root="$(realpath "$from")"
  else
    root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    [[ -n "$root" ]] || self_fail SOURCE_NOT_FOUND "source repo not found; pass --from <repo>" true "Pass --from with an Agently checkout path."
    root="$(realpath "$root")"
  fi
  if git -C "$root" rev-parse --show-toplevel >/dev/null 2>&1; then
    root="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)"
    root="$(realpath "$root")"
  fi
  [[ -f "$root/bin/agently" && -f "$root/lib/agently.sh" && -d "$root/templates" && -f "$root/VERSION" ]] || \
    self_fail SOURCE_INVALID "source path is not an Agently repository: $root" true "Pass --from with an Agently checkout path."
  printf '%s\n' "$root"
}

self_git_commit_for_repo() {
  local repo="$1"
  GIT_OPTIONAL_LOCKS=0 git -C "$repo" rev-parse --verify HEAD 2>/dev/null || true
}

self_git_dirty_for_repo() {
  local repo="$1" status
  if ! GIT_OPTIONAL_LOCKS=0 git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'false\n'
    return 0
  fi
  status="$(GIT_OPTIONAL_LOCKS=0 git -C "$repo" status --porcelain=1 --untracked-files=normal 2>/dev/null || true)"
  if [[ -n "$status" ]]; then
    printf 'true\n'
  else
    printf 'false\n'
  fi
}

self_release_id_for_repo() {
  local repo="$1" ts commit suffix
  ts="$(date -u '+%Y%m%d-%H%M%S')"
  commit="$(self_git_commit_for_repo "$repo")"
  if [[ -n "$commit" ]]; then
    suffix="${commit:0:12}"
  else
    suffix="nogit"
  fi
  printf '%s-%s\n' "$ts" "$suffix"
}

self_version_from_repo() {
  local repo="$1"
  sed -n '1p' "$repo/VERSION"
}

self_include_rules() {
  printf '%s\n' "bin/" "lib/" "templates/" "docs/" "VERSION"
}

self_exclude_rules() {
  printf '%s\n' "tests/" ".git/" "docs/tmp/"
}

self_planned_file_count() {
  local repo="$1" count=0 path rel
  while IFS= read -r path; do
    [[ -e "$path" ]] || continue
    if [[ -d "$path" ]]; then
      while IFS= read -r rel; do
        rel="${rel#"$repo/"}"
        case "$rel" in
          docs/tmp/*) continue ;;
        esac
        count=$((count + 1))
      done < <(find "$path" -type f 2>/dev/null)
    elif [[ -f "$path" ]]; then
      count=$((count + 1))
    fi
  done < <(printf '%s\n' "$repo/bin" "$repo/lib" "$repo/templates" "$repo/docs" "$repo/VERSION")
  printf '%s\n' "$count"
}

self_manifest_files_json() {
  local stage="$1" first=1 file rel bytes sha
  printf '['
  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    rel="$(realpath --relative-to="$stage" "$file" 2>/dev/null || true)"
    [[ -n "$rel" ]] || rel="${file#"$stage/"}"
    [[ "$rel" == "INSTALL-MANIFEST.json" ]] && continue
    bytes="$(wc -c < "$file" 2>/dev/null | awk '{ print $1 + 0 }')"
    sha="$(sha256sum "$file" | awk '{ print $1 }')"
    [[ "$first" -eq 0 ]] && printf ','
    printf '{"path":'
    json_string "$rel"
    printf ',"bytes":%s,"sha256":' "$bytes"
    json_string "$sha"
    printf '}'
    first=0
  done < <(find "$stage" -type f -print 2>/dev/null | LC_ALL=C sort)
  printf ']'
}

self_write_install_manifest() {
  local stage="$1" release_id="$2" version="$3" repo="$4" commit="$5" dirty="$6" installed_at="$7"
  local tmp
  tmp="$(mktemp "$stage/.INSTALL-MANIFEST.XXXXXX.tmp")" || self_fail STAGED_RELEASE_INVALID "failed to create install manifest temp file" false "Check filesystem permissions."
  {
    printf '{"schema_version":1'
    printf ',"release_id":'
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
    printf ',"install_mode":"user"'
    printf ',"installer":"agently self install"'
    printf ',"files":'
    self_manifest_files_json "$stage"
    printf '}\n'
  } > "$tmp"
  jq -e . "$tmp" >/dev/null || self_fail MANIFEST_INVALID "generated install manifest is invalid JSON" false "Inspect staged release generation."
  mv "$tmp" "$stage/INSTALL-MANIFEST.json" || self_fail STAGED_RELEASE_INVALID "failed to write install manifest" false "Check filesystem permissions."
}

self_stage_release() {
  local repo="$1" stage="$2" release_id="$3" version="$4" commit="$5" dirty="$6" installed_at="$7"
  local item src dst
  mkdir -p "$stage" || self_fail STAGED_RELEASE_INVALID "failed to create staged release directory" false "Check XDG_DATA_HOME permissions."
  for item in bin lib templates docs; do
    src="$repo/$item"
    [[ -d "$src" ]] || self_fail SOURCE_INVALID "source path missing required directory: $src" true "Pass --from with an Agently checkout path."
    cp -R "$src" "$stage/$item" || self_fail STAGED_RELEASE_INVALID "failed to copy source directory: $item" false "Check filesystem permissions."
  done
  src="$repo/VERSION"
  dst="$stage/VERSION"
  [[ -f "$src" ]] || self_fail SOURCE_INVALID "source path missing VERSION: $repo" true "Pass --from with an Agently checkout path."
  cp "$src" "$dst" || self_fail STAGED_RELEASE_INVALID "failed to copy VERSION" false "Check filesystem permissions."
  rm -rf "$stage/tests" "$stage/.git" "$stage/docs/tmp"
  chmod +x "$stage/bin/agently" 2>/dev/null || true
  self_write_install_manifest "$stage" "$release_id" "$version" "$repo" "$commit" "$dirty" "$installed_at"
}

self_validate_staged_release() {
  local stage="$1"
  [[ -x "$stage/bin/agently" ]] || self_fail STAGED_RELEASE_INVALID "staged release is missing executable bin/agently" false "Inspect staged release contents."
  [[ -f "$stage/lib/agently.sh" ]] || self_fail STAGED_RELEASE_INVALID "staged release is missing lib/agently.sh" false "Inspect staged release contents."
  [[ -d "$stage/templates" ]] || self_fail STAGED_RELEASE_INVALID "staged release is missing templates/" false "Inspect staged release contents."
  [[ -n "$(find "$stage/templates" -type f -print -quit 2>/dev/null)" ]] || self_fail STAGED_RELEASE_INVALID "staged release templates/ is empty" false "Inspect staged release contents."
  [[ -s "$stage/VERSION" ]] || self_fail STAGED_RELEASE_INVALID "staged release VERSION is empty" false "Inspect staged release contents."
  [[ -f "$stage/INSTALL-MANIFEST.json" ]] || self_fail STAGED_RELEASE_INVALID "staged release is missing INSTALL-MANIFEST.json" false "Inspect staged release contents."
  jq -e . "$stage/INSTALL-MANIFEST.json" >/dev/null || self_fail MANIFEST_INVALID "staged INSTALL-MANIFEST.json is invalid" false "Inspect staged release contents."
}

self_current_path_allows_atomic_swap() {
  local current
  current="$(self_current_link)"
  [[ ! -e "$current" || -L "$current" ]]
}

self_activate_release() {
  local release_id="$1" share current tmp_link
  share="$(self_share_dir)"
  current="$(self_current_link)"
  self_current_path_allows_atomic_swap || self_fail STAGED_RELEASE_INVALID "current path exists but is not a symlink: $current" false "Inspect the Agently share directory."
  tmp_link="$share/.current.stage.$$.$RANDOM"
  trap 'rm -f "$tmp_link"' EXIT INT TERM
  ln -s "releases/$release_id" "$tmp_link" || self_fail STAGED_RELEASE_INVALID "failed to create temporary current symlink" false "Check filesystem permissions."
  mv -T "$tmp_link" "$current" || self_fail STAGED_RELEASE_INVALID "failed to atomically activate current release" false "Check filesystem permissions."
  trap - EXIT INT TERM
}

self_shim_action_for_path() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    printf 'write_managed_shim\n'
  elif self_shim_is_managed "$path"; then
    printf 'replace_managed_shim\n'
  else
    printf 'refuse_unmanaged_shim\n'
  fi
}

self_install_shim() {
  local shim_path tmp
  shim_path="$(self_bin_path)"
  if [[ -e "$shim_path" ]] && ! self_shim_is_managed "$shim_path"; then
    self_fail REFUSE_UNMANAGED_SHIM "refusing to overwrite unmanaged Agently shim: $shim_path" true "Remove or rename the existing file, then rerun self install."
  fi
  mkdir -p "$(self_bin_dir)" || self_fail STAGED_RELEASE_INVALID "failed to create user bin directory" false "Check HOME permissions."
  tmp="$(mktemp "$(self_bin_dir)/.agently.stage.XXXXXX")" || self_fail STAGED_RELEASE_INVALID "failed to create temporary shim" false "Check HOME permissions."
  trap 'rm -f "$tmp"' EXIT INT TERM
  self_render_shim > "$tmp" || self_fail STAGED_RELEASE_INVALID "failed to render managed shim" false "Check HOME permissions."
  chmod +x "$tmp" || self_fail STAGED_RELEASE_INVALID "failed to chmod managed shim" false "Check HOME permissions."
  mv "$tmp" "$shim_path" || self_fail STAGED_RELEASE_INVALID "failed to install managed shim" false "Check HOME permissions."
  trap - EXIT INT TERM
}

self_confirm_timeout_seconds() {
  local timeout="${AGENTLY_SELF_CONFIRM_TIMEOUT_SECONDS:-120}"
  if [[ "$timeout" =~ ^[0-9]+$ && "$timeout" -gt 0 ]]; then
    printf '%s\n' "$timeout"
  else
    printf '120\n'
  fi
}

self_confirm_uninstall_gate() {
  local phrase="$1" timeout reply
  timeout="$(self_confirm_timeout_seconds)"
  if ! { exec 202<>/dev/tty; } 2>/dev/null; then
    self_fail UNINSTALL_REQUIRES_INTERACTIVE_PATH "confirmed uninstall requires an interactive terminal" true "Run from an interactive shell and type the exact share path."
  fi
  {
    printf 'Agently self uninstall will remove the managed tool install only.\n'
    printf 'Type this exact path to confirm:\n%s\n> ' "$phrase"
  } >&202
  if ! IFS= read -r -t "$timeout" reply <&202; then
    exec 202>&- 202<&-
    self_fail UNINSTALL_CONFIRMATION_TIMEOUT "uninstall confirmation timed out" true "Rerun the command and type the exact share path before the timeout."
  fi
  exec 202>&- 202<&-
  [[ "$reply" == "$phrase" ]] || self_fail UNINSTALL_NOT_CONFIRMED "uninstall was not confirmed" true "Rerun the command and type the exact share path."
}

self_uninstall_removed_json() {
  local first=1 item
  printf '['
  for item in "$@"; do
    [[ -n "$item" ]] || continue
    [[ "$first" -eq 0 ]] && printf ','
    json_string "$item"
    first=0
  done
  printf ']'
}
