#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/check-local-tools.sh [--core] [--validation] [--recommended] [--all]

Checks local tool availability by tier. With no flags, --all is used.

Flags:
  --core          Check required core tools.
  --validation    Check required validation tools.
  --recommended   Check recommended tools.
  --all           Check core, validation, recommended, and optional integrations.
  --help          Show this help.
USAGE
}

have() {
  command -v "$1" >/dev/null 2>&1
}

status_line() {
  local name="$1" status="$2"
  printf '  %-28s %s\n' "$name" "$status"
}

check_required_tools() {
  local heading="$1" missing=0 tool
  shift
  printf '%s\n' "$heading"
  for tool in "$@"; do
    if have "$tool"; then
      status_line "$tool" "ok"
    else
      status_line "$tool" "MISSING"
      missing=1
    fi
  done
  printf '\n'
  return "$missing"
}

check_report_only_tools() {
  local heading="$1" tool
  shift
  printf '%s\n' "$heading"
  for tool in "$@"; do
    if have "$tool"; then
      status_line "$tool" "ok"
    else
      status_line "$tool" "MISSING"
    fi
  done
  printf '\n'
}

check_validation() {
  local missing=0

  printf 'required validation\n'
  for tool in shellcheck python3; do
    if have "$tool"; then
      status_line "$tool" "ok"
    else
      status_line "$tool" "MISSING"
      missing=1
    fi
  done

  if have rg; then
    status_line "offline-tripwire-checker" "ok (rg)"
  elif have find && have grep; then
    status_line "offline-tripwire-checker" "ok (find+grep)"
  else
    status_line "offline-tripwire-checker" "MISSING"
    printf 'FAIL: offline tripwire cannot be enforced: need rg or find+grep\n' >&2
    missing=1
  fi

  printf '\n'
  return "$missing"
}

want_core=0
want_validation=0
want_recommended=0
want_optional=0

if [[ "$#" -eq 0 ]]; then
  want_core=1
  want_validation=1
  want_recommended=1
  want_optional=1
fi

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --core)
      want_core=1
      ;;
    --validation)
      want_validation=1
      ;;
    --recommended)
      want_recommended=1
      ;;
    --all)
      want_core=1
      want_validation=1
      want_recommended=1
      want_optional=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'FAIL: unknown flag: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

exit_status=0

if [[ "$want_core" -eq 1 ]]; then
  check_required_tools "required core" \
    bash git jq realpath mktemp sha256sum flock grep sed awk find sort date || exit_status=1
fi

if [[ "$want_validation" -eq 1 ]]; then
  check_validation || exit_status=1
fi

if [[ "$want_recommended" -eq 1 ]]; then
  check_report_only_tools "recommended" tree ast-grep rg
fi

if [[ "$want_optional" -eq 1 ]]; then
  check_report_only_tools "optional integrations (informational)" \
    claude codex serena serena-mcp-server uvx go pytest ruff mypy phpstan phpunit bats
fi

exit "$exit_status"
