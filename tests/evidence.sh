#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1" needle="$2"
  grep -Fq -- "$needle" "$file" || fail "expected $file to contain: $needle"
}

assert_not_exists() {
  [[ ! -e "$1" ]] || fail "unexpected path: $1"
}

make_fake_shellcheck() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/shellcheck" <<'SH'
#!/usr/bin/env bash
if [[ -n "${AGENTLY_FAKE_TOOL_LOG:-}" ]]; then
  printf 'shellcheck %s\n' "$*" >> "$AGENTLY_FAKE_TOOL_LOG"
fi
i=1
lines="${AGENTLY_FAKE_LINES:-1}"
while [[ "$i" -le "$lines" ]]; do
  printf 'fake shellcheck evidence line %s\n' "$i"
  i=$((i + 1))
done
exit 0
SH
  chmod +x "$dir/shellcheck"
}

new_repo() {
  local dir="$1"
  mkdir -p "$dir"
  cd "$dir"
  git init -q
  git config user.email evidence-smoke@example.invalid
  git config user.name EvidenceSmoke
  cat > script.sh <<'SH'
#!/usr/bin/env bash
echo ok
SH
  git add script.sh
  git commit -q -m init
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" init --codex >/dev/null
}

AGENTLY=(env AGENTLY_HOME="$ROOT" "$ROOT/bin/agently")

FAKEBIN="$TMP/fakebin"
make_fake_shellcheck "$FAKEBIN"
export PATH="$FAKEBIN:/usr/bin:/bin"
export AGENTLY_FAKE_TOOL_LOG="$TMP/tools.log"

new_repo "$TMP/repo"

if grep -Fq 'bash -c "$test_cmd"' "$ROOT/lib/cmd-tooling.sh"; then
  fail "unsafe evidence bash -c test_cmd path remains"
fi
if grep -Eq 'eval[[:space:]].*test_cmd' "$ROOT/lib/cmd-tooling.sh"; then
  fail "unsafe evidence eval test_cmd path remains"
fi

printf '\ntest_command: touch evidence-executed\n' >> .agently/config.yml
AGENTLY_FAKE_LINES=120 AGENTLY_TRUNCATE_LINES=20 AGENTLY_TRUNCATE_HEAD=5 AGENTLY_TRUNCATE_TAIL=5 AGENTLY_EVIDENCE_TEST_LINES=10 \
  "${AGENTLY[@]}" evidence --tests > "$TMP/evidence.md" 2> "$TMP/evidence.err"

assert_not_exists evidence-executed
assert_contains "$TMP/evidence.md" "# Evidence Pack"
assert_contains "$TMP/evidence.md" "Configured command: \`touch evidence-executed\`"
assert_contains "$TMP/evidence.md" "Runner: \`agently guard\`"
assert_contains "$TMP/evidence.md" "[TRUNCATED"
assert_contains "$TMP/evidence.md" "full log:"
assert_contains "$TMP/evidence.md" "Log: \`.agently/cache/logs/evidence/"
assert_contains "$TMP/evidence.err" "full output logged"
assert_contains "$TMP/tools.log" "shellcheck --format=gcc script.sh"

find .agently/cache/logs/evidence -type f -name '*.log' -print -quit | grep -q . ||
  fail "missing evidence log"

printf 'evidence smoke ok\n'
