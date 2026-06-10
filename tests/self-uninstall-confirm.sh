#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_empty() { [[ ! -s "$1" ]] || fail "expected empty file: $1"; }
assert_json() { jq -e . "$1" >/dev/null || fail "invalid JSON: $1"; }
assert_code() { [[ "$(jq -r '.error.code' "$1")" == "$2" ]] || fail "expected code $2 in $1"; }
assert_file() { [[ -f "$1" ]] || fail "missing file: $1"; }
assert_dir() { [[ -d "$1" ]] || fail "missing directory: $1"; }
assert_not_exists() { [[ ! -e "$1" ]] || fail "unexpected path: $1"; }

command -v jq >/dev/null 2>&1 || fail "jq required for self uninstall confirm tests"
command -v python3 >/dev/null 2>&1 || fail "python3 pty support required for self uninstall confirm tests"

cat > "$TMP/run-pty.py" <<'PY'
import os
import pty
import select
import signal
import sys
import time

cmd = sys.argv[1]
out_path = sys.argv[2]
err_path = sys.argv[3]
response = sys.argv[4] if len(sys.argv) > 4 else ""
wait_before_write = float(os.environ.get("PTY_WRITE_DELAY", "0.2"))
deadline = time.time() + float(os.environ.get("PTY_DEADLINE", "8"))

