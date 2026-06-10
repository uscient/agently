#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

assert_no_path() {
  [[ ! -e "$1" ]] || fail "unexpected path: $1"
}

assert_contains() {
  local file="$1" needle="$2"
  grep -Fq -- "$needle" "$file" || fail "expected $file to contain: $needle"
}

assert_status_fails() {
  local status="$1" label="$2"
  [[ "$status" -ne 0 ]] || fail "$label should have failed"
}

branch_exists() {
  git show-ref --verify --quiet "refs/heads/$1"
}

assert_branch_exists() {
  branch_exists "$1" || fail "missing branch: $1"
}

assert_branch_missing() {
  ! branch_exists "$1" || fail "unexpected branch: $1"
}

commit_all() {
  git add .
  git commit -q -m "$1"
}

new_repo() {
  local dir="$1"
  mkdir -p "$dir"
  cd "$dir"
  git init -q
  git config user.email branch-smoke@example.invalid
  git config user.name BranchSmoke
  printf '# Branch Smoke\n' > README.md
  git add README.md
  git commit -q -m init
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" init --codex >/dev/null
  commit_all agently-init
}

set_branch_config() {
  local key="$1" value="$2"
  sed -i "s#    $key: .*#    $key: $value#" .agently/config.yml
  git add .agently/config.yml
  git commit -q -m "set branch $key $value"
}

AGENTLY=(env AGENTLY_HOME="$ROOT" "$ROOT/bin/agently")

if grep -R -E 'git .*push|git .*merge|git .*rebase|git .*reset|git .*branch -[dD]|git .*switch -C|git .*checkout -B|--set-upstream' "$ROOT/lib" >/dev/null; then
  fail "forbidden Git branch automation found in lib/"
fi

new_repo "$TMP/manual"
base="$(git branch --show-current)"
"${AGENTLY[@]}" workstream new "Default Manual" >/dev/null
[[ "$(git branch --show-current)" == "$base" ]] || fail "manual mode changed branches"
assert_branch_missing workstream/default-manual
assert_file .agently/workstreams/default-manual/state.yml
assert_contains .agently/workstreams/default-manual/state.yml "enabled: false"
assert_contains .agently/workstreams/default-manual/state.yml "reason: 'mode_manual_without_cli_branch'"

new_repo "$TMP/auto"
base="$(git branch --show-current)"
set_branch_config mode auto
base_commit="$(git rev-parse HEAD)"
"${AGENTLY[@]}" workstream new "Auto Branch" >/dev/null
[[ "$(git branch --show-current)" == "workstream/auto-branch" ]] || fail "auto mode did not check out workstream branch"
assert_branch_exists workstream/auto-branch
assert_contains .agently/workstreams/auto-branch/state.yml "name: 'workstream/auto-branch'"
assert_contains .agently/workstreams/auto-branch/state.yml "base_branch: '$base'"
assert_contains .agently/workstreams/auto-branch/state.yml "base_commit: '$base_commit'"
assert_contains .agently/workstreams/auto-branch/state.yml "created: true"
git switch "$base" >/dev/null
"${AGENTLY[@]}" workstream status "Auto Branch" > "$TMP/auto-status.md"
assert_contains "$TMP/auto-status.md" "Branch status: branch exists, not checked out"
assert_contains "$TMP/auto-status.md" "current branch does not match active workstream branch"

new_repo "$TMP/auto-no-branch"
base="$(git branch --show-current)"
set_branch_config mode auto
"${AGENTLY[@]}" workstream new "Suppressed Branch" --no-branch >/dev/null
[[ "$(git branch --show-current)" == "$base" ]] || fail "--no-branch changed branches"
assert_branch_missing workstream/suppressed-branch
assert_contains .agently/workstreams/suppressed-branch/state.yml "reason: 'cli_no_branch'"

new_repo "$TMP/off-force"
set_branch_config mode off
"${AGENTLY[@]}" workstream new "Forced Branch" --branch >/dev/null
[[ "$(git branch --show-current)" == "workstream/forced-branch" ]] || fail "--branch did not override off mode"
assert_branch_exists workstream/forced-branch

