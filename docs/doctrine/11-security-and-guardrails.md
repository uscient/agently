---
title: Security And Guardrails
status: active
authority: doctrine
last_reviewed: 2026-06-03
---

# Security And Guardrails

## Current Guard Status

Guard commands are active local checks:

```bash
agently guard
agently guard --changed
agently guard --file <file>
agently guard --lang bash|python|go|php
agently guard scope|secret|artifact|diff|doctrine
```

They run only detected local tools. Missing optional tools are reported and
skipped unless strict mode is requested.

## Eval Guard Status

Eval commands aggregate guard evidence:

```bash
agently eval
agently eval patch <id> --workstream <ws>
agently eval claude --workstream <ws> --task <task>
```

Patch eval MUST use a throwaway worktree and MUST NOT mutate the live tree.

## Phase 1 Safety Model

Phase 1 safety is based on:

- local filesystem operation;
- visible `.agently/` state;
- conservative init overwrite behavior;
- no database;
- no daemon;
- no autonomous execution;
- no source mutation by Agently beyond init scaffolding, workflow state, and
  explicit `agently patch apply <id> --workstream <ws> --reviewed`;
- no secret management promise.
- no hidden global Codex, Claude, or Serena configuration mutation.

See [15-serena-integration.md](15-serena-integration.md) for the Serena-specific
MCP mutation boundary, generated-snippet-first policy, and onboarding limits.

## Client Boundary

Serena, future `agently-mcp`, future TUI clients, and other clients are not
authority layers. They MUST NOT administer Agently self lifecycle, directly
mutate `.agently/**`, or promote canonical workflow state autonomously. Canonical
workflow mutation goes through Agently CLI contracts and promotion requires an
explicit human/governance gate.

## Risks

Known risks:

- shell quoting mistakes;
- unsafe overwrite;
- Claude/Codex authority collision;
- stale doctrine;
- accidental source mutation;
- `AGENTLY_CLAUDE_CMD` misuse.
- missing optional guard tools causing degraded local checks.

## Command Override Warning

`AGENTLY_CLAUDE_CMD` is trusted local environment configuration only. It executes
through `bash -c` in the current implementation. Users and agents MUST treat it as
code execution authority, not as untrusted project config.

## Secret Management Boundary

Agently is not a secret manager. Its secret guard is a bounded local heuristic. It
MUST NOT promise to detect, store, rotate, or protect secrets.
