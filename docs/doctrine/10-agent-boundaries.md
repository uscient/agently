---
title: Agent Boundaries
status: active
authority: doctrine
last_reviewed: 2026-06-02
---

# Agent Boundaries

## Agents Modifying Agently

Agents working on Agently MUST:

- read relevant doctrine before changing architecture, workflow behavior, command
  contracts, templates, authority boundaries, safety, or tests;
- inspect implementation before editing;
- keep changes bounded to the task;
- avoid hidden state;
- avoid network and real model calls in tests;
- run required validation when reasonable;
- report doctrine files consulted when relevant.

Agents MUST NOT silently change doctrine. Doctrine changes require explicit edits
and final-report disclosure.

## Agents Operating In Agently-Managed Projects

Agents working inside initialized projects MUST:

- read `.agently/` or use Agently commands for durable workflow state;
- prefer `agently packet ...` and `agently doc show ...` for copy surfaces;
- pass explicit project, workstream, and task handles as required by the command;
- record user decisions with Agently commands.

Agently core has no current workstream or current task. Agents MUST NOT invent
workstream or task state from chat memory.

## Requirements And Docs Changes

Agents SHOULD show diffs or explain intended changes before rewriting requirements
or durable task docs when appropriate.

Agents MUST NOT silently rewrite requirements to fit a preferred implementation.

## Commit Boundary

Agents MUST NOT commit unless the user asks.

## Model Call Boundary

Tests MUST NOT require real Claude or Codex model calls. Use stubs.

## Lifecycle Administration Boundary

Serena, MCP, TUI, and other clients MUST never administer Agently self lifecycle
or execute `self install`, `self update`, `self rollback`, `self uninstall`,
`project migrate --apply`, `templates update --apply`, or `init --refresh
--apply`. At most, clients MAY call read-only status, doctor, or plan commands if
explicitly allowed.

TTY friction and allow-lists are workflow controls, not a security boundary
against same-user shell bypass.

## MCP Adapter Boundary

Future `agently-mcp` is a separate deferred facade over Agently CLI contracts,
not an authority. It belongs in a separate Python project/repo and exposes
Agently workflow tooling by calling the Agently CLI. It MUST NOT directly rewrite
`.agently/` state, implement an independent state machine, hide workflow state,
administer self lifecycle, or decide promotion.

Future `agently-mcp` MUST expand any UI or chat focus into explicit Agently
handles before invoking the CLI. MCP/client focus is client-local view state only;
it is never workflow authority.

MCP tool schemas do not grant workflow authority. Agent-facing tools MAY inspect
workflow state, submit candidates, request promotion, and surface governance
state. Agent-facing tools MUST NOT promote canonical workflow state
autonomously; promotion requires an explicit human/governance gate.

Serena is not `agently-mcp`. Serena remains an optional semantic
code-intelligence capability provider.

Generic shell access as the same Unix user remains a trust-tier issue. CLI
intent alone is not a security boundary.

## TUI Client Boundary

A future TUI is a separate Go client over Agently CLI contracts. It is not
embedded in the Bash core, not a second workflow implementation, and not an
authority layer. It MAY display, review, and request workflow operations, but all
canonical workflow mutation MUST go through Agently CLI contracts. It MUST NOT
directly mutate `.agently/` or administer self lifecycle.

Client-side focus is view state, not workflow authority. Clients must expand
focus into explicit handles before invoking Agently. Hidden session, process,
chat, TUI, or MCP state is never workflow authority.

## Planned Adapter Payload Protocol

This is planned `agently-mcp`/Serena-readiness and future MCP adapter doctrine.
It is not a global command contract unless a specific command already implements
a file-path intake surface.

Agent adapters and future MCP wrappers MUST NOT pass large model output as shell
arguments. Large Markdown/model payloads SHOULD be transferred by file path. The
adapter writes the raw payload to a controlled spool file. The Agently CLI
receives only the file path. Agently validates the file, copies accepted content
into the appropriate workflow location, records metadata, and handles cleanup or
retirement by policy.

Bad future adapter behavior:

```bash
agently ws ingest W31 --content "$RAW_LLM_OUTPUT"
```

Preferred future adapter behavior:

```bash
agently ws ingest W31 --type plan --file .agently/spool/<id>/payload.md --json
```

Future MCP wrappers MUST invoke Agently through argv-safe subprocess execution,
not shell string interpolation.

## Doctrine Drift Boundary

If a code change conflicts with doctrine, the agent MUST either adjust code to
match doctrine or update doctrine through [14-doctrine-change-process.md](14-doctrine-change-process.md).
