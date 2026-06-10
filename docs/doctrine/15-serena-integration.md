---
title: Serena Integration
status: active
authority: doctrine
last_reviewed: 2026-06-02
---

# Serena Integration

Serena is an optional semantic code-intelligence provider for
Agently-managed projects. It may help agents with symbol lookup, references,
structure inspection, onboarding, memories, and semantic edits or refactors when
explicitly allowed.

Serena MUST NOT become Agently's source of truth.

Serena is not an Agently role. Serena is an optional semantic code-intelligence
capability provider that may support allowed code roles when explicitly enabled.
Serena is not source authority, workflow authority, doctrine authority,
promotion authority, cache authority, self-lifecycle authority, `agently-mcp`,
or the Agently workflow-control adapter.

Future workflow MCP server work belongs in a separate `agently-mcp` Python
project. `agently-mcp` is a deferred facade over Agently CLI contracts, not a
second implementation or authority layer. Serena remains a separate
MCP/code-intelligence capability provider.

## Serena Lane Separation

Serena participates in a separate capability lane in Agently-managed projects:

1. Lane 1 — Agently Workflow Lane
   - Controlled exclusively by Agently CLI commands and Agently-owned files.
   - Agently MAY generate Serena-oriented artifacts, prompts, reports, smoke checks, onboarding guidance, and integration files for future code-lane sessions.
   - Agently does NOT call Serena, drive MCP/LLM sessions, or consume Serena output during workflow-lane execution.

2. Lane 2 — Code-Intelligence Lane
   - Used by code-role agents under explicit authorization, where the agent calls Serena MCP tools directly.
   - This lane is governed by the active task, project doctrine, user permission, and the selected Agently Serena profile.

The lanes MUST NOT merge. Agently may generate Serena guidance and snippets for
future code-lane sessions. Codex or Claude Code may use Serena to work the code
when explicitly allowed. Serena does not own either lane.

Agently remains the workflow authority through the CLI and `.agently/` state.
Serena remains a semantic code-intelligence provider.
Serena MUST never become source, workflow, promotion, doctrine, cache, or
self-lifecycle authority.

Serena may coexist with `agently-mcp` in the same client environment. An agent
may use `agently-mcp` for workflow/governance context and Serena MCP for code
intelligence during a bounded task. These lanes MUST remain separate.

## Control Plane And Tool Plane

The key boundary is workflow control plane versus agent code tool plane.

Agently commands own the workflow control plane. They may render docs, snippets,
prompts, status reports, smoke checks, and onboarding guidance under
`.agently/**`. They MUST NOT drive an LLM or Serena MCP session to perform
semantic inspection.

Future `agently-mcp` may expose this workflow control plane to MCP clients only
by calling Agently CLI commands. It MUST NOT be implemented as Serena tooling,
MUST NOT directly mutate `.agently/`, MUST NOT implement an independent state
machine, and MUST NOT give Serena workflow authority.

Codex or Claude Code owns the code tool plane when a user authorizes an agent to
use Serena MCP tools during a task. That use is bounded by the active task,
project doctrine, user permission, and the selected Agently Serena profile.

## Profiles

Agently Serena profiles are advisory policy bundles:

```text
lite
review
edit
```

Aliases `serena-lite`, `serena-review`, and `serena-edit` normalize to the short
values above.

Profiles MAY influence generated prompts, MCP snippets, project examples, status
warnings, and documentation. Profiles MUST NOT be treated as Serena client
contexts or as a hard sandbox.

Serena context follows the MCP client:

```text
Codex MCP wiring       -> --context=codex
Claude Code MCP wiring -> --context claude-code
```

Agently profile follows the intended authority level.

## Optional Enablement

Plain `agently init --codex` MUST NOT enable the Serena pack and MUST NOT create
`.serena/`.

`agently init --codex --serena` MAY render reviewable Serena integration files
under `.agently/integrations/serena/**` and generated snippets under
`.agently/generated/serena/**`. It MUST NOT create `.serena/`, memories, or
global MCP config.

## Project Schema Boundary

Agently does not own Serena project schema.
Agently may generate a reviewable `.agently/generated/serena/project.yml.example`.
Agently may write `.serena/project.yml` only with explicit `--apply`, preferably
by delegating to Serena's own generator.
Once written, `.serena/project.yml` is Serena-owned operational state.

## MCP Config Mutation

Default posture is generate, do not mutate.

Agently MUST NOT mutate Codex, Claude Code, or Serena global config unless the
user passes an explicit `--apply` flag to a command designed for that mutation.

Codex TOML mutation in v1 is conservative: append an Agently-generated Serena
block only if no existing `[mcp_servers.serena]` block exists, after creating a
timestamped backup. If an existing block is present, refuse safely and print
manual instructions.

Claude Code MCP mutation MUST delegate to `claude mcp add` or
`claude mcp remove`. Agently MUST NOT hand-edit Claude JSON config.

## Onboarding Boundary

`agently serena onboard` prepares an onboarding prompt. It MUST clearly state:

```text
Prepared Serena onboarding prompt.
Agently did not run onboarding.
Agently did not create memories.
Agently did not mutate source.
```

No `--run` behavior exists in Phase 1.

## Deferred Work

`agently serena code-intel` and semantic workflow reports are deferred unless
Serena exposes a deterministic non-LLM CLI path for the needed data. Agently MUST
NOT drive an agent/MCP semantic inspection session from the workflow lane.
