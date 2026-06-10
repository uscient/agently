---
title: Guard And Eval Pipeline
status: active
authority: doctrine
last_reviewed: 2026-06-03
---

# Guard And Eval Pipeline

## Guard Role

Guard commands run bounded local checks through detected local tools. Missing
optional tools should be reported clearly and degrade gracefully unless strict
mode is requested.

## Eval Role

Eval commands aggregate guard evidence. Patch eval applies a proposed patch only
inside a throwaway Git worktree and MUST NOT mutate the live tree.

## Safe Execution

Guard/eval commands MUST run external tools as argv arrays. They MUST NOT use
`eval` or run agent-provided command strings through `bash -c`.

## Output And Logs

Long command output should be routed through safe truncation. Full logs belong in
visible Agently cache or patch artifact paths. Exit codes from failing tools must
be preserved or surfaced as the aggregate eval status.

## Tool Scope

Guard support is best-effort for Bash, Python, Go, and PHP using locally detected
linters, analyzers, and test runners. Agently does not install tools.
