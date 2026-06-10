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

assert_not_exists() {
  [[ ! -e "$1" ]] || fail "unexpected path: $1"
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
  git config user.email inspect-smoke@example.invalid
  git config user.name InspectSmoke
  printf '# Inspect Smoke\n' > README.md
  mkdir -p fixtures
  cp -R "$ROOT/tests/fixtures/"* fixtures/
  git add README.md fixtures
  git commit -q -m init
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" init --codex >/dev/null
}

AGENTLY=(env AGENTLY_HOME="$ROOT" "$ROOT/bin/agently")

new_repo "$TMP/repo"

"${AGENTLY[@]}" inspect symbols fixtures/bash/sample.sh > "$TMP/symbols-bash.out"
assert_contains "$TMP/symbols-bash.out" "say_hello"
"${AGENTLY[@]}" inspect symbols fixtures/python/sample.py > "$TMP/symbols-python.out"
assert_contains "$TMP/symbols-python.out" "class Greeter"
"${AGENTLY[@]}" inspect symbols fixtures/go/sample.go > "$TMP/symbols-go.out"
assert_contains "$TMP/symbols-go.out" "func Hello"
"${AGENTLY[@]}" inspect symbols fixtures/php/sample.php > "$TMP/symbols-php.out"
assert_contains "$TMP/symbols-php.out" "class Greeter"
"${AGENTLY[@]}" inspect skeleton fixtures/md/sample.md > "$TMP/skeleton-md.out"
assert_contains "$TMP/skeleton-md.out" "## Section"
"${AGENTLY[@]}" inspect skeleton fixtures/yaml/sample.yml > "$TMP/skeleton-yaml.out"
assert_contains "$TMP/skeleton-yaml.out" "enabled: true"

"${AGENTLY[@]}" inspect read fixtures/md/sample.md --start 1 --end 2 > "$TMP/read-range.out"
assert_contains "$TMP/read-range.out" "# Fixture"
set +e
"${AGENTLY[@]}" inspect read fixtures/md/sample.md > "$TMP/read-unbounded.out" 2> "$TMP/read-unbounded.err"
read_status=$?
set -e
assert_status_fails "$read_status" "unbounded inspect read"
assert_contains "$TMP/read-unbounded.err" "requires --start and --end"

seq 1 2105 > huge.txt
set +e
"${AGENTLY[@]}" inspect read huge.txt --full > "$TMP/read-full.out" 2> "$TMP/read-full.err"
full_status=$?
set -e
assert_status_fails "$full_status" "over-cap inspect read --full"
assert_contains "$TMP/read-full.err" "exceeds cap"
assert_contains "$TMP/read-full.err" "full read logged"

for n in 1 2 3 4 5 6 7 8; do
  printf 'alpha %s\n' "$n" >> matches.txt
done
"${AGENTLY[@]}" inspect grep alpha . --max 3 > "$TMP/grep.out"
assert_contains "$TMP/grep.out" "[TRUNCATED"
assert_contains "$TMP/grep.out" "full log:"

# Mask rg so inspect grep takes the grep -R fallback, which must not fail
# on its own log file under .agently/cache.
mkdir -p "$TMP/norg-bin"
ln -s /usr/bin/* "$TMP/norg-bin/" 2>/dev/null || true
ln -sf /bin/* "$TMP/norg-bin/" 2>/dev/null || true
rm -f "$TMP/norg-bin/rg"
if PATH="$TMP/norg-bin" command -v rg >/dev/null 2>&1; then
  fail "rg still resolvable; grep fallback not exercised"
fi
PATH="$TMP/norg-bin" "${AGENTLY[@]}" inspect grep alpha . --max 3 > "$TMP/grep-fallback.out"
assert_contains "$TMP/grep-fallback.out" "[TRUNCATED"
assert_contains "$TMP/grep-fallback.out" "full log:"

"${AGENTLY[@]}" inspect tree fixtures --depth 2 > "$TMP/tree.out"
assert_contains "$TMP/tree.out" "sample.sh"

mkdir -p "$TMP/bin"
cat > "$TMP/bin/sg" <<'SH'
#!/usr/bin/env bash
printf 'bare sg was called\n' > "$TMPDIR/bare-sg-called"
exit 99
SH
chmod +x "$TMP/bin/sg"
TMPDIR="$TMP" PATH="$TMP/bin:/usr/bin:/bin" "${AGENTLY[@]}" inspect sg alpha --lang bash . --max 2 > "$TMP/sg-degrade.out" 2> "$TMP/sg-degrade.err" || true
assert_contains "$TMP/sg-degrade.err" "ast-grep not found"
assert_not_exists "$TMP/bare-sg-called"

cat > "$TMP/bin/ast-grep" <<'SH'
#!/usr/bin/env bash
printf 'fake ast-grep invoked: %s\n' "$*"
SH
chmod +x "$TMP/bin/ast-grep"
PATH="$TMP/bin:/usr/bin:/bin" "${AGENTLY[@]}" inspect sg 'say_hello' --lang bash fixtures/bash/sample.sh > "$TMP/sg-present.out"
assert_contains "$TMP/sg-present.out" "fake ast-grep invoked"
assert_contains "$TMP/sg-present.out" "--pattern say_hello"

find .agently/cache/logs/inspect -type f -name '*.log' -print -quit | grep -q . || fail "missing inspect log"

printf 'inspect smoke ok\n'
