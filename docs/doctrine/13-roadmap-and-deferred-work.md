---
title: Roadmap And Deferred Work
status: active
authority: doctrine
last_reviewed: 2026-06-03
---

# Roadmap And Deferred Work

## Deferred Work

Deferred items include:

- clipboard helper;
- separate `agently-mcp` Python MCP server/repo;
- headless Codex eval polish;
- public release polish;
- self update and rollback;
- project migration and template refresh commands;
- richer docs/reference generation;
- packaged install or remote install path, if desired later;
- richer `agently packet --help` and per-section packet diagnostics;
- raw Claude JSON capture.
- full Serena MCP setup and global MCP config mutation.
- Serena semantic `code-intel` reports unless backed by deterministic non-LLM CLI data.
- richer AST/symbol adapters beyond the current bounded text and optional
  `ast-grep` inspection.
- broader guard adapters for additional languages and project-specific tools.

## Planned `agently-mcp`

`agently-mcp` is a deferred/next project item, not implemented in this repo.
It should be a separate Python MCP server/repo and a thin facade over the
Agently CLI.

It should provide:

- typed MCP tools for workflow state, packets, handoffs, candidates, governance
  surfaces, and read-only status/doctor surfaces;
- JSON normalization for Agently stdout/stderr/exit status;
- drop-file/spool handling for large model payloads;
- argv-safe subprocess invocation of Agently commands;
- governance surfaces for agents and future TUI/client workflows.

It MUST NOT provide:

- independent workflow state;
- direct `.agently/` mutation outside Agently CLI commands;
- promotion authority;
- a second implementation of the Agently workflow state machine.

## Planned TUI Client

A future TUI is deferred and belongs outside the Bash core as a separate Go
client over Agently CLI contracts. It MAY display, review, and request workflow
operations, but MUST NOT become an authority layer, directly mutate
`.agently/**`, administer self lifecycle, or promote without an explicit
human/governance gate.

## Not Planned For Phase 1

Phase 1 MUST NOT add:

- database;
- daemon;
- web UI;
- custom TUI;
- autonomous code mutation.
- hidden global Codex, Claude, or Serena configuration changes.

The approved MCP direction is the separate `agently-mcp` facade. The Bash core
repo MUST NOT grow an embedded MCP server as part of Phase 1.

`agently self status`, `agently self install --user --dry-run|--apply`, and
`agently self uninstall --user --dry-run|--confirm` are implemented lifecycle
commands. Self update/rollback, project migration, and template refresh remain
deferred.

## Promotion Criteria

Deferred work SHOULD only be promoted when it:

- improves workflow throughput or safety;
- preserves visible source of truth;
- keeps authority boundaries explicit;
- has tests;
- avoids hidden workflow state;
- does not require real model calls in tests.

## Roadmap Discipline

Do not add features because they are conceptually attractive. Add features when
they solve a concrete workflow or safety problem and fit the authority model in
[02-authority-model.md](02-authority-model.md).
