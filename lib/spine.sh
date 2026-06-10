#!/usr/bin/env bash
# shellcheck disable=SC2034

ws_json_enabled() {
  [[ "${AGENTLY_WS_JSON:-0}" -eq 1 ]]
}

ws_json_value() {
  case "${1:-}" in
    true|false|null) printf '%s' "$1" ;;
    *) json_string "${1:-}" ;;
  esac
}

ws_emit() {
  local first=1 key value
  printf '{'
  while [[ $# -gt 0 ]]; do
    key="$1"
    value="${2:-}"
    shift 2
    [[ "$first" -eq 0 ]] && printf ','
    json_string "$key"
    printf ':'
    ws_json_value "$value"
    first=0
  done
  printf '}\n'
}

ws_emit_json() {
  printf '%s\n' "$1"
}

ws_exit_code_for() {
  case "$1" in
    INVALID_ARGUMENT|INVALID_WS_ID|WORKSTREAM_NOT_FOUND|ALIAS_NOT_FOUND|INVALID_TYPE|DEPENDENCY_MISSING|ALREADY_EXISTS|WORKSTREAM_LAYOUT_CONFLICT)
      printf '1\n' ;;
    WORKSTREAM_ESCROWED|WORKSTREAM_BLOCKED|NOT_PROPOSED|PROMOTION_REQUIRES_INTERACTIVE_PATH|REJECTION_REQUIRES_INTERACTIVE_PATH|PROMOTION_CONFIRMATION_TIMEOUT|REJECTION_CONFIRMATION_TIMEOUT|PROMOTION_NOT_CONFIRMED|REJECTION_NOT_CONFIRMED)
      printf '2\n' ;;
    PAYLOAD_TOO_LARGE|PAYLOAD_NOT_FILE|PAYLOAD_SYMLINK_REJECTED|HASH_MISMATCH)
      printf '3\n' ;;
    MANIFEST_INVALID|EVENT_LOG_INVALID|STATE_INCOHERENT)
      printf '4\n' ;;
    LOCK_FAILED)
      printf '75\n' ;;
    *)
      printf '1\n' ;;
  esac
}

ws_required_actions_json() {
  local first=1 action
  printf '['
  for action in "$@"; do
    [[ "$first" -eq 0 ]] && printf ','
    json_string "$action"
    first=0
  done
  printf ']'
}

ws_fail() {
  local code="$1" message="$2" recoverable="${3:-true}" exit_code
  shift 3 || true
  exit_code="$(ws_exit_code_for "$code")"
  if ws_json_enabled; then
    {
      printf '{"ok":false,"error":{"code":'
      json_string "$code"
      printf ',"message":'
      json_string "$message"
      printf ',"recoverable":'
      json_bool "$recoverable"
      printf ',"required_next_actions":'
      ws_required_actions_json "$@"
      printf '}}\n'
    } >&2
  else
    printf 'FAIL: %s\n' "$message" >&2
  fi
  exit "$exit_code"
}

ws_spine_dependency_missing() {
  local tool="$1" message action
  case "$tool" in
    jq)
      message="jq is required for Agently ws spine commands."
      action="Install jq and rerun the command."
      ;;
    sha256sum)
      message="sha256sum is required for Agently ws spine commands."
      action="Install coreutils sha256sum and rerun the command."
      ;;
    flock)
      message="flock is required for Agently ws spine commands."
      action="Install util-linux flock and rerun the command."
      ;;
    *)
      message="$tool is required for Agently ws spine commands."
      action="Install $tool and rerun the command."
      ;;
  esac
  ws_fail DEPENDENCY_MISSING "$message" true "$action"
}

ws_spine_preflight() {
  has_cmd jq || ws_spine_dependency_missing jq
  has_cmd sha256sum || ws_spine_dependency_missing sha256sum
  has_cmd flock || ws_spine_dependency_missing flock
}

spine_project_root() {
  local root
  root="$(project_dir_or_empty)"
  [[ -n "$root" ]] || ws_fail INVALID_ARGUMENT "not inside a git repo" true "Run from an initialized Agently project."
  git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || ws_fail INVALID_ARGUMENT "not inside a git repo" true "Run from an initialized Agently project."
  root="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -f "$root/.agently/config.yml" ]] || ws_fail INVALID_ARGUMENT "Agently is not initialized here. Run: agently init --codex" true "Run agently init --codex."
  printf '%s\n' "$root"
}

