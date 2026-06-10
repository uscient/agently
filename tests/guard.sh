#!/usr/bin/env bash
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

assert_status_fails() {
  local status="$1" label="$2"
  [[ "$status" -ne 0 ]] || fail "$label should have failed"
}

make_fake_tool() {
  local dir="$1" name="$2"
  cat > "$dir/$name" <<'SH'
#!/usr/bin/env bash
name="$(basename "$0")"
if [[ -n "${AGENTLY_FAKE_TOOL_LOG:-}" ]]; then
  printf '%s %s\n' "$name" "$*" >> "$AGENTLY_FAKE_TOOL_LOG"
fi
if [[ "$name" == "shellcheck" ]]; then
  i=1
  lines="${AGENTLY_FAKE_LINES:-1}"
  while [[ "$i" -le "$lines" ]]; do
    printf 'fake shellcheck line %s\n' "$i"
    i=$((i + 1))
  done
  exit "${AGENTLY_FAKE_SHELLCHECK_STATUS:-0}"
fi
printf 'fake %s ok\n' "$name"
exit 0
SH
  chmod +x "$dir/$name"
}

make_fake_path() {
  local dir="$1"
  mkdir -p "$dir"
  for tool in shellcheck bats ruff mypy pytest go golangci-lint php phpstan phpunit pest; do
    make_fake_tool "$dir" "$tool"
  done
}

make_core_path_without_optionals() {
  local dir="$1" tool path
  mkdir -p "$dir"
  for tool in env bash git sed awk grep find sort mktemp mkdir cat chmod date realpath wc head tail dirname basename tr cp mv rm rmdir sha256sum; do
    path="$(command -v "$tool")" || fail "missing core command for test: $tool"
    ln -s "$path" "$dir/$tool"
  done
}

new_repo() {
  local dir="$1"
  mkdir -p "$dir"
  cd "$dir"
  git init -q
  git config user.email guard-smoke@example.invalid
  git config user.name GuardSmoke
  cat > script.sh <<'SH'
#!/usr/bin/env bash
echo ok
SH
  cat > script.py <<'PY'
def main() -> None:
    print("ok")
PY
  cat > go.mod <<'GO'
module example.invalid/guard

go 1.20
GO
  cat > main.go <<'GO'
package main

func main() {}
GO
  cat > sample.php <<'PHP'
<?php
echo "ok";
PHP
  cat > pyproject.toml <<'TOML'
[tool.mypy]
python_version = "3.11"

[tool.pytest.ini_options]
testpaths = ["tests"]
TOML
  mkdir -p tests
  printf 'def test_ok():\n    assert True\n' > tests/test_sample.py
  printf 'linters-settings: {}\n' > .golangci.yml
  printf 'parameters: {}\n' > phpstan.neon
  printf '<phpunit></phpunit>\n' > phpunit.xml
  git add .
  git commit -q -m init
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" init --codex >/dev/null
}

AGENTLY=(env AGENTLY_HOME="$ROOT" "$ROOT/bin/agently")

FAKEBIN="$TMP/fakebin"
make_fake_path "$FAKEBIN"
export PATH="$FAKEBIN:/usr/bin:/bin"
export AGENTLY_FAKE_TOOL_LOG="$TMP/tools.log"

new_repo "$TMP/repo"

"${AGENTLY[@]}" guard --lang bash --file script.sh > "$TMP/bash.md"
assert_contains "$TMP/bash.md" "# Agently Guard Report"
assert_contains "$TMP/bash.md" "shellcheck"
assert_contains "$TMP/tools.log" "shellcheck --format=gcc script.sh"

: > "$TMP/tools.log"
"${AGENTLY[@]}" guard --lang python > "$TMP/python.md"
assert_contains "$TMP/python.md" "ruff check"
assert_contains "$TMP/tools.log" "ruff check --output-format=concise"
assert_contains "$TMP/tools.log" "mypy"
assert_contains "$TMP/tools.log" "pytest -q --tb=short"

