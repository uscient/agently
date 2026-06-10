---
title: Patch Proposal Lane
status: active
authority: doctrine
last_reviewed: 2026-06-03
---

# Patch Proposal Lane

## Purpose

The patch lane lets agents propose source changes as diff artifacts without
silently mutating source files.

## Artifact Location

Patch artifacts live under:

```text
.agently/workstreams/<workstream>/artifacts/patches/<id>/
```

Artifacts include metadata, the diff, check logs, eval reports when present, and
status updates.

## Mutation Boundary

The only Agently patch command allowed to mutate source files is:

```bash
agently patch apply <id> --workstream <ws> --reviewed
```

It MUST refuse without `--reviewed`, MUST run `git apply --check
--whitespace=error`, MUST be dirty-aware, MUST apply with `git apply
--whitespace=error`, MUST write a full bounded apply log, and MUST NOT commit.

Patch IDs are scoped by workstream. Patch commands that operate on patch artifact
IDs MUST require an explicit workstream handle and MUST NOT search all
workstreams for the first matching ID.

## Git Authority

Git remains source-control authority. Agently records patch review state and
applies reviewed patches; it does not stage, commit, push, publish, or open PRs.
