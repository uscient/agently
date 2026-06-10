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

assert_no_ansi() {
  local file="$1"
  if LC_ALL=C grep -q "$(printf '\033')" "$file"; then
    fail "ANSI byte found in $file"
  fi
}

new_repo() {
  local dir="$1"
  mkdir -p "$dir"
  cd "$dir"
  git init -q
  git config user.email packet-smoke@example.invalid
  git config user.name PacketSmoke
  printf '# Packet Smoke\n' > README.md
  git add README.md
  git commit -q -m init
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" init --codex >/dev/null
}

AGENTLY=(env AGENTLY_HOME="$ROOT" "$ROOT/bin/agently")

new_repo "$TMP/repo"
"${AGENTLY[@]}" ws new packet-ws >/dev/null
"${AGENTLY[@]}" task new compile-packet --workstream packet-ws >/dev/null
cat <<'MD' | "${AGENTLY[@]}" doc replace requirements --workstream packet-ws --task compile-packet >/dev/null
# Requirements

- Keep packet prefixes stable.
- Use digests at normal budget.

This exact raw paragraph should only appear in full budget packets.

Full budget fixture line 01 with implementation detail text.
Full budget fixture line 02 with implementation detail text.
Full budget fixture line 03 with implementation detail text.
Full budget fixture line 04 with implementation detail text.
Full budget fixture line 05 with implementation detail text.
Full budget fixture line 06 with implementation detail text.
Full budget fixture line 07 with implementation detail text.
Full budget fixture line 08 with implementation detail text.
Full budget fixture line 09 with implementation detail text.
Full budget fixture line 10 with implementation detail text.
Full budget fixture line 11 with implementation detail text.
Full budget fixture line 12 with implementation detail text.
Full budget fixture line 13 with implementation detail text.
Full budget fixture line 14 with implementation detail text.
Full budget fixture line 15 with implementation detail text.
Full budget fixture line 16 with implementation detail text.
Full budget fixture line 17 with implementation detail text.
Full budget fixture line 18 with implementation detail text.
Full budget fixture line 19 with implementation detail text.
Full budget fixture line 20 with implementation detail text.
MD
cat <<'MD' | "${AGENTLY[@]}" doc replace context --workstream packet-ws --task compile-packet >/dev/null
# Context

- Context bullet one.
- Context bullet two.
MD
"${AGENTLY[@]}" task set-state requirements_ready --workstream packet-ws --task compile-packet >/dev/null

for packet in claude codex status review; do
  "${AGENTLY[@]}" packet "$packet" --workstream packet-ws --task compile-packet > "$TMP/shortcut-$packet.md"
  assert_contains "$TMP/shortcut-$packet.md" '<cache_breakpoint/>'
  assert_contains "$TMP/shortcut-$packet.md" '<workstream_state>'
  assert_not_contains "$TMP/shortcut-$packet.md" "This exact raw paragraph should only appear"
  head -n 1 "$TMP/shortcut-$packet.md" | grep -q '^<base_contract profile=' || fail "packet shortcut $packet did not use compiler output"
  awk '/<cache_breakpoint\/>/{exit} {print}' "$TMP/shortcut-$packet.md" > "$TMP/shortcut-prefix-$packet.md"
  assert_not_contains "$TMP/shortcut-prefix-$packet.md" "generated:"
  assert_not_contains "$TMP/shortcut-prefix-$packet.md" "dirty_count:"
  assert_no_ansi "$TMP/shortcut-$packet.md"
done
"${AGENTLY[@]}" packet --profile claude --workstream packet-ws --task compile-packet --budget normal > "$TMP/explicit-claude.md"
awk '/<cache_breakpoint\/>/{exit} {print}' "$TMP/explicit-claude.md" > "$TMP/explicit-prefix-claude.md"
diff -u "$TMP/shortcut-prefix-claude.md" "$TMP/explicit-prefix-claude.md" >/dev/null ||
  fail "packet claude shortcut does not map to --profile claude --budget normal prefix"
