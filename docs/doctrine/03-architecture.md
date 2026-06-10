---
title: Architecture
status: active
authority: doctrine
last_reviewed: 2026-06-02
---

# Architecture

## Installed Command Layout

Managed self install is the only supported install path:

```text
~/.local/bin/agently        # managed proxy shim
~/.local/share/agently/
  current -> releases/<release-id>
  releases/<release-id>/
    bin/
    lib/
    templates/
    docs/
    VERSION
    INSTALL-MANIFEST.json
```

`${XDG_DATA_HOME:-$HOME/.local/share}/agently` is the managed install share root.
The managed release/current layout above is the only current install layout.
`agently self status` reports the active command, managed shim, release pointer,
PATH candidates, and current-layout integrity warnings.

## Repository Architecture

The Agently repository is organized as:

```text
bin/
lib/
templates/
tests/
docs/
VERSION
```

- `bin/agently` is the launcher.
- `lib/agently.sh` dispatches commands.
- `lib/cmd-*.sh` implements command groups.
- `lib/common.sh` contains shared helpers.
- `templates/` contains real project scaffolding files.
- `tests/smoke.sh` validates the Phase 1 vertical slice.
- `docs/doctrine/` contains this doctrine.

## Project-Local Architecture

`agently init --codex` creates:

```text
AGENTS.md
.agently/
.agents/
.codex/
```

The project receives workflow state and templates. It does not receive copied
runtime scripts.

Tool lifecycle updates MUST NOT mutate project `.agently` state. Project
migration and template refresh are separate explicit commands from self lifecycle
commands.

## Launcher Resolution

`bin/agently` MUST locate the share root in this order:

1. `AGENTLY_HOME`, if it contains `lib/agently.sh`.
2. Sibling mode: `bin/agently` with sibling `../lib/agently.sh`.

The managed self lifecycle shim executes
`${XDG_DATA_HOME:-$HOME/.local/share}/agently/current/bin/agently`; after
resolution, that launcher uses sibling `../lib/agently.sh` inside the selected
release.

If no share root is found, the launcher fails clearly.

## Command Dispatch

The launcher exports `AGENTLY_SHARE` and executes `bash "$share/lib/agently.sh"`.
Command dispatch lives in `lib/agently.sh`.

## MCP Adapter Split

Agently CLI/core owns the canonical Bash workflow state machine. `.agently/` is
the project-local workflow source of truth. Git remains source-control
authority.

Future `agently-mcp` work belongs in a separate Python project/repo. It is the
planned MCP adapter/facade over the Agently CLI. It should validate requests,
spool large payloads, call Agently commands through argv-safe subprocess
execution, consume Agently JSON contracts, normalize results, and expose
workflow/governance tools to MCP clients.

`agently-mcp` MUST NOT become a second workflow implementation, a hidden state
store, or an authority layer. It MUST invoke Agently through the CLI and MUST
NOT directly mutate canonical workflow state except through Agently commands.

Intended workflow-control path:

```text
MCP client / agent
  -> agently-mcp for workflow state, packets, handoffs, candidates, governance surfaces
  -> Agently CLI for canonical workflow mutation
  -> .agently/ for workflow source of truth
  -> user/governance path for promotion
```

Serena remains a separate optional code-intelligence MCP provider:

```text
MCP client / agent
  -> Serena MCP for code intelligence only
```

## Logic Location

Runtime logic MUST live in the installed command share under `lib/`. Projects
SHOULD NOT receive copied runtime scripts. This prevents per-project script drift.

## Template Location

Default project content MUST live as real files under `templates/`. Do not move
defaults back into giant generated heredocs.

## Phase 1 Architecture Boundaries

Phase 1 core avoids a database, daemon, web UI, custom TUI, and MCP server in
this Bash repo. Future work MAY revisit those boundaries only through
[13-roadmap-and-deferred-work.md](13-roadmap-and-deferred-work.md) and
[14-doctrine-change-process.md](14-doctrine-change-process.md). The approved
MCP direction is a separate `agently-mcp` Python facade over this CLI.
