---
title: Identity And Scope
status: active
authority: doctrine
last_reviewed: 2026-06-02
---

# Identity And Scope

> Agents think. Agently files remember. You decide.

## What Agently Is

Agently is a local workflow helper for agent-assisted development.

Agently Phase 1:

- uses Bash;
- installs a local `agently` command;
- renders filesystem-backed templates into projects;
- stores project workflow memory under `.agently/`;
- supports workstreams and task capsules;
- generates copy-ready Markdown packets;
- supports Claude as a current/default planner/reviewer binding through handoff files;
- supports Codex as a current/default operator/evaluator binding through packets, eval scaffolds, reports, and user decisions.

Roles are abstract. Agents are configurable bindings to roles. Codex CLI is the
current/default local operator console. Agently CLI owns deterministic workflow
state. Claude MAY be used as a planner/reviewer binding. The user decides.

## What Agently Is Not

Agently is not currently:

- a public-ready product;
- a SaaS;
- a database-backed platform;
- a daemon;
- a web UI;
- a custom TUI;
- an MCP server;
- a source-control replacement;
- a secret manager;
- an autonomous source mutation system;
- a replacement for Codex or Claude.

Future `agently-mcp` work belongs in a separate Python project/repo. It is not
part of this Bash core repo and MUST be a facade over the Agently CLI, not a
second implementation or authority layer.

## Phase 1 Scope

Phase 1 is optimized for private/local throughput. It SHOULD prefer simple,
inspectable filesystem behavior over product polish.

Agently MUST NOT introduce a database, daemon, web UI, custom TUI, or MCP server
inside the Bash core repo as part of Phase 1 work. See
[13-roadmap-and-deferred-work.md](13-roadmap-and-deferred-work.md).

## Project Memory

`.agently/` is project-local memory. It stores templates, workstreams, tasks,
handoffs, evaluations, reports, decisions, and ledgers.

Agently SHOULD keep that memory readable by humans and useful to agents.