: > "$TMP/tools.log"
"${AGENTLY[@]}" guard --lang go > "$TMP/go.md"
assert_contains "$TMP/go.md" "go test"
assert_contains "$TMP/tools.log" "go test -short ./..."
assert_contains "$TMP/tools.log" "go vet ./..."
assert_contains "$TMP/tools.log" "golangci-lint run"

: > "$TMP/tools.log"
"${AGENTLY[@]}" guard --lang php > "$TMP/php.md"
assert_contains "$TMP/php.md" "php -l"
assert_contains "$TMP/tools.log" "php -l sample.php"
assert_contains "$TMP/tools.log" "phpstan analyse --error-format=raw"
assert_contains "$TMP/tools.log" "phpunit"

printf 'echo changed\n' >> script.sh
"${AGENTLY[@]}" guard --changed --lang bash > "$TMP/changed.md"
assert_contains "$TMP/changed.md" "mode: changed"

set +e
AGENTLY_FAKE_SHELLCHECK_STATUS=7 AGENTLY_FAKE_LINES=12 AGENTLY_TRUNCATE_LINES=5 AGENTLY_TRUNCATE_HEAD=2 AGENTLY_TRUNCATE_TAIL=2 \
  "${AGENTLY[@]}" guard --lang bash --file script.sh > "$TMP/fail-truncate.out" 2> "$TMP/fail-truncate.err"
guard_status=$?
set -e
[[ "$guard_status" -eq 7 ]] || fail "guard should preserve shellcheck exit 7, got $guard_status"
assert_contains "$TMP/fail-truncate.out" "[TRUNCATED"
assert_contains "$TMP/fail-truncate.out" "full log:"

printf 'trailing whitespace \n' >> script.sh
set +e
"${AGENTLY[@]}" guard diff > "$TMP/diff.out" 2> "$TMP/diff.err"
diff_status=$?
set -e
assert_status_fails "$diff_status" "guard diff with whitespace"
assert_contains "$TMP/diff.out" "git diff --check"

COREBIN="$TMP/corebin"
make_core_path_without_optionals "$COREBIN"
set +e
PATH="$COREBIN" "${AGENTLY[@]}" guard --lang bash --strict > "$TMP/missing.out" 2> "$TMP/missing.err"
missing_status=$?
set -e
[[ "$missing_status" -eq 3 ]] || fail "strict missing tool should return 3, got $missing_status"
assert_contains "$TMP/missing.out" "missing optional tool: shellcheck"
assert_contains "$TMP/missing.err" "missing optional tool"

config_before="$(sha256sum .agently/config.yml | awk '{ print $1 }')"
status_before="$(git status --short)"
PATH="$COREBIN" "${AGENTLY[@]}" doctor --fix > "$TMP/doctor-fix.md"
config_after="$(sha256sum .agently/config.yml | awk '{ print $1 }')"
status_after="$(git status --short)"
[[ "$config_before" == "$config_after" ]] || fail "doctor --fix mutated config.yml"
[[ "$status_before" == "$status_after" ]] || fail "doctor --fix mutated files"
assert_contains "$TMP/doctor-fix.md" "Tool Readiness"
assert_contains "$TMP/doctor-fix.md" "Fix Suggestions"
assert_contains "$TMP/doctor-fix.md" "suggestions only"
assert_contains "$TMP/doctor-fix.md" "ast-grep"
PATH="$COREBIN" "${AGENTLY[@]}" doctor --json > "$TMP/doctor.json"
assert_contains "$TMP/doctor.json" "\"readiness\""
assert_contains "$TMP/doctor.json" "\"ast-grep\""

"${AGENTLY[@]}" guard scope > "$TMP/scope.md"
assert_contains "$TMP/scope.md" "# Agently Scope Guard"
"${AGENTLY[@]}" guard secret > "$TMP/secret.md"
assert_contains "$TMP/secret.md" "# Agently Secret Guard"
"${AGENTLY[@]}" guard artifact > "$TMP/artifact.md"
assert_contains "$TMP/artifact.md" "cache_is_source_authority: false"

printf 'guard smoke ok\n'
