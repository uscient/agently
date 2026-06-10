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

make_fake_shellcheck() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/shellcheck" <<'SH'
#!/usr/bin/env bash
if [[ -n "${AGENTLY_FAKE_TOOL_LOG:-}" ]]; then
  printf 'shellcheck %s\n' "$*" >> "$AGENTLY_FAKE_TOOL_LOG"
fi
printf 'fake shellcheck\n'
exit "${AGENTLY_FAKE_SHELLCHECK_STATUS:-0}"
SH
  chmod +x "$dir/shellcheck"
}

new_repo() {
  local dir="$1"
  mkdir -p "$dir"
  cd "$dir"
  git init -q
  git config user.email eval-smoke@example.invalid
  git config user.name EvalSmoke
  cat > script.sh <<'SH'
#!/usr/bin/env bash
echo before
SH
  git add script.sh
  git commit -q -m init
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" init --codex >/dev/null
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws new eval-ws >/dev/null
}

AGENTLY=(env AGENTLY_HOME="$ROOT" "$ROOT/bin/agently")
FAKEBIN="$TMP/fakebin"
make_fake_shellcheck "$FAKEBIN"
export PATH="$FAKEBIN:/usr/bin:/bin"
export AGENTLY_FAKE_TOOL_LOG="$TMP/tools.log"

new_repo "$TMP/repo"

"${AGENTLY[@]}" eval --lang bash > "$TMP/eval.md"
assert_contains "$TMP/eval.md" "# Agently Eval Report"
assert_contains "$TMP/eval.md" "# Agently Guard Report"
assert_contains "$TMP/eval.md" "project_tests: covered by detected language guard runners"
assert_contains "$TMP/tools.log" "shellcheck --format=gcc script.sh"

set +e
AGENTLY_FAKE_SHELLCHECK_STATUS=5 "${AGENTLY[@]}" eval --lang bash > "$TMP/eval-fail.out" 2> "$TMP/eval-fail.err"
eval_status=$?
set -e
[[ "$eval_status" -eq 5 ]] || fail "eval should preserve guard exit 5, got $eval_status"

cat > "$TMP/script.patch" <<'DIFF'
diff --git a/script.sh b/script.sh
--- a/script.sh
+++ b/script.sh
@@ -1,2 +1,2 @@
 #!/usr/bin/env bash
-echo before
+echo after
DIFF

"${AGENTLY[@]}" patch propose "$TMP/script.patch" --workstream eval-ws > "$TMP/propose.md"
assert_contains "$TMP/propose.md" "id: 001"
before_content="$(cat script.sh)"
AGENTLY_FAKE_SHELLCHECK_STATUS=0 "${AGENTLY[@]}" eval patch 001 --workstream eval-ws > "$TMP/eval-patch.md"
after_content="$(cat script.sh)"
[[ "$before_content" == "$after_content" ]] || fail "eval patch touched the live tree"
assert_contains "$TMP/eval-patch.md" "# Agently Patch Eval"
assert_contains "$TMP/eval-patch.md" "live_tree_mutated: false"
assert_contains "$TMP/eval-patch.md" "apply_status: 0"
assert_contains "$TMP/eval-patch.md" "eval-logs"
assert_file .agently/workstreams/eval-ws/artifacts/patches/001/eval.md
assert_file .agently/workstreams/eval-ws/artifacts/patches/001/eval-guard.md
assert_contains .agently/workstreams/eval-ws/artifacts/patches/001/meta.yml "eval_status: passed"
find .agently/workstreams/eval-ws/artifacts/patches/001/eval-logs -type f -name '*.log' -print -quit | grep -q . ||
  fail "eval patch did not preserve guard logs"

printf 'eval smoke ok\n'
