#!/usr/bin/env bash
# shellcheck disable=SC2016

cmd_doctrine() {
  local sub="${1:-help}"
  if [[ $# -gt 0 ]]; then
    shift
  fi
  case "$sub" in
    status) doctrine_status "$@" ;;
    refresh) doctrine_refresh "$@" ;;
    help|-h|--help|"") doctrine_help ;;
    *) die "unknown doctrine command: $sub" ;;
  esac
}

doctrine_help() {
  cat >&2 <<'EOF'
Usage:
  agently doctrine status [--json]
  agently doctrine refresh [--force]
EOF
}

doctrine_status() {
  local json=0 root dir provenance installed_dir installed_hash marker marker_hash marker_version marker_generated marker_count snapshot_status
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json=1; shift ;;
      -h|--help) doctrine_help; return 0 ;;
      *) die "unknown doctrine status option: $1" ;;
    esac
  done

  root="$(project_dir_or_empty)"
  [[ -n "$root" ]] || root="$(pwd)"
  dir="$(agently_doctrine_dir "$root")"
  provenance="$(agently_doctrine_provenance "$root" "$dir")"
  installed_dir="${AGENTLY_SHARE:-}/docs/doctrine"
  installed_hash=""
  [[ -d "$installed_dir" ]] && installed_hash="$(agently_doctrine_manifest_hash "$installed_dir")"

  marker="$root/.agently/doctrine/.agently-doctrine-snapshot.yml"
  marker_hash="$(config_get_top "$marker" manifest_hash)"
  marker_version="$(config_get_top "$marker" agently_version)"
  marker_generated="$(config_get_top "$marker" generated_at)"
  marker_count="$(config_get_top "$marker" file_count)"

  case "$provenance" in
    runtime-snapshot)
      if [[ -n "$installed_hash" && -n "$marker_hash" && "$marker_hash" == "$installed_hash" ]]; then
        snapshot_status="fresh"
      else
        snapshot_status="stale"
      fi
      ;;
    source)
      snapshot_status="source"
      ;;
    installed-fallback)
      snapshot_status="missing"
      ;;
    *)
      snapshot_status="none"
      ;;
  esac

  if [[ "$json" -eq 1 ]]; then
    printf '{\n'
    printf '  "root": '; json_string "$root"; printf ',\n'
    printf '  "doctrine_dir": '; json_string "$dir"; printf ',\n'
    printf '  "provenance": '; json_string "$provenance"; printf ',\n'
    printf '  "snapshot_status": '; json_string "$snapshot_status"; printf ',\n'
    printf '  "marker": {"path": '; json_string "$marker"
    printf ', "manifest_hash": '; json_string "$marker_hash"
    printf ', "agently_version": '; json_string "$marker_version"
    printf ', "generated_at": '; json_string "$marker_generated"
    printf ', "file_count": '; json_string "$marker_count"; printf '},\n'
    printf '  "installed": {"path": '; json_string "$installed_dir"
    printf ', "manifest_hash": '; json_string "$installed_hash"; printf '}\n'
    printf '}\n'
    return 0
  fi

  printf '# Agently Doctrine Status\n\n'
  printf -- '- root: `%s`\n' "$root"
  printf -- '- doctrine_dir: `%s`\n' "${dir:-none}"
  printf -- '- provenance: %s\n' "$provenance"
  printf -- '- snapshot: %s\n' "$snapshot_status"
  printf -- '- installed_hash: %s\n' "${installed_hash:-none}"
  if [[ -f "$marker" ]]; then
    printf -- '- marker: `%s`\n' "$(rel_to_root "$root" "$marker")"
    printf -- '- marker_manifest_hash: %s\n' "${marker_hash:-none}"
    printf -- '- marker_agently_version: %s\n' "${marker_version:-unknown}"
    printf -- '- marker_generated_at: %s\n' "${marker_generated:-unknown}"
    printf -- '- marker_file_count: %s\n' "${marker_count:-unknown}"
  else
    printf -- '- marker: missing\n'
  fi
}

doctrine_refresh() {
  local force=0 root
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force=1; shift ;;
      -h|--help) doctrine_help; return 0 ;;
      *) die "unknown doctrine refresh option: $1" ;;
    esac
  done
  root="$(require_initialized)"
  init_snapshot_doctrine "$root" "$(agently_version)" "$force" 0
}
