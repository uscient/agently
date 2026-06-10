---
title: Markdown Packets And Copy UX
status: active
authority: doctrine
last_reviewed: 2026-06-03
---

# Markdown Packets And Copy UX

## Copy/Paste-First Design

Packets are generated Markdown surfaces designed for copying from Codex, pasting
into Claude, or handing back to Codex.

Packet commands MUST print payload-only stdout. Notes and warnings MUST go to
stderr.

## Output Rules

Packets MUST:

- be readable Markdown;
- avoid ANSI color;
- avoid spinners;
- avoid terminal tables by default;
- not depend on hidden chat context;
- include enough file-backed context for another agent to reason about the task;
- avoid unbounded raw file dumps by default.

## Compiled Packet Shape

Compiled packets are structured views. Static source and contract sections belong
above:

```xml
<cache_breakpoint/>
```

Dynamic data such as generated timestamps, dirty counts, current round numbers,
log tails, handoff tails, and task-specific prompt text belongs below the
breakpoint.

The prefix above `<cache_breakpoint/>` SHOULD be byte-stable across runs when the
static source files have not changed.

## Packet Profiles And Shortcuts

Current compiled packet profiles are `claude`, `codex`, and `generic`. Current
budgets are `small`, `normal`, and `full`. Normal budget should favor manifests,
digests, and structural summaries over full source text.

The positional spellings are shortcuts into the compiler, not separate raw dump
templates:

```text
agently packet claude --workstream <ws> [--task <task>] -> --profile claude --workstream <ws> [--task <task>] --budget normal
agently packet codex  --workstream <ws> [--task <task>] -> --profile codex --workstream <ws> [--task <task>] --budget normal
agently packet status --workstream <ws> [--task <task>] -> --profile generic --workstream <ws> [--task <task>] --budget normal
agently packet review --workstream <ws> [--task <task>] -> --profile codex --workstream <ws> [--task <task>] --budget normal
```

### `claude`

The Claude packet is a planning/review request. It includes bounded workstream,
artifact, doctrine, context-menu, and explicit task sections when `--task` is
supplied.

### `codex`

The Codex packet is an evaluation/execution packet for after user direction. It
includes authority reminders, bounded workstream context, explicit task context
when `--task` is supplied, artifacts, and guard/eval follow-up guidance.

### `status`

The status shortcut uses the `generic` compiled profile with normal budget.

### `review`

The review shortcut uses the `codex` compiled profile with normal budget.

## Tooling Markdown Surfaces

The following commands also produce copy/paste-friendly Markdown by default:

```text
agently doctor
agently status
agently evidence
agently prompt ...
agently workstream status
agently workstream prompt
agently workstream handoff
agently serena status
agently serena onboard
agently serena memories check
agently serena smoke
```

They are not packet templates, but they follow the same stdout rule: payload only
on stdout, notes and errors on stderr. Commands with `--json` produce stable
machine-readable output. Agently remains Bash/filesystem-native; `jq` is allowed
only for explicit JSON validation and structured manifest mutation surfaces, not
for casual human-output formatting.

## Relationship To Codex `/copy`

Because packet stdout is clean Markdown, users can copy it through Codex `/copy`
or normal shell redirection.

## Future Packet Changes

Future packet changes SHOULD:

- keep headings clear;
- keep role and authority boundaries explicit;
- render missing files as `_(empty)_`;
- avoid relying on chat memory;
- remain useful to both humans and agents;
- keep cacheable static sections separated from volatile sections.

Packets SHOULD be readable by humans and useful to agents.
