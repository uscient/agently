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

assert_fails() {
  local label="$1" out="$2" err="$3" status
  shift 3
  set +e
  "$@" > "$out" 2> "$err"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail "$label should have failed"
}

readme_doctrine_section="$(awk '
  /^## Doctrine$/ { in_section=1 }
  in_section { print }
  /^## / && in_section && $0 != "## Doctrine" { exit }
' "$ROOT/README.md")"

if grep -RIlq "docs/doctrine" "$ROOT/templates"; then
  fail "templates/ must not reference docs/doctrine (use .agently/doctrine runtime snapshot)"
fi

printf "%s\n" "$readme_doctrine_section" | grep -Fq "Agently source repository" \
  || fail "README Doctrine section must qualify docs/doctrine as Agently source-repo-only"

printf "%s\n" "$readme_doctrine_section" | grep -Fq ".agently/doctrine" \
  || fail "README Doctrine section must document the runtime .agently/doctrine snapshot path"

if printf "%s\n" "$readme_doctrine_section" | grep -Eq '^[[:space:]]*agently docs[[:space:]]*$'; then
  fail "README Doctrine section must not use agently docs as a doctrine example"
fi

new_repo() {
  local dir="$1"
  mkdir -p "$dir"
  cd "$dir"
  git init -q
  git config user.email doctrine-snapshot@example.invalid
  git config user.name DoctrineSnapshot
  printf '# Doctrine Snapshot\n' > README.md
  git add README.md
  git commit -q -m init
}

AGENTLY=(env AGENTLY_HOME="$ROOT" "$ROOT/bin/agently")

new_repo "$TMP/repo"
"${AGENTLY[@]}" init --codex > "$TMP/init.out" 2> "$TMP/init.err"
assert_dir .agently/doctrine
assert_file .agently/doctrine/00-source-of-truth.md
assert_file .agently/doctrine/.agently-doctrine-snapshot.yml
assert_not_exists docs/doctrine
assert_contains .agently/.gitignore "doctrine/"
assert_contains .agently/doctrine/.agently-doctrine-snapshot.yml "source: installed-agently"
assert_contains .agently/doctrine/.agently-doctrine-snapshot.yml "snapshot_kind: runtime-readonly-copy"
assert_contains .agently/doctrine/.agently-doctrine-snapshot.yml "do_not_edit: true"
assert_contains .agently/doctrine/.agently-doctrine-snapshot.yml "manifest_hash:"
assert_contains .agently/doctrine/.agently-doctrine-snapshot.yml "canonical_source:"
assert_contains .agently/doctrine/.agently-doctrine-snapshot.yml "agently_version:"
if [[ -w .agently/doctrine/00-source-of-truth.md ]]; then
  fail "snapshot markdown should be non-writable"
fi
[[ -x .agently/doctrine ]] || fail "snapshot directory should be traversable"

"${AGENTLY[@]}" doctrine status > "$TMP/status.md"
assert_contains "$TMP/status.md" "provenance: runtime-snapshot"
assert_contains "$TMP/status.md" "snapshot: fresh"
"${AGENTLY[@]}" doctrine status --json > "$TMP/status.json"
assert_contains "$TMP/status.json" '"provenance": "runtime-snapshot"'
assert_contains "$TMP/status.json" '"snapshot_status": "fresh"'

"${AGENTLY[@]}" ws new snap-ws >/dev/null
"${AGENTLY[@]}" packet status --workstream snap-ws > "$TMP/packet.md"
assert_contains "$TMP/packet.md" ".agently/doctrine"
assert_contains "$TMP/packet.md" "provenance: runtime-snapshot"
"${AGENTLY[@]}" context manifest > "$TMP/context.md"
assert_contains "$TMP/context.md" ".agently/doctrine"
"${AGENTLY[@]}" guard doctrine > "$TMP/guard.md"
assert_contains "$TMP/guard.md" "provenance: runtime-snapshot"
assert_contains "$TMP/guard.md" ".agently/doctrine"

mkdir -p docs/doctrine
printf 'STRAY TARGET DOCTRINE\n' > docs/doctrine/00-source-of-truth.md
rm -rf .agently/doctrine
"${AGENTLY[@]}" doctrine status > "$TMP/fallback-status.md"
assert_contains "$TMP/fallback-status.md" "provenance: installed-fallback"
assert_contains "$TMP/fallback-status.md" "snapshot: missing"
assert_not_contains "$TMP/fallback-status.md" "$PWD/docs/doctrine"
"${AGENTLY[@]}" packet status --workstream snap-ws > "$TMP/fallback-packet.md"
assert_contains "$TMP/fallback-packet.md" "provenance: installed-fallback"
assert_not_contains "$TMP/fallback-packet.md" "STRAY TARGET DOCTRINE"
assert_not_contains "$TMP/fallback-packet.md" "$PWD/docs/doctrine"

