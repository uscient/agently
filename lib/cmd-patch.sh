#!/usr/bin/env bash
# shellcheck disable=SC2016

cmd_patch() {
  local sub="${1:-help}"
  if [[ $# -gt 0 ]]; then
    shift
  fi
  case "$sub" in
    propose) patch_propose "$@" ;;
    check) patch_check "$@" ;;
    apply) patch_apply "$@" ;;
    list) patch_list "$@" ;;
    show) patch_show "$@" ;;
    reject) patch_reject "$@" ;;
    explain) patch_explain "$@" ;;
    help|-h|--help|"") patch_help ;;
    *) die "unknown patch command: $sub" ;;
  esac
}

patch_help() {
  cat >&2 <<'EOF'
Usage:
  agently patch propose <patch-file> --workstream <id> [--format unified|srep] [--note "..."]
  agently patch check <id|patch-file> --workstream <id>
  agently patch apply <id> --workstream <id> --reviewed [--allow-dirty]
  agently patch list --workstream <id> [--json]
  agently patch show <id> --workstream <id>
  agently patch reject <id> --workstream <id> [--note "..."]
  agently patch explain <id> --workstream <id>
EOF
}

patch_validate_format() {
  case "$1" in
    unified|srep) return 0 ;;
    *) die "invalid patch format: $1" ;;
  esac
}

patch_workstream_required() {
  local ws="${1:-}" json="${2:-0}"
  [[ -n "$ws" ]] || die_or_json "$json" WORKSTREAM_REQUIRED "--workstream is required"
  require_workstream_handle "$ws"
}

