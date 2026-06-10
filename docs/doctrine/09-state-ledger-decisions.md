---
title: State Ledger Decisions
status: active
authority: doctrine
last_reviewed: 2026-06-02
---

# State, Ledger, And Decisions

## STATE.yaml

Each task capsule contains `STATE.yaml`. It is intentionally flat and simple.
There is no YAML parser dependency in Phase 1.

Generic task state SHOULD use role/agent-neutral keys. Target task-state keys
include:

```yaml
id:
slug:
workstream:
status:
created_at:
updated_at:
round:
current_handoff:
current_eval:
last_handoff_role:
last_handoff_agent:
last_handoff_model:
last_handoff_reasoning:
last_handoff_profile:
last_handoff_path:
```

Generic workflow and task state MUST NOT contain vendor-specific agent fields.
Agent, model, and reasoning metadata MAY be recorded as invocation provenance,
but it MUST be expressed through role/agent-neutral keys such as role, agent,
model, reasoning, profile, and invocation or handoff path.

Task state MAY keep a compact latest-handoff summary through fields such as
`last_handoff_role`, `last_handoff_agent`, `last_handoff_model`,
`last_handoff_reasoning`, `last_handoff_profile`, and `last_handoff_path`.

Full invocation metadata belongs in handoff receipts, audit events, or
agent-specific handoff artifacts.

Do not write vendor-shaped provenance keys in new generic state surfaces.

State mutation uses temp files and `mv` through Bash helpers.

## Allowed States

```text
draft
requirements_ready
claude_request_ready
claude_response_ready
codex_eval_ready
user_decision_needed
accepted
needs_revision
rejected
execution_ready
done
```

## State Transitions

Expected lifecycle:

```text
draft
-> requirements_ready
-> claude_request_ready / claude_response_ready
-> codex_eval_ready
-> user_decision_needed
-> accepted / needs_revision / rejected
-> execution_ready
-> done
```

`task set-state` MAY be used for manual state changes, but agents SHOULD preserve
the meaning of the lifecycle.

## Ledger

`ledger.md` is an append-oriented task event log. Mutating workflow commands SHOULD
append concise timestamped events.

The ledger is not a database. It is readable historical context.

## Decision Files

User decisions live under:

```text
decisions/NNN-decision.md
```

Decision files SHOULD record:

- generated timestamp;
- decision type;
- resulting state;
- round;
- pointers to Claude response, Codex eval, and decision report;
- note or stdin reason.

## Receipt Files

Claude receipts live under:

```text
handoffs/claude/NNN-receipt.md
```

Receipts SHOULD record command source, model, effort, permission mode, max turns,
command display, exit code, request path, response path, raw JSON path if any, and
hashes when available.

## No DB In Phase 1

Phase 1 MUST NOT introduce a database. Filesystem state is the source of truth.

## Deferred State Migrations

State migration tooling is deferred. If added later, it MUST preserve readable
history and keep decision, receipt, and ledger content inspectable or provide
explicit migration records.