rm -rf docs/doctrine
"${AGENTLY[@]}" doctrine refresh --force > "$TMP/refresh.out" 2> "$TMP/refresh.err"
"${AGENTLY[@]}" doctrine status > "$TMP/refreshed-status.md"
assert_contains "$TMP/refreshed-status.md" "snapshot: fresh"

(cd "$ROOT" && "${AGENTLY[@]}" doctrine status > "$TMP/source-status.md")
assert_contains "$TMP/source-status.md" "provenance: source"
assert_contains "$TMP/source-status.md" "docs/doctrine"
[[ ! -e "$ROOT/.agently/doctrine" ]] || fail "source repo should not get .agently/doctrine from status"

FAKE_SOURCE="$TMP/fake-source"
new_repo "$FAKE_SOURCE"
mkdir -p "$FAKE_SOURCE/docs/doctrine" "$FAKE_SOURCE/lib" "$FAKE_SOURCE/bin"
printf '# Fake Source Doctrine\n' > "$FAKE_SOURCE/docs/doctrine/00-source-of-truth.md"
printf '#!/usr/bin/env bash\n' > "$FAKE_SOURCE/lib/agently.sh"
printf '#!/usr/bin/env bash\n' > "$FAKE_SOURCE/bin/agently"
chmod +x "$FAKE_SOURCE/bin/agently"
printf '0.0.0-test\n' > "$FAKE_SOURCE/VERSION"
"${AGENTLY[@]}" --project "$FAKE_SOURCE" init --codex > "$TMP/fake-source-init.out" 2> "$TMP/fake-source-init.err"
assert_not_exists "$FAKE_SOURCE/.agently/doctrine"

cd "$TMP/repo"
rm -rf .agently/doctrine
mkdir -p "$TMP/link-target"
ln -s "$TMP/link-target" .agently/doctrine
assert_fails init-symlink "$TMP/init-symlink.out" "$TMP/init-symlink.err" "${AGENTLY[@]}" init --codex --force
assert_contains "$TMP/init-symlink.err" "symlink"
assert_not_exists "$TMP/link-target/00-source-of-truth.md"
[[ -L .agently/doctrine ]] || fail "symlink should remain after refused init"
rm .agently/doctrine
"${AGENTLY[@]}" doctrine refresh --force >/dev/null
rm -rf .agently/doctrine
mkdir -p "$TMP/link-target-refresh"
ln -s "$TMP/link-target-refresh" .agently/doctrine
assert_fails refresh-symlink "$TMP/refresh-symlink.out" "$TMP/refresh-symlink.err" "${AGENTLY[@]}" doctrine refresh --force
assert_contains "$TMP/refresh-symlink.err" "symlink"
assert_not_exists "$TMP/link-target-refresh/00-source-of-truth.md"
rm .agently/doctrine
"${AGENTLY[@]}" doctrine refresh --force >/dev/null

marker=".agently/doctrine/.agently-doctrine-snapshot.yml"
tmp_marker="$TMP/marker.yml"
awk '{ if ($1 == "manifest_hash:") print "manifest_hash: corrupt"; else print }' "$marker" > "$tmp_marker"
mv "$tmp_marker" "$marker"
chmod 0444 "$marker"
"${AGENTLY[@]}" doctrine status > "$TMP/stale-status.md"
assert_contains "$TMP/stale-status.md" "snapshot: stale"
"${AGENTLY[@]}" doctor > "$TMP/doctor.md"
assert_contains "$TMP/doctor.md" "Doctrine snapshot is stale"
"${AGENTLY[@]}" doctrine refresh --force >/dev/null
"${AGENTLY[@]}" doctrine status > "$TMP/fresh-again.md"
assert_contains "$TMP/fresh-again.md" "snapshot: fresh"

cat > "$TMP/snapshot.diff" <<'DIFF'
diff --git a/.agently/doctrine/00-source-of-truth.md b/.agently/doctrine/00-source-of-truth.md
--- a/.agently/doctrine/00-source-of-truth.md
+++ b/.agently/doctrine/00-source-of-truth.md
@@ -1,1 +1,1 @@
-# Source Of Truth
+# Source Of Truth Edited
DIFF
"${AGENTLY[@]}" patch propose "$TMP/snapshot.diff" --workstream snap-ws > "$TMP/propose-snapshot.out" 2> "$TMP/propose-snapshot.err"
assert_contains "$TMP/propose-snapshot.out" "id: 001"
assert_contains "$TMP/propose-snapshot.err" "runtime-locked authority surface"
assert_fails apply-snapshot "$TMP/apply-snapshot.out" "$TMP/apply-snapshot.err" "${AGENTLY[@]}" patch apply 001 --workstream snap-ws --reviewed
assert_contains "$TMP/apply-snapshot.err" "runtime-locked authority surface: .agently/doctrine/00-source-of-truth.md"

printf 'doctrine snapshot ok\n'
