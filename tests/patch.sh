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

assert_contains() {
  local file="$1" needle="$2"
  grep -Fq -- "$needle" "$file" || fail "expected $file to contain: $needle"
}

assert_not_contains() {
  local file="$1" needle="$2"
  ! grep -Fq -- "$needle" "$file" || fail "expected $file not to contain: $needle"
}

assert_status_fails() {
  local status="$1" label="$2"
  [[ "$status" -ne 0 ]] || fail "$label should have failed"
}

new_repo() {
  local dir="$1"
  mkdir -p "$dir"
  cd "$dir"
  git init -q
  git config user.email patch-smoke@example.invalid
  git config user.name PatchSmoke
  printf 'hello\n' > hello.txt
  printf 'dup\ndup\n' > dup.txt
  git add hello.txt dup.txt
  git commit -q -m init
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" init --codex >/dev/null
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws new patch-ws >/dev/null
}

AGENTLY=(env AGENTLY_HOME="$ROOT" "$ROOT/bin/agently")

new_repo "$TMP/repo"
head_before="$(git rev-parse HEAD)"
REAL_GIT="$(command -v git)"

"${AGENTLY[@]}" patch propose "$ROOT/tests/fixtures/patch/good.diff" --workstream patch-ws > "$TMP/propose.md"
assert_contains "$TMP/propose.md" "id: 001"
assert_file .agently/workstreams/patch-ws/artifacts/patches/001/patch.diff
assert_file .agently/workstreams/patch-ws/artifacts/patches/001/meta.yml
assert_file .agently/workstreams/patch-ws/artifacts/patches/001/README.md
assert_contains .agently/workstreams/patch-ws/artifacts/patches/001/meta.yml "status: proposed"

"${AGENTLY[@]}" patch check 001 --workstream patch-ws > "$TMP/check.md"
assert_contains "$TMP/check.md" "applies_clean: true"
assert_contains .agently/workstreams/patch-ws/artifacts/patches/001/meta.yml "status: checked"
assert_file .agently/workstreams/patch-ws/artifacts/patches/001/check.log

set +e
"${AGENTLY[@]}" patch apply 001 --workstream patch-ws > "$TMP/apply-unreviewed.out" 2> "$TMP/apply-unreviewed.err"
unreviewed_status=$?
set -e
assert_status_fails "$unreviewed_status" "patch apply without --reviewed"
assert_contains "$TMP/apply-unreviewed.err" "requires --reviewed"
assert_contains hello.txt "hello"
assert_not_contains hello.txt "hello patched"

"${AGENTLY[@]}" patch apply 001 --workstream patch-ws --reviewed > "$TMP/apply.md"
assert_contains "$TMP/apply.md" "## Apply Output"
assert_contains "$TMP/apply.md" "committed: false"
assert_contains hello.txt "hello patched"
assert_contains .agently/workstreams/patch-ws/artifacts/patches/001/meta.yml "status: applied"
assert_contains .agently/workstreams/patch-ws/artifacts/patches/001/meta.yml "apply_log:"
[[ "$(git rev-parse HEAD)" == "$head_before" ]] || fail "patch apply committed or changed HEAD"

"${AGENTLY[@]}" patch list --workstream patch-ws --json > "$TMP/list.json"
assert_contains "$TMP/list.json" '"id":"001"'
"${AGENTLY[@]}" patch show 001 --workstream patch-ws > "$TMP/show.md"
assert_contains "$TMP/show.md" "## Diff"
"${AGENTLY[@]}" patch explain 001 --workstream patch-ws > "$TMP/explain.md"
assert_contains "$TMP/explain.md" "added_lines:"
assert_contains "$TMP/explain.md" "hello.txt"

"${AGENTLY[@]}" patch propose "$ROOT/tests/fixtures/patch/bad.diff" --workstream patch-ws > "$TMP/propose-bad.md"
assert_contains "$TMP/propose-bad.md" "id: 002"
set +e
"${AGENTLY[@]}" patch check 002 --workstream patch-ws > "$TMP/check-bad.out" 2> "$TMP/check-bad.err"
bad_check_status=$?
set -e
assert_status_fails "$bad_check_status" "bad patch check"
assert_contains "$TMP/check-bad.out" "applies_clean: false"
set +e
"${AGENTLY[@]}" patch apply 002 --workstream patch-ws --reviewed > "$TMP/apply-bad.out" 2> "$TMP/apply-bad.err"
bad_apply_status=$?
set -e
assert_status_fails "$bad_apply_status" "bad patch apply"
assert_contains "$TMP/apply-bad.err" "patch check failed"

