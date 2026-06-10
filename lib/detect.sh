#!/usr/bin/env bash

tool_path_or_missing() {
  local name="$1"
  if has_cmd "$name"; then
    command -v "$name"
  else
    printf 'missing\n'
  fi
}

tool_state() {
  local name="$1"
  if has_cmd "$name"; then
    printf 'present\n'
  else
    printf 'missing\n'
  fi
}

tool_version_line() {
  local name="$1" out=""
  has_cmd "$name" || return 1
  case "$name" in
    shellcheck|ruff|mypy|pytest|go|golangci-lint|php|phpunit|pest|bats|ast-grep|rg|tree)
      set +e
      out="$("$name" --version 2>/dev/null | sed -n '1p')"
      local status=$?
      set -e
      [[ "$status" -eq 0 && -n "$out" ]] || return 1
      printf '%s\n' "$out"
      ;;
    *)
      command -v "$name"
      ;;
  esac
}

detect_tool_names() {
  cat <<'EOF'
ast-grep
rg
tree
shellcheck
ruff
mypy
pytest
go
golangci-lint
php
phpstan
phpunit
pest
bats
EOF
}

detect_vendor_tool() {
  local root="$1" tool="$2"
  case "$tool" in
    phpstan)
      [[ -x "$root/vendor/bin/phpstan" ]] && printf '%s/vendor/bin/phpstan\n' "$root" && return 0
      has_cmd phpstan && command -v phpstan && return 0
      ;;
    phpunit)
      [[ -x "$root/vendor/bin/phpunit" ]] && printf '%s/vendor/bin/phpunit\n' "$root" && return 0
      has_cmd phpunit && command -v phpunit && return 0
      ;;
    pest)
      [[ -x "$root/vendor/bin/pest" ]] && printf '%s/vendor/bin/pest\n' "$root" && return 0
      has_cmd pest && command -v pest && return 0
      ;;
  esac
  return 1
}

detect_tool_path_for_root() {
  local root="$1" tool="$2"
  case "$tool" in
    phpstan|phpunit|pest) detect_vendor_tool "$root" "$tool" ;;
    *) has_cmd "$tool" && command -v "$tool" ;;
  esac
}

detect_python_mypy_config() {
  local root="$1"
  [[ -f "$root/mypy.ini" ]] && return 0
  [[ -f "$root/.mypy.ini" ]] && return 0
  [[ -f "$root/setup.cfg" ]] && grep -Eq '^\[mypy\]' "$root/setup.cfg" && return 0
  [[ -f "$root/pyproject.toml" ]] && grep -Eq '^\[tool\.mypy\]' "$root/pyproject.toml" && return 0
  return 1
}

detect_python_tests() {
  local root="$1"
  [[ -f "$root/pytest.ini" || -f "$root/tox.ini" ]] && return 0
  [[ -f "$root/pyproject.toml" ]] && grep -Eq '^\[tool\.pytest' "$root/pyproject.toml" && return 0
  [[ -d "$root/tests" ]] && find "$root/tests" -type f -name '*.py' -print -quit 2>/dev/null | grep -q . && return 0
  return 1
}

detect_go_project() {
  local root="$1"
  [[ -f "$root/go.mod" ]]
}

detect_golangci_config() {
  local root="$1"
  [[ -f "$root/.golangci.yml" || -f "$root/.golangci.yaml" || -f "$root/golangci.yml" || -f "$root/golangci.yaml" ]]
}

detect_phpstan_config() {
  local root="$1"
  [[ -f "$root/phpstan.neon" || -f "$root/phpstan.neon.dist" ]]
}

detect_phpunit_config() {
  local root="$1"
  [[ -f "$root/phpunit.xml" || -f "$root/phpunit.xml.dist" ]]
}

detect_pest_config() {
  local root="$1"
  [[ -f "$root/tests/Pest.php" || -f "$root/pest.php" || -f "$root/pest.xml" || -f "$root/pest.xml.dist" ]]
}

detect_bats_tests() {
  local root="$1"
  find "$root" -type f -name '*.bats' -print -quit 2>/dev/null | grep -q .
}

detect_files_by_lang() {
  local root="$1" lang="$2" mode="${3:-all}" file rel
  case "$mode" in
    changed)
      while IFS= read -r rel; do
        [[ -n "$rel" && -f "$root/$rel" ]] || continue
        if [[ "$(detect_language_for_file "$root/$rel")" == "$lang" ]]; then
          printf '%s\n' "$rel"
        fi
      done < <(changed_files_for_root "$root")
      ;;
    all)
      case "$lang" in
        bash) find "$root" -type f \( -name '*.sh' -o -name '*.bash' \) -not -path "$root/.git/*" -not -path "$root/.agently/cache/*" | sort ;;
        python) find "$root" -type f -name '*.py' -not -path "$root/.git/*" -not -path "$root/.agently/cache/*" | sort ;;
        go) find "$root" -type f -name '*.go' -not -path "$root/.git/*" -not -path "$root/.agently/cache/*" | sort ;;
        php) find "$root" -type f -name '*.php' -not -path "$root/.git/*" -not -path "$root/.agently/cache/*" | sort ;;
        *) return 0 ;;
      esac | while IFS= read -r file; do
        rel_to_root "$root" "$file"
      done
      ;;
    *) die "unknown file detection mode: $mode" ;;
  esac
}

detect_project_languages() {
  local root="$1" found=0
  if find "$root" -type f \( -name '*.sh' -o -name '*.bash' \) -not -path "$root/.git/*" -print -quit 2>/dev/null | grep -q .; then
    printf 'bash\n'
    found=1
  fi
  if find "$root" -type f -name '*.py' -not -path "$root/.git/*" -print -quit 2>/dev/null | grep -q .; then
    printf 'python\n'
    found=1
  fi
  if detect_go_project "$root" || find "$root" -type f -name '*.go' -not -path "$root/.git/*" -print -quit 2>/dev/null | grep -q .; then
    printf 'go\n'
    found=1
  fi
  if find "$root" -type f -name '*.php' -not -path "$root/.git/*" -print -quit 2>/dev/null | grep -q .; then
    printf 'php\n'
    found=1
  fi
  [[ "$found" -eq 1 ]] || return 0
}
