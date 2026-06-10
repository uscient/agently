#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_no_direct_model_tool_invocations() {
  local pattern='(^|[;&|])[[:space:]]*(env[[:space:]][^[:space:]]+[[:space:]])*(claude|codex|serena)([[:space:]]|$)'
  local status script found list_file

  if command -v rg >/dev/null 2>&1; then
    set +e
    rg -n "$pattern" "$ROOT"/tests/*.sh
    status=$?
    set -e
    case "$status" in
      0)
        fail "direct model/tool invocation found in tests"
        ;;
      1)
        return 0
        ;;
      *)
        fail "no-real-model-call tripwire rg scan failed"
        ;;
    esac
  fi

  if command -v find >/dev/null 2>&1 && command -v grep >/dev/null 2>&1; then
    found=0
    list_file="$TMP/no-real-model-call-files"
    find "$ROOT/tests" -maxdepth 1 -name '*.sh' > "$list_file" || fail "no-real-model-call tripwire find fallback failed"
    while IFS= read -r script; do
      set +e
      grep -En "$pattern" "$script"
      status=$?
      set -e
      case "$status" in
        0)
          found=1
          ;;
        1)
          ;;
        *)
          fail "no-real-model-call tripwire grep fallback failed for $script"
          ;;
      esac
    done < "$list_file"
    [[ "$found" -eq 0 ]] || fail "direct model/tool invocation found in tests"
    return 0
  fi

  fail "no-real-model-call tripwire cannot be enforced: need rg or find+grep"
}

assert_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

assert_not_exists() {
  [[ ! -e "$1" ]] || fail "unexpected path: $1"
}

assert_contains() {
  local file="$1" needle="$2"
  grep -Fq -- "$needle" "$file" || fail "expected $file to contain: $needle"
}

assert_json() {
  jq -e . "$1" >/dev/null || fail "invalid JSON: $1"
}

assert_code() {
  local file="$1" code="$2"
  [[ "$(jq -r '.error.code' "$file")" == "$code" ]] || fail "expected code $code in $file"
}

regex_escape() {
  printf '%s' "$1" | sed 's/[][(){}.^$+*?|\\]/\\&/g'
}

assert_refusal() {
  local file="$1" regex="$2"
  grep -Eq -- "$regex" "$file" || fail "expected $file to match: $regex"
}

assert_no_mutation() {
  local file="$1" baseline="$2"
  cmp -s "$file" "$baseline" || fail "unexpected mutation in $file"
}

assert_status_fails() {
  local status="$1" label="$2"
  [[ "$status" -ne 0 ]] || fail "$label should have failed"
}

run_fails() {
  local label="$1" status
  shift
  set +e
  "$@" > "$TMP/$label.out" 2> "$TMP/$label.err"
  status=$?
  set -e
  assert_status_fails "$status" "$label"
}

run_json_fails() {
  local label="$1" code="$2"
  shift 2
  run_fails "$label" "$@"
  assert_json "$TMP/$label.err"
  assert_code "$TMP/$label.err" "$code"
}

spine_snapshot() {
  find .agently/workstreams/WSEC -type f ! -name '.manifest.lock' -exec sha256sum {} \; | sort
}

assert_no_spine_tmp() {
  if find .agently/workstreams/WSEC -name '.manifest.*.tmp' -print | grep -q .; then
    fail "manifest temp left behind"
  fi
}

run_spine_json_fails_no_mutation() {
  local label="$1" code="$2" before after
  shift 2
  before="$(spine_snapshot)"
  run_json_fails "$label" "$code" "$@"
  after="$(spine_snapshot)"
  [[ "$before" == "$after" ]] || fail "$label mutated spine state"
  assert_no_spine_tmp
}

run_provenance_failure() {
  local label="$1" field="$2" payload="$3"
  if [[ "$field" == "actor" ]]; then
    run_spine_json_fails_no_mutation "$label" INVALID_ARGUMENT "${AGENTLY[@]}" ws ingest WSEC --type plan --file payload.md --actor "$payload" --json
  else
    run_spine_json_fails_no_mutation "$label" INVALID_ARGUMENT "${AGENTLY[@]}" ws ingest WSEC --type plan --file payload.md --via "$payload" --json
  fi
}

snapshot_xdg() {
  local path
  for path in "$HOME/.local" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME"; do
    if [[ -e "$path" ]]; then
      find "$path" -maxdepth 8 -print -exec sha256sum {} \; 2>/dev/null | sort
    fi
  done
}

doctrine_snapshot_hash() {
  find .agently/doctrine -type f -exec sha256sum {} \; | sort | sha256sum | awk '{ print $1 }'
}

config_payload_before_command() {
  local label="$1" payload="$2" before
  before="$TMP/$label.config.before"
  cp "$TMP/base-config.yml" .agently/config.yml
  printf '\n%s\n' "$payload" >> .agently/config.yml
  cp .agently/config.yml "$before"
  printf '%s\n' "$before"
}

expect_config_failure() {
  local label="$1" payload="$2" regex="$3" before
  before="$(config_payload_before_command "$label" "$payload")"
  run_fails "$label" "${AGENTLY[@]}" profile get claude.model
  assert_refusal "$TMP/$label.err" "$regex"
  assert_no_mutation .agently/config.yml "$before"
  assert_no_mutation "$STATE_FILE" "$TMP/state.before"
}

expect_local_failure() {
  local label="$1" payload="$2" regex="$3"
  cp "$TMP/base-config.yml" .agently/config.yml
  rm -f .agently/local.yml
  printf '%s\n' "$payload" > .agently/local.yml
  cp .agently/local.yml "$TMP/$label.local.before"
  run_fails "$label" "${AGENTLY[@]}" profile get claude.model
  assert_refusal "$TMP/$label.err" "$regex"
  assert_no_mutation .agently/local.yml "$TMP/$label.local.before"
  assert_no_mutation .agently/config.yml "$TMP/base-config.yml"
  assert_no_mutation "$STATE_FILE" "$TMP/state.before"
  rm -f .agently/local.yml
}

expect_reserved_env_failure() {
  local label="$1" name="$2"
  cp "$TMP/base-config.yml" .agently/config.yml
  run_fails "$label" env "$name=hostile" AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" doctor
  assert_refusal "$TMP/$label.err" "^FAIL: reserved environment namespace is not accepted: $(regex_escape "$name")$"
  assert_no_mutation .agently/config.yml "$TMP/base-config.yml"
  assert_no_mutation "$STATE_FILE" "$TMP/state.before"
}

expect_unit_refusal() {
  local label="$1" regex="$2" script="$3" status
  shift 3
  set +e
  bash -c "$script" _ "$@" > "$TMP/$label.out" 2> "$TMP/$label.err"
  status=$?
  set -e
  assert_status_fails "$status" "$label"
  assert_refusal "$TMP/$label.err" "$regex"
}

make_edit_patch() {
  local rel="$1" replacement="$2" patch_file="$3"
  printf '%s\n' "$replacement" > "$rel"
  git diff -- "$rel" > "$patch_file"
  git checkout -- "$rel"
}

branch_exists() {
  git show-ref --verify --quiet "refs/heads/$1"
}

for tool in jq sha256sum flock; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool required for adversarial security tests"
done

export HOME="$TMP/home"
export XDG_DATA_HOME="$TMP/xdg-data"
export XDG_STATE_HOME="$TMP/xdg-state"
export XDG_CONFIG_HOME="$TMP/xdg-config"
mkdir -p "$HOME" "$TMP/repo"

AGENTLY=(env AGENTLY_HOME="$ROOT" "$ROOT/bin/agently")

cd "$TMP/repo"
git init -q
git config user.email security-adversarial@example.invalid
git config user.name SecurityAdversarial
printf '# Security Adversarial\n' > README.md
printf 'root agents\n' > AGENTS.md
git add README.md AGENTS.md
git commit -q -m init

"${AGENTLY[@]}" init --codex >/dev/null
"${AGENTLY[@]}" ws new security-ws >/dev/null
"${AGENTLY[@]}" task new verify --workstream security-ws >/dev/null
"${AGENTLY[@]}" ws init WSEC --json >/dev/null
printf 'payload\n' > payload.md
cp .agently/config.yml "$TMP/base-config.yml"
STATE_FILE=".agently/workstreams/security-ws/tasks/verify/STATE.yaml"
cp "$STATE_FILE" "$TMP/state.before"
cp AGENTS.md "$TMP/agents.before"

assert_no_direct_model_tool_invocations

before_doctrine="$(doctrine_snapshot_hash)"
"${AGENTLY[@]}" ws list > "$TMP/offline-ws-list.out"
"${AGENTLY[@]}" packet status --workstream security-ws > "$TMP/offline-packet.md"
"${AGENTLY[@]}" guard doctrine > "$TMP/offline-guard.md"
"${AGENTLY[@]}" patch list --workstream security-ws > "$TMP/offline-patch.md"
"${AGENTLY[@]}" profile get claude.model > "$TMP/offline-profile.out"
"${AGENTLY[@]}" doctor > "$TMP/offline-doctor.md"
after_doctrine="$(doctrine_snapshot_hash)"
[[ "$before_doctrine" == "$after_doctrine" ]] || fail "offline sweep mutated doctrine snapshot"
assert_not_exists docs/doctrine

long_value="$(printf 'a%.0s' {1..4096})"
while IFS='|' read -r label payload regex; do
  [[ -n "${label:-}" && "${label:0:1}" != "#" ]] || continue
  expect_config_failure "$label" "$payload" "$regex"
done <<CASES
# label|payload|regex
unknown-key|unknown_option: true|^FAIL: unknown config key in \.agently/config\.yml line [0-9]+: unknown_option$
long-unknown|unknown_long: $long_value|^FAIL: unknown config key in \.agently/config\.yml line [0-9]+: unknown_long$
reserved-ag-cfg|ag.cfg.review_required: false|^FAIL: reserved config namespace is not accepted: ag\\.cfg\\.review_required$
reserved-ag-meta|ag.meta.doctrine_locked: false|^FAIL: reserved config namespace is not accepted: ag\\.meta\\.doctrine_locked$
state-status|status: done|^FAIL: unknown config key in \.agently/config\.yml line [0-9]+: status$
state-round|round: 99|^FAIL: unknown config key in \.agently/config\.yml line [0-9]+: round$
CASES

authority_keys=(
  authority
  authority.source_of_truth
  doctrine
  doctrine.rules.locked
  review
  review.required
  promotion
  promotion.gate
  source_of_truth
  source.of.truth
  agent.write_boundary
  agents_may_write_doctrine
  review_required
)
for key in "${authority_keys[@]}"; do
  label="authority-${key//[^A-Za-z0-9]/-}"
  expect_config_failure "$label" "$key: forged" "^FAIL: authority-shaped config key is not accepted: $(regex_escape "$key")$"
done

expect_local_failure local-unknown 'patch.dir: elsewhere' '^FAIL: unknown local config key in \.agently/local\.yml line [0-9]+: patch\.dir$'
expect_local_failure local-authority 'review.required: false' '^FAIL: authority-shaped config key is not accepted: review\.required$'

for name in AG_META_DOCTRINE_LOCKED AG_CFG_REVIEW_REQUIRED AG_CFG_CONTEXT_DEFAULT_BUDGET AG_CFG_STATUS; do
  expect_reserved_env_failure "env-$name" "$name"
done

expect_unit_refusal unsupported-env '^FAIL: unsupported Agently environment override: AGENTLY_UNSUPPORTED$' \
  'source "$1/lib/config-keys.sh"; agently_config_validate_env_override AGENTLY_UNSUPPORTED' "$ROOT"

ln -s payload.md payload-link.md
mkdir payload-dir
run_spine_json_fails_no_mutation spine-link PAYLOAD_SYMLINK_REJECTED "${AGENTLY[@]}" ws ingest WSEC --type plan --file payload-link.md --json
run_spine_json_fails_no_mutation spine-dir PAYLOAD_NOT_FILE "${AGENTLY[@]}" ws ingest WSEC --type plan --file payload-dir --json
if mkfifo payload-fifo 2>/dev/null; then
  run_spine_json_fails_no_mutation spine-fifo PAYLOAD_NOT_FILE "${AGENTLY[@]}" ws ingest WSEC --type plan --file payload-fifo --json
else
  printf 'SKIP: mkfifo unsupported\n' >&2
fi

awk '{ if ($1 == "max_payload_bytes:") print "    max_payload_bytes: 4"; else print }' .agently/config.yml > "$TMP/config-small.yml"
mv "$TMP/config-small.yml" .agently/config.yml
printf '12345\n' > too-large.md
run_spine_json_fails_no_mutation spine-large PAYLOAD_TOO_LARGE "${AGENTLY[@]}" ws ingest WSEC --type plan --file too-large.md --json
cp "$TMP/base-config.yml" .agently/config.yml

actor64="$(printf '%064d' 0 | tr '0' 'a')"
actor65="${actor64}a"
"${AGENTLY[@]}" ws ingest WSEC --type plan --file payload.md --actor "$actor64" --via cli --json > "$TMP/actor64.json" 2> "$TMP/actor64.err"
assert_json "$TMP/actor64.json"
[[ ! -s "$TMP/actor64.err" ]] || fail "64-char actor emitted stderr"

run_provenance_failure actor-newline actor $'bad\nactor'
run_provenance_failure actor-cr actor $'bad\ractor'
run_provenance_failure actor-tab actor $'bad\tactor'
run_provenance_failure actor-space actor 'bad actor'
run_provenance_failure actor-metachar actor 'bad;actor'
run_provenance_failure actor-long actor "$actor65"
run_provenance_failure via-newline via $'bad\nvia'

for flag in --status --authority --canonical --promotion-status --author-actor --author-role; do
  run_spine_json_fails_no_mutation "spine-flag-${flag#--}" INVALID_ARGUMENT "${AGENTLY[@]}" ws ingest WSEC "$flag" --type plan --file payload.md --json
done

run_json_fails invalid-ws INVALID_WS_ID "${AGENTLY[@]}" ws status bad/id --json
run_json_fails invalid-alias ALIAS_NOT_FOUND "${AGENTLY[@]}" ws show WSEC-PLN999 --json

make_edit_patch AGENTS.md "root agents changed" "$TMP/agents.diff"
"${AGENTLY[@]}" patch propose "$TMP/agents.diff" --workstream security-ws > "$TMP/propose-agents.out" 2> "$TMP/propose-agents.err"
assert_contains "$TMP/propose-agents.out" "id: 001"
assert_refusal "$TMP/propose-agents.err" '^WARN: patch touches runtime-locked authority surface; apply will be refused: AGENTS\.md$'
assert_file .agently/workstreams/security-ws/artifacts/patches/001/meta.yml
assert_contains .agently/workstreams/security-ws/artifacts/patches/001/meta.yml "protected: true"
run_fails apply-agents "${AGENTLY[@]}" patch apply 001 --workstream security-ws --reviewed
assert_refusal "$TMP/apply-agents.err" '^FAIL: patch touches runtime-locked authority surface: AGENTS\.md$'
assert_no_mutation AGENTS.md "$TMP/agents.before"

for path in '../outside.md' '../../../etc/passwd' '/etc/passwd'; do
  label="path-${path//[^A-Za-z0-9]/-}"
  expect_unit_refusal "$label" "^FAIL: path escapes repository: $(regex_escape "$path")$" \
    'source "$1/lib/config-keys.sh"; source "$1/lib/common.sh"; resolve_repo_file "$2" "$3"' "$ROOT" "$PWD" "$path"
done
assert_not_exists "$TMP/outside.md"

cp "$TMP/base-config.yml" .agently/config.yml
cp .agently/config.yml "$TMP/profile-model-meta.config.before"
run_fails profile-model-meta "${AGENTLY[@]}" claude config --model 'bad;touch pwned'
assert_refusal "$TMP/profile-model-meta.err" '^FAIL: Claude model contains unsafe shell characters: bad;touch pwned$'
assert_no_mutation .agently/config.yml "$TMP/profile-model-meta.config.before"

cp .agently/config.yml "$TMP/profile-effort.config.before"
run_fails profile-effort "${AGENTLY[@]}" claude config --effort impossible
assert_refusal "$TMP/profile-effort.err" '^FAIL: invalid Claude effort: impossible$'
assert_no_mutation .agently/config.yml "$TMP/profile-effort.config.before"

cp .agently/config.yml "$TMP/profile-authority.config.before"
run_fails profile-authority "${AGENTLY[@]}" profile set review.required false
assert_refusal "$TMP/profile-authority.err" '^FAIL: unknown profile key: review\.required$'
assert_no_mutation .agently/config.yml "$TMP/profile-authority.config.before"
assert_not_exists pwned

run_fails bad-branch "${AGENTLY[@]}" ws new "Bad Branch" --branch-name "bad name"
assert_refusal "$TMP/bad-branch.err" '^FAIL: invalid Git branch name: bad name$'
assert_not_exists .agently/workstreams/bad-branch
! branch_exists "bad name" || fail "invalid branch was created"

for payload in 'serena --version' 'serena;touch pwned' '$(touch pwned)' '`touch pwned`' 'a|b' 'a&b' 'a>b' 'a<b'; do
  bash -c 'source "$1/lib/cmd-serena.sh"; ! serena_executable_safe "$2"' _ "$ROOT" "$payload" || fail "unsafe Serena command accepted: $payload"
done
AGENTLY_SERENA_CMD='serena;touch serena-pwned' "${AGENTLY[@]}" serena status --json > "$TMP/serena-status.json"
assert_json "$TMP/serena-status.json"
jq -e '.command_status != "installed" and .tokens_verified == false' "$TMP/serena-status.json" >/dev/null || fail "unsafe Serena command treated as installed"
assert_not_exists serena-pwned

awk '{ if ($1 == "cache_dir:") print "  cache_dir: .agently/cache/../../escape"; else print }' "$TMP/base-config.yml" > .agently/config.yml
run_fails cache-escape "${AGENTLY[@]}" inspect read README.md --full
cache_dir="$PWD/.agently/cache/../../escape/logs/inspect"
assert_refusal "$TMP/cache-escape.err" "^FAIL: cache path escapes \\.agently: $(regex_escape "$cache_dir")$"
assert_not_exists escape
cp "$TMP/base-config.yml" .agently/config.yml

cp .agently/workstreams/security-ws/state.yml "$TMP/branch-state.before"
cp .agently/workstreams/WSEC/manifest.json "$TMP/spine-manifest.before"
expect_config_failure branch-authority $'workstreams:\n  branch:\n    authority: false' '^FAIL: unknown config key in \.agently/config\.yml line [0-9]+: workstreams\.branch\.authority$'
assert_no_mutation .agently/workstreams/security-ws/state.yml "$TMP/branch-state.before"
assert_no_mutation .agently/workstreams/WSEC/manifest.json "$TMP/spine-manifest.before"
expect_config_failure spine-promotion $'ws:\n  spine:\n    promotion: auto' '^FAIL: unknown config key in \.agently/config\.yml line [0-9]+: ws\.spine\.promotion$'
assert_no_mutation .agently/workstreams/security-ws/state.yml "$TMP/branch-state.before"
assert_no_mutation .agently/workstreams/WSEC/manifest.json "$TMP/spine-manifest.before"
expect_reserved_env_failure branch-env AG_CFG_WORKSTREAMS_BRANCH_AUTHORITY

for row in \
  "self-traversal|$TMP/repo/../outside-source|SOURCE_NOT_FOUND" \
  "self-symlink|$TMP/source-link|SOURCE_INVALID" \
  "self-metachar|$TMP/source;touch self-pwned|SOURCE_NOT_FOUND"
do
  IFS='|' read -r label source_path code <<<"$row"
  if [[ "$label" == "self-symlink" ]]; then
    mkdir -p "$TMP/not-agently"
    ln -s "$TMP/not-agently" "$source_path"
  fi
  before_xdg="$(snapshot_xdg)"
  run_json_fails "$label" "$code" "${AGENTLY[@]}" self install --user --from "$source_path" --apply --json
  after_xdg="$(snapshot_xdg)"
  [[ "$before_xdg" == "$after_xdg" ]] || fail "$label mutated managed install paths"
done
assert_not_exists "$TMP/self-pwned"
assert_not_exists "$HOME/.local/bin/agently"
assert_not_exists "$XDG_DATA_HOME/agently"

printf 'security adversarial ok\n'