"${AGENTLY[@]}" patch reject 002 --workstream patch-ws --note "invalid context" > "$TMP/reject.md"
assert_contains "$TMP/reject.md" "status: rejected"
assert_contains .agently/workstreams/patch-ws/artifacts/patches/002/meta.yml "status: rejected"
assert_file .agently/workstreams/patch-ws/artifacts/patches/002/patch.diff

cat > "$TMP/apply-fails.diff" <<'DIFF'
diff --git a/dup.txt b/dup.txt
--- a/dup.txt
+++ b/dup.txt
@@ -1,2 +1,2 @@
-dup
+dup patched
 dup
DIFF
"${AGENTLY[@]}" patch propose "$TMP/apply-fails.diff" --workstream patch-ws > "$TMP/propose-apply-fails.md"
assert_contains "$TMP/propose-apply-fails.md" "id: 003"

mkdir -p "$TMP/fakegit"
cat > "$TMP/fakegit/git" <<'SH'
#!/usr/bin/env bash
real_git="${REAL_GIT:?}"
args=("$@")
if [[ "${args[0]:-}" == "-C" && "${#args[@]}" -ge 3 ]]; then
  if [[ "${args[2]}" == "apply" ]]; then
    is_check=0
    for arg in "${args[@]}"; do
      [[ "$arg" == "--check" ]] && is_check=1
    done
    if [[ "$is_check" -eq 0 ]]; then
      i=1
      while [[ "$i" -le 40 ]]; do
        printf 'fake apply failure line %s\n' "$i"
        i=$((i + 1))
      done
      exit 9
    fi
  fi
fi
exec "$real_git" "$@"
SH
chmod +x "$TMP/fakegit/git"
set +e
REAL_GIT="$REAL_GIT" PATH="$TMP/fakegit:$PATH" AGENTLY_TRUNCATE_LINES=8 AGENTLY_TRUNCATE_HEAD=3 AGENTLY_TRUNCATE_TAIL=3 \
  "${AGENTLY[@]}" patch apply 003 --workstream patch-ws --reviewed > "$TMP/apply-fail.out" 2> "$TMP/apply-fail.err"
apply_fail_status=$?
set -e
[[ "$apply_fail_status" -eq 9 ]] || fail "patch apply should preserve git apply status 9, got $apply_fail_status"
assert_contains "$TMP/apply-fail.out" "[TRUNCATED"
assert_contains "$TMP/apply-fail.out" "full log:"
assert_contains "$TMP/apply-fail.err" "FAIL: git apply failed with status 9"
assert_file .agently/workstreams/patch-ws/artifacts/patches/003/apply.log
assert_contains .agently/workstreams/patch-ws/artifacts/patches/003/meta.yml "apply_log:"
assert_contains dup.txt "dup"
assert_not_contains dup.txt "dup patched"

"${AGENTLY[@]}" patch propose "$ROOT/tests/fixtures/patch/sample.srep" --workstream patch-ws --format srep > "$TMP/propose-srep.md"
assert_contains "$TMP/propose-srep.md" "id: 004"
"${AGENTLY[@]}" patch check 004 --workstream patch-ws > "$TMP/check-srep.md"
assert_contains "$TMP/check-srep.md" "applies_clean: true"

set +e
"${AGENTLY[@]}" patch propose "$ROOT/tests/fixtures/patch/ambiguous.srep" --workstream patch-ws --format srep > "$TMP/propose-ambiguous.out" 2> "$TMP/propose-ambiguous.err"
ambiguous_status=$?
set -e
assert_status_fails "$ambiguous_status" "ambiguous srep propose"
assert_contains "$TMP/propose-ambiguous.err" "match exactly once"

printf 'patch smoke ok\n'
