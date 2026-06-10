# AGENTS.md

This repository contains **Agently**, a portable Bash workflow harness for
agent-assisted project workflows. Codex CLI is the current/default local
operator console, not Agently itself.

## Repository Shape

- `bin/agently` is the launcher.
- `lib/` contains runtime command logic.
- `templates/` contains real filesystem-backed project templates.
- `agently self install` installs managed user-local releases.
- `tests/smoke.sh` proves the local install and workflow slice.
- `tests/workstream-branch.sh` proves optional local workstream branch binding.
- `tests/serena.sh` proves the optional Serena capability pack with stubs.

## Ground Rules

- Before changing Agently architecture, workflow behavior, command contracts, templates, authority boundaries, safety posture, or roadmap scope, read `docs/doctrine/README.md`.
- If code changes conflict with doctrine, either update code to match doctrine or update doctrine explicitly.
- Final reports should mention doctrine files consulted when doctrine is relevant to the change.
- Do not silently drift doctrine.
- Keep managed self lifecycle logic focused on the user-local Agently tool install.
- Keep runtime logic under `lib/`.
- Keep generated defaults as real files under `templates/`.
- Do not put generated project defaults inside giant Bash heredocs.
- `agently init` copies a read-only runtime doctrine snapshot into target
  project `.agently/doctrine/`; source authority remains `docs/doctrine/`.
- Bash only for installed runtime scripts unless explicitly justified.
- Agently remains Bash/filesystem-native. `jq` is allowed only for explicit JSON validation and read/modify/write surfaces where safe structured mutation is required, currently the workstream spine manifests and self lifecycle install manifests. Do not introduce `jq` casually into legacy/simple commands or human-output formatting.
- Do not add secrets, credentials, telemetry, background services, databases, web UIs, custom TUIs, MCP servers, or agent runtimes to this Bash core repo.
- Future `agently-mcp` belongs in a separate Python project as a facade over the Agently CLI, not as a second implementation or authority layer.
- Serena integration is an optional capability pack only; preserve lane separation and do not make Serena the workflow source of truth.
- Do not mutate global Codex, Claude, or Serena/MCP config without an explicit apply command, backup/rollback behavior where applicable, and clear user-facing output.
- Workstream branch support is local-only in v1; do not add push, upstream, merge, delete, reset, rewrite, publish, or PR automation to it.
- Do not add hidden network behavior. Phase 1 local install and init are offline.
- Do not make real Claude or real Codex model calls in tests.
- Do not overwrite user files by default.
- Keep stdout copy-safe: payload only on stdout; notes, warnings, progress, and errors on stderr.
- Use `FAIL: ...` on stderr for failures.
- Use the product name **Agently** in prose.
- License is Apache-2.0.

## Workflow Model

- Roles are abstract jobs to be done; agents are configurable bindings to those roles.
- Codex CLI is the current/default operator console.
- Agently CLI is the deterministic workflow API.
- `.agently/` is the project-local source of truth.
- Markdown files are first-class workflow surfaces.
- In the current/default Phase 1 binding, Claude is commonly used for planning and review roles.
- In the current/default Phase 1 binding, Codex is commonly used for implementation, evaluation, and operator roles under user direction.
- These are bindings, not role definitions or authority grants.
- Serena is a capability provider, not a workflow-control adapter.
- Future `agently-mcp` is the planned workflow MCP adapter over the Agently CLI.
- The user decides.

## Validation

Before final response after changes, run:

```bash
bash -n bin/agently lib/*.sh tests/*.sh
./tests/smoke.sh
```

If `shellcheck` is available, run:

```bash
shellcheck bin/agently lib/*.sh tests/*.sh
```

## Shell Safety

Public entrypoints should be source-safe and return harmlessly if accidentally
sourced. Agently scripts are CLI entrypoints and should be executed directly.