"${AGENTLY[@]}" packet --profile codex --workstream packet-ws --task compile-packet --budget normal > "$TMP/explicit-codex.md"
awk '/<cache_breakpoint\/>/{exit} {print}' "$TMP/explicit-codex.md" > "$TMP/explicit-prefix-codex.md"
diff -u "$TMP/shortcut-prefix-codex.md" "$TMP/explicit-prefix-codex.md" >/dev/null ||
  fail "packet codex shortcut does not map to --profile codex --budget normal prefix"

"${AGENTLY[@]}" packet --profile claude --workstream packet-ws --task compile-packet --budget normal --objective "Plan the packet compiler." > "$TMP/packet-a.md"
"${AGENTLY[@]}" packet --profile claude --workstream packet-ws --task compile-packet --budget normal --objective "Plan the packet compiler." > "$TMP/packet-b.md"

assert_contains "$TMP/packet-a.md" '<base_contract profile="claude"'
assert_contains "$TMP/packet-a.md" '<doctrine_manifest>'
assert_contains "$TMP/packet-a.md" ".agently/doctrine"
assert_contains "$TMP/packet-a.md" "provenance: runtime-snapshot"
assert_contains "$TMP/packet-a.md" '<agent_rules>'
assert_contains "$TMP/packet-a.md" '<cache_breakpoint/>'
assert_contains "$TMP/packet-a.md" '<workstream_state>'
assert_contains "$TMP/packet-a.md" '<context_menu>'
assert_no_ansi "$TMP/packet-a.md"

awk '/<cache_breakpoint\/>/{exit} {print}' "$TMP/packet-a.md" > "$TMP/prefix-a.md"
awk '/<cache_breakpoint\/>/{exit} {print}' "$TMP/packet-b.md" > "$TMP/prefix-b.md"
diff -u "$TMP/prefix-a.md" "$TMP/prefix-b.md" >/dev/null || fail "compiled packet prefix changed across runs"
assert_not_contains "$TMP/prefix-a.md" "generated:"
assert_not_contains "$TMP/prefix-a.md" "dirty_count:"

awk 'seen { print } /<cache_breakpoint\/>/ { seen=1 }' "$TMP/packet-a.md" > "$TMP/dynamic.md"
assert_contains "$TMP/dynamic.md" "generated:"
assert_contains "$TMP/dynamic.md" "dirty_count:"

assert_not_contains "$TMP/packet-a.md" "This exact raw paragraph should only appear"
"${AGENTLY[@]}" packet --profile codex --workstream packet-ws --task compile-packet --budget small > "$TMP/packet-small.md"
"${AGENTLY[@]}" packet --profile codex --workstream packet-ws --task compile-packet --budget full > "$TMP/packet-full.md"
assert_contains "$TMP/packet-full.md" "This exact raw paragraph should only appear"

small_bytes="$(wc -c < "$TMP/packet-small.md")"
normal_bytes="$(wc -c < "$TMP/packet-a.md")"
full_bytes="$(wc -c < "$TMP/packet-full.md")"
[[ "$small_bytes" -lt "$normal_bytes" ]] || fail "small packet should be smaller than normal"
[[ "$normal_bytes" -lt "$full_bytes" ]] || fail "normal packet should be smaller than full"

"${AGENTLY[@]}" packet --budget small --workstream packet-ws --task compile-packet > "$TMP/packet-budget-only.md"
assert_contains "$TMP/packet-budget-only.md" '<base_contract profile="generic"'

"${AGENTLY[@]}" packet inspect --profile claude --workstream packet-ws --task compile-packet --budget normal --json > "$TMP/packet-inspect.json"
assert_contains "$TMP/packet-inspect.json" '"sections"'
assert_contains "$TMP/packet-inspect.json" '"base_contract"'
assert_contains "$TMP/packet-inspect.json" '"est_tokens"'

printf 'packet compiler smoke ok\n'
