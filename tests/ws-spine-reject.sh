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

pty_reject() {
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
    os.execv(cmd, [cmd, "ws", "reject", alias, "--json"])
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
  printf '# Reject\n' > README.md
  git add README.md
  git commit -q -m init
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" init --codex >/dev/null
  awk '{ if ($1 == "confirm_timeout_seconds:") print "    confirm_timeout_seconds: 1"; else print }' .agently/config.yml > .agently/config.tmp
  mv .agently/config.tmp .agently/config.yml
  printf 'reject body\n' > payload.md
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws init "$ws" --json >/dev/null
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws ingest "$ws" --type plan --file payload.md --json >/dev/null
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws propose "$ws-PLN1" --json >/dev/null
}

setup_case "$TMP/noninteractive" WRN
cd "$TMP/noninteractive"
set +e
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws reject WRN-PLN1 --json > "$TMP/non.out" 2> "$TMP/non.err"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "noninteractive reject should fail"
assert_code "$TMP/non.err" REJECTION_REQUIRES_INTERACTIVE_PATH

setup_case "$TMP/wrong" WRW
cd "$TMP/wrong"
set +e
pty_reject "$TMP/wrong" WRW-PLN1 WRONG "$TMP/wrong.out" "$TMP/wrong.err"
status=$?
set -e
[[ "$status" -ne 0 && "$status" -ne 77 ]] || fail "wrong alias reject should fail"
assert_code "$TMP/wrong.err" REJECTION_NOT_CONFIRMED

setup_case "$TMP/timeout" WRT
cd "$TMP/timeout"
set +e
pty_reject "$TMP/timeout" WRT-PLN1 WRT-PLN1 "$TMP/timeout.out" "$TMP/timeout.err" nowrite
status=$?
set -e
[[ "$status" -ne 0 && "$status" -ne 77 ]] || fail "timeout reject should fail"
assert_code "$TMP/timeout.err" REJECTION_CONFIRMATION_TIMEOUT

setup_case "$TMP/success" WRS
cd "$TMP/success"
pty_reject "$TMP/success" WRS-PLN1 WRS-PLN1 "$TMP/success.out" "$TMP/success.err"
assert_json "$TMP/success.out"
[[ ! -s "$TMP/success.err" ]] || fail "reject success stderr not empty"
[[ "$(jq -r '.state' .agently/workstreams/WRS/manifest.json)" == "open" ]] || fail "reject did not reopen"
[[ "$(jq -r '.proposed // empty' .agently/workstreams/WRS/manifest.json)" == "" ]] || fail "proposed not cleared"
[[ "$(jq -r '.candidates["WRS-PLN1"].status' .agently/workstreams/WRS/manifest.json)" == "rejected" ]] || fail "candidate not rejected"
[[ -f .agently/workstreams/WRS/raw/WRS-PLN1.raw.md ]] || fail "raw evidence missing"
[[ -f .agently/workstreams/WRS/candidates/WRS-PLN1.md ]] || fail "candidate evidence missing"
[[ -f .agently/workstreams/WRS/proposed/WRS-PLN1.md ]] || fail "proposed evidence missing"
[[ ! -e .agently/workstreams/WRS/canonical/WRS-PLN1.md ]] || fail "canonical should not exist after reject"
grep -Fq "candidate_rejected" .agently/workstreams/WRS/events.jsonl || fail "rejection event missing"
set +e
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws propose WRS-PLN1 --json > "$TMP/reprop.out" 2> "$TMP/reprop.err"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "rejected artifact should not be reproposed"
assert_code "$TMP/reprop.err" NOT_PROPOSED
AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" ws doctor WRS --verify-hashes --json >/dev/null
