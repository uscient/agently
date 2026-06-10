#!/usr/bin/env bash
# shellcheck disable=SC2016

ws_spine_json_flag() {
  case "$1" in
    --json)
      AGENTLY_WS_JSON=1
      export AGENTLY_WS_JSON
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

ws_spine_detect_json_arg() {
  AGENTLY_WS_JSON=0
  local arg
  for arg in "$@"; do
    if [[ "$arg" == "--json" ]]; then
      AGENTLY_WS_JSON=1
      break
    fi
  done
  export AGENTLY_WS_JSON
}

ws_spine_human_or_json_help() {
  local usage="$1"
  if ws_json_enabled; then
    ws_fail INVALID_ARGUMENT "$usage" true "$usage"
  fi
  printf '%s\n' "$usage" >&2
}

ws_init_spine() {
  ws_spine_detect_json_arg "$@"
  local ws_id="" absolute_name="" root ws_dir
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) AGENTLY_WS_JSON=1; export AGENTLY_WS_JSON; shift ;;
      --absolute-name)
        [[ $# -ge 2 ]] || ws_fail INVALID_ARGUMENT "--absolute-name requires a value" true "Pass --absolute-name VALUE."
        absolute_name="$2"; shift 2 ;;
      -h|--help)
        ws_spine_human_or_json_help "usage: agently ws init <WS_ID> [--json]"
        return 0 ;;
      --*) ws_fail INVALID_ARGUMENT "unknown ws init option: $1" true "Run agently ws init <WS_ID> [--json]." ;;
      *)
        [[ -z "$ws_id" ]] || ws_fail INVALID_ARGUMENT "ws init takes exactly one WS_ID" true "Run agently ws init <WS_ID> [--json]."
        ws_id="$1"; shift ;;
    esac
  done
  ws_spine_preflight
  [[ -n "$ws_id" ]] || ws_fail INVALID_ARGUMENT "usage: agently ws init <WS_ID> [--json]" true "Pass a spine WS_ID."
  validate_spine_ws_id "$ws_id"
  root="$(spine_project_root)"
  ws_dir="$(spine_ws_dir_for_root "$root" "$ws_id")"
  [[ -n "$absolute_name" ]] || absolute_name="Agently / Workstream $ws_id"
  mkdir -p "$ws_dir"
  : > "$(spine_lock_path "$ws_dir")"
  with_ws_lock "$ws_dir" -- _ws_init_spine_locked "$root" "$ws_dir" "$ws_id" "$absolute_name"
}

