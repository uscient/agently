# Agently Workflow Rules

## Source Of Truth

Use `.agently/` as the source of truth. Agently core has no current workstream
or task pointer; pass explicit handles to workflow commands.

`.agently/cache/` is regenerable cache and is not source authority.

## State Flow

```text
draft
requirements_ready
claude_request_ready
claude_response_ready
codex_eval_ready
user_decision_needed
accepted | needs_revision | rejected
execution_ready
done
```

## Round Files

- Claude request: `handoffs/claude/NNN-request.md`
- Claude response: `handoffs/claude/NNN-response.md`
- Claude receipt: `handoffs/claude/NNN-receipt.md`
- Codex eval: `handoffs/codex/NNN-eval.md`
- Decision report: `handoffs/codex/NNN-decision-report.md`
- User decision: `decisions/NNN-decision.md`

## Do

- Use Agently commands to move workflow state.
- Keep stdout copy-safe when generating packets.
- Use compiled packets, context manifests, and inspect commands for bounded context.
- Propose source edits through `agently patch propose --workstream <ws>` when using the patch lane.
- Run `agently guard ...` or `agently eval` for local tool-backed evidence.
- Use `agently evidence` for reviewable local evidence.
- Use `agently prompt ...` for agent prompts grounded in workstream files.
- Use `agently serena ...` only for the optional Serena capability-provider setup and checks.
- Use workstream branch flags only for local branch creation or checkout.
- When using the current/default Claude binding, keep Claude in planning/review mode.
- Record user decisions visibly.

## Do Not

- Do not silently rewrite requirements.
- Do not ask Claude to modify files.
- Do not execute a plan before user acceptance.
- Do not apply a patch unless the user has reviewed it; use `agently patch apply <id> --workstream <ws> --reviewed`.
- Do not write global Codex, Claude, or Serena config.
- Do not treat Serena memories or MCP output as Agently doctrine.
- Do not treat Serena as the Agently workflow MCP adapter.
- Do not push, merge, delete, reset, rewrite, publish, or configure upstreams for workstream branches unless the user explicitly requests it.
- Do not commit unless the user asks.
