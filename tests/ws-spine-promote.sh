#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_code() { [[ "$(jq -r '.error.code' "$1")" == "$2" ]] || fail "expected code $2 in $1"; }
assert_json() { jq -e . "$1" >/dev/null || fail "invalid JSON: $1"; }

for tool in jq sha256sum flock; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool required for spine tests"
done

pty_confirm() {
  local repo="$1" alias="$2" typed="$3" out="$4" err="$5" mode="${6:-write}"
  command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 pty helper unavailable" >&2; return 77; }
  python3 - "$ROOT/bin/agently" "$repo" "$alias" "$typed" "$out" "$err" "$mode" <<'PY'
import os, pty, select, sys, time
cmd, repo, alias, typed, out_path, err_path, mode = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    os.chdir(repo)
    os.environ["AGENTLY_HOME"] = os.path.dirname(os.path.dirname(cmd))
    out = os.open(out_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
    err = os.open(err_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
    os.dup2(out, 1)
    os.dup2(err, 2)
    os.execv(cmd, [cmd, "ws", "promote", alias, "--json"])
deadline = time.time() + 6
sent = False
buf = b""
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.1)
    if fd in r:
        try:
            chunk = os.read(fd, 1024)
        except OSError:
            break
        if not chunk:
            break
        buf += chunk
        if mode == "write" and not sent and b"Type " in buf:
            os.write(fd, typed.encode() + b"\n")
            sent = True
_, status = os.waitpid(pid, 0)
sys.exit(os.WEXITSTATUS(status))
PY
}

setup_case() {
  local repo="$1" ws="$2"
  mkdir -p "$repo"
  cd "$repo"
  git init -q
  git config user.email spine@example.invalid
  git config user.name Spine
  printf '# Promote\n' > README.md
  git add README.md
  git commit -q -m init
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" init --codex >/dev/null
  awk '{ if ($1 == "confirm_timeout_seconds:") print "    confirm_timeout_seconds: 1"; else print }' .agently/config.yml > .agently/config.tmp
  mv .agently/config.tmp .agently/config.yml
  printf 'promote body\n' > payload.md
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws init "$ws" --json >/dev/null
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws ingest "$ws" --type plan --file payload.md --json >/dev/null
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws propose "$ws-PLN1" --json >/dev/null
}

setup_case "$TMP/noninteractive" WPR
cd "$TMP/noninteractive"
set +e
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws promote WPR-PLN1 --json > "$TMP/non.out" 2> "$TMP/non.err"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "noninteractive promote should fail"
assert_code "$TMP/non.err" PROMOTION_REQUIRES_INTERACTIVE_PATH
[[ ! -e .agently/workstreams/WPR/canonical/WPR-PLN1.md ]] || fail "canonical written after failed promote"

setup_case "$TMP/wrong" WPW
cd "$TMP/wrong"
set +e
pty_confirm "$TMP/wrong" WPW-PLN1 WRONG "$TMP/wrong.out" "$TMP/wrong.err"
status=$?
set -e
[[ "$status" -ne 0 && "$status" -ne 77 ]] || fail "wrong alias promote should fail"
assert_code "$TMP/wrong.err" PROMOTION_NOT_CONFIRMED
[[ ! -e .agently/workstreams/WPW/canonical/WPW-PLN1.md ]] || fail "canonical written after wrong confirmation"

setup_case "$TMP/timeout" WPT
cd "$TMP/timeout"
set +e
pty_confirm "$TMP/timeout" WPT-PLN1 WPT-PLN1 "$TMP/timeout.out" "$TMP/timeout.err" nowrite
status=$?
set -e
[[ "$status" -ne 0 && "$status" -ne 77 ]] || fail "timeout promote should fail"
assert_code "$TMP/timeout.err" PROMOTION_CONFIRMATION_TIMEOUT
[[ ! -e .agently/workstreams/WPT/canonical/WPT-PLN1.md ]] || fail "canonical written after timeout"

setup_case "$TMP/success" WPS
cd "$TMP/success"
pty_confirm "$TMP/success" WPS-PLN1 WPS-PLN1 "$TMP/success.out" "$TMP/success.err" write
assert_json "$TMP/success.out"
[[ ! -s "$TMP/success.err" ]] || fail "promote success stderr not empty"
[[ -f .agently/workstreams/WPS/canonical/WPS-PLN1.md ]] || fail "missing canonical"
grep -Fq "status: canonical" .agently/workstreams/WPS/canonical/WPS-PLN1.md || fail "canonical header missing status"
grep -Fq "authority: promoted_canonical" .agently/workstreams/WPS/canonical/WPS-PLN1.md || fail "canonical header missing authority"
[[ "$(jq -r '.state' .agently/workstreams/WPS/manifest.json)" == "open" ]] || fail "promote did not clear escrow"
[[ "$(jq -r '.candidates["WPS-PLN1"].status' .agently/workstreams/WPS/manifest.json)" == "promoted" ]] || fail "candidate not promoted"
grep -Fq "candidate_promoted" .agently/workstreams/WPS/events.jsonl || fail "promotion event missing"
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws doctor WPS --verify-hashes --json >/dev/null