patch_root_dir() {
  local root="$1" ws="$2" rel dir
  rel="$(agently_config_get "$root" patch dir)"
  case "$rel" in
    artifacts/patches|artifacts/patches/*) ;;
    *) die "patch.dir must stay under artifacts/patches: $rel" ;;
  esac
  dir="$root/.agently/workstreams/$ws/$rel"
  mkdir -p "$dir"
  ensure_under_agently "$dir" >/dev/null
  printf '%s\n' "$dir"
}

patch_next_id() {
  local dir="$1" max=0 child base
  shopt -s nullglob
  for child in "$dir"/*; do
    [[ -d "$child" ]] || continue
    base="$(basename "$child")"
    if [[ "$base" =~ ^[0-9][0-9][0-9]$ && $((10#$base)) -gt "$max" ]]; then
      max=$((10#$base))
    fi
  done
  shopt -u nullglob
  printf '%03d\n' "$((max + 1))"
}

patch_meta_get() {
  local meta="$1" key="$2"
  config_get_top "$meta" "$key"
}

patch_meta_set() {
  local meta="$1" key="$2" value="$3" dir tmp
  dir="$(dirname "$meta")"
  tmp="$(mktemp "$dir/.meta.tmp.XXXXXX")"
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
  ' "$meta" > "$tmp"
  mv "$tmp" "$meta"
}

patch_files_from_diff() {
  local patch="$1"
  awk '
    /^diff --git a\// {
      old = $3
      new = $4
      sub(/^a\//, "", old)
      sub(/^b\//, "", new)
      if (old != "" && old != "/dev/null") print old
      if (new != "" && new != "/dev/null") print new
      next
    }
    /^\+\+\+ b\// {
      p = $0
      sub(/^\+\+\+ b\//, "", p)
      if (p != "" && p != "/dev/null") print p
      next
    }
    /^--- a\// {
      p = $0
      sub(/^--- a\//, "", p)
      if (p != "" && p != "/dev/null") print p
      next
    }
  ' "$patch" | sort -u
}

patch_protected_paths_in_diff() {
  local patch_file="$1"
  patch_files_from_diff "$patch_file" | while IFS= read -r rel; do
    if is_protected_authority_path "$rel"; then
      printf '%s\n' "$rel"
    fi
  done | sort -u
}

patch_count_added() {
  awk '/^\+/ && !/^\+\+\+/ { count++ } END { print count + 0 }' "$1"
}

patch_count_removed() {
  awk '/^-/ && !/^---/ { count++ } END { print count + 0 }' "$1"
}

patch_csv_files() {
  local patch="$1" first=1 file
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    if [[ "$first" -eq 0 ]]; then
      printf ', '
    fi
    printf '%s' "$file"
    first=0
  done < <(patch_files_from_diff "$patch")
}

patch_artifact_for_id() {
  local root="$1" ws="$2" id="$3" dir patch_dir
  [[ "$id" =~ ^[0-9][0-9][0-9]$ ]] || die "patch id must be NNN: $id"
  patch_dir="$(patch_root_dir "$root" "$ws")"
  dir="$patch_dir/$id"
  [[ -d "$dir" ]] || die "patch not found: $id"
  printf '%s\n' "$dir"
}

patch_srep_apply_one() {
  local root="$1" rel="$2" search="$3" replace="$4" out_dir="$5" source content rest count=0 new_content out_file
  source="$(resolve_repo_file "$root" "$rel")"
  content="$(cat "$source")"
  rest="$content"
  while [[ "$rest" == *"$search"* ]]; do
    count=$((count + 1))
    rest="${rest#*"$search"}"
  done
  [[ "$count" -eq 1 ]] || die "srep search must match exactly once in $rel; count=$count"
  new_content="${content/"$search"/$replace}"
  out_file="$out_dir/$rel"
  mkdir -p "$(dirname "$out_file")"
  printf '%s\n' "$new_content" > "$out_file"
}

patch_srep_to_diff() {
  local root="$1" srep="$2" diff_out="$3" tmp rel="" mode="" search="" replace="" line source new_file any=0
  tmp="$(mktemp -d)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      '@@ file: '*)
        rel="${line#@@ file: }"
        mode=""
        search=""
        replace=""
        ;;
      '<<<<<<< SEARCH')
        [[ -n "$rel" ]] || die "srep block missing file header"
        mode="search"
        search=""
        ;;
      '=======')
        [[ "$mode" == "search" ]] || die "srep separator outside search block"
        mode="replace"
        replace=""
        ;;
      '>>>>>>> REPLACE')
        [[ "$mode" == "replace" ]] || die "srep replace terminator outside replace block"
        patch_srep_apply_one "$root" "$rel" "${search%$'\n'}" "${replace%$'\n'}" "$tmp/new"
        mode=""
        any=1
        ;;
      *)
        case "$mode" in
          search) search+="$line"$'\n' ;;
          replace) replace+="$line"$'\n' ;;
          "") ;;
          *) die "unknown srep parser state" ;;
        esac
        ;;
    esac
  done < "$srep"
  [[ "$any" -eq 1 ]] || die "no srep blocks found"
  : > "$diff_out"
  while IFS= read -r new_file; do
    rel="${new_file#"$tmp/new"/}"
    source="$(resolve_repo_file "$root" "$rel")"
    diff -u --label "a/$rel" --label "b/$rel" "$source" "$new_file" >> "$diff_out" || true
  done < <(find "$tmp/new" -type f | sort)
  rm -rf "$tmp"
  [[ -s "$diff_out" ]] || die "srep produced an empty diff"
}

patch_write_meta() {
  local dir="$1" id="$2" ws="$3" format="$4" patch_file="$5" note_text="$6" root="$7" files added removed base patch_sha
  files="$(patch_csv_files "$patch_file")"
  added="$(patch_count_added "$patch_file")"
  removed="$(patch_count_removed "$patch_file")"
  base="$(git -C "$root" rev-parse HEAD 2>/dev/null || printf 'unknown')"
  patch_sha="$(sha256_of "$patch_file")"
  cat > "$dir/meta.yml" <<EOF
id: $id
workstream: $ws
status: proposed
format: $format
created_at: $(now)
author_agent: codex
base_commit: $base
patch_sha256: $patch_sha
files: [$files]
added_lines: $added
removed_lines: $removed
check_ran_at:
check_ok:
check_log:
reviewed: false
review_note: $note_text
applied_at:
git_status:
EOF
}

patch_write_readme() {
  local dir="$1" id="$2" ws="$3" format="$4" root="$5" base patch_sha
  base="$(patch_meta_get "$dir/meta.yml" base_commit)"
  patch_sha="$(patch_meta_get "$dir/meta.yml" patch_sha256)"
  render_file_to_stdout "$root/.agently/templates/patch/README.md" \
    "PATCH_ID=$id" \
    "WORKSTREAM_SLUG=$ws" \
    "PATCH_FORMAT=$format" \
    "DATETIME=$(now)" \
    "BASE_COMMIT=$base" \
    "PATCH_SHA256=$patch_sha" > "$dir/README.md"
}

patch_propose() {
  local patch_file="${1:-}" ws="" format="unified" note_text="" root patch_dir id dir protected_paths first_protected
  [[ -n "$patch_file" ]] || die "usage: agently patch propose <patch-file>"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workstream)
        [[ $# -ge 2 ]] || die "--workstream requires a value"
        ws="$2"; shift 2 ;;
      --format)
        [[ $# -ge 2 ]] || die "--format requires a value"
        format="$2"; shift 2 ;;
      --note)
        [[ $# -ge 2 ]] || die "--note requires a value"
        note_text="$2"; shift 2 ;;
      -h|--help) patch_help; return 0 ;;
      *) die "unknown patch propose option: $1" ;;
    esac
  done
  [[ -f "$patch_file" ]] || die "patch file not found: $patch_file"
  patch_validate_format "$format"
  root="$(require_initialized)"
  ws="$(patch_workstream_required "$ws")"
  patch_dir="$(patch_root_dir "$root" "$ws")"
  id="$(patch_next_id "$patch_dir")"
  dir="$patch_dir/$id"
  mkdir -p "$dir"
  if [[ "$format" == "srep" ]]; then
    cp "$patch_file" "$dir/proposal.srep"
    patch_srep_to_diff "$root" "$patch_file" "$dir/patch.diff"
  else
    cp "$patch_file" "$dir/patch.diff"
  fi
  patch_write_meta "$dir" "$id" "$ws" "$format" "$dir/patch.diff" "$note_text" "$root"
  protected_paths="$(patch_protected_paths_in_diff "$dir/patch.diff" || true)"
  if [[ -n "$protected_paths" ]]; then
    first_protected="$(printf '%s\n' "$protected_paths" | sed -n '1p')"
    warn "patch touches runtime-locked authority surface; apply will be refused: $first_protected"
    patch_meta_set "$dir/meta.yml" protected true
  fi
  if [[ -f "$root/.agently/templates/patch/README.md" ]]; then
    patch_write_readme "$dir" "$id" "$ws" "$format" "$root"
  else
    printf '# Agently Patch %s\n' "$id" > "$dir/README.md"
  fi
  cat <<EOF
# Patch Proposed

- id: $id
- workstream: $ws
- artifact: $(rel_to_root "$root" "$dir")
- status: proposed
EOF
}

patch_check_file() {
  local root="$1" patch_file="$2" log="$3" meta="${4:-}" status apply_status markers=0
  if grep -Eq '^(<<<<<<<|=======|>>>>>>>)' "$patch_file"; then
    markers=1
  fi
  set +e
  run_and_truncate "$log" -- git -C "$root" apply --check --whitespace=error "$patch_file"
  apply_status=$?
  set -e
  if [[ "$markers" -eq 1 ]]; then
    status=2
  elif [[ "$apply_status" -ne 0 ]]; then
    status=1
  else
    status=0
  fi
  if [[ -n "$meta" ]]; then
    patch_meta_set "$meta" check_ran_at "$(now)"
    patch_meta_set "$meta" check_ok "$([[ "$status" -eq 0 ]] && printf true || printf false)"
    patch_meta_set "$meta" check_log "$(rel_to_root "$root" "$log")"
    if [[ "$status" -eq 0 ]]; then
      patch_meta_set "$meta" status checked
    fi
  fi
  cat <<EOF
# Patch Check

- patch: $(rel_to_root "$root" "$patch_file")
- applies_clean: $([[ "$apply_status" -eq 0 ]] && printf true || printf false)
- conflict_markers: $([[ "$markers" -eq 1 ]] && printf true || printf false)
- log: $(rel_to_root "$root" "$log")
EOF
  return "$status"
}

patch_check() {
  local target="${1:-}" root ws="" dir patch_file log meta=""
  [[ -n "$target" ]] || die "usage: agently patch check <id|patch-file>"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workstream)
        option_has_value "$@" || die "--workstream requires a value"
        ws="$2"; shift 2 ;;
      -h|--help) patch_help; return 0 ;;
      *) die "unknown patch check option: $1" ;;
    esac
  done
  root="$(require_initialized)"
  if [[ -f "$target" ]]; then
    patch_file="$(realpath "$target")"
    log="$(agently_log_file "$root" patch check)"
  else
    ws="$(patch_workstream_required "$ws")"
    dir="$(patch_artifact_for_id "$root" "$ws" "$target")"
    patch_file="$dir/patch.diff"
    meta="$dir/meta.yml"
    log="$dir/check.log"
  fi
  patch_check_file "$root" "$patch_file" "$log" "$meta"
}

patch_dirty_on_targets() {
  local root="$1" patch_file="$2" file status dirty=0
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    status="$(git -C "$root" status --porcelain -- "$file")"
    if [[ -n "$status" ]]; then
      printf '%s\n' "$file"
      dirty=1
    fi
  done < <(patch_files_from_diff "$patch_file")
  return "$dirty"
}

patch_apply() {
  local id="${1:-}" reviewed=0 allow_dirty=0 root ws="" dir patch_file protected_paths first_protected meta dirty log apply_log apply_status before_head after_head
  [[ -n "$id" ]] || die "usage: agently patch apply <id> --reviewed"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reviewed) reviewed=1; shift ;;
      --workstream)
        option_has_value "$@" || die "--workstream requires a value"
        ws="$2"; shift 2 ;;
      --allow-dirty) allow_dirty=1; shift ;;
      -h|--help) patch_help; return 0 ;;
      *) die "unknown patch apply option: $1" ;;
    esac
  done
  [[ "$reviewed" -eq 1 ]] || die "patch apply requires --reviewed"
  root="$(require_initialized)"
  ws="$(patch_workstream_required "$ws")"
  dir="$(patch_artifact_for_id "$root" "$ws" "$id")"
  patch_file="$dir/patch.diff"
  protected_paths="$(patch_protected_paths_in_diff "$patch_file" || true)"
  if [[ -n "$protected_paths" ]]; then
    first_protected="$(printf '%s\n' "$protected_paths" | sed -n '1p')"
    die "patch touches runtime-locked authority surface: $first_protected"
  fi
  meta="$dir/meta.yml"
  log="$dir/check.log"
  patch_check_file "$root" "$patch_file" "$log" "$meta" >/dev/null || die "patch check failed; refusing to apply"
  if [[ "$allow_dirty" -eq 0 ]]; then
    dirty="$(patch_dirty_on_targets "$root" "$patch_file" || true)"
    [[ -z "$dirty" ]] || die "patch target files are dirty; use --allow-dirty if intentional: $dirty"
  fi
  before_head="$(git -C "$root" rev-parse HEAD 2>/dev/null || printf unknown)"
  apply_log="$dir/apply.log"
  printf '## Apply Output\n\n```text\n'
  set +e
  run_and_truncate "$apply_log" -- git -C "$root" apply --whitespace=error "$patch_file"
  apply_status=$?
  set -e
  printf '```\n\n'
  patch_meta_set "$meta" apply_log "$(rel_to_root "$root" "$apply_log")"
  if [[ "$apply_status" -ne 0 ]]; then
    echo "FAIL: git apply failed with status $apply_status; see $(rel_to_root "$root" "$apply_log")" >&2
    return "$apply_status"
  fi
  after_head="$(git -C "$root" rev-parse HEAD 2>/dev/null || printf unknown)"
  [[ "$before_head" == "$after_head" ]] || die "patch apply changed HEAD unexpectedly"
  patch_meta_set "$meta" status applied
  patch_meta_set "$meta" reviewed true
  patch_meta_set "$meta" applied_at "$(now)"
  git -C "$root" status --short > "$dir/git-status-after-apply.txt"
  patch_meta_set "$meta" git_status "$(rel_to_root "$root" "$dir/git-status-after-apply.txt")"
  cat <<EOF
# Patch Applied

- id: $id
- artifact: $(rel_to_root "$root" "$dir")
- committed: false
- git_status: $(rel_to_root "$root" "$dir/git-status-after-apply.txt")
EOF
}

patch_list() {
  local ws="" json=0 root patch_dir dir meta first=1 id status files
  local json_requested=0
  args_include_flag --json "$@" && json_requested=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workstream)
        option_has_value "$@" || die_or_json "$json_requested" WORKSTREAM_REQUIRED "--workstream requires a value"
        ws="$2"; shift 2 ;;
      --json) json=1; shift ;;
      -h|--help) patch_help; return 0 ;;
      *) die "unknown patch list option: $1" ;;
    esac
  done
  root="$(require_initialized)"
  ws="$(patch_workstream_required "$ws" "$json")"
  patch_dir="$(patch_root_dir "$root" "$ws")"
  if [[ "$json" -eq 1 ]]; then
    printf '{"workstream":'; json_string "$ws"; printf ',"patches":['
    shopt -s nullglob
    for dir in "$patch_dir"/*; do
      [[ -f "$dir/meta.yml" ]] || continue
      id="$(basename "$dir")"
      status="$(patch_meta_get "$dir/meta.yml" status)"
      files="$(patch_meta_get "$dir/meta.yml" files)"
      [[ "$first" -eq 0 ]] && printf ','
      printf '{"id":'; json_string "$id"; printf ',"status":'; json_string "$status"; printf ',"files":'; json_string "$files"; printf '}'
      first=0
    done
    shopt -u nullglob
    printf ']}\n'
    return 0
  fi
  printf '# Patch List\n\n'
  printf -- '- workstream: %s\n\n' "$ws"
  printf '| ID | Status | Files |\n| --- | --- | --- |\n'
  shopt -s nullglob
  for dir in "$patch_dir"/*; do
    meta="$dir/meta.yml"
    [[ -f "$meta" ]] || continue
    id="$(basename "$dir")"
    status="$(patch_meta_get "$meta" status)"
    files="$(patch_meta_get "$meta" files)"
    printf '| %s | %s | %s |\n' "$id" "$status" "$files"
  done
  shopt -u nullglob
}

patch_show() {
  local id="${1:-}" root ws="" dir
  [[ -n "$id" ]] || die "usage: agently patch show <id>"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workstream)
        option_has_value "$@" || die "--workstream requires a value"
        ws="$2"; shift 2 ;;
      -h|--help) patch_help; return 0 ;;
      *) die "unknown patch show option: $1" ;;
    esac
  done
  root="$(require_initialized)"
  ws="$(patch_workstream_required "$ws")"
  dir="$(patch_artifact_for_id "$root" "$ws" "$id")"
  printf '# Patch %s\n\n' "$id"
  printf '## Metadata\n\n```yaml\n'
  cat "$dir/meta.yml"
  printf '```\n\n## Diff\n\n```diff\n'
  cat "$dir/patch.diff"
  printf '\n```\n'
}

patch_reject() {
  local id="${1:-}" note_text="" root ws="" dir meta
  [[ -n "$id" ]] || die "usage: agently patch reject <id> [--note ...]"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --note)
        [[ $# -ge 2 ]] || die "--note requires a value"
        note_text="$2"; shift 2 ;;
      --workstream)
        option_has_value "$@" || die "--workstream requires a value"
        ws="$2"; shift 2 ;;
      -h|--help) patch_help; return 0 ;;
      *) die "unknown patch reject option: $1" ;;
    esac
  done
  root="$(require_initialized)"
  ws="$(patch_workstream_required "$ws")"
  dir="$(patch_artifact_for_id "$root" "$ws" "$id")"
  meta="$dir/meta.yml"
  patch_meta_set "$meta" status rejected
  patch_meta_set "$meta" review_note "$note_text"
  patch_meta_set "$meta" reviewed false
  cat <<EOF
# Patch Rejected

- id: $id
- artifact: $(rel_to_root "$root" "$dir")
- status: rejected
EOF
}

patch_explain() {
  local id="${1:-}" root ws="" dir patch_file meta
  [[ -n "$id" ]] || die "usage: agently patch explain <id>"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workstream)
        option_has_value "$@" || die "--workstream requires a value"
        ws="$2"; shift 2 ;;
      -h|--help) patch_help; return 0 ;;
      *) die "unknown patch explain option: $1" ;;
    esac
  done
  root="$(require_initialized)"
  ws="$(patch_workstream_required "$ws")"
  dir="$(patch_artifact_for_id "$root" "$ws" "$id")"
  patch_file="$dir/patch.diff"
  meta="$dir/meta.yml"
  cat <<EOF
# Patch Explain

- id: $id
- status: $(patch_meta_get "$meta" status)
- base_commit: $(patch_meta_get "$meta" base_commit)
- patch_sha256: $(sha256_of "$patch_file")
- added_lines: $(patch_count_added "$patch_file")
- removed_lines: $(patch_count_removed "$patch_file")

## Files
EOF
  while IFS= read -r file; do
    printf -- '- %s\n' "$file"
  done < <(patch_files_from_diff "$patch_file")
}
