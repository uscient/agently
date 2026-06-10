#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/install-local-tools.sh --core|--validation|--recommended [--dry-run] [--yes]

Installs local tool packages for explicitly selected tiers.

Flags:
  --core          Include required core packages.
  --validation    Include required validation packages.
  --recommended   Include recommended packages.
  --dry-run       Print the install command and exit without installing.
  --yes           Skip confirmation prompt.
  --help          Show this help.
USAGE
}

have() {
  command -v "$1" >/dev/null 2>&1
}

append_package() {
  local package="$1" existing
  for existing in "${packages[@]}"; do
    [[ "$existing" == "$package" ]] && return 0
  done
  packages+=("$package")
}

append_packages() {
  local package
  for package in "$@"; do
    append_package "$package"
  done
}

print_command() {
  local part
  for part in "$@"; do
    printf '%q ' "$part"
  done
  printf '\n'
}

sudo_prefix() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    return 0
  fi
  if have sudo; then
    printf '%s\n' sudo
  fi
}

manager=""
manager_cmd=""
if have apt-get; then
  manager="apt"
  manager_cmd="apt-get"
elif have apt; then
  manager="apt"
  manager_cmd="apt"
elif have dnf; then
  manager="dnf"
  manager_cmd="dnf"
elif have brew; then
  manager="brew"
  manager_cmd="brew"
elif have pacman; then
  manager="pacman"
  manager_cmd="pacman"
fi

want_core=0
want_validation=0
want_recommended=0
dry_run=0
yes=0

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
    --dry-run)
      dry_run=1
      ;;
    --yes)
      yes=1
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

if [[ "$want_core" -eq 0 && "$want_validation" -eq 0 && "$want_recommended" -eq 0 ]]; then
  printf 'FAIL: select at least one tier: --core, --validation, or --recommended\n' >&2
  usage >&2
  exit 2
fi

packages=()

if [[ -z "$manager" ]]; then
  [[ "$want_core" -eq 1 ]] && append_packages bash git jq coreutils util-linux grep sed gawk findutils
  [[ "$want_validation" -eq 1 ]] && append_packages shellcheck ripgrep python3
  [[ "$want_recommended" -eq 1 ]] && append_packages tree ast-grep
  printf 'FAIL: no supported package manager found; install these packages manually:\n' >&2
  printf '  %s\n' "${packages[*]}" >&2
  exit 1
fi

case "$manager" in
  apt)
    [[ "$want_core" -eq 1 ]] && append_packages bash git jq coreutils util-linux grep sed gawk findutils
    [[ "$want_validation" -eq 1 ]] && append_packages shellcheck ripgrep python3
    [[ "$want_recommended" -eq 1 ]] && append_packages tree ast-grep
    install_cmd=("$manager_cmd" install -y)
    ;;
  dnf)
    [[ "$want_core" -eq 1 ]] && append_packages bash git jq coreutils util-linux grep sed gawk findutils
    [[ "$want_validation" -eq 1 ]] && append_packages ShellCheck ripgrep python3
    [[ "$want_recommended" -eq 1 ]] && append_packages tree ast-grep
    install_cmd=("$manager_cmd" install -y)
    ;;
  brew)
    [[ "$want_core" -eq 1 ]] && append_packages bash git jq coreutils util-linux grep gnu-sed gawk findutils
    [[ "$want_validation" -eq 1 ]] && append_packages shellcheck ripgrep python
    [[ "$want_recommended" -eq 1 ]] && append_packages tree ast-grep
    install_cmd=("$manager_cmd" install)
    ;;
  pacman)
    [[ "$want_core" -eq 1 ]] && append_packages bash git jq coreutils util-linux grep sed gawk findutils
    [[ "$want_validation" -eq 1 ]] && append_packages shellcheck ripgrep python
    [[ "$want_recommended" -eq 1 ]] && append_packages tree ast-grep
    install_cmd=("$manager_cmd" -S --needed --noconfirm)
    ;;
  *)
    printf 'FAIL: unsupported package manager: %s\n' "$manager" >&2
    exit 1
    ;;
esac

if [[ "$manager" != "brew" ]]; then
  sudo_bin="$(sudo_prefix)"
  if [[ -n "$sudo_bin" ]]; then
    install_cmd=("$sudo_bin" "${install_cmd[@]}")
  fi
fi

install_cmd+=("${packages[@]}")

printf 'Package manager: %s\n' "$manager_cmd"
printf 'Packages: %s\n' "${packages[*]}"
printf 'Command: '
print_command "${install_cmd[@]}"

if [[ "$dry_run" -eq 1 ]]; then
  exit 0
fi

if [[ "$yes" -ne 1 ]]; then
  printf 'Proceed with install? [y/N] '
  if ! read -r reply; then
    printf 'Aborted.\n'
    exit 1
  fi
  case "$reply" in
    y|Y|yes|YES)
      ;;
    *)
      printf 'Aborted.\n'
      exit 1
      ;;
  esac
fi

"${install_cmd[@]}"
