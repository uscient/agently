---
title: Workstreams And Tasks
status: active
authority: doctrine
last_reviewed: 2026-06-02
---

# Workstreams And Tasks

## Workstream Definition

A workstream is a named lane of related work. It MAY represent a feature,
migration, integration, release track, hardening effort, or investigation.

Workstreams live under:

```text
.agently/workstreams/<workstream-slug>/
```

## Workstream Layout

Current Phase 1 workstreams contain:

```text
README.md
PLAN.md
TASKS.md
DECISIONS.md
HANDOFF.md
CODEX.md
CLAUDE.md
LOG.md
workstream.md
status.md
requirements.md
decisions.md
inbox.md
state.yml
tasks/
```

`state.yml` stores workstream metadata captured at creation time, including the
branch binding decision when branch support is enabled.

The uppercase files are the agent-tooling cockpit surfaces. The lowercase files
are task-capsule and workstream surfaces used by `agently ws`, `agently task`,
`agently doc`, and packet generation.

## Optional Git Branch Binding

Agently may create and record a local Git branch for a workstream when project
config or an explicit CLI flag requests it. Git remains the source-control
authority. Agently must not push, merge, delete, reset, rewrite, or publish
branches unless explicitly requested.

Workstream branch binding is configured under `.agently/config.yml`:

```yaml
workstreams:
  branch:
    mode: manual
    prefix: workstream/
    checkout_on_create: true
    require_clean_tree: true
    if_exists: fail
    base: current
    push_on_create: false
    set_upstream: false
    delete_on_close: false
```

Default public behavior is `mode: manual`: branch support is available, but a new
workstream creates no branch unless `--branch`, `--branch-name`,
`--branch-from`, or `--checkout-existing` requests one. `mode: auto` creates a
local branch for each new workstream unless `--no-branch` is passed. `mode: off`
does not create branches by default, but explicit `--branch` may still force a
local branch.

The v1 branch integration is local-only. It may create a branch and switch to a
branch. It must not push, configure upstreams, merge, rebase, reset, delete, or
rewrite branches. `push_on_create`, `set_upstream`, and `delete_on_close` are
reserved config placeholders and remain no-op values in v1.

## Task Capsule Definition

A task capsule is a bounded unit of work inside a workstream. It stores task docs,
state, ledger, handoffs, artifacts, and decisions together.

Task capsules live under:

```text
.agently/workstreams/<workstream-slug>/tasks/<task-slug>/
```

## Task Layout

Current Phase 1 tasks contain:

```text
TASK.md
STATE.yaml
REQUIREMENTS.md
CONTEXT.md
NOTES.md
ledger.md
handoffs/
  claude/
  codex/
artifacts/
decisions/
```

## Handle Addressing

Agently is filesystem-stateful and session-stateless. Agently core has no current
workstream or current task.

Workflow-targeted operations are handle-addressed:

- commands that operate on a workstream require a workstream handle;
- commands that operate on a task require both workstream and task handles.

Workstream handles may be positional where a command already takes a named
workstream, or passed with `--workstream`. Task handles are passed with `--task`
alongside `--workstream`.

Project discovery may use `--project`, `AGENTLY_PROJECT`, or `$PWD` git-root
discovery. Project discovery never implies workstream or task selection.

Client-side focus is view state, not workflow authority. Clients must expand
focus into explicit handles before invoking Agently. Hidden session state is
never workflow authority.

`.agently/current` and `.agently/workstreams/<ws>/current` are not part of the
project or workstream layout. Stray old pointer files in an old worktree are
non-authoritative and may only be reported by diagnostics.

## Slug Doctrine

Slugs MUST be lowercase. Spaces become `-`. Valid characters are:

```text
a-z 0-9 . _ -
```

Slugs MUST NOT be empty, `.`, `..`, contain `/`, or contain `..`.

## Task State Lifecycle

Allowed states:

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

See [09-state-ledger-decisions.md](09-state-ledger-decisions.md) for state rules.

## Workstream Vs Task Docs

Workstream docs capture broad context:

- `README.md` - human-readable workstream orientation.
- `PLAN.md` - objective, scope, non-goals, and acceptance criteria.
- `TASKS.md` - checklist and active/backlog/done notes.
- `DECISIONS.md` - durable decision table.
- `HANDOFF.md` - latest continuation notes.
- `CODEX.md` - Codex-specific execution notes.
- `CLAUDE.md` - Claude-specific planning/review notes.
- `LOG.md` - chronological workstream notes.
- `workstream.md` - purpose and boundaries.
- `status.md` - workstream status notes.
- `state.yml` - creation-time workstream metadata, including branch binding.
- `requirements.md` - cross-task requirements.
- `decisions.md` - durable workstream decisions.
- `inbox.md` - raw notes and candidate tasks.

Task docs capture bounded work:

- `TASK.md` - goal, scope, and done criteria.
- `REQUIREMENTS.md` - concrete task requirements.
- `CONTEXT.md` - relevant context, constraints, links, and findings.
- `NOTES.md` - working notes.
- `ledger.md` - append-only event log.
- `handoffs/` - Claude and Codex round files.
- `artifacts/` - task-local supporting outputs.
- `decisions/` - user decision records.