_ws_init_dir_is_empty_or_lock_only() {
  local ws_dir="$1" child base count=0
  shopt -s nullglob dotglob
  for child in "$ws_dir"/*; do
    base="$(basename "$child")"
    [[ "$base" == ".manifest.lock" ]] && continue
    count=$((count + 1))
  done
  shopt -u nullglob dotglob
  [[ "$count" -eq 0 ]]
}

_ws_init_spine_locked() {
  local root="$1" ws_dir="$2" ws_id="$3" absolute_name="$4" manifest ts event line tmp
  manifest="$(spine_manifest_path "$ws_dir")"
  if [[ -f "$manifest" ]]; then
    if jq -e . "$manifest" >/dev/null 2>&1; then
      ws_fail ALREADY_EXISTS "spine workstream already exists: $ws_id" true "Run agently ws status $ws_id."
    fi
    ws_fail MANIFEST_INVALID "existing manifest is invalid for workstream: $ws_id" false "Inspect $manifest."
  fi
  if ! _ws_init_dir_is_empty_or_lock_only "$ws_dir"; then
    ws_fail WORKSTREAM_LAYOUT_CONFLICT "workstream directory is not an empty spine layout: $ws_id" false "Choose a new uppercase WS_ID; legacy workstreams are not converted."
  fi
  mkdir -p "$ws_dir/raw" "$ws_dir/candidates" "$ws_dir/proposed" "$ws_dir/canonical" "$ws_dir/spool"
  ts="$(now)"
  tmp="$(mktemp "$ws_dir/.manifest.XXXXXX.tmp")"
  trap 'rm -f "$tmp"' EXIT INT TERM
  jq -n \
    --arg ws_id "$ws_id" \
    --arg absolute_name "$absolute_name" \
    --arg ts "$ts" \
    '{
      schema_version: 1,
      ws_id: $ws_id,
      absolute_name: $absolute_name,
      state: "open",
      created_at: $ts,
      updated_at: $ts,
      version: 1,
      event_seq: 1,
      alias_counters: {SCOPE:0, REQ:0, PLN:0, REV:0, SYN:0, AUD:0, HND:0},
      candidates: {},
      proposed: null,
      canonical: {}
    }' > "$tmp"
  jq -e . "$tmp" >/dev/null || ws_fail MANIFEST_INVALID "failed to initialize manifest" false "Inspect filesystem permissions."
  mv "$tmp" "$manifest" || ws_fail MANIFEST_INVALID "failed to write manifest" false "Inspect filesystem permissions."
  trap - EXIT INT TERM
  : > "$(spine_events_path "$ws_dir")"
  event="$(spine_event_id_for_seq 1)"
  line="$(spine_event_json "$event" workstream_initialized "$ws_id" "$ts" human_operator cli '{}')"
  events_append "$ws_dir" "$line"
  if ws_json_enabled; then
    ws_emit ok true command ws_init ws_id "$ws_id" state open message "Workstream initialized."
  else
    printf 'Workstream initialized: %s\n' "$ws_id"
  fi
}

ws_status_spine() {
  ws_spine_detect_json_arg "$@"
  local ws_id="" root ws_dir json
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) AGENTLY_WS_JSON=1; export AGENTLY_WS_JSON; shift ;;
      --*) ws_fail INVALID_ARGUMENT "unknown ws status option: $1" true "Run agently ws status <WS_ID> [--json]." ;;
      *) [[ -z "$ws_id" ]] || ws_fail INVALID_ARGUMENT "ws status takes one WS_ID" true "Run agently ws status <WS_ID> [--json]."; ws_id="$1"; shift ;;
    esac
  done
  ws_spine_preflight
  [[ -n "$ws_id" ]] || ws_fail INVALID_ARGUMENT "usage: agently ws status <WS_ID> [--json]" true "Pass a spine WS_ID."
  validate_spine_ws_id "$ws_id"
  root="$(spine_project_root)"
  ws_dir="$(spine_ws_dir_existing "$root" "$ws_id")"
  spine_manifest_validate_file "$(spine_manifest_path "$ws_dir")"
  if ws_json_enabled; then
    json="$(jq -c '{ok:true,command:"ws_status",ws_id,state,proposed,version,event_seq,candidate_count:(.candidates|length),canonical_count:(.canonical|length)}' "$(spine_manifest_path "$ws_dir")")"
    ws_emit_json "$json"
  else
    jq -r '"\(.ws_id) — \(.absolute_name)\nState: \(.state)\nProposed: \(.proposed // "none")\nCandidates: \(.candidates | length)\nCanonical: \(.canonical | length)"' "$(spine_manifest_path "$ws_dir")"
  fi
}

ws_summary_spine() {
  ws_spine_detect_json_arg "$@"
  local ws_id="" root ws_dir json
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) AGENTLY_WS_JSON=1; export AGENTLY_WS_JSON; shift ;;
      --*) ws_fail INVALID_ARGUMENT "unknown ws summary option: $1" true "Run agently ws summary <WS_ID> [--json]." ;;
      *) [[ -z "$ws_id" ]] || ws_fail INVALID_ARGUMENT "ws summary takes one WS_ID" true "Run agently ws summary <WS_ID> [--json]."; ws_id="$1"; shift ;;
    esac
  done
  ws_spine_preflight
  [[ -n "$ws_id" ]] || ws_fail INVALID_ARGUMENT "usage: agently ws summary <WS_ID> [--json]" true "Pass a spine WS_ID."
  validate_spine_ws_id "$ws_id"
  root="$(spine_project_root)"
  ws_dir="$(spine_ws_dir_existing "$root" "$ws_id")"
  spine_manifest_validate_file "$(spine_manifest_path "$ws_dir")"
  if ws_json_enabled; then
    json="$(jq -c '{ok:true,command:"ws_summary",ws_id,absolute_name,state,proposed,candidates:(.candidates|to_entries|map({alias:.key,type:.value.type,status:.value.status})),canonical:(.canonical|to_entries|map({alias:.key,type:.value.type,canonical_path:.value.canonical_path}))}' "$(spine_manifest_path "$ws_dir")")"
    ws_emit_json "$json"
  else
    jq -r '
      "\(.ws_id) — \(.absolute_name)\nState: \(.state)\nCandidates:" ,
      (if (.candidates|length)==0 then "  none" else (.candidates|to_entries[] | "  \(.key)  \(.value.type)  \(.value.status)") end),
      "Next: propose an artifact, or continue candidate generation"
    ' "$(spine_manifest_path "$ws_dir")"
  fi
}

ws_show_spine() {
  ws_spine_detect_json_arg "$@"
  local alias="" root ws_dir ws_id path json
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) AGENTLY_WS_JSON=1; export AGENTLY_WS_JSON; shift ;;
      --*) ws_fail INVALID_ARGUMENT "unknown ws show option: $1" true "Run agently ws show <ALIAS> [--json]." ;;
      *) [[ -z "$alias" ]] || ws_fail INVALID_ARGUMENT "ws show takes one alias" true "Run agently ws show <ALIAS> [--json]."; alias="$1"; shift ;;
    esac
  done
  ws_spine_preflight
  [[ -n "$alias" ]] || ws_fail INVALID_ARGUMENT "usage: agently ws show <ALIAS> [--json]" true "Pass a spine alias."
  validate_alias "$alias"
  ws_type_for_code "$SPINE_ALIAS_CODE" >/dev/null || ws_fail ALIAS_NOT_FOUND "unsupported spine alias code: $SPINE_ALIAS_CODE" true "Use a Phase 1 alias type."
  ws_id="$SPINE_ALIAS_WS_ID"
  root="$(spine_project_root)"
  ws_dir="$(spine_ws_dir_existing "$root" "$ws_id")"
  spine_manifest_validate_file "$(spine_manifest_path "$ws_dir")"
  jq -e --arg a "$alias" '.candidates[$a]' "$(spine_manifest_path "$ws_dir")" >/dev/null || ws_fail ALIAS_NOT_FOUND "spine alias not found: $alias" true "Run agently ws summary $ws_id."
  path="$(jq -r --arg a "$alias" '
    if .canonical[$a] then .canonical[$a].canonical_path
    elif .candidates[$a].proposed_path then .candidates[$a].proposed_path
    else .candidates[$a].candidate_path end
  ' "$(spine_manifest_path "$ws_dir")")"
  ws_assert_under_ws_root "$ws_dir" "$path"
  [[ -f "$ws_dir/$path" ]] || ws_fail PAYLOAD_NOT_FILE "referenced artifact file is missing: $path" false "Run agently ws doctor $ws_id --json."
  if ws_json_enabled; then
    json="$(jq -c --arg a "$alias" --arg path "$path" --rawfile content "$ws_dir/$path" '{ok:true,command:"ws_show",ws_id:.ws_id,alias:$a,path:$path,artifact:.candidates[$a],canonical:.canonical[$a],content:$content}' "$(spine_manifest_path "$ws_dir")")"
    ws_emit_json "$json"
  else
    cat "$ws_dir/$path"
  fi
}

ws_ingest_spine() {
  ws_spine_detect_json_arg "$@"
  local ws_id="" type="" file="" actor="human_operator" via="cli" root ws_dir
  while [[ $# -gt 0 ]]; do
    ws_reject_authority_flag "$1"
    case "$1" in
      --json) AGENTLY_WS_JSON=1; export AGENTLY_WS_JSON; shift ;;
      --type) [[ $# -ge 2 ]] || ws_fail INVALID_ARGUMENT "--type requires a value" true "Pass --type TYPE."; type="$2"; shift 2 ;;
      --file) [[ $# -ge 2 ]] || ws_fail INVALID_ARGUMENT "--file requires a value" true "Pass --file PATH."; file="$2"; shift 2 ;;
      --actor) [[ $# -ge 2 ]] || ws_fail INVALID_ARGUMENT "--actor requires a value" true "Pass --actor VALUE."; actor="$2"; shift 2 ;;
      --via) [[ $# -ge 2 ]] || ws_fail INVALID_ARGUMENT "--via requires a value" true "Pass --via VALUE."; via="$2"; shift 2 ;;
      --*) ws_fail INVALID_ARGUMENT "unknown ws ingest option: $1" true "Run agently ws ingest <WS_ID> --type <TYPE> --file <PATH> [--json]." ;;
      *) [[ -z "$ws_id" ]] || ws_fail INVALID_ARGUMENT "ws ingest takes one WS_ID" true "Run agently ws ingest <WS_ID> --type <TYPE> --file <PATH> [--json]."; ws_id="$1"; shift ;;
    esac
  done
  ws_spine_preflight
  [[ -n "$ws_id" && -n "$type" && -n "$file" ]] || ws_fail INVALID_ARGUMENT "usage: agently ws ingest <WS_ID> --type <TYPE> --file <PATH> [--json]" true "Pass WS_ID, --type, and --file."
  validate_spine_ws_id "$ws_id"
  ws_alias_code_for_type "$type" >/dev/null
  actor="$(ws_sanitize_provenance actor "$actor")"
  via="$(ws_sanitize_provenance via "$via")"
  root="$(spine_project_root)"
  ws_dir="$(spine_ws_dir_existing "$root" "$ws_id")"
  with_ws_lock "$ws_dir" -- _ws_ingest_spine_locked "$root" "$ws_dir" "$ws_id" "$type" "$file" "$actor" "$via"
}

_ws_ingest_spine_locked() {
  local root="$1" ws_dir="$2" ws_id="$3" type="$4" file="$5" actor="$6" via="$7"
  local manifest code next alias raw_rel candidate_rel raw_path candidate_path body_tmp packet_tmp max ts
  local raw_sha content_sha packet_sha quarantined event_seq event_id event_line artifact_json extra
  manifest="$(spine_manifest_path "$ws_dir")"
  spine_manifest_validate_file "$manifest"
  if [[ "$(jq -r '.state' "$manifest")" != "open" ]]; then
    ws_fail WORKSTREAM_ESCROWED "This workstream is awaiting promotion or rejection." true "agently ws status $ws_id --json" "agently ws promote $(jq -r '.proposed // empty' "$manifest")" "agently ws reject $(jq -r '.proposed // empty' "$manifest")"
  fi
  code="$(ws_alias_code_for_type "$type")"
  next="$(jq -r --arg code "$code" '.alias_counters[$code] + 1' "$manifest")"
  alias="$ws_id-$code$next"
  raw_rel="$(ws_artifact_relpath raw "$alias")"
  candidate_rel="$(ws_artifact_relpath candidate "$alias")"
  ws_assert_under_ws_root "$ws_dir" "$raw_rel"
  ws_assert_under_ws_root "$ws_dir" "$candidate_rel"
  raw_path="$ws_dir/$raw_rel"
  candidate_path="$ws_dir/$candidate_rel"
  ws_lstat_guard "$file"
  max="$(ws_spine_config_get "$root" max_payload_bytes)"
  ws_size_guard "$file" "$max"
  ws_path_sanity "$file" "$ws_dir"
  cp -- "$file" "$raw_path" || ws_fail PAYLOAD_NOT_FILE "failed to copy payload into custody" false "Inspect payload permissions."
  raw_sha="$(spine_sha256 "$raw_path")"
  body_tmp="$(mktemp "$ws_dir/spool/$alias.body.XXXXXX.tmp")"
  packet_tmp="$(mktemp "$ws_dir/spool/$alias.packet.XXXXXX.tmp")"
  quarantined="$(ws_quarantine_frontmatter "$raw_path" "$body_tmp")"
  content_sha="$(spine_sha256 "$body_tmp")"
  ts="$(now)"
  spine_render_candidate_packet "$packet_tmp" "$alias" "$ws_id" "$type" "$ts" "$actor" "$via" "$raw_rel" "$candidate_rel" "$raw_sha" "$content_sha" "$quarantined" "$body_tmp"
  mv "$packet_tmp" "$candidate_path" || ws_fail PAYLOAD_NOT_FILE "failed to write candidate packet" false "Inspect filesystem permissions."
  rm -f "$body_tmp"
  packet_sha="$(spine_sha256 "$candidate_path")"
  event_seq="$(jq -r '.event_seq + 1' "$manifest")"
  event_id="$(spine_event_id_for_seq "$event_seq")"
  artifact_json="$(jq -cn \
    --arg type "$type" \
    --arg raw_path "$raw_rel" \
    --arg candidate_path "$candidate_rel" \
    --arg raw_sha "$raw_sha" \
    --arg content_sha "$content_sha" \
    --arg packet_sha "$packet_sha" \
    --argjson quarantined "$quarantined" \
    --arg created_at "$ts" \
    --arg actor "$actor" \
    --arg via "$via" \
    '{type:$type,status:"candidate",raw_path:$raw_path,candidate_path:$candidate_path,raw_sha256:$raw_sha,content_sha256:$content_sha,packet_sha256:$packet_sha,quarantined_front_matter:$quarantined,created_at:$created_at,actor:$actor,via:$via}')"
  spine_manifest_update "$ws_dir" \
    --arg ts "$ts" \
    --arg code "$code" \
    --arg alias "$alias" \
    --argjson artifact "$artifact_json" \
    '.version += 1
      | .event_seq += 1
      | .updated_at = $ts
      | .alias_counters[$code] += 1
      | .candidates[$alias] = $artifact'
  extra="$(jq -cn \
    --arg alias "$alias" \
    --arg type "$type" \
    --arg raw_sha "$raw_sha" \
    --arg content_sha "$content_sha" \
    --arg packet_sha "$packet_sha" \
    --argjson quarantined "$quarantined" \
    '{alias:$alias,type:$type,raw_sha256:$raw_sha,content_sha256:$content_sha,packet_sha256:$packet_sha,quarantined_front_matter:$quarantined}')"
  event_line="$(spine_event_json "$event_id" candidate_ingested "$ws_id" "$ts" "$actor" "$via" "$extra")"
  events_append "$ws_dir" "$event_line"
  if ws_json_enabled; then
    ws_emit ok true command ws_ingest ws_id "$ws_id" alias "$alias" type "$type" status candidate raw_sha256 "$raw_sha" content_sha256 "$content_sha" packet_sha256 "$packet_sha" quarantined_front_matter "$quarantined"
  else
    printf 'Candidate ingested: %s\n' "$alias"
  fi
}

ws_propose_spine() {
  ws_spine_detect_json_arg "$@"
  local alias="" root ws_dir ws_id
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) AGENTLY_WS_JSON=1; export AGENTLY_WS_JSON; shift ;;
      --*) ws_fail INVALID_ARGUMENT "unknown ws propose option: $1" true "Run agently ws propose <ALIAS> [--json]." ;;
      *) [[ -z "$alias" ]] || ws_fail INVALID_ARGUMENT "ws propose takes one alias" true "Run agently ws propose <ALIAS> [--json]."; alias="$1"; shift ;;
    esac
  done
  ws_spine_preflight
  [[ -n "$alias" ]] || ws_fail INVALID_ARGUMENT "usage: agently ws propose <ALIAS> [--json]" true "Pass a spine alias."
  validate_alias "$alias"
  ws_id="$SPINE_ALIAS_WS_ID"
  root="$(spine_project_root)"
  ws_dir="$(spine_ws_dir_existing "$root" "$ws_id")"
  with_ws_lock "$ws_dir" -- _ws_propose_spine_locked "$ws_dir" "$ws_id" "$alias"
}

_ws_propose_spine_locked() {
  local ws_dir="$1" ws_id="$2" alias="$3" manifest status candidate_rel proposed_rel ts event_seq event_id event_line extra
  manifest="$(spine_manifest_path "$ws_dir")"
  spine_manifest_validate_file "$manifest"
  if [[ "$(jq -r '.state' "$manifest")" != "open" ]]; then
    ws_fail WORKSTREAM_ESCROWED "This workstream is awaiting promotion or rejection." true "agently ws status $ws_id --json" "agently ws promote $(jq -r '.proposed // empty' "$manifest")" "agently ws reject $(jq -r '.proposed // empty' "$manifest")"
  fi
  status="$(jq -r --arg a "$alias" '.candidates[$a].status // empty' "$manifest")"
  [[ -n "$status" ]] || ws_fail ALIAS_NOT_FOUND "spine alias not found: $alias" true "Run agently ws summary $ws_id."
  [[ "$status" == "candidate" ]] || ws_fail NOT_PROPOSED "artifact is not a candidate: $alias" true "Ingest a revised candidate."
  candidate_rel="$(jq -r --arg a "$alias" '.candidates[$a].candidate_path' "$manifest")"
  proposed_rel="$(ws_artifact_relpath proposed "$alias")"
  ws_assert_under_ws_root "$ws_dir" "$candidate_rel"
  ws_assert_under_ws_root "$ws_dir" "$proposed_rel"
  [[ -f "$ws_dir/$candidate_rel" ]] || ws_fail PAYLOAD_NOT_FILE "candidate file missing: $candidate_rel" false "Run agently ws doctor $ws_id --json."
  cp -- "$ws_dir/$candidate_rel" "$ws_dir/$proposed_rel" || ws_fail PAYLOAD_NOT_FILE "failed to copy proposed evidence" false "Inspect filesystem permissions."
  ts="$(now)"
  event_seq="$(jq -r '.event_seq + 1' "$manifest")"
  event_id="$(spine_event_id_for_seq "$event_seq")"
  spine_manifest_update "$ws_dir" \
    --arg ts "$ts" \
    --arg alias "$alias" \
    --arg proposed_path "$proposed_rel" \
    '.version += 1
      | .event_seq += 1
      | .updated_at = $ts
      | .state = "escrowed"
      | .proposed = $alias
      | .candidates[$alias].status = "proposed"
      | .candidates[$alias].proposed_path = $proposed_path'
  extra="$(jq -cn --arg alias "$alias" '{alias:$alias}')"
  event_line="$(spine_event_json "$event_id" candidate_proposed "$ws_id" "$ts" human_operator cli "$extra")"
  events_append "$ws_dir" "$event_line"
  if ws_json_enabled; then
    ws_emit ok true command ws_propose ws_id "$ws_id" alias "$alias" state escrowed status proposed
  else
    printf 'Candidate proposed: %s\n' "$alias"
  fi
}

ws_confirm_gate() {
  local alias="$1" kind="$2" timeout="$3" typed="" tty_fd=201
  if ! { true <> /dev/tty; } 2>/dev/null; then
    case "$kind" in
      promote) ws_fail PROMOTION_REQUIRES_INTERACTIVE_PATH "Promotion requires an interactive /dev/tty path; state unchanged." true "Run agently ws promote $alias from an interactive terminal." ;;
      reject) ws_fail REJECTION_REQUIRES_INTERACTIVE_PATH "Rejection requires an interactive /dev/tty path; state unchanged." true "Run agently ws reject $alias from an interactive terminal." ;;
    esac
  fi
  eval "exec ${tty_fd}<>/dev/tty"
  printf 'Type %s to %s: ' "$alias" "$kind" >&"$tty_fd"
  if ! IFS= read -r -t "$timeout" typed <&"$tty_fd"; then
    eval "exec ${tty_fd}>&-"
    case "$kind" in
      promote) ws_fail PROMOTION_CONFIRMATION_TIMEOUT "Promotion confirmation timed out after ${timeout}s; state unchanged." true "agently ws promote $alias" ;;
      reject) ws_fail REJECTION_CONFIRMATION_TIMEOUT "Rejection confirmation timed out after ${timeout}s; state unchanged." true "agently ws reject $alias" ;;
    esac
  fi
  printf '\n' >&"$tty_fd"
  eval "exec ${tty_fd}>&-"
  if [[ "$typed" != "$alias" ]]; then
    case "$kind" in
      promote) ws_fail PROMOTION_NOT_CONFIRMED "Promotion was not confirmed; state unchanged." true "Retry and type the full alias." ;;
      reject) ws_fail REJECTION_NOT_CONFIRMED "Rejection was not confirmed; state unchanged." true "Retry and type the full alias." ;;
    esac
  fi
}

_ws_require_current_proposed() {
  local manifest="$1" ws_id="$2" alias="$3" op="$4" state proposed status
  state="$(jq -r '.state' "$manifest")"
  proposed="$(jq -r '.proposed // empty' "$manifest")"
  status="$(jq -r --arg a "$alias" '.candidates[$a].status // empty' "$manifest")"
  if [[ "$state" != "escrowed" || -z "$proposed" ]]; then
    ws_fail NOT_PROPOSED "no candidate is currently proposed for workstream: $ws_id" true "Run agently ws status $ws_id --json."
  fi
  if [[ "$proposed" != "$alias" ]]; then
    ws_fail WORKSTREAM_ESCROWED "This workstream is escrowed for a different alias: $proposed" true "agently ws $op $proposed"
  fi
  [[ "$status" == "proposed" ]] || ws_fail STATE_INCOHERENT "proposed alias is not in proposed status: $alias" false "Run agently ws doctor $ws_id --json."
}

ws_reject_spine() {
  ws_spine_detect_json_arg "$@"
  local alias="" reason="operator_rejected" root ws_dir ws_id
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) AGENTLY_WS_JSON=1; export AGENTLY_WS_JSON; shift ;;
      --reason) [[ $# -ge 2 ]] || ws_fail INVALID_ARGUMENT "--reason requires a value" true "Pass --reason VALUE."; reason="$2"; shift 2 ;;
      --*) ws_fail INVALID_ARGUMENT "unknown ws reject option: $1" true "Run agently ws reject <ALIAS> [--json]." ;;
      *) [[ -z "$alias" ]] || ws_fail INVALID_ARGUMENT "ws reject takes one alias" true "Run agently ws reject <ALIAS> [--json]."; alias="$1"; shift ;;
    esac
  done
  ws_spine_preflight
  [[ -n "$alias" ]] || ws_fail INVALID_ARGUMENT "usage: agently ws reject <ALIAS> [--json]" true "Pass a spine alias."
  validate_alias "$alias"
  ws_id="$SPINE_ALIAS_WS_ID"
  root="$(spine_project_root)"
  ws_dir="$(spine_ws_dir_existing "$root" "$ws_id")"
  with_ws_lock "$ws_dir" -- _ws_reject_spine_locked "$root" "$ws_dir" "$ws_id" "$alias" "$reason"
}

_ws_reject_spine_locked() {
  local root="$1" ws_dir="$2" ws_id="$3" alias="$4" reason="$5" manifest timeout ts event_seq event_id extra event_line
  manifest="$(spine_manifest_path "$ws_dir")"
  spine_manifest_validate_file "$manifest"
  _ws_require_current_proposed "$manifest" "$ws_id" "$alias" reject
  timeout="$(ws_spine_config_get "$root" confirm_timeout_seconds)"
  ws_confirm_gate "$alias" reject "$timeout"
  spine_manifest_validate_file "$manifest"
  _ws_require_current_proposed "$manifest" "$ws_id" "$alias" reject
  ts="$(now)"
  event_seq="$(jq -r '.event_seq + 1' "$manifest")"
  event_id="$(spine_event_id_for_seq "$event_seq")"
  spine_manifest_update "$ws_dir" \
    --arg ts "$ts" \
    --arg alias "$alias" \
    --arg reason "$reason" \
    '.version += 1
      | .event_seq += 1
      | .updated_at = $ts
      | .state = "open"
      | .proposed = null
      | .candidates[$alias].status = "rejected"
      | .candidates[$alias].rejected_at = $ts
      | .candidates[$alias].reject_reason = $reason'
  extra="$(jq -cn --arg alias "$alias" --arg reason "$reason" '{alias:$alias,reject_reason:$reason}')"
  event_line="$(spine_event_json "$event_id" candidate_rejected "$ws_id" "$ts" human_operator cli "$extra")"
  events_append "$ws_dir" "$event_line"
  if ws_json_enabled; then
    ws_emit ok true command ws_reject ws_id "$ws_id" alias "$alias" state open status rejected
  else
    printf 'Candidate rejected: %s\n' "$alias"
  fi
}

ws_promote_spine() {
  ws_spine_detect_json_arg "$@"
  local alias="" root ws_dir ws_id
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) AGENTLY_WS_JSON=1; export AGENTLY_WS_JSON; shift ;;
      --*) ws_fail INVALID_ARGUMENT "unknown ws promote option: $1" true "Run agently ws promote <ALIAS> [--json]." ;;
      *) [[ -z "$alias" ]] || ws_fail INVALID_ARGUMENT "ws promote takes one alias" true "Run agently ws promote <ALIAS> [--json]."; alias="$1"; shift ;;
    esac
  done
  ws_spine_preflight
  [[ -n "$alias" ]] || ws_fail INVALID_ARGUMENT "usage: agently ws promote <ALIAS> [--json]" true "Pass a spine alias."
  validate_alias "$alias"
  ws_id="$SPINE_ALIAS_WS_ID"
  root="$(spine_project_root)"
  ws_dir="$(spine_ws_dir_existing "$root" "$ws_id")"
  with_ws_lock "$ws_dir" -- _ws_promote_spine_locked "$root" "$ws_dir" "$ws_id" "$alias"
}

_ws_promote_spine_locked() {
  local root="$1" ws_dir="$2" ws_id="$3" alias="$4" manifest timeout type proposed_rel canonical_rel body_tmp packet_tmp ts event_seq event_id canonical_sha extra event_line canonical_json
  manifest="$(spine_manifest_path "$ws_dir")"
  spine_manifest_validate_file "$manifest"
  _ws_require_current_proposed "$manifest" "$ws_id" "$alias" promote
  timeout="$(ws_spine_config_get "$root" confirm_timeout_seconds)"
  ws_confirm_gate "$alias" promote "$timeout"
  spine_manifest_validate_file "$manifest"
  _ws_require_current_proposed "$manifest" "$ws_id" "$alias" promote
  type="$(jq -r --arg a "$alias" '.candidates[$a].type' "$manifest")"
  proposed_rel="$(jq -r --arg a "$alias" '.candidates[$a].proposed_path' "$manifest")"
  canonical_rel="$(ws_artifact_relpath canonical "$alias")"
  ws_assert_under_ws_root "$ws_dir" "$proposed_rel"
  ws_assert_under_ws_root "$ws_dir" "$canonical_rel"
  [[ -f "$ws_dir/$proposed_rel" ]] || ws_fail PAYLOAD_NOT_FILE "proposed evidence missing: $proposed_rel" false "Run agently ws doctor $ws_id --json."
  body_tmp="$(mktemp "$ws_dir/spool/$alias.canonical-body.XXXXXX.tmp")"
  packet_tmp="$(mktemp "$ws_dir/spool/$alias.canonical.XXXXXX.tmp")"
  spine_extract_packet_body "$ws_dir/$proposed_rel" "$body_tmp"
  ts="$(now)"
  event_seq="$(jq -r '.event_seq + 1' "$manifest")"
  event_id="$(spine_event_id_for_seq "$event_seq")"
  spine_render_canonical_packet "$packet_tmp" "$alias" "$ws_id" "$type" "$ts" human_operator cli "$canonical_rel" "$event_id" "$body_tmp"
  mv "$packet_tmp" "$ws_dir/$canonical_rel" || ws_fail PAYLOAD_NOT_FILE "failed to write canonical packet" false "Inspect filesystem permissions."
  rm -f "$body_tmp"
  canonical_sha="$(spine_sha256 "$ws_dir/$canonical_rel")"
  canonical_json="$(jq -cn \
    --arg type "$type" \
    --arg canonical_path "$canonical_rel" \
    --arg canonical_sha "$canonical_sha" \
    --arg alias "$alias" \
    --arg event_id "$event_id" \
    --arg promoted_at "$ts" \
    '{type:$type,canonical_path:$canonical_path,canonical_sha256:$canonical_sha,promoted_from:$alias,promotion_event_id:$event_id,promoted_at:$promoted_at,actor:"human_operator",via:"cli"}')"
  spine_manifest_update "$ws_dir" \
    --arg ts "$ts" \
    --arg alias "$alias" \
    --arg canonical_path "$canonical_rel" \
    --arg canonical_sha "$canonical_sha" \
    --argjson canonical "$canonical_json" \
    '.version += 1
      | .event_seq += 1
      | .updated_at = $ts
      | .state = "open"
      | .proposed = null
      | .candidates[$alias].status = "promoted"
      | .candidates[$alias].canonical_path = $canonical_path
      | .candidates[$alias].canonical_sha256 = $canonical_sha
      | .canonical[$alias] = $canonical'
  extra="$(jq -cn --arg alias "$alias" --arg canonical_path "$canonical_rel" --arg canonical_sha "$canonical_sha" '{alias:$alias,canonical_path:$canonical_path,canonical_sha256:$canonical_sha}')"
  event_line="$(spine_event_json "$event_id" candidate_promoted "$ws_id" "$ts" human_operator cli "$extra")"
  events_append "$ws_dir" "$event_line"
  if ws_json_enabled; then
    ws_emit ok true command ws_promote ws_id "$ws_id" alias "$alias" status promoted canonical_path "$canonical_rel" canonical_sha256 "$canonical_sha"
  else
    printf 'Candidate promoted: %s\n' "$alias"
  fi
}

ws_doctor_spine() {
  ws_spine_detect_json_arg "$@"
  local ws_id="" verify=0 root ws_dir result ok errors_count first_code checks_json errors_json warnings_json
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) AGENTLY_WS_JSON=1; export AGENTLY_WS_JSON; shift ;;
      --verify-hashes) verify=1; shift ;;
      --*) ws_fail INVALID_ARGUMENT "unknown ws doctor option: $1" true "Run agently ws doctor <WS_ID> [--verify-hashes] [--json]." ;;
      *) [[ -z "$ws_id" ]] || ws_fail INVALID_ARGUMENT "ws doctor takes one WS_ID" true "Run agently ws doctor <WS_ID> [--verify-hashes] [--json]."; ws_id="$1"; shift ;;
    esac
  done
  ws_spine_preflight
  [[ -n "$ws_id" ]] || ws_fail INVALID_ARGUMENT "usage: agently ws doctor <WS_ID> [--verify-hashes] [--json]" true "Pass a spine WS_ID."
  validate_spine_ws_id "$ws_id"
  root="$(spine_project_root)"
  ws_dir="$(spine_ws_dir_for_root "$root" "$ws_id")"
  result="$(_ws_doctor_spine_collect "$ws_dir" "$ws_id" "$verify")"
  ok="$(printf '%s' "$result" | jq -r '.ok')"
  errors_count="$(printf '%s' "$result" | jq -r '.errors | length')"
  if [[ "$ok" == "true" ]]; then
    if ws_json_enabled; then
      ws_emit_json "$result"
    else
      printf 'Spine doctor passed: %s\n' "$ws_id"
    fi
    return 0
  fi
  first_code="$(printf '%s' "$result" | jq -r '.errors[0].code // "MANIFEST_INVALID"')"
  if ws_json_enabled; then
    checks_json="$(printf '%s' "$result" | jq -c '.checks')"
    errors_json="$(printf '%s' "$result" | jq -c '.errors')"
    warnings_json="$(printf '%s' "$result" | jq -c '.warnings')"
    {
      printf '{"ok":false,"error":{"code":'
      json_string "$first_code"
      printf ',"message":'
      json_string "ws doctor found $errors_count integrity issue(s)."
      printf ',"recoverable":false,"required_next_actions":["Inspect the reported doctor errors."]},"ws_id":'
      json_string "$ws_id"
      printf ',"checks":%s,"errors":%s,"warnings":%s}\n' "$checks_json" "$errors_json" "$warnings_json"
    } >&2
  else
    printf 'FAIL: ws doctor found %s integrity issue(s) for %s\n' "$errors_count" "$ws_id" >&2
    printf '%s\n' "$result" | jq -r '.errors[] | "- \(.code): \(.message)"' >&2
  fi
  exit "$(ws_exit_code_for "$first_code")"
}

_ws_doctor_spine_collect() {
  local ws_dir="$1" ws_id="$2" verify="$3"
  local manifest events errors_json warnings_json
  local check_manifest_valid=false check_events_valid=true check_files_present=true check_paths_under_root=true
  local check_aliases_coherent=true check_counters_coherent=true check_state_coherent=true check_manifest_event_relationship=true check_hashes_valid=true
  local alias code num rel key status state proposed event_count=0 event_max_seq=0 event_seq
  local promoted_events="" rejected_events="" candidate_aliases canonical_aliases expected actual body_tmp
  errors_json='[]'
  warnings_json='[]'
  manifest="$(spine_manifest_path "$ws_dir")"
  events="$(spine_events_path "$ws_dir")"

  _ws_doctor_add_error() {
    local code_arg="$1" message_arg="$2" check_arg="${3:-}"
    errors_json="$(jq -cn --argjson arr "$errors_json" --arg code "$code_arg" --arg message "$message_arg" '$arr + [{code:$code,message:$message}]')"
    case "$check_arg" in
      manifest_valid) check_manifest_valid=false ;;
      events_valid) check_events_valid=false ;;
      files_present) check_files_present=false ;;
      paths_under_root) check_paths_under_root=false ;;
      aliases_coherent) check_aliases_coherent=false ;;
      counters_coherent) check_counters_coherent=false ;;
      state_coherent) check_state_coherent=false ;;
      manifest_event_relationship) check_manifest_event_relationship=false ;;
      hashes_valid) check_hashes_valid=false ;;
    esac
  }

  _ws_doctor_result() {
    local ok
    if [[ "$(printf '%s' "$errors_json" | jq 'length')" -eq 0 ]]; then
      ok=true
    else
      ok=false
    fi
    jq -cn \
      --argjson ok "$ok" \
      --arg ws_id "$ws_id" \
      --argjson manifest_valid "$check_manifest_valid" \
      --argjson events_valid "$check_events_valid" \
      --argjson files_present "$check_files_present" \
      --argjson paths_under_root "$check_paths_under_root" \
      --argjson aliases_coherent "$check_aliases_coherent" \
      --argjson counters_coherent "$check_counters_coherent" \
      --argjson state_coherent "$check_state_coherent" \
      --argjson manifest_event_relationship "$check_manifest_event_relationship" \
      --argjson hashes_valid "$check_hashes_valid" \
      --argjson errors "$errors_json" \
      --argjson warnings "$warnings_json" \
      '{ok:$ok,ws_id:$ws_id,checks:{manifest_valid:$manifest_valid,events_valid:$events_valid,files_present:$files_present,paths_under_root:$paths_under_root,aliases_coherent:$aliases_coherent,counters_coherent:$counters_coherent,state_coherent:$state_coherent,manifest_event_relationship:$manifest_event_relationship,hashes_valid:$hashes_valid},errors:$errors,warnings:$warnings}'
  }

  if [[ "$verify" -eq 0 ]]; then
    check_hashes_valid=true
  fi
  if [[ ! -d "$ws_dir" ]]; then
    _ws_doctor_add_error WORKSTREAM_NOT_FOUND "workstream directory is missing: $ws_id" manifest_valid
    _ws_doctor_result
    return 0
  fi
  if [[ ! -f "$manifest" ]] || ! jq -e . "$manifest" >/dev/null 2>&1; then
    _ws_doctor_add_error MANIFEST_INVALID "manifest.json is missing or invalid" manifest_valid
    _ws_doctor_result
    return 0
  fi
  check_manifest_valid=true
  if [[ "$(jq -r '.schema_version // empty' "$manifest")" != "1" || "$(jq -r '.ws_id // empty' "$manifest")" != "$ws_id" ]]; then
    _ws_doctor_add_error MANIFEST_INVALID "manifest schema_version/ws_id is invalid" manifest_valid
  fi

  if [[ ! -f "$events" ]]; then
    _ws_doctor_add_error EVENT_LOG_INVALID "events.jsonl is missing" events_valid
  else
    local line lineno=0 eid event_alias event_name seq
    while IFS= read -r line || [[ -n "$line" ]]; do
      lineno=$((lineno + 1))
      [[ -n "$line" ]] || continue
      if ! printf '%s\n' "$line" | jq -e . >/dev/null 2>&1; then
        _ws_doctor_add_error EVENT_LOG_INVALID "invalid event log line: $lineno" events_valid
        continue
      fi
      event_count=$((event_count + 1))
      eid="$(printf '%s\n' "$line" | jq -r '.event_id // empty')"
      if [[ "$eid" =~ ^evt_([0-9]+)$ ]]; then
        seq=$((10#${BASH_REMATCH[1]}))
        (( seq > event_max_seq )) && event_max_seq="$seq"
      fi
      event_name="$(printf '%s\n' "$line" | jq -r '.event // empty')"
      event_alias="$(printf '%s\n' "$line" | jq -r '.alias // empty')"
      case "$event_name" in
        candidate_promoted) promoted_events+="$event_alias"$'\n' ;;
        candidate_rejected) rejected_events+="$event_alias"$'\n' ;;
      esac
    done < "$events"
  fi

  candidate_aliases="$(jq -r '.candidates | keys[]?' "$manifest")"
  canonical_aliases="$(jq -r '.canonical | keys[]?' "$manifest")"
  local max_SCOPE=0 max_REQ=0 max_PLN=0 max_REV=0 max_SYN=0 max_AUD=0 max_HND=0
  while IFS= read -r alias; do
    [[ -n "$alias" ]] || continue
    if [[ "$alias" =~ ^([A-Z][A-Z0-9]{0,31})-([A-Z]+)([0-9]+)$ && "${BASH_REMATCH[1]}" == "$ws_id" ]]; then
      code="${BASH_REMATCH[2]}"
      num=$((10#${BASH_REMATCH[3]}))
      case "$code" in
        SCOPE) (( num > max_SCOPE )) && max_SCOPE="$num" ;;
        REQ) (( num > max_REQ )) && max_REQ="$num" ;;
        PLN) (( num > max_PLN )) && max_PLN="$num" ;;
        REV) (( num > max_REV )) && max_REV="$num" ;;
        SYN) (( num > max_SYN )) && max_SYN="$num" ;;
        AUD) (( num > max_AUD )) && max_AUD="$num" ;;
        HND) (( num > max_HND )) && max_HND="$num" ;;
        *) _ws_doctor_add_error STATE_INCOHERENT "candidate alias has unsupported code: $alias" aliases_coherent ;;
      esac
    else
      _ws_doctor_add_error STATE_INCOHERENT "candidate alias is incoherent: $alias" aliases_coherent
    fi
    for key in raw_path candidate_path proposed_path canonical_path; do
      rel="$(jq -r --arg a "$alias" --arg key "$key" '.candidates[$a][$key] // empty' "$manifest")"
      [[ -n "$rel" ]] || continue
      if ! spine_path_under_ws_root "$ws_dir" "$rel"; then
        _ws_doctor_add_error STATE_INCOHERENT "manifest path escapes workstream root: $alias $key" paths_under_root
        continue
      fi
      [[ -f "$ws_dir/$rel" ]] || _ws_doctor_add_error PAYLOAD_NOT_FILE "referenced file is missing: $rel" files_present
    done
  done <<< "$candidate_aliases"

  while IFS= read -r alias; do
    [[ -n "$alias" ]] || continue
    rel="$(jq -r --arg a "$alias" '.canonical[$a].canonical_path // empty' "$manifest")"
    if ! spine_path_under_ws_root "$ws_dir" "$rel"; then
      _ws_doctor_add_error STATE_INCOHERENT "canonical path escapes workstream root: $alias" paths_under_root
    elif [[ ! -f "$ws_dir/$rel" ]]; then
      _ws_doctor_add_error PAYLOAD_NOT_FILE "canonical file is missing: $rel" files_present
    fi
  done <<< "$canonical_aliases"

  for code in SCOPE REQ PLN REV SYN AUD HND; do
    local var="max_$code" seen counter
    seen="${!var}"
    counter="$(jq -r --arg code "$code" '.alias_counters[$code] // -1' "$manifest")"
    [[ "$counter" =~ ^[0-9]+$ ]] || counter=-1
    if (( counter < seen )); then
      _ws_doctor_add_error STATE_INCOHERENT "alias counter is behind max alias for $code" counters_coherent
    fi
  done

  state="$(jq -r '.state // empty' "$manifest")"
  proposed="$(jq -r '.proposed // empty' "$manifest")"
  if [[ "$state" == "open" ]]; then
    [[ -z "$proposed" ]] || _ws_doctor_add_error STATE_INCOHERENT "open state has non-null proposed alias" state_coherent
  elif [[ "$state" == "escrowed" ]]; then
    if [[ -z "$proposed" ]]; then
      _ws_doctor_add_error STATE_INCOHERENT "escrowed state has no proposed alias" state_coherent
    else
      status="$(jq -r --arg a "$proposed" '.candidates[$a].status // empty' "$manifest")"
      [[ "$status" == "proposed" ]] || _ws_doctor_add_error STATE_INCOHERENT "escrowed proposed alias is missing or not proposed" state_coherent
    fi
  else
    _ws_doctor_add_error STATE_INCOHERENT "unsupported workstream state: $state" state_coherent
  fi

  while IFS= read -r alias; do
    [[ -n "$alias" ]] || continue
    if ! grep -Fxq "$alias" <<< "$promoted_events"; then
      _ws_doctor_add_error EVENT_LOG_INVALID "canonical entry has no candidate_promoted event: $alias" manifest_event_relationship
    fi
  done <<< "$canonical_aliases"

  while IFS= read -r alias; do
    [[ -n "$alias" ]] || continue
    status="$(jq -r --arg a "$alias" '.candidates[$a].status // empty' "$manifest")"
    if [[ "$status" == "promoted" ]] && ! grep -Fxq "$alias" <<< "$promoted_events"; then
      _ws_doctor_add_error EVENT_LOG_INVALID "promoted candidate has no candidate_promoted event: $alias" manifest_event_relationship
    fi
    if [[ "$status" == "rejected" ]] && ! grep -Fxq "$alias" <<< "$rejected_events"; then
      _ws_doctor_add_error EVENT_LOG_INVALID "rejected candidate has no candidate_rejected event: $alias" manifest_event_relationship
    fi
  done <<< "$candidate_aliases"

  event_seq="$(jq -r '.event_seq // empty' "$manifest")"
  if [[ "$event_seq" =~ ^[0-9]+$ ]]; then
    if (( event_seq != event_count )) || (( event_seq != event_max_seq )); then
      _ws_doctor_add_error EVENT_LOG_INVALID "manifest event_seq does not match events.jsonl" manifest_event_relationship
    fi
  else
    _ws_doctor_add_error MANIFEST_INVALID "manifest event_seq is not an integer" manifest_valid
  fi

  if [[ "$verify" -eq 1 ]]; then
    while IFS= read -r alias; do
      [[ -n "$alias" ]] || continue
      rel="$(jq -r --arg a "$alias" '.candidates[$a].raw_path // empty' "$manifest")"
      expected="$(jq -r --arg a "$alias" '.candidates[$a].raw_sha256 // empty' "$manifest")"
      if [[ -n "$rel" && -n "$expected" && -f "$ws_dir/$rel" ]]; then
        actual="$(sha256sum "$ws_dir/$rel" | awk '{print $1}')"
        [[ "$actual" == "$expected" ]] || _ws_doctor_add_error HASH_MISMATCH "raw_sha256 mismatch for $alias" hashes_valid
      fi
      rel="$(jq -r --arg a "$alias" '.candidates[$a].candidate_path // empty' "$manifest")"
      expected="$(jq -r --arg a "$alias" '.candidates[$a].packet_sha256 // empty' "$manifest")"
      if [[ -n "$rel" && -n "$expected" && -f "$ws_dir/$rel" ]]; then
        actual="$(sha256sum "$ws_dir/$rel" | awk '{print $1}')"
        [[ "$actual" == "$expected" ]] || _ws_doctor_add_error HASH_MISMATCH "packet_sha256 mismatch for $alias" hashes_valid
      fi
      expected="$(jq -r --arg a "$alias" '.candidates[$a].content_sha256 // empty' "$manifest")"
      if [[ -n "$rel" && -n "$expected" && -f "$ws_dir/$rel" ]]; then
        body_tmp="$(mktemp)"
        spine_extract_packet_body "$ws_dir/$rel" "$body_tmp"
        actual="$(sha256sum "$body_tmp" | awk '{print $1}')"
        rm -f "$body_tmp"
        [[ "$actual" == "$expected" ]] || _ws_doctor_add_error HASH_MISMATCH "content_sha256 mismatch for $alias" hashes_valid
      fi
    done <<< "$candidate_aliases"
    while IFS= read -r alias; do
      [[ -n "$alias" ]] || continue
      rel="$(jq -r --arg a "$alias" '.canonical[$a].canonical_path // empty' "$manifest")"
      expected="$(jq -r --arg a "$alias" '.canonical[$a].canonical_sha256 // empty' "$manifest")"
      if [[ -n "$rel" && -n "$expected" && -f "$ws_dir/$rel" ]]; then
        actual="$(sha256sum "$ws_dir/$rel" | awk '{print $1}')"
        [[ "$actual" == "$expected" ]] || _ws_doctor_add_error HASH_MISMATCH "canonical_sha256 mismatch for $alias" hashes_valid
      fi
    done <<< "$canonical_aliases"
  fi

  _ws_doctor_result
}
