# Decision Report - {{TASK_SLUG}} round {{ROUND}}

- status: {{STATUS}}
- generated: {{DATETIME}}

## Summary of Claude Plan

{{CLAUDE_RESPONSE_MD}}

## Codex Evaluation

{{CODEX_EVAL_MD}}

## Recommendation

Review the Codex evaluation and choose accept, revise, or reject.

## Decide

```bash
agently decide accept --note "<reason>"
agently decide revise --note "<reason>"
agently decide reject --note "<reason>"
```