spine_ws_parent_dir_for_root() {
  printf '%s/.agently/workstreams\n' "$1"
}

spine_ws_dir_for_root() {
  printf '%s/.agently/workstreams/%s\n' "$1" "$2"
}

spine_manifest_path() {
  printf '%s/manifest.json\n' "$1"
}

spine_events_path() {
  printf '%s/events.jsonl\n' "$1"
}

spine_lock_path() {
  printf '%s/.manifest.lock\n' "$1"
}

validate_spine_ws_id() {
  local ws_id="$1"
  [[ "$ws_id" =~ ^[A-Z][A-Z0-9]{0,31}$ ]] || ws_fail INVALID_WS_ID "invalid spine workstream id: $ws_id" true "Use an uppercase id matching ^[A-Z][A-Z0-9]{0,31}$."
}

spine_alias_regex() {
  [[ "${1:-}" =~ ^[A-Z][A-Z0-9]{0,31}-[A-Z]+[0-9]+$ ]]
}

validate_alias() {
  local alias="$1" rest code num
  spine_alias_regex "$alias" || ws_fail ALIAS_NOT_FOUND "invalid or unknown spine alias: $alias" true "Use an alias such as W31-PLN1."
  SPINE_ALIAS_WS_ID="${alias%%-*}"
  rest="${alias#*-}"
  code="${rest%%[0-9]*}"
  num="${rest#"$code"}"
  [[ -n "$code" && "$num" =~ ^[0-9]+$ ]] || ws_fail ALIAS_NOT_FOUND "invalid or unknown spine alias: $alias" true "Use an alias such as W31-PLN1."
  SPINE_ALIAS_CODE="$code"
  SPINE_ALIAS_NUM="$num"
}

ws_alias_code_for_type() {
  case "$1" in
    scope) printf 'SCOPE\n' ;;
    requirements) printf 'REQ\n' ;;
    plan) printf 'PLN\n' ;;
    review) printf 'REV\n' ;;
    synthesis) printf 'SYN\n' ;;
    audit) printf 'AUD\n' ;;
    handoff) printf 'HND\n' ;;
    *) ws_fail INVALID_TYPE "invalid spine artifact type: $1" true "Use one of: scope, requirements, plan, review, synthesis, audit, handoff." ;;
  esac
}

ws_type_for_code() {
  case "$1" in
    SCOPE) printf 'scope\n' ;;
    REQ) printf 'requirements\n' ;;
    PLN) printf 'plan\n' ;;
    REV) printf 'review\n' ;;
    SYN) printf 'synthesis\n' ;;
    AUD) printf 'audit\n' ;;
    HND) printf 'handoff\n' ;;
    *) return 1 ;;
  esac
}

spine_ws_dir_existing() {
  local root="$1" ws_id="$2" ws_dir
  ws_dir="$(spine_ws_dir_for_root "$root" "$ws_id")"
  [[ -d "$ws_dir" ]] || ws_fail WORKSTREAM_NOT_FOUND "spine workstream not found: $ws_id" true "Run agently ws init $ws_id."
  [[ -f "$(spine_manifest_path "$ws_dir")" ]] || ws_fail WORKSTREAM_NOT_FOUND "spine manifest not found for workstream: $ws_id" true "Run agently ws init $ws_id."
  printf '%s\n' "$ws_dir"
}

spine_manifest_validate_file() {
  local file="$1"
  [[ -f "$file" ]] || ws_fail MANIFEST_INVALID "missing manifest: $file" false "Inspect the workstream layout."
  jq -e . "$file" >/dev/null || ws_fail MANIFEST_INVALID "invalid manifest JSON: $file" false "Restore or repair manifest.json."
}

