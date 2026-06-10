# AGENTS.md

This project uses **Agently** for workflow state and agent handoffs.

## Operator Model

- Codex is the operator console used with the human.
- Agently is the deterministic workflow API.
- `.agently/` is the source of truth for workstreams, tasks, handoffs, evaluations, and decisions.
- Markdown files in `.agently/` are first-class workflow surfaces.
- In the current/default binding, Claude is commonly used for planning and review only.
- In the current/default binding, Codex is commonly used for evaluation, implementation, and operation under user direction.
- These are bindings, not role definitions or authority grants.
- Serena is an optional code-intelligence capability provider, not workflow authority.
- Future `agently-mcp` is a workflow MCP adapter over the Agently CLI; do not assume it is installed.
- The user decides.

## Workflow Doctrine

Use these doctrine rules inside this initialized project:

- Agents think. Agently files remember. The user decides.
- Do not treat chat transcript as workflow source of truth.
- Use `.agently/` files and explicit Agently handles for workflow state.
- Claude planning does not equal execution approval.
- Codex evaluation does not equal user acceptance.
- Acceptance records a decision; source execution still happens only under user direction.

## Ground Rules

- Do not invent workstream or task state from chat memory. Read it from Agently files.
- Prefer compiled `agently packet ...`, `agently inspect ...`, and `agently doc show <name> --workstream <ws> --task <task>` for bounded, copy-ready context.
- Do not silently rewrite requirements.
- Show diffs or explain intended task-doc changes before changing task docs when appropriate.
- Do not commit unless the user asks.
- Do not mutate project source through Agently commands beyond init-time scaffolding
  and explicit reviewed patch application:
  `agently patch apply <id> --workstream <ws> --reviewed`.
- Workflow state changes belong under `.agently/`.
- `.agently/cache/` is regenerable cache, not source authority.
- `.agently/doctrine/` is a read-only runtime snapshot of Agently doctrine.
  Agents may read it, but must not edit it. It is not project-owned doctrine.
  Compiled `agently packet ...` output remains the primary doctrine delivery mechanism.

## Useful Commands

```bash
agently ws list
agently task status --workstream <ws> --task <task>
agently docs
agently packet --profile claude --workstream <ws> --task <task> --budget normal
agently inspect tree . --depth 2
agently inspect read <file> --start <n> --end <m>
agently patch list --workstream <ws>
agently guard --changed
agently eval
agently eval claude --workstream <ws> --task <task>
agently report --workstream <ws> --task <task>
```

## Claude Handoffs

Claude handoffs are planning/review only. Use:

```bash
agently claude plan --workstream <ws> --task <task>
agently claude followup --workstream <ws> --task <task> --note "<note>"
```

Responses, receipts, Codex evaluations, reports, and decisions are kept in the
explicit task capsule.
