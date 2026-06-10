---
title: Source Of Truth
status: active
authority: doctrine
last_reviewed: 2026-06-02
---

# Source Of Truth

## Core Rule

Agently doctrine MUST be written down before it becomes a constraint on future development.

## Authority Hierarchy

When sources conflict, use this hierarchy:

1. User/founder explicit instruction in the current task.
2. Current repository code and tests, authoritative for what Agently does today.
3. [docs/doctrine/](README.md), authoritative for intended architecture,
   contracts, and boundaries.
4. [AGENTS.md](../../AGENTS.md).
5. [README.md](../../README.md), which must not contradict doctrine.
6. Generated project templates under [templates/](../../templates/), reviewed
   like implementation.
7. [CHANGELOG.md](../../CHANGELOG.md), dated history only.

Current implementation is higher authority than old plans. Doctrine SHOULD
describe and constrain implementation, but if doctrine and implementation conflict,
future work MUST either update implementation to match doctrine or update doctrine
through [14-doctrine-change-process.md](14-doctrine-change-process.md). Do not
silently drift.

Code and tests reveal current behavior. Doctrine defines intended architecture.
Disagreement between them is drift requiring explicit review and reconciliation.

## What Counts As Doctrine

Doctrine is the active Markdown corpus under `docs/doctrine/`. It defines:

- identity and scope;
- architecture and source-of-truth rules;
- command contracts and workflow UX;
- authority boundaries;
- safety and guardrail posture;
- testing and validation obligations;
- roadmap boundaries.

## What Counts As Implementation

Implementation is the executable and shipped source:

- `bin/agently`;
- `lib/*.sh`;
- `templates/**`;
- `tests/smoke.sh`;
- `VERSION`.

Implementation MUST be inspected before changing doctrine or documenting command
behavior.

## Generated And Project-Local State

Generated project-local state is created by `agently init --codex` and workflow
commands:

- `AGENTS.md`;
- `.agently/**`;
- `.agents/**`;
- `.codex/config.toml.example`.

Inside initialized projects, `.agently/` is visible, diffable project memory. It
MUST NOT be replaced by chat transcript memory. It is project-local workflow-state
authority, not source-code, implementation, or doctrine authority.

## Non-Authoritative Material

The following are not authority for Agently code, contracts, or doctrine:

- temporary reports, audits, and plans under `docs/tmp/`;
- chat transcripts;
- generated caches, packets, handoffs, reports, and other workflow artifacts;
- project-local `.agently/` state outside the initialized project it belongs to.

## Doctrine Lock Charter

Agently is unreleased and internal. There is no public compatibility or migration
burden for removed pre-release surfaces. Active doctrine describes the current
intended model only; no legacy, flat, or pre-managed install surfaces belong in
active code, tests, doctrine, or templates. Historical context belongs only in
clearly historical or temporary locations such as `CHANGELOG.md` or `docs/tmp/`.

## Conflict Handling

If two sources conflict:

- Identify the higher-authority source.
- Update the lower-authority source or open an explicit change.
- State the conflict in the final report.
- Do not rely on private chat context as the only explanation.

## Deprecated Documentation

Deprecated docs SHOULD be marked with an explicit heading or status note. Historical
references MAY remain when they explain migration or decision context, but they
MUST be labeled historical.

## Chat Transcript Rule

The chat transcript MUST NOT become the only source of truth for Agently behavior,
workflow state, or doctrine. Durable constraints belong in repository files.

## Markdown State Rule

Agently SHOULD preserve visible, diffable Markdown state. Plans, reviews,
decisions, and handoffs SHOULD be inspectable in normal filesystem and Git tools.

## Final Report Rule

Future agents SHOULD cite which doctrine files guided a change when the change
touches architecture, command behavior, templates, authority boundaries, safety,
or workflow state.
