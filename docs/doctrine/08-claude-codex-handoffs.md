---
title: Claude Codex Handoffs
status: active
authority: doctrine
last_reviewed: 2026-06-02
---

# Claude And Codex Handoffs

## Handoff Model

In the current/default Phase 1 binding, Claude is commonly used for planning and
review roles. In the current/default Phase 1 binding, Codex is commonly used for
implementation, evaluation, and operator roles under user direction. These are
bindings, not role definitions. Agently stores the handoff files.

Claude planning does not equal execution approval. Codex evaluation does not equal
user acceptance.

## Round Numbering

Rounds use deterministic zero-padded numbers:

```text
001
002
003
```

The next Claude round is derived from existing `handoffs/claude/*-request.md`
filenames.

## File Names

Claude files:

```text
handoffs/claude/NNN-request.md
handoffs/claude/NNN-response.md
handoffs/claude/NNN-receipt.md
handoffs/claude/NNN-response.raw.json
```

Codex and decision files:

```text
handoffs/codex/NNN-eval.md
handoffs/codex/NNN-decision-report.md
decisions/NNN-decision.md
```

Current implementation reserves raw JSON naming in receipts but does not write or
parse raw JSON.

## Claude Config Resolution

Claude model and effort resolve in this order:

1. Command flags: `--model`, `--effort`.
2. Environment variables: `AGENTLY_CLAUDE_MODEL`, `AGENTLY_CLAUDE_EFFORT`.
3. `.agently/config.yml` profile keys.
4. Defaults: model `opus`, effort `max`, permission mode `plan`, max turns `6`.

Profile keys used by prompt generation and Claude config resolution include:

```text
claude.model
claude.reasoning
```

Top-level project config keys `claude_model` and `claude_effort` are not read.
Generic task state SHOULD move toward role/agent-neutral handoff provenance keys
such as `last_handoff_agent`, `last_handoff_model`, and
`last_handoff_reasoning`. New generic task-state writes MUST use
role/agent-neutral keys.

`AGENTLY_CLAUDE_CMD` is a trusted full command override. It bypasses normal command
construction and may bypass model/effort for actual execution. Receipts record this
as `command_source: AGENTLY_CLAUDE_CMD`.

## Missing Claude Fallback

If Claude is missing or the command fails, Agently MUST keep the request, write a
receipt, update the task to `claude_request_ready`, and print manual instructions.
The workflow MUST remain recoverable by saving a response to the expected response
path.

## Tests

Tests MUST NOT make real Claude or Codex model calls. Smoke tests use a local
stubbed Claude script through `AGENTLY_CLAUDE_CMD`.

## Execution Boundary

Accepted plans do not automatically execute. Execution happens later in Codex
under user direction when Codex is the selected implementation/operator binding.
