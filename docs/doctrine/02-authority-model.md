---
title: Authority Model
status: active
authority: doctrine
last_reviewed: 2026-06-03
---

# Authority Model

## Human Authority

The user is the final authority. Agent plans, Codex evaluations, and Agently
reports do not replace user judgment.

## Role, Agent, And Provider Model

Roles are abstract. Agents are configurable bindings. Loops call roles.
Profiles and project config bind roles to agents. Capability providers support
roles without owning workflow authority. The user/governance path decides what
becomes canonical.

Role set:

```text
PLANNER      designs scope, approach, risks, and acceptance criteria
IMPLEMENTER  performs bounded code or document changes
REVIEWER     checks correctness, risks, and omissions
SCOUT        gathers fast external or adversarial signals
AUDITOR      verifies evidence against requirements and doctrine
SYNTHESIZER  compares candidates and proposes a coherent result
EVALUATOR    runs checks, tests, and acceptance review
OPERATOR     drives local execution under user direction
GOVERNOR     approves promotion to canonical state
```

Claude, Codex, Grok, and future agents are configurable bindings to compatible
roles. Default bindings may exist, but they are examples/defaults, not doctrine.
A preferred binding is not an authority grant. Agent output remains candidate
context until reviewed and accepted.

Roles are abstract, but bindings are capability-aware. Agently SHOULD prefer
agents and models whose training, runtime tools, evaluation history, known
failure modes, cost profile, context behavior, and tool affordances fit the role
contract. A preferred binding selects who performs candidate work; it does not
grant authority.

Capability providers are not roles. Serena is an optional semantic
code-intelligence capability provider. Serena may support allowed code roles
with symbol lookup, references, structure inspection, onboarding memories, and
semantic editing/refactor tools. Serena does not own workflow authority,
Agently state, Git authority, promotion authority, or the workflow control
plane.

An MCP adapter is not workflow authority. Future `agently-mcp` may expose typed
tools and governance surfaces to MCP clients, but it MUST call Agently commands
for canonical workflow mutation and MUST NOT decide promotion. MCP tool schemas
do not grant authority.

No tool promotes autonomously. Promotion to canonical workflow state requires an
explicit human/governance gate.

## Agently State Authority

Within an initialized project, `.agently/` is the authoritative workflow state.
Workflow authority is durable explicit records addressed by handles. Agently is
filesystem-stateful and session-stateless.

Agently core has no current workstream or current task. Project discovery may use
`--project`, `AGENTLY_PROJECT`, or `$PWD` git-root discovery. Project discovery
never implies workstream or task selection.

Agents MUST NOT invent workstream, task, round, status, or decision state from
memory. Client-side focus is view state, not workflow authority, and hidden
session state is never workflow authority.

## Current Default Codex Binding

In the current/default Phase 1 binding, Codex is commonly used for
implementation, evaluation, and operator roles under user direction. Codex MAY:

- inspect `.agently/`;
- run Agently commands under user direction;
- evaluate Claude output;
- execute accepted plans when the user directs execution.

Codex MUST NOT treat a Claude plan as execution approval.

This binding is not a role definition and does not grant authority.

## Current Default Claude Binding

In the current/default Phase 1 binding, Claude is commonly used for planning and
review roles. Claude output SHOULD be captured under `handoffs/claude/`. Claude
MUST NOT be treated as the final decision maker.

This binding is not a role definition and does not grant authority.

## Template Role

Templates under `templates/` define initial project scaffolding and project-local
copy surfaces. Templates are source artifacts and SHOULD be reviewed like code.
See [04-filesystem-and-templates.md](04-filesystem-and-templates.md).

## Decision Role

Decision files under `decisions/NNN-decision.md` record explicit user decisions.
Acceptance gates execution readiness but does not execute source changes.

## Acceptance Gate

`agently decide accept` records acceptance. It MUST NOT automatically apply a
plan, mutate source, stage changes, commit changes, or call Codex.

## Source Mutation Boundary

Agently commands SHOULD write workflow state, not source mutations. Init-time
scaffolding MAY write:

```text
AGENTS.md
.agently/
.agents/
.codex/config.toml.example
```

Normal workflow commands SHOULD write under `.agently/`. The explicit exception
is reviewed patch application:

```bash
agently patch apply <id> --workstream <ws> --reviewed
```

That command may mutate source files through `git apply --whitespace=error` after
the patch has passed `git apply --check --whitespace=error`. It MUST NOT stage,
commit, push, publish, or otherwise become Git authority.

The self lifecycle lane is a separate tool-install boundary. `agently self
install` and `agently self uninstall` may mutate only the user-local Agently tool
install under the managed shim, XDG data share, and XDG state/log paths. They
MUST NOT mutate project `.agently` state. Project migration and template refresh
are separate explicit commands.

## Visibility Rule

Agently state MUST remain visible and diffable. Hidden chat state MUST NOT replace
tracked Markdown and simple text state.