pid, fd = pty.fork()
if pid == 0:
    out_fd = os.open(out_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    err_fd = os.open(err_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.dup2(out_fd, 1)
    os.dup2(err_fd, 2)
    os.close(out_fd)
    os.close(err_fd)
    os.execv(cmd, [cmd, "self", "uninstall", "--user", "--confirm", "--json"])

if response != "__NO_WRITE__":
    time.sleep(wait_before_write)
    os.write(fd, response.encode("utf-8") + b"\n")

status = None
while True:
    try:
        ready, _, _ = select.select([fd], [], [], 0.1)
        if ready:
            try:
                os.read(fd, 4096)
            except OSError:
                pass
    except OSError:
        pass
    waited, raw = os.waitpid(pid, os.WNOHANG)
    if waited == pid:
        status = raw
        break
    if time.time() > deadline:
        os.kill(pid, signal.SIGTERM)
        waited, raw = os.waitpid(pid, 0)
        status = raw
        break

if os.WIFEXITED(status):
    sys.exit(os.WEXITSTATUS(status))
sys.exit(128)
PY

cat > "$TMP/run-no-tty.py" <<'PY'
import os
import subprocess
import sys

cmd = sys.argv[1]
out_path = sys.argv[2]
err_path = sys.argv[3]
with open(out_path, "wb") as out, open(err_path, "wb") as err, open(os.devnull, "rb") as devnull:
    proc = subprocess.run(
        [cmd, "self", "uninstall", "--user", "--confirm", "--json"],
        stdin=devnull,
        stdout=out,
        stderr=err,
        start_new_session=True,
        check=False,
    )
sys.exit(proc.returncode)
PY

setup_env() {
  local name="$1"
  export HOME="$TMP/$name/home"
  export XDG_DATA_HOME="$TMP/$name/xdg-data"
  export XDG_STATE_HOME="$TMP/$name/xdg-state"
  export XDG_CONFIG_HOME="$TMP/$name/xdg-config"
  mkdir -p "$HOME"
}

install_managed() {
  AGENTLY_HOME="$ROOT" "$ROOT/bin/agently" self install --user --from "$ROOT" --apply --json > "$TMP/install-$1.json" 2> "$TMP/install-$1.err"
  assert_json "$TMP/install-$1.json"
  assert_empty "$TMP/install-$1.err"
}

setup_env managed
install_managed managed
mkdir -p "$XDG_CONFIG_HOME/agently" "$XDG_STATE_HOME/agently" "$TMP/project/.agently"
printf 'config\n' > "$XDG_CONFIG_HOME/agently/config"
printf 'state\n' > "$XDG_STATE_HOME/agently/state"
printf 'project\n' > "$TMP/project/.agently/state"

set +e
AGENTLY_HOME="$ROOT" python3 "$TMP/run-no-tty.py" "$ROOT/bin/agently" "$TMP/notty.out" "$TMP/notty.err"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "no-tty uninstall should fail"
assert_empty "$TMP/notty.out"
assert_json "$TMP/notty.err"
assert_code "$TMP/notty.err" UNINSTALL_REQUIRES_INTERACTIVE_PATH
assert_file "$HOME/.local/bin/agently"
assert_dir "$XDG_DATA_HOME/agently"

set +e
AGENTLY_HOME="$ROOT" python3 "$TMP/run-pty.py" "$ROOT/bin/agently" "$TMP/wrong.out" "$TMP/wrong.err" "wrong phrase"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "wrong confirmation should fail"
assert_empty "$TMP/wrong.out"
assert_json "$TMP/wrong.err"
assert_code "$TMP/wrong.err" UNINSTALL_NOT_CONFIRMED
assert_file "$HOME/.local/bin/agently"
assert_dir "$XDG_DATA_HOME/agently"

set +e
AGENTLY_SELF_CONFIRM_TIMEOUT_SECONDS=1 AGENTLY_HOME="$ROOT" PTY_DEADLINE=5 python3 "$TMP/run-pty.py" "$ROOT/bin/agently" "$TMP/timeout.out" "$TMP/timeout.err" "__NO_WRITE__"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "timeout confirmation should fail"
assert_empty "$TMP/timeout.out"
assert_json "$TMP/timeout.err"
assert_code "$TMP/timeout.err" UNINSTALL_CONFIRMATION_TIMEOUT
assert_file "$HOME/.local/bin/agently"
assert_dir "$XDG_DATA_HOME/agently"

phrase="$XDG_DATA_HOME/agently"
(
  cd "$TMP/project"
  set +e
  AGENTLY_HOME="$ROOT" python3 "$TMP/run-pty.py" "$ROOT/bin/agently" "$TMP/confirm.out" "$TMP/confirm.err" "$phrase"
  status=$?
  set -e
  [[ "$status" -eq 0 ]] || fail "confirmed uninstall failed"
)
assert_json "$TMP/confirm.out"
assert_empty "$TMP/confirm.err"
jq -e --arg shim "$HOME/.local/bin/agently" --arg share "$XDG_DATA_HOME/agently" --arg config "$XDG_CONFIG_HOME/agently" --arg state "$XDG_STATE_HOME/agently" '
  .ok == true and
  .command == "self_uninstall" and
  .dry_run == false and
  .mutated == true and
  (.removed | index($shim)) and
  (.removed | index($share)) and
  (.kept | index($config)) and
  (.kept | index($state))
' "$TMP/confirm.out" >/dev/null || fail "bad confirmed uninstall JSON"
grep -Fq "$TMP/project/.agently" "$TMP/confirm.out" && fail "confirmed uninstall listed project .agently path"
assert_not_exists "$HOME/.local/bin/agently"
assert_not_exists "$XDG_DATA_HOME/agently"
assert_file "$XDG_CONFIG_HOME/agently/config"
assert_file "$XDG_STATE_HOME/agently/state"
assert_file "$TMP/project/.agently/state"

setup_env unmanaged
mkdir -p "$HOME/.local/bin" "$XDG_DATA_HOME/agently" "$XDG_STATE_HOME/agently"
printf '#!/usr/bin/env bash\nprintf unmanaged\n' > "$HOME/.local/bin/agently"
chmod +x "$HOME/.local/bin/agently"
printf 'share\n' > "$XDG_DATA_HOME/agently/file"
phrase="$XDG_DATA_HOME/agently"
set +e
AGENTLY_HOME="$ROOT" python3 "$TMP/run-pty.py" "$ROOT/bin/agently" "$TMP/unmanaged.out" "$TMP/unmanaged.err" "$phrase"
status=$?
set -e
[[ "$status" -eq 0 ]] || fail "unmanaged shim confirm should still remove share"
assert_json "$TMP/unmanaged.out"
assert_empty "$TMP/unmanaged.err"
jq -e '.warnings[]? | select(.code == "UNMANAGED_SHIM")' "$TMP/unmanaged.out" >/dev/null || fail "unmanaged shim warning missing"
assert_file "$HOME/.local/bin/agently"
assert_not_exists "$XDG_DATA_HOME/agently"

printf 'self uninstall confirm ok\n'

