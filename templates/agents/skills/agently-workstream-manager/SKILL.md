# Agently Workstream Manager

## When To Use

Use this skill when a project has Agently initialized and the user wants to manage
workstreams, task capsules, explicit Claude planning handoffs, Codex evaluations, reports,
user decision records, evidence packs, profile preferences, generated prompts,
compiled packets, bounded inspection, patch artifacts, and local guard/eval runs.
Use the Serena commands only when the optional Serena pack is enabled or the user
asks about Serena/MCP setup.

## Command Map

- `agently ws list|new|show|path`
- `agently workstream list|create|new|open|status|prompt|handoff`
- `agently task list|new|show|path|status|docs|set-state` with `--workstream` and task handles where needed
- `agently doc show|path|edit|replace --workstream <ws> --task <task>`
- `agently packet claude|codex|status|review --workstream <ws> [--task <task>]`
- `agently packet --profile claude|codex|generic --workstream <ws> [--task <task>] --budget small|normal|full`
- `agently context budget|manifest [--workstream <ws> [--task <task>]]`
- `agently compact workstream|doctrine`
- `agently inspect symbols|skeleton|read|grep|sg|tree|doc`
- `agently patch propose|check|apply|list|show|reject|explain --workstream <ws>`
- `agently profile list|get|set`
- `agently serena status|create-project|onboard|memories|profile|smoke`
- `agently mcp status|add|remove`
- `agently doctor [--codex] [--claude] [--serena] [--fix] [--json]`
- `agently status [--workstream NAME] [--json]`
- `agently evidence [--since BASE] [--tests] [--output PATH] [--json]`
- `agently prompt codex|claude|review ...`
- `agently claude config|plan|followup`
- `agently guard [--changed] [--file PATH] [--lang LANG] [--strict]`
- `agently eval`
- `agently eval patch <id> --workstream <ws>`
- `agently eval claude --workstream <ws> --task <task>`
- `agently report --workstream <ws> --task <task>`
- `agently decide accept|revise|reject --workstream <ws> --task <task>`

## Copy/Paste Packet Workflow

Use compiled packets for bounded planner/execution context. The shortcut
spellings `agently packet claude|review|codex|status --workstream <ws>` route through the compiler.
Use `agently inspect ...` for targeted follow-up context.

Use `agently prompt codex ...` and `agently prompt claude ...` when a fresh
agent prompt should be grounded in workstream files and profile preferences.

## Serena Boundary

Serena is optional. Serena is a semantic code-intelligence capability provider,
not the Agently workflow-control adapter. Agently controls workflow files and
generated guidance. Codex or Claude Code may use Serena MCP tools directly in
the code lane only when authorized by the user, task, and active Serena profile.

Future `agently-mcp` is the planned workflow MCP adapter over the Agently CLI.
Do not assume it is installed or use Serena as a substitute for it.

## State Rules

Read workflow state from `.agently/`. Do not reconstruct workstream, task, round,
or decision state from chat memory. Pass explicit workstream/task handles.

## Claude Handoff Workflow

Run `agently claude plan --workstream <ws> --task <task>` for the first planning request and
`agently claude followup --workstream <ws> --task <task> --note "<note>"` for revision rounds. In the current
default binding, Claude is used for planning and review only; this is a binding,
not a role definition or authority grant.

## Evaluation, Report, Decision

Run `agently eval claude --workstream <ws> --task <task>`, then
`agently report --workstream <ws> --task <task>`, then wait for the user decision.
Record the decision with `agently decide accept|revise|reject --workstream <ws> --task <task>`.

## Patch And Guard Workflow

Use `agently patch propose --workstream <ws>`, `check`, `show`, and `explain`
before source files are touched. Only `agently patch apply <id> --workstream <ws>
--reviewed` may mutate source, and it must not commit. Use `agently guard ...`,
`agently eval`, and `agently eval patch <id> --workstream <ws>` for local
tool-backed evidence.
