#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

shellcheck_version() {
  shellcheck --version 2>/dev/null | awk '/^version:/ { print $2; exit }' || true
}

install_shellcheck_binary() {
  local binary
  local install_dir
  local target

  binary="$1"
  install_dir="$2"
  target="$install_dir/shellcheck"

  if [ -d "$install_dir" ] && [ -w "$install_dir" ]; then
    mv "$binary" "$target" || fail "failed to install ShellCheck to $target"
    chmod +x "$target" || fail "failed to mark ShellCheck executable at $target"
    return
  fi

  command -v sudo >/dev/null 2>&1 || fail "install dir is not writable and sudo is unavailable: $install_dir"
  sudo mkdir -p "$install_dir" || fail "failed to create install dir: $install_dir"
  sudo mv "$binary" "$target" || fail "failed to install ShellCheck to $target"
  sudo chmod +x "$target" || fail "failed to mark ShellCheck executable at $target"
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
toolchain_env="$repo_root/ci/toolchain.env"

[ -f "$toolchain_env" ] || fail "missing toolchain manifest: $toolchain_env"

# shellcheck source=../ci/toolchain.env
# shellcheck disable=SC1091
. "$toolchain_env"

: "${SHELLCHECK_VERSION:?}"
: "${SHELLCHECK_LINUX_X86_64_SHA256:?}"
: "${SHELLCHECK_LINUX_AARCH64_SHA256:?}"
: "${SHELLCHECK_DARWIN_X86_64_SHA256:?}"
: "${SHELLCHECK_DARWIN_AARCH64_SHA256:?}"

if command -v shellcheck >/dev/null 2>&1; then
  installed_version="$(shellcheck_version)"
  if [ "$installed_version" = "$SHELLCHECK_VERSION" ]; then
    echo "ShellCheck $SHELLCHECK_VERSION already installed; skipping." >&2
    shellcheck --version
    exit 0
  fi
fi

os="$(uname -s)"
arch="$(uname -m)"

case "$os:$arch" in
  Linux:x86_64 | Linux:amd64)
    platform="linux.x86_64"
    sha256="$SHELLCHECK_LINUX_X86_64_SHA256"
    ;;
  Linux:aarch64 | Linux:arm64)
    platform="linux.aarch64"
    sha256="$SHELLCHECK_LINUX_AARCH64_SHA256"
    ;;
  Darwin:x86_64 | Darwin:amd64)
    platform="darwin.x86_64"
    sha256="$SHELLCHECK_DARWIN_X86_64_SHA256"
    ;;
  Darwin:aarch64 | Darwin:arm64)
    platform="darwin.aarch64"
    sha256="$SHELLCHECK_DARWIN_AARCH64_SHA256"
    ;;
  *)
    fail "unsupported ShellCheck platform: $os $arch"
    ;;
esac

asset="shellcheck-v${SHELLCHECK_VERSION}.${platform}.tar.xz"
url="https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/${asset}"
install_dir="${INSTALL_DIR:-/usr/local/bin}"
tmp_dir="$(mktemp -d)"
asset_path="$tmp_dir/$asset"
checksum_file="$tmp_dir/${asset}.sha256"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

echo "Installing ShellCheck $SHELLCHECK_VERSION for $platform." >&2

if command -v curl >/dev/null 2>&1; then
  curl -fsSL -o "$asset_path" "$url" || fail "failed to download $url"
elif command -v wget >/dev/null 2>&1; then
  wget -q -O "$asset_path" "$url" || fail "failed to download $url"
else
  fail "curl or wget is required to download ShellCheck"
fi

printf '%s  %s\n' "$sha256" "$asset_path" > "$checksum_file"
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum -c "$checksum_file" >/dev/null || fail "SHA256 verification failed for $asset"
elif command -v shasum >/dev/null 2>&1; then
  shasum -a 256 -c "$checksum_file" >/dev/null || fail "SHA256 verification failed for $asset"
else
  fail "sha256sum or shasum is required to verify ShellCheck"
fi

tar -xJf "$asset_path" -C "$tmp_dir" || fail "failed to extract $asset"
binary="$tmp_dir/shellcheck-v${SHELLCHECK_VERSION}/shellcheck"
[ -x "$binary" ] || fail "ShellCheck binary not found in $asset"

install_shellcheck_binary "$binary" "$install_dir"
hash -r 2>/dev/null || true

shellcheck --version
