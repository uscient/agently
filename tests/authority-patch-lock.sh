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

assert_file_content() {
  local file="$1" expected="$2" actual
  actual="$(cat "$file")"
  [[ "$actual" == "$expected" ]] || fail "unexpected content in $file"
}

artifact_dir() {
  printf '.agently/workstreams/authority-ws/artifacts/patches/%s\n' "$1"
}

assert_protected_meta() {
  local id="$1" meta
  meta="$(artifact_dir "$id")/meta.yml"
  assert_file "$meta"
  assert_contains "$meta" "protected: true"
}

assert_protected_warning() {
  local file="$1" protected="$2"
  assert_refusal "$file" "^WARN: patch touches runtime-locked authority surface; apply will be refused: $(regex_escape "$protected")$"
}

assert_protected_failure() {
  local file="$1" protected="$2"
  assert_refusal "$file" "^FAIL: patch touches runtime-locked authority surface: $(regex_escape "$protected")$"
}

assert_apply_refuses() {
  local id="$1" protected="$2" out="$3" err="$4" status
  shift 4
  set +e
  "${AGENTLY[@]}" patch apply "$id" --workstream authority-ws --reviewed "$@" > "$out" 2> "$err"
  status=$?
  set -e
  assert_status_fails "$status" "protected patch apply $id"
  assert_protected_failure "$err" "$protected"
}

make_edit_patch() {
  local rel="$1" replacement="$2" patch_file="$3"
  printf '%s\n' "$replacement" > "$rel"
  git diff -- "$rel" > "$patch_file"
  git checkout -- "$rel"
}

AGENTLY=(env AGENTLY_HOME="$ROOT" "$ROOT/bin/agently")

mkdir -p "$TMP/repo"
cd "$TMP/repo"
git init -q
git config user.email authority-patch-lock@example.invalid
git config user.name AuthorityPatchLock

mkdir -p docs/doctrine
printf 'root agents\n' > AGENTS.md
printf 'truth doctrine\n' > docs/doctrine/00-source-of-truth.md
printf 'command doctrine\n' > docs/doctrine/06-command-contract.md
printf 'hello\n' > hello.txt
printf 'rename source\n' > rename-source.md
git add AGENTS.md docs/doctrine/00-source-of-truth.md docs/doctrine/06-command-contract.md hello.txt rename-source.md
git commit -q -m init

"${AGENTLY[@]}" init --codex >/dev/null
"${AGENTLY[@]}" ws new authority-ws >/dev/null
cp AGENTS.md "$TMP/AGENTS.before"
cp docs/doctrine/00-source-of-truth.md "$TMP/doctrine-00.before"
cp docs/doctrine/06-command-contract.md "$TMP/doctrine-06.before"
cp .agently/doctrine/00-source-of-truth.md "$TMP/snapshot-00.before"

REAL_GIT="$(command -v git)"

make_edit_patch AGENTS.md "root agents changed" "$TMP/agents.diff"
"${AGENTLY[@]}" patch propose "$TMP/agents.diff" --workstream authority-ws > "$TMP/propose-agents.out" 2> "$TMP/propose-agents.err"
assert_contains "$TMP/propose-agents.out" "id: 001"
assert_protected_warning "$TMP/propose-agents.err" "AGENTS.md"
assert_file "$(artifact_dir 001)/patch.diff"
assert_protected_meta 001

mkdir -p "$TMP/fakegit"
cat > "$TMP/fakegit/git" <<'SH'
#!/usr/bin/env bash
real_git="${REAL_GIT:?}"
args=("$@")
if [[ "${args[0]:-}" == "-C" && "${#args[@]}" -ge 3 && "${args[2]}" == "apply" ]]; then
  echo "git apply should not run for protected patches" >&2
  exit 73
fi
exec "$real_git" "$@"
SH
chmod +x "$TMP/fakegit/git"

set +e
REAL_GIT="$REAL_GIT" PATH="$TMP/fakegit:$PATH" "${AGENTLY[@]}" patch apply 001 --workstream authority-ws --reviewed > "$TMP/apply-agents.out" 2> "$TMP/apply-agents.err"
agents_status=$?
set -e
assert_status_fails "$agents_status" "root AGENTS.md protected patch apply"
assert_protected_failure "$TMP/apply-agents.err" "AGENTS.md"
assert_not_contains "$TMP/apply-agents.err" "git apply should not run"
assert_no_mutation AGENTS.md "$TMP/AGENTS.before"

make_edit_patch docs/doctrine/00-source-of-truth.md "truth doctrine changed" "$TMP/doctrine-00.diff"
"${AGENTLY[@]}" patch propose "$TMP/doctrine-00.diff" --workstream authority-ws > "$TMP/propose-doctrine-00.out" 2> "$TMP/propose-doctrine-00.err"
assert_contains "$TMP/propose-doctrine-00.out" "id: 002"
assert_protected_warning "$TMP/propose-doctrine-00.err" "docs/doctrine/00-source-of-truth.md"
assert_protected_meta 002
assert_apply_refuses 002 "docs/doctrine/00-source-of-truth.md" "$TMP/apply-doctrine-00.out" "$TMP/apply-doctrine-00.err" --allow-dirty
assert_no_mutation docs/doctrine/00-source-of-truth.md "$TMP/doctrine-00.before"

