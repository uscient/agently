#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2031
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

assert_dir() {
  [[ -d "$1" ]] || fail "missing dir: $1"
}

assert_not_exists() {
  [[ ! -e "$1" ]] || fail "unexpected path: $1"
}

assert_contains() {
  local file="$1" needle="$2"
  grep -Fq -- "$needle" "$file" || fail "expected $file to contain: $needle"
}

assert_not_contains() {
  local file="$1" needle="$2"
  ! grep -Fq -- "$needle" "$file" || fail "expected $file not to contain: $needle"
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

assert_protected_warning() {
  local file="$1" protected="$2"
  assert_refusal "$file" "^WARN: patch touches runtime-locked authority surface; apply will be refused: $(regex_escape "$protected")$"
}

assert_protected_failure() {
  local file="$1" protected="$2"
  assert_refusal "$file" "^FAIL: patch touches runtime-locked authority surface: $(regex_escape "$protected")$"
}

artifact_dir() {
  printf '.agently/workstreams/protected-ws/artifacts/patches/%s\n' "$1"
}

assert_protected_meta() {
  local id="$1" meta
  meta="$(artifact_dir "$id")/meta.yml"
  assert_file "$meta"
  assert_contains "$meta" "protected: true"
}

assert_apply_refuses() {
  local id="$1" protected="$2" target="$3" baseline="$4" status
  set +e
  "${AGENTLY[@]}" patch apply "$id" --workstream protected-ws --reviewed --allow-dirty > "$TMP/apply-$id.out" 2> "$TMP/apply-$id.err"
  status=$?
  set -e
  assert_status_fails "$status" "protected patch apply $id"
  assert_protected_failure "$TMP/apply-$id.err" "$protected"
  assert_no_mutation "$target" "$baseline"
}

make_edit_patch() {
  local rel="$1" replacement="$2" patch_file="$3"
  printf '%s\n' "$replacement" > "$rel"
  git diff -- "$rel" > "$patch_file"
  git checkout -- "$rel"
}

snapshot_hash() {
  find .agently/doctrine -type f -exec sha256sum {} \; | sort | sha256sum | awk '{ print $1 }'
}

command -v sha256sum >/dev/null 2>&1 || fail "sha256sum required for protected surface tests"

AGENTLY=(env AGENTLY_HOME="$ROOT" "$ROOT/bin/agently")

while IFS='|' read -r label path expected; do
  [[ -n "${label:-}" && "${label:0:1}" != "#" ]] || continue
  (
    source "$ROOT/lib/config-keys.sh"
    source "$ROOT/lib/common.sh"
    if is_protected_authority_path "$path"; then
      verdict="protected"
    else
      verdict="writable"
    fi
    [[ "$verdict" == "$expected" ]]
  ) || fail "protected matcher mismatch for $label: $path"
done <<'CASES'
# label|path|expected
root-agents|AGENTS.md|protected
root-agents-dot|./AGENTS.md|protected
source-truth|docs/doctrine/00-source-of-truth.md|protected
source-contract|docs/doctrine/06-command-contract.md|protected
source-promotion|docs/doctrine/10-promotion.md|protected
source-boundary|docs/doctrine/11-boundary.md|protected
source-nested|docs/doctrine/sub/deep.md|protected
source-created|docs/doctrine/19-new.md|protected
runtime-dir|.agently/doctrine|protected
runtime-truth|.agently/doctrine/00-source-of-truth.md|protected
runtime-marker|.agently/doctrine/.agently-doctrine-snapshot.yml|protected
agents-backup|AGENTS.md.bak|writable
docs-agents|docs/AGENTS.md|writable
src-agents|src/AGENTS.md|writable
doctrine-notes|docs/doctrine-notes.md|writable
notdocs|notdocs/doctrine/x.md|writable
config|.agently/config.yml|writable
local|.agently/local.yml|writable
workstream|.agently/workstreams/W1/candidates/W1-PLN1.md|writable
doctrinex|.agently/doctrineX|writable
readme|README.md|writable
source|src/app.sh|writable
CASES

mkdir -p "$TMP/protected-repo"
cd "$TMP/protected-repo"
git init -q
git config user.email protected-surfaces@example.invalid
git config user.name ProtectedSurfaces
mkdir -p docs/doctrine
printf 'root agents\n' > AGENTS.md
printf 'truth doctrine\n' > docs/doctrine/00-source-of-truth.md
printf 'command doctrine\n' > docs/doctrine/06-command-contract.md
printf '# Protected Surfaces\n' > README.md
git add AGENTS.md docs/doctrine/00-source-of-truth.md docs/doctrine/06-command-contract.md README.md
git commit -q -m init

"${AGENTLY[@]}" init --codex >/dev/null
"${AGENTLY[@]}" ws new protected-ws >/dev/null
cp AGENTS.md "$TMP/agents.before"
cp docs/doctrine/06-command-contract.md "$TMP/doctrine-06.before"
cp .agently/doctrine/00-source-of-truth.md "$TMP/snapshot-00.before"

make_edit_patch AGENTS.md "root agents changed" "$TMP/agents.diff"
"${AGENTLY[@]}" patch propose "$TMP/agents.diff" --workstream protected-ws > "$TMP/propose-agents.out" 2> "$TMP/propose-agents.err"
assert_contains "$TMP/propose-agents.out" "id: 001"
assert_protected_warning "$TMP/propose-agents.err" "AGENTS.md"
assert_protected_meta 001
assert_apply_refuses 001 "AGENTS.md" AGENTS.md "$TMP/agents.before"

make_edit_patch docs/doctrine/06-command-contract.md "command doctrine changed" "$TMP/doctrine-06.diff"
"${AGENTLY[@]}" patch propose "$TMP/doctrine-06.diff" --workstream protected-ws > "$TMP/propose-doctrine.out" 2> "$TMP/propose-doctrine.err"
assert_contains "$TMP/propose-doctrine.out" "id: 002"
assert_protected_warning "$TMP/propose-doctrine.err" "docs/doctrine/06-command-contract.md"
assert_protected_meta 002
assert_apply_refuses 002 "docs/doctrine/06-command-contract.md" docs/doctrine/06-command-contract.md "$TMP/doctrine-06.before"

cat > "$TMP/snapshot.diff" <<'DIFF'
diff --git a/.agently/doctrine/00-source-of-truth.md b/.agently/doctrine/00-source-of-truth.md
--- a/.agently/doctrine/00-source-of-truth.md
+++ b/.agently/doctrine/00-source-of-truth.md
@@ -1,1 +1,1 @@
-# Source Of Truth
+# Source Of Truth Edited
DIFF
"${AGENTLY[@]}" patch propose "$TMP/snapshot.diff" --workstream protected-ws > "$TMP/propose-snapshot.out" 2> "$TMP/propose-snapshot.err"
assert_contains "$TMP/propose-snapshot.out" "id: 003"
assert_protected_warning "$TMP/propose-snapshot.err" ".agently/doctrine/00-source-of-truth.md"
assert_protected_meta 003
assert_apply_refuses 003 ".agently/doctrine/00-source-of-truth.md" .agently/doctrine/00-source-of-truth.md "$TMP/snapshot-00.before"

mkdir -p "$TMP/runtime-repo"
cd "$TMP/runtime-repo"
git init -q
git config user.email protected-runtime@example.invalid
git config user.name ProtectedRuntime
printf '# Runtime Doctrine\n' > README.md
git add README.md
git commit -q -m init

"${AGENTLY[@]}" init --codex >/dev/null
assert_dir .agently/doctrine
assert_not_exists docs/doctrine
"${AGENTLY[@]}" doctrine status > "$TMP/runtime-status.md"
assert_contains "$TMP/runtime-status.md" "provenance: runtime-snapshot"
assert_not_contains "$TMP/runtime-status.md" "provenance: source"

before_hash="$(snapshot_hash)"
"${AGENTLY[@]}" ws new runtime-ws >/dev/null
"${AGENTLY[@]}" ws list > "$TMP/ws-list.out"
"${AGENTLY[@]}" packet status --workstream runtime-ws > "$TMP/packet-status.md"
"${AGENTLY[@]}" guard doctrine > "$TMP/guard-doctrine.md"
"${AGENTLY[@]}" patch list --workstream runtime-ws > "$TMP/patch-list.md"
"${AGENTLY[@]}" profile get claude.model > "$TMP/profile-get.out"
"${AGENTLY[@]}" doctor > "$TMP/doctor.md"
"${AGENTLY[@]}" context manifest > "$TMP/context.md"
after_hash="$(snapshot_hash)"
[[ "$before_hash" == "$after_hash" ]] || fail "runtime commands mutated .agently/doctrine"
assert_not_exists docs/doctrine

printf 'protected surfaces ok\n'
