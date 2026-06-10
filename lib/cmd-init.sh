#!/usr/bin/env bash

init_usage() {
  cat >&2 <<'EOF'
Usage:
  agently init --codex [--serena] [--profile lite|review|edit] [--project DIR|--target DIR] [--name NAME] [--force] [--dry-run] [--allow-non-git]
EOF
}

init_dest_for_template() {
  local rel="$1"
  case "$rel" in
    AGENTS.md) printf 'AGENTS.md\n' ;;
    agently/*) printf '.agently/%s\n' "${rel#agently/}" ;;
    agents/*) printf '.agents/%s\n' "${rel#agents/}" ;;
    codex/*) printf '.codex/%s\n' "${rel#codex/}" ;;
    *) die "unknown template mapping: $rel" ;;
  esac
}

init_protected_path() {
  local rel="$1"
  case "$rel" in
    .agently/config.yml|.agently/local.yml|.agently/workstreams|.agently/workstreams/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

init_should_render() {
  case "$1" in
    AGENTS.md|.agently/config.yml) return 0 ;;
    *) return 1 ;;
  esac
}

init_write_doctrine_marker() {
  local dst="$1" src="$2" version="$3" hash="$4" file_count="$5" marker f rel
  marker="$dst/.agently-doctrine-snapshot.yml"
  {
    printf 'source: installed-agently\n'
    printf 'snapshot_kind: runtime-readonly-copy\n'
    printf 'do_not_edit: true\n'
    printf 'agently_version: %s\n' "$version"
    printf 'canonical_source: %s\n' "$src"
    printf 'generated_at: %s\n' "$(now)"
    printf 'manifest_hash: %s\n' "$hash"
    printf 'file_count: %s\n' "$file_count"
    printf 'files:\n'
    while IFS= read -r f; do
      rel="${f#"$dst"/}"
      printf '  - path: %s\n' "$rel"
      printf '    sha256: %s\n' "$(sha256_of "$f")"
    done < <(find "$dst" -type f -name '*.md' | sort)
  } > "$marker"
  chmod 0444 "$marker"
}

init_snapshot_doctrine() {
  local root="$1" version="$2" force="$3" dry_run="$4"
  local src dst marker src_hash dst_hash f rel target file_count

  src="$AGENTLY_SHARE/docs/doctrine"
  dst="$root/.agently/doctrine"
  marker="$dst/.agently-doctrine-snapshot.yml"

  if agently_is_source_repo "$root"; then
    return 0
  fi

  if [[ ! -d "$src" ]]; then
    note "doctrine snapshot skipped: no installed doctrine at $src"
    return 0
  fi

  if [[ -L "$dst" ]]; then
    die ".agently/doctrine is a symlink. Refusing to proceed."
  fi

  src_hash="$(agently_doctrine_manifest_hash "$src")"
  dst_hash=""
  [[ -f "$marker" ]] && dst_hash="$(config_get_top "$marker" manifest_hash)"

  if [[ "$force" -ne 1 && -n "$dst_hash" && "$dst_hash" == "$src_hash" ]]; then
    note "doctrine snapshot fresh (manifest_hash matches installed)"
    return 0
  fi

  file_count="$(find "$src" -type f -name '*.md' | wc -l | awk '{print $1 + 0}')"
  if [[ "$dry_run" -eq 1 ]]; then
    note "DRY doctrine snapshot -> .agently/doctrine/ ($file_count files)"
    return 0
  fi

  if [[ -L "$dst" ]]; then
    die ".agently/doctrine is a symlink. Refusing to proceed."
  fi

  if [[ -d "$dst" ]]; then
    find "$dst" -type d -exec chmod u+w {} + 2>/dev/null || true
    find "$dst" -type f -exec chmod u+w {} + 2>/dev/null || true
    rm -rf "$dst"
  fi
  mkdir -p "$dst"

  while IFS= read -r f; do
    rel="${f#"$src"/}"
    target="$dst/$rel"
    mkdir -p "$(dirname "$target")"
    cp "$f" "$target"
    chmod 0444 "$target"
  done < <(find "$src" -type f -name '*.md' | sort)

  init_write_doctrine_marker "$dst" "$src" "$version" "$src_hash" "$file_count"
  note "doctrine snapshot: wrote $file_count read-only files to .agently/doctrine/"
  AGENTLY_WRITES_DONE="${AGENTLY_WRITES_DONE:-0}"
  AGENTLY_WRITES_DONE=$((AGENTLY_WRITES_DONE + 1))
}

cmd_init() {
  local profile="" target="" name="" force=0 dry_run=0 allow_non_git=0 enable_serena=0 serena_profile=""
  local templates="$AGENTLY_SHARE/templates" root project rel dst_rel src dst content
  local date datetime version title

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --codex) profile="codex"; shift ;;
      --serena) enable_serena=1; shift ;;
      --profile)
        [[ $# -ge 2 ]] || die "--profile requires a value"
        serena_profile="$(serena_profile_normalize "$2")" || die "invalid Serena profile: $2"
        shift 2 ;;
      --target|--project)
        option_has_value "$@" || die "$1 requires a value"
        target="$2"; shift 2 ;;
      --name)
        [[ $# -ge 2 ]] || die "--name requires a value"
        name="$(slugify "$2")" || die "invalid --name: $2"
        shift 2 ;;
      --force) force=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      --allow-non-git) allow_non_git=1; shift ;;
      -h|--help) init_usage; return 0 ;;
      *) die "unknown init option: $1" ;;
    esac
  done

  if [[ -z "$profile" ]]; then
    profile="codex"
    note "defaulting to --codex profile"
  fi
  [[ "$profile" == "codex" ]] || die "unsupported profile: $profile"
  [[ -d "$templates" ]] || die "missing templates at $templates. Reinstall Agently or set AGENTLY_HOME."

  if [[ -z "$target" && -n "${AGENTLY_PROJECT:-}" ]]; then
    target="$AGENTLY_PROJECT"
  fi

  if [[ -n "$target" ]]; then
    [[ -d "$target" ]] || die "target does not exist: $target"
    root="$(cd "$target" && pwd)"
  elif git rev-parse --show-toplevel >/dev/null 2>&1; then
    root="$(git rev-parse --show-toplevel)"
  else
    [[ "$allow_non_git" -eq 1 ]] || die "not inside a git repo. Use --target DIR --allow-non-git if intentional."
    root="$(pwd)"
  fi

  if [[ "$allow_non_git" -ne 1 ]]; then
    git -C "$root" rev-parse --show-toplevel >/dev/null 2>&1 || die "target is not a git repo: $root"
  fi

  if [[ -z "$name" ]]; then
    project="$(basename "$root")"
    name="$(slugify "$project")" || name="project"
  fi
  title="$(titleize "$name")"
  date="$(today)"
  datetime="$(now)"
  version="$(agently_version)"

  AGENTLY_WRITES_DONE=0
  AGENTLY_WRITES_SKIPPED=0

  while IFS= read -r src; do
    rel="${src#"$templates"/}"
    case "$rel" in
      serena/*) continue ;;
    esac
    dst_rel="$(init_dest_for_template "$rel")"
    dst="$root/$dst_rel"

    if [[ "$dst_rel" == "AGENTS.md" && -e "$dst" ]]; then
      note "keep existing AGENTS.md; merge manually from $templates/AGENTS.md if needed"
      AGENTLY_WRITES_SKIPPED=$((AGENTLY_WRITES_SKIPPED + 1))
      continue
    fi

    if init_protected_path "$dst_rel" && [[ -e "$dst" ]]; then
      note "keep protected: $dst_rel"
      AGENTLY_WRITES_SKIPPED=$((AGENTLY_WRITES_SKIPPED + 1))
      continue
    fi

    if [[ -e "$dst" && "$force" -ne 1 ]]; then
      note "keep existing: $dst_rel"
      AGENTLY_WRITES_SKIPPED=$((AGENTLY_WRITES_SKIPPED + 1))
      continue
    fi

    if init_should_render "$dst_rel"; then
      content="$(render_file_to_stdout "$src" \
        "PROJECT=$name" \
        "TITLE=$title" \
        "PROFILE=$profile" \
        "AGENTLY_VERSION=$version" \
        "DATE=$date" \
        "DATETIME=$datetime")"
    else
      content="$(cat "$src")"
    fi
    write_text_file "$dst" 0644 "$content" "$force" "$dry_run" "$dst_rel"
  done < <(find "$templates" -type f | sort)

  init_snapshot_doctrine "$root" "$version" "$force" "$dry_run"

  if [[ "$enable_serena" -eq 1 ]]; then
    if [[ -z "$serena_profile" ]]; then
      serena_profile="$(config_get_profile_key_from_file "$(agently_config_path_for_root "$root")" serena.profile)"
      serena_profile="$(serena_profile_normalize "${serena_profile:-lite}")" || serena_profile="lite"
    fi
    serena_render_pack "$root" "$name" "$serena_profile" "$force" "$dry_run"
    serena_config_set_enabled_profile "$root" true "$serena_profile" "$dry_run"
    note "Serena capability pack enabled with profile: $serena_profile"
    note "Next: agently serena status"
  fi

  note "Agently init complete: wrote $AGENTLY_WRITES_DONE, kept $AGENTLY_WRITES_SKIPPED"
  note "Next: agently ws new <workstream>"
}
