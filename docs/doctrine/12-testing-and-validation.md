---
title: Testing And Validation
status: active
authority: doctrine
last_reviewed: 2026-06-03
---

# Testing And Validation

## Required Syntax Check

Run:

```bash
bash -n bin/agently lib/*.sh tests/*.sh
```

## Smoke Test

Run when reasonable:

```bash
./tests/smoke.sh
```

The smoke test MUST avoid network and real model calls.

## Optional Shellcheck

If available:

```bash
shellcheck bin/agently lib/*.sh tests/*.sh
```

## Smoke Test Doctrine

The smoke test SHOULD cover:

- temp HOME/XDG managed self install;
- dev-mode `AGENTLY_HOME`;
- managed self-install shim launcher;
- `agently init --codex`;
- idempotency and no-clobber;
- workstream lifecycle;
- task lifecycle;
- doc replace/show/path;
- Claude config and env overrides;
- packet clean-output behavior;
- stubbed Claude success;
- missing Claude fallback;
- eval/report/decide;
- real guard/eval behavior with stubbed local tools;
- packet compiler determinism;
- context cache and compaction freshness;
- bounded inspection;
- patch proposal/check/apply/reject behavior;
- new tooling command help;
- doctor/status/profile/workstream/evidence/prompt basics.
- Serena optional pack behavior, with stubbed Serena and Claude binaries.
- workstream branch binding, with local-only Git branch creation and no
  push/upstream/merge/delete/reset behavior.

## Stubbed Claude Pattern

Tests SHOULD use a local executable assigned to `AGENTLY_CLAUDE_CMD`. Tests MUST
NOT call a real model.

## Stubbed Tool Pattern

Guard/eval tests SHOULD inject fake tools through `PATH` for ShellCheck, Bats,
Ruff, Mypy, Go, golangci-lint, PHP, PHPStan, PHPUnit, Pest, and related optional
tooling. Tests MUST NOT require network access, package installation, or real
model calls.

## Packet Output Testing

Packet tests SHOULD assert:

- output starts with `#`;
- output is non-empty;
- output contains no ANSI escape byte.

## Final Report Expectations

Codex changes SHOULD report:

- files changed;
- commands run;
- validation results;
- deviations;
- final `git status --short`;
- doctrine files consulted when relevant.
