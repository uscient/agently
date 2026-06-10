# Agently

A local-first control plane for bounded agentic development loops.

Status: pre-release | v0.5.0 | CLI-only | Bash core | alpha - not production-ready

Agently runs today as a Bash CLI. It writes workflow state as files, compiles
bounded context packets, and runs guard/eval checks through detected local tools.

## Hook / Positioning

> Agently is a loop control plane, not a runaway loop runner.
>
> Agent loops are here. Agently makes them governable.

Agently sits around your external coding agents and local tools. It names the
work, compiles bounded Markdown context, records handoffs, runs local checks,
and keeps a review gate before anything becomes canonical workflow state. It is
not a model, IDE, cloud service, or CI system; it does not write code or operate
agents for you. Its state is local files under `.agently/`, so the loop stays
visible, diffable, and under developer authority.

| Agently is | Agently is not |
| --- | --- |
| A control plane for bounded agent-assisted loops. | An autonomous coding agent or model provider. |
| Local, file-backed workflow state under `.agently/`. | A SaaS, daemon, database, dashboard, or cloud orchestrator. |
| A compiler for copy-safe packets, prompts, evidence, and handoffs. | An IDE, CI/CD platform, or generic agent framework. |
| A guard/eval and reviewable patch surface for local checks. | A runaway retry engine or auto-promotion system. |
| A review gate around candidate work. | A replacement for maintainer approval. |
| Tool-agnostic around external agents/tools. | An integration with every named coding tool. |

## Core Concepts

- **loop control plane** - the layer that names, sequences, and gates the steps
  of an agent-assisted development loop; it coordinates the work around your
  coding agents instead of doing the coding.
- **bounded loop** - a cycle with an explicit start, explicit scope, compiled
  context instead of the whole repo, and an explicit review gate to close it.
- **packet** - a compiled, copy-safe Markdown context surface for a role/agent,
  built from file-backed state with size budgets.
- **handoff** - a recorded request/response exchange passed between roles or
  agents so work transfers as durable files, not hidden chat state.
- **gate** - a required human decision point, such as accept, revise, reject, or
  promote, before anything becomes canonical workflow state.
- **guard / eval** - local validation; guard runs bounded checks through
  detected tools, and eval aggregates guard evidence or checks proposed patches
  inside a throwaway git worktree.
- **local-first** - Agently runs on your machine from visible files; no daemon,
  database, dashboard, or hidden network calls.
- **human authority** - agent output is candidate context until reviewed; the
  developer or maintainer remains the final authority.
- **MCP** - Model Context Protocol. Agently currently has optional MCP config
  helper commands for Serena; a dedicated workflow adapter, `agently-mcp`, is
  planned/deferred and not implemented in this Bash core.
- **doctrine / project rules** - versioned Markdown rules under
  `docs/doctrine/` defining authority, scope, command contracts, and safety
  boundaries; `init` copies a read-only snapshot into `.agently/doctrine/`, and
  `agently guard doctrine` checks drift.

## How Agently Works: The Loop

```text
you name a workstream / task
           |
           v
+---------------------------+   bounded, file-backed context
| agently packet / prompt   |   compiled as copy-safe Markdown
+-------------+-------------+
              |
              | hand off
              v
+---------------------------+   runs outside Agently
| external agent / tool     |   operated by the developer
+-------------+-------------+
              |
              | candidate output pasted or recorded
              v
+---------------------------+   local checks, evidence,
| agently guard / eval /    |   reviewable patch proposal
| patch                     |
+-------------+-------------+
              |
              v
+===========================+   closes the loop only by
| HUMAN / REVIEW GATE       |   explicit human authority
| accept / revise / reject  |
| promote                   |
+=============+=============+
              |
promote ------+----> canonical state in .agently/
revise ------------> new human-initiated round
```

The loop is intentionally bounded:

1. Name a workstream or task explicitly.
2. Generate a packet or prompt from file-backed context.
3. Hand that context to an external agent or local tool.
4. Bring candidate output back for guard/eval, evidence, or a patch proposal.
5. Close the loop at a human review gate: accept, revise, reject, or promote.

Revise starts a new human-initiated round. Agently does not auto-retry,
auto-promote, stage, commit, push, or replace Git authority.

## Getting Started / CLI Quickstart

From the Agently source checkout, try the CLI without installing:

```bash
AGENTLY_HOME="$PWD" ./bin/agently version
AGENTLY_HOME="$PWD" ./bin/agently help
```

Optional user-local install from the checkout:

```bash
./bin/agently self install --user --from . --apply
export PATH="$HOME/.local/bin:$PATH"
agently version
```

Inside a Git project with `agently` on `PATH`, this is a minimal real loop:

```bash
agently init --codex
agently workstream create main
agently prompt codex --workstream main \
  --objective "Inspect the project and propose next steps"
agently packet claude --workstream main
agently guard --changed
agently status
```

That first-run sequence creates project-local Agently state, creates a
workstream, emits copy-safe context, runs local checks where tools are detected,
and reports status. It intentionally stops before the review gate because a gate
requires real candidate output and an open decision round.

Illustrative gate example only, not a first-run copy sequence:

```text
agently task new implementation-pass --workstream main
agently claude plan --workstream main --task implementation-pass
# review the generated packet and save the agent response as a handoff
agently eval claude --workstream main --task implementation-pass
agently report --workstream main --task implementation-pass
agently decide accept --workstream main --task implementation-pass --note "Accepted for execution."
```

## Current Scope & Roadmap

| Current in v0.5.0 pre-release | Directional or deferred |
| --- | --- |
| Bash CLI under `bin/` and `lib/`. | Packaged or remote install paths. |
| Managed user-local `self install`, `self status`, and `self uninstall`. | Self update and rollback. |
| `init`, `doctor`, `status`, workstreams, tasks, docs, packets, prompts, context, compact, inspect, evidence, report, decide, guard, eval, and patch commands. | Richer packet diagnostics, broader guard adapters, and project migration/template refresh. |
| File-backed `.agently/` state, handoffs, decisions, and doctrine snapshots. | A dedicated `agently-mcp` workflow adapter in a separate Python project. |
| Reviewable patch lane with `patch apply` gated by `--reviewed`; Git remains source-control authority. | A separate future TUI client over CLI contracts. |
| Optional Serena capability pack and explicit MCP config helper commands. | Full Serena setup automation or Agently-owned semantic code-intelligence reports. |

Out of scope for this Bash core today: production readiness, a daemon, database,
web UI, dashboard, embedded MCP server, autonomous source mutation, CI/CD
replacement, enterprise RBAC/SSO, hidden global config mutation, and hidden
network behavior.

Doctrine and project rules live in `docs/doctrine/`. For development on
Agently itself, those files define authority, architecture, command contracts,
safety boundaries, testing, packet behavior, MCP boundaries, and roadmap
discipline. Initialized projects receive a read-only snapshot under
`.agently/doctrine/` so project-local loops can inspect the same rules.

Development validation:

```bash
bash -n bin/agently lib/*.sh tests/*.sh
./tests/smoke.sh
```

If available:

```bash
shellcheck bin/agently lib/*.sh tests/*.sh
```

## License

Agently is licensed under the Apache License, Version 2.0.

See `LICENSE` for the full license text and `NOTICE` for attribution notices.
