---
title: Context And Packet Compiler
status: active
authority: doctrine
last_reviewed: 2026-06-03
---

# Context And Packet Compiler

## Packet Authority

Packets are compiled views, not source authority. Source documents remain in Git
and `.agently/`; packet output exists to give agents bounded context.

## Cache Boundary

Generated context summaries, manifests, logs, and digests may be written under
`.agently/cache/`. The cache is regenerable and MUST NOT become workflow source
authority.

## Deterministic Prefix

Compiled packets MUST keep stable/static content above `<cache_breakpoint/>`.
Dynamic content such as generation time, dirty counts, log tails, active rounds,
and task-specific prompts belongs below `<cache_breakpoint/>`.

## Budgets

Packet and context commands SHOULD support `small`, `normal`, and `full` budgets.
Normal budget SHOULD prefer manifests, digests, and structural summaries over raw
document dumps. Full budget may include more source text, but still intentionally.

## Compaction

Compaction is deterministic and filesystem-backed. It uses sha256 content hashes
for freshness where available and never calls an LLM to summarize source files.
