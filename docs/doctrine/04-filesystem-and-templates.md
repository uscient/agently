---
title: Filesystem And Templates
status: active
authority: doctrine
last_reviewed: 2026-06-02
---

# Filesystem And Templates

## Template Doctrine

Agently defaults MUST be filesystem-backed template files. They MUST NOT be hidden
inside giant Bash heredocs.

Templates are source artifacts. They SHOULD be reviewed, diffed, and tested like
code because they become project-local workflow surfaces.

## Template Mapping

`agently init --codex` maps installed templates to target project paths:

```text
templates/AGENTS.md   -> AGENTS.md
templates/agently/... -> .agently/...
templates/agents/...  -> .agents/...
templates/codex/...   -> .codex/...
```

`templates/serena/**` is excluded from ordinary init. It is rendered only when
the user explicitly requests the optional Serena capability pack with
`agently init --codex --serena` or a Serena command that regenerates a specific
artifact.

## Safe Overwrite Rules

Init SHOULD be idempotent and conservative.

Rules:

- Existing files are skipped by default.
- Root `AGENTS.md` is skipped if it already exists.
- Ordinary template files MAY be refreshed with `--force`.
- Protected workflow state MUST NOT be overwritten by init.

## Protected Paths

The following paths are protected:

```text
.agently/config.yml
.agently/local.yml
.agently/workstreams/**
.agently/workstreams/<ws>/state.yml
```

These paths MUST remain protected even when `--force` is used.

## Codex Config Boundary

Agently writes:

```text
.codex/config.toml.example
```

Agently MUST NOT write `.codex/config.toml`.

## Placeholder Rendering

The current renderer performs simple placeholder replacement for known template
files. Placeholders SHOULD be explicit and readable, for example:

```text
{{PROJECT}}
{{PROFILE}}
{{AGENTLY_VERSION}}
{{DATETIME}}
{{SLUG}}
{{TITLE}}
{{WORKSTREAM_SLUG}}
{{TASK_SLUG}}
{{BRANCH_METADATA}}
```

Compiled packet base templates avoid raw content placeholders. Report templates
may still use explicit content placeholders such as `{{CLAUDE_RESPONSE_MD}}` and
`{{CODEX_EVAL_MD}}`. Missing source files render as `_(empty)_` where those
report helpers call for it.

## Project Config Files

New Agently projects use:

```text
.agently/config.yml
.agently/local.yml
```

`.agently/config.yml` stores reviewable project preferences. `.agently/local.yml`
is for machine-local overrides and MUST be gitignored by generated defaults.

The `workstreams.branch` subtree in `.agently/config.yml` controls optional
local branch binding for new workstreams. The runtime reader is intentionally
bounded to that exact subtree shape and is not a generic YAML parser.

`.agently/config.yml` is the only project config file.

## Generated Serena Files

Serena pack docs under `.agently/integrations/serena/**` are reviewable project
guidance and SHOULD be preserved unless `--force` is used.

Generated files under `.agently/generated/serena/**` and `.agently/reports/**`
MAY be overwritten by their generating commands and SHOULD include generated
metadata.

## Template Change Rule

Template changes SHOULD be tested with `./tests/smoke.sh` because templates are
installed and then copied into initialized projects.