new_repo "$TMP/custom"
base="$(git branch --show-current)"
"${AGENTLY[@]}" workstream new "Custom Name" --branch-name custom/name --branch-from "$base" >/dev/null
[[ "$(git branch --show-current)" == "custom/name" ]] || fail "--branch-name did not check out custom branch"
assert_contains .agently/workstreams/custom-name/state.yml "name: 'custom/name'"
assert_contains .agently/workstreams/custom-name/state.yml "base: '$base'"

new_repo "$TMP/no-checkout"
base="$(git branch --show-current)"
set_branch_config mode auto
set_branch_config checkout_on_create false
"${AGENTLY[@]}" workstream new "No Checkout" >/dev/null
[[ "$(git branch --show-current)" == "$base" ]] || fail "checkout_on_create=false changed branches"
assert_branch_exists workstream/no-checkout
assert_contains .agently/workstreams/no-checkout/state.yml "checked_out: false"

new_repo "$TMP/invalid"
set +e
"${AGENTLY[@]}" workstream new "Bad Branch" --branch-name "bad name" > "$TMP/invalid.out" 2> "$TMP/invalid.err"
invalid_status=$?
set -e
assert_status_fails "$invalid_status" "invalid branch name"
assert_contains "$TMP/invalid.err" "FAIL: invalid Git branch name"
assert_no_path .agently/workstreams/bad-branch

new_repo "$TMP/dirty"
printf 'dirty\n' > dirty.txt
set +e
"${AGENTLY[@]}" workstream new "Dirty Branch" --branch > "$TMP/dirty.out" 2> "$TMP/dirty.err"
dirty_status=$?
set -e
assert_status_fails "$dirty_status" "dirty branch creation"
assert_contains "$TMP/dirty.err" "FAIL: dirty git tree"
assert_no_path .agently/workstreams/dirty-branch
"${AGENTLY[@]}" workstream new "Dirty Branch" --branch --allow-dirty >/dev/null
[[ "$(git branch --show-current)" == "workstream/dirty-branch" ]] || fail "--allow-dirty did not create branch"

new_repo "$TMP/existing"
git branch workstream/existing-branch
set +e
"${AGENTLY[@]}" workstream new "Existing Branch" --branch > "$TMP/existing.out" 2> "$TMP/existing.err"
existing_status=$?
set -e
assert_status_fails "$existing_status" "existing branch default"
assert_contains "$TMP/existing.err" "FAIL: Git branch already exists"
assert_no_path .agently/workstreams/existing-branch
"${AGENTLY[@]}" workstream new "Existing Branch" --branch --checkout-existing >/dev/null
[[ "$(git branch --show-current)" == "workstream/existing-branch" ]] || fail "--checkout-existing did not switch"
assert_contains .agently/workstreams/existing-branch/state.yml "created: false"
assert_contains .agently/workstreams/existing-branch/state.yml "checked_out: true"

new_repo "$TMP/conflict"
set +e
"${AGENTLY[@]}" workstream new "Conflict" --branch --no-branch > "$TMP/conflict.out" 2> "$TMP/conflict.err"
conflict_status=$?
set -e
assert_status_fails "$conflict_status" "conflicting branch flags"
assert_contains "$TMP/conflict.err" "FAIL: --branch and --no-branch cannot be used together"
set +e
"${AGENTLY[@]}" workstream new "Conflict Name" --branch-name x/y --no-branch > "$TMP/conflict-name.out" 2> "$TMP/conflict-name.err"
conflict_name_status=$?
set -e
assert_status_fails "$conflict_name_status" "branch-name with no-branch"
assert_contains "$TMP/conflict-name.err" "FAIL: --branch-name cannot be used with --no-branch"

mkdir -p "$TMP/not-git"
cd "$TMP/not-git"
"${AGENTLY[@]}" init --codex --allow-non-git >/dev/null
set +e
"${AGENTLY[@]}" workstream new "Non Git" --branch > "$TMP/not-git.out" 2> "$TMP/not-git.err"
not_git_status=$?
set -e
assert_status_fails "$not_git_status" "branch creation outside git"
assert_contains "$TMP/not-git.err" "FAIL:"
assert_no_path .agently/workstreams/non-git

printf 'workstream branch smoke ok\n'