spine_manifest_update() {
  local ws_dir="$1" tmp
  shift
  tmp="$(mktemp "$ws_dir/.manifest.XXXXXX.tmp")"
  trap 'rm -f "$tmp"' EXIT INT TERM
  if ! jq "$@" "$(spine_manifest_path "$ws_dir")" > "$tmp"; then
    ws_fail MANIFEST_INVALID "manifest update failed" false "Inspect manifest.json."
  fi
  if ! jq -e . "$tmp" >/dev/null; then
    ws_fail MANIFEST_INVALID "manifest update produced invalid JSON" false "Inspect manifest.json."
  fi
  mv "$tmp" "$(spine_manifest_path "$ws_dir")" || ws_fail MANIFEST_INVALID "failed to replace manifest atomically" false "Inspect filesystem permissions."
  trap - EXIT INT TERM
}

events_append() {
  local ws_dir="$1" line="$2"
  printf '%s\n' "$line" | jq -e . >/dev/null || ws_fail EVENT_LOG_INVALID "event line is not valid JSON" false "Inspect events.jsonl."
  printf '%s\n' "$line" >> "$(spine_events_path "$ws_dir")" || ws_fail EVENT_LOG_INVALID "failed to append event log" false "Inspect events.jsonl permissions."
}

spine_event_id_for_seq() {
  printf 'evt_%04d\n' "$1"
}

spine_sha256() {
  local file="$1" hash
  has_cmd sha256sum || ws_spine_dependency_missing sha256sum
  [[ -f "$file" ]] || ws_fail PAYLOAD_NOT_FILE "file not found for hashing: $file" false "Inspect the referenced file."
  hash="$(sha256sum "$file" | awk '{print $1}')"
  [[ "$hash" =~ ^[a-fA-F0-9]{64}$ ]] || ws_fail HASH_MISMATCH "failed to compute SHA-256 for: $file" false "Inspect sha256sum output."
  printf '%s\n' "$hash"
}

