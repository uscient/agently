---
title: Agently Doctrine Index
status: active
authority: doctrine
last_reviewed: 2026-06-03
---

# Agently Doctrine

This directory is the formal source-of-truth doctrine collection for Agently.
It constrains future development, agent behavior, architecture decisions,
workflow UX, safety boundaries, command contracts, and roadmap discipline.

Doctrine is not marketing. Doctrine is the written operating contract future
Codex, Claude, ChatGPT, and human sessions SHOULD read before changing Agently.

## Fast Start For Agents

1. Read [00-source-of-truth.md](00-source-of-truth.md).
2. Read [01-identity-and-scope.md](01-identity-and-scope.md).
3. Read the doctrine file relevant to the task.
4. Inspect the implementation under `bin/`, `lib/`, `templates/`, and `tests/`.
5. Make bounded changes.
6. Run `bash -n bin/agently lib/*.sh tests/*.sh`.
7. Run `./tests/smoke.sh` when reasonable.
8. Report deviations and name the doctrine files consulted.

## Doctrine Files

- [00-source-of-truth.md](00-source-of-truth.md) - authority hierarchy and conflict handling.
- [01-identity-and-scope.md](01-identity-and-scope.md) - what Agently is and is not.
- [02-authority-model.md](02-authority-model.md) - user authority, role/agent/provider model, and decision gates.
- [03-architecture.md](03-architecture.md) - installed, repository, project-local, and planned `agently-mcp` adapter architecture.
- [04-filesystem-and-templates.md](04-filesystem-and-templates.md) - template and safe-overwrite doctrine.
- [05-workstreams-and-tasks.md](05-workstreams-and-tasks.md) - workstream and task capsule model.
- [06-command-contract.md](06-command-contract.md) - implemented CLI command contract and future adapter machine-interface rules.
- [07-markdown-packets-and-copy-ux.md](07-markdown-packets-and-copy-ux.md) - packet UX and stdout rules.
- [08-claude-codex-handoffs.md](08-claude-codex-handoffs.md) - Claude planning and Codex evaluation loop.
- [09-state-ledger-decisions.md](09-state-ledger-decisions.md) - task state, neutral handoff metadata, ledger, receipts, and decisions.
- [10-agent-boundaries.md](10-agent-boundaries.md) - agent boundaries, future `agently-mcp` boundary, and drop-file payload doctrine.
- [11-security-and-guardrails.md](11-security-and-guardrails.md) - safety posture and local guardrails.
- [12-testing-and-validation.md](12-testing-and-validation.md) - required validation and reporting.
- [13-roadmap-and-deferred-work.md](13-roadmap-and-deferred-work.md) - deferred work, including separate `agently-mcp`, and roadmap boundaries.
- [14-doctrine-change-process.md](14-doctrine-change-process.md) - how doctrine changes happen.
- [15-serena-integration.md](15-serena-integration.md) - optional Serena capability provider boundaries.
- [16-context-and-packet-compiler.md](16-context-and-packet-compiler.md) - bounded context, cache, compaction, and packet compiler rules.
- [17-patch-proposal-lane.md](17-patch-proposal-lane.md) - diff-only patch proposal, review, and apply boundaries.
- [18-guard-eval-pipeline.md](18-guard-eval-pipeline.md) - local guard/eval execution, safe truncation, and tool detection.

## Surface Status Labels

Major commands, config keys, layouts, client responsibilities, and status fields
are Current, Deferred, or Forbidden. Unlabeled planning material is non-current.

| Label | Surfaces |
| --- | --- |
| Current | Bash CLI core under `bin/` and `lib/`; managed self `status`, `install`, and `uninstall`; project init/status/doctor; workstream, `ws`, task, doc, packet, context, compact, inspect, patch, guard, eval, evidence, prompt, claude, report, decide, serena, and mcp commands documented in [06-command-contract.md](06-command-contract.md); `.agently/` project workflow state; filesystem templates; local-only workstream branch binding; workstream spine commands; `inspect doc go`. |
| Deferred | Separate `agently-mcp` facade over CLI contracts; separate Go TUI client; archive/close/GC; self update/rollback; project migration; template refresh; binary packaging; ScientDB. |
| Forbidden | Hidden network behavior; background services, databases, web UIs, or custom TUIs in the Bash core; direct `.agently/**` mutation by clients outside Agently CLI contracts; second workflow implementations or authority layers; v1 workstream branch push, upstream, merge, delete, reset, rewrite, publish, or PR automation; secrets, telemetry, or real model calls in tests. |

## Doctrine Rule

Future Agently changes MUST NOT silently drift from this doctrine. If an
implementation change intentionally changes architecture, authority, command
contracts, workflow state, templates, or safety boundaries, update doctrine
explicitly.