make_edit_patch docs/doctrine/06-command-contract.md "command doctrine changed" "$TMP/doctrine-06.diff"
"${AGENTLY[@]}" patch propose "$TMP/doctrine-06.diff" --workstream authority-ws > "$TMP/propose-doctrine-06.out" 2> "$TMP/propose-doctrine-06.err"
assert_contains "$TMP/propose-doctrine-06.out" "id: 003"
assert_protected_warning "$TMP/propose-doctrine-06.err" "docs/doctrine/06-command-contract.md"
assert_protected_meta 003
assert_apply_refuses 003 "docs/doctrine/06-command-contract.md" "$TMP/apply-doctrine-06.out" "$TMP/apply-doctrine-06.err"
assert_no_mutation docs/doctrine/06-command-contract.md "$TMP/doctrine-06.before"

cat > "$TMP/agents.srep" <<'SREP'
@@ file: AGENTS.md
<<<<<<< SEARCH
root agents
=======
root agents changed by srep
>>>>>>> REPLACE
SREP
"${AGENTLY[@]}" patch propose "$TMP/agents.srep" --workstream authority-ws --format srep > "$TMP/propose-agents-srep.out" 2> "$TMP/propose-agents-srep.err"
assert_contains "$TMP/propose-agents-srep.out" "id: 004"
assert_protected_warning "$TMP/propose-agents-srep.err" "AGENTS.md"
assert_protected_meta 004
assert_apply_refuses 004 "AGENTS.md" "$TMP/apply-agents-srep.out" "$TMP/apply-agents-srep.err"
assert_no_mutation AGENTS.md "$TMP/AGENTS.before"

printf 'new doctrine\n' > docs/doctrine/19-new.md
git add docs/doctrine/19-new.md
git diff --cached > "$TMP/create-doctrine.diff"
git reset --hard -q
rm -f docs/doctrine/19-new.md
"${AGENTLY[@]}" patch propose "$TMP/create-doctrine.diff" --workstream authority-ws > "$TMP/propose-create.out" 2> "$TMP/propose-create.err"
assert_contains "$TMP/propose-create.out" "id: 005"
assert_protected_warning "$TMP/propose-create.err" "docs/doctrine/19-new.md"
assert_protected_meta 005
assert_apply_refuses 005 "docs/doctrine/19-new.md" "$TMP/apply-create.out" "$TMP/apply-create.err"
assert_not_exists docs/doctrine/19-new.md

git mv rename-source.md docs/doctrine/19-rename.md
git diff --cached > "$TMP/rename-into.diff"
git reset --hard -q
rm -f docs/doctrine/19-rename.md
"${AGENTLY[@]}" patch propose "$TMP/rename-into.diff" --workstream authority-ws > "$TMP/propose-rename-into.out" 2> "$TMP/propose-rename-into.err"
assert_contains "$TMP/propose-rename-into.out" "id: 006"
assert_protected_warning "$TMP/propose-rename-into.err" "docs/doctrine/19-rename.md"
assert_protected_meta 006
assert_apply_refuses 006 "docs/doctrine/19-rename.md" "$TMP/apply-rename-into.out" "$TMP/apply-rename-into.err"
assert_not_exists docs/doctrine/19-rename.md
assert_file rename-source.md

git mv docs/doctrine/00-source-of-truth.md moved.md
git diff --cached > "$TMP/rename-out.diff"
git reset --hard -q
rm -f moved.md
"${AGENTLY[@]}" patch propose "$TMP/rename-out.diff" --workstream authority-ws > "$TMP/propose-rename-out.out" 2> "$TMP/propose-rename-out.err"
assert_contains "$TMP/propose-rename-out.out" "id: 007"
assert_protected_warning "$TMP/propose-rename-out.err" "docs/doctrine/00-source-of-truth.md"
assert_protected_meta 007
assert_apply_refuses 007 "docs/doctrine/00-source-of-truth.md" "$TMP/apply-rename-out.out" "$TMP/apply-rename-out.err"
assert_no_mutation docs/doctrine/00-source-of-truth.md "$TMP/doctrine-00.before"
assert_not_exists moved.md

make_edit_patch hello.txt "hello patched" "$TMP/safe.diff"
"${AGENTLY[@]}" patch propose "$TMP/safe.diff" --workstream authority-ws > "$TMP/propose-safe.out" 2> "$TMP/propose-safe.err"
assert_contains "$TMP/propose-safe.out" "id: 008"
"${AGENTLY[@]}" patch apply 008 --workstream authority-ws --reviewed > "$TMP/apply-safe.out" 2> "$TMP/apply-safe.err"
assert_contains "$TMP/apply-safe.out" "committed: false"
assert_file_content hello.txt "hello patched"

cat > "$TMP/snapshot.diff" <<'DIFF'
diff --git a/.agently/doctrine/00-source-of-truth.md b/.agently/doctrine/00-source-of-truth.md
--- a/.agently/doctrine/00-source-of-truth.md
+++ b/.agently/doctrine/00-source-of-truth.md
@@ -1,1 +1,1 @@
-# Source Of Truth
+# Source Of Truth Edited
DIFF
"${AGENTLY[@]}" patch propose "$TMP/snapshot.diff" --workstream authority-ws > "$TMP/propose-snapshot.out" 2> "$TMP/propose-snapshot.err"
assert_contains "$TMP/propose-snapshot.out" "id: 009"
assert_protected_warning "$TMP/propose-snapshot.err" ".agently/doctrine/00-source-of-truth.md"
assert_protected_meta 009
assert_apply_refuses 009 ".agently/doctrine/00-source-of-truth.md" "$TMP/apply-snapshot.out" "$TMP/apply-snapshot.err"
assert_no_mutation .agently/doctrine/00-source-of-truth.md "$TMP/snapshot-00.before"

printf 'authority patch lock ok\n'