spine_path_under_ws_root() {
  local ws_dir="$1" rel="$2" root resolved
  case "$rel" in
    ""|/*) return 1 ;;
  esac
  root="$(realpath -m "$ws_dir")"
  resolved="$(realpath -m "$ws_dir/$rel")"
  case "$resolved" in
    "$root"/*) return 0 ;;
    *) return 1 ;;
  esac
}

ws_assert_under_ws_root() {
  local ws_dir="$1" rel="$2"
  spine_path_under_ws_root "$ws_dir" "$rel" || ws_fail INVALID_ARGUMENT "generated path escapes workstream root: $rel" false "Inspect manifest path generation."
}

ws_artifact_relpath() {
  local kind="$1" alias="$2"
  case "$kind" in
    raw) printf 'raw/%s.raw.md\n' "$alias" ;;
    candidate) printf 'candidates/%s.md\n' "$alias" ;;
    proposed) printf 'proposed/%s.md\n' "$alias" ;;
    canonical) printf 'canonical/%s.md\n' "$alias" ;;
    *) ws_fail INVALID_ARGUMENT "unknown artifact path kind: $kind" false "Inspect command implementation." ;;
  esac
}

ws_spine_config_default() {
  case "$1" in
    schema_version) printf '1\n' ;;
    max_payload_bytes) printf '5242880\n' ;;
    lock_timeout_seconds) printf '10\n' ;;
    confirm_timeout_seconds) printf '120\n' ;;
    *) return 1 ;;
  esac
}

ws_spine_config_get() {
  local root="$1" key="$2" file value
  ws_spine_config_default "$key" >/dev/null || ws_fail INVALID_ARGUMENT "unknown ws.spine config key: $key" false "Inspect command implementation."
  file="$(config_file_for_root "$root")"
  if [[ -f "$file" ]]; then
    agently_config_validate_project_config_file "$file"
    value="$(awk -v key="$key" '
      /^[^[:space:]#][^:]*:/ {
        top = $1
        sub(":", "", top)
        in_ws = (top == "ws")
        in_spine = 0
      }
      in_ws && /^[[:space:]]{2}spine:[[:space:]]*($|#)/ {
        in_spine = 1
        next
      }
      in_ws && in_spine && /^[[:space:]]{2}[^[:space:]#][^:]*:/ {
        in_spine = 0
      }
      in_ws && in_spine {
        pattern = "^[[:space:]]{4}" key ":[[:space:]]*"
        if ($0 ~ pattern) {
          value = $0
          sub(pattern, "", value)
          sub(/[[:space:]]+#.*$/, "", value)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
          if (value ~ /^".*"$/ || value ~ /^'\''.*'\''$/) {
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
  if [[ -z "$value" ]]; then
    ws_spine_config_default "$key"
  else
    [[ "$value" =~ ^[0-9]+$ && "$value" -gt 0 ]] || ws_fail INVALID_ARGUMENT "ws.spine.$key must be a positive integer" true "Fix .agently/config.yml."
    printf '%s\n' "$value"
  fi
}

ws_spine_config_get_for_dir() {
  local ws_dir="$1" key="$2" root
  root="${ws_dir%%/.agently/workstreams/*}"
  ws_spine_config_get "$root" "$key"
}

with_ws_lock() {
  local ws_dir="$1" timeout
  shift
  [[ "${1:-}" == "--" ]] && shift
  timeout="$(ws_spine_config_get_for_dir "$ws_dir" lock_timeout_seconds)"
  (
    flock -w "$timeout" -x 200 || ws_fail LOCK_FAILED "could not acquire workstream lock within ${timeout}s" true "Retry the command."
    "$@"
  ) 200>"$(spine_lock_path "$ws_dir")"
}

spine_event_json() {
  local event_id="$1" event="$2" ws_id="$3" ts="$4" actor="$5" via="$6"
  local extra_json
  shift 6
  if [[ $# -gt 0 ]]; then
    extra_json="$1"
  else
    extra_json='{}'
  fi
  jq -cn \
    --arg event_id "$event_id" \
    --arg event "$event" \
    --arg ws_id "$ws_id" \
    --arg ts "$ts" \
    --arg actor "$actor" \
    --arg via "$via" \
    --argjson extra "$extra_json" \
    '{event_id:$event_id,event:$event,schema_version:1,ws_id:$ws_id,ts:$ts,actor:$actor,via:$via} + $extra'
}

ws_sanitize_provenance() {
  local label="$1" value="$2"
  [[ -n "$value" ]] || ws_fail INVALID_ARGUMENT "$label cannot be empty" true "Use a simple provenance value."
  [[ "${#value}" -le 64 ]] || ws_fail INVALID_ARGUMENT "$label must be at most 64 characters" true "Use a shorter provenance value."
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || ws_fail INVALID_ARGUMENT "$label must be single-line" true "Use [A-Za-z0-9._:-] only."
  [[ "$value" =~ ^[A-Za-z0-9._:-]+$ ]] || ws_fail INVALID_ARGUMENT "$label contains unsupported characters" true "Use [A-Za-z0-9._:-] only."
  printf '%s\n' "$value"
}

ws_reject_authority_flag() {
  case "$1" in
    --status|--authority|--canonical|--promotion-status|--author-actor|--author-role)
      ws_fail INVALID_ARGUMENT "authority-looking option is not accepted by spine commands: $1" true "Remove authority/status options; Agently assigns status and authority."
      ;;
  esac
}

ws_lstat_guard() {
  local file="$1"
  [[ -e "$file" ]] || ws_fail PAYLOAD_NOT_FILE "payload file does not exist: $file" true "Pass --file with a regular file path."
  [[ ! -L "$file" ]] || ws_fail PAYLOAD_SYMLINK_REJECTED "payload symlink rejected: $file" true "Pass a regular file, not a symlink."
  [[ -f "$file" ]] || ws_fail PAYLOAD_NOT_FILE "payload is not a regular file: $file" true "Pass --file with a regular file path."
  [[ ! -d "$file" ]] || ws_fail PAYLOAD_NOT_FILE "payload is a directory: $file" true "Pass --file with a regular file path."
}

ws_size_guard() {
  local file="$1" max="$2" bytes
  bytes="$(byte_count "$file")"
  [[ "$bytes" -le "$max" ]] || ws_fail PAYLOAD_TOO_LARGE "payload exceeds ws.spine.max_payload_bytes ($bytes > $max)" true "Use a smaller payload file."
}

ws_path_sanity() {
  local file="$1" ws_dir="$2" root resolved ws_root
  root="$(realpath -m "$(dirname "$ws_dir")/../..")"
  resolved="$(realpath -m "$file")"
  ws_root="$(realpath -m "$ws_dir")"
  case "$resolved" in
    "$ws_root"|"$ws_root"/*) ws_fail INVALID_ARGUMENT "payload source may not be inside the target spine workstream" true "Use a payload outside .agently/workstreams/$(basename "$ws_dir")." ;;
    "$root/.git"|"$root/.git"/*) ws_fail INVALID_ARGUMENT "payload source may not be inside .git" true "Use a regular project file." ;;
  esac
}

ws_quarantine_frontmatter() {
  local raw="$1" body_out="$2"
  local first
  first="$(sed -n '1p' "$raw")"
  if [[ "$first" == "---" ]] && awk 'NR > 1 && $0 == "---" { found=1; exit } END { exit(found ? 0 : 1) }' "$raw"; then
    awk '
      NR == 1 { in_fm = 1; next }
      in_fm && $0 == "---" { in_fm = 0; next }
      !in_fm { print }
    ' "$raw" > "$body_out"
    printf 'true\n'
  else
    cp -- "$raw" "$body_out"
    printf 'false\n'
  fi
}

spine_render_candidate_packet() {
  local out="$1" alias="$2" ws_id="$3" type="$4" created_at="$5" actor="$6" via="$7" raw_rel="$8" candidate_rel="$9" raw_sha="${10}" content_sha="${11}" quarantined="${12}" body_file="${13}"
  local code title n
  validate_alias "$alias"
  code="$SPINE_ALIAS_CODE"
  n="$SPINE_ALIAS_NUM"
  title="$(titleize "$(ws_type_for_code "$code")")"
  {
    printf '%s\n' '---'
    printf 'agently_packet_schema: 1\n'
    printf 'alias: %s\n' "$alias"
    printf 'absolute_name: Agently / Workstream %s / %s Candidate %s\n' "$ws_id" "$title" "$n"
    printf 'workstream_id: %s\n' "$ws_id"
    printf 'type: %s\n' "$type"
    printf 'status: candidate\n'
    printf 'authority: candidate_only\n'
    printf 'generated_by: agently\n'
    printf 'created_at: %s\n' "$created_at"
    printf 'actor: %s\n' "$actor"
    printf 'via: %s\n' "$via"
    printf 'raw_path: %s\n' "$raw_rel"
    printf 'candidate_path: %s\n' "$candidate_rel"
    printf 'raw_sha256: "%s"\n' "$raw_sha"
    printf 'content_sha256: "%s"\n' "$content_sha"
    printf 'quarantined_front_matter: %s\n' "$quarantined"
    printf 'promotion_status: not_proposed\n'
    printf '%s\n' '---'
    cat "$body_file"
  } > "$out"
}

spine_extract_packet_body() {
  local packet="$1" body_out="$2"
  local first
  first="$(sed -n '1p' "$packet")"
  if [[ "$first" == "---" ]] && awk 'NR > 1 && $0 == "---" { found=1; exit } END { exit(found ? 0 : 1) }' "$packet"; then
    awk '
      NR == 1 { in_fm = 1; next }
      in_fm && $0 == "---" { in_fm = 0; next }
      !in_fm { print }
    ' "$packet" > "$body_out"
  else
    cp -- "$packet" "$body_out"
  fi
}

spine_render_canonical_packet() {
  local out="$1" alias="$2" ws_id="$3" type="$4" promoted_at="$5" actor="$6" via="$7" canonical_rel="$8" event_id="$9" body_file="${10}"
  {
    printf '%s\n' '---'
    printf 'agently_packet_schema: 1\n'
    printf 'alias: %s\n' "$alias"
    printf 'absolute_name: Agently / Workstream %s / Canonical %s\n' "$ws_id" "$alias"
    printf 'workstream_id: %s\n' "$ws_id"
    printf 'type: %s\n' "$type"
    printf 'status: canonical\n'
    printf 'authority: promoted_canonical\n'
    printf 'generated_by: agently\n'
    printf 'promoted_at: %s\n' "$promoted_at"
    printf 'actor: %s\n' "$actor"
    printf 'via: %s\n' "$via"
    printf 'canonical_path: %s\n' "$canonical_rel"
    printf 'promotion_event_id: %s\n' "$event_id"
    printf '%s\n' '---'
    cat "$body_file"
  } > "$out"
}
