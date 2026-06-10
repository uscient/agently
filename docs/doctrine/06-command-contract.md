---
title: Command Contract
status: active
authority: doctrine
last_reviewed: 2026-06-03
---

# Command Contract

This document describes the implemented current command contract. If it conflicts
with `lib/*.sh`, the implementation has higher immediate authority; reconcile both
through [14-doctrine-change-process.md](14-doctrine-change-process.md).

## General Contract

- stdout MUST be payload only.
- stderr SHOULD contain notes, warnings, progress, and errors.
- Failures MUST use `FAIL: ...` on stderr.
- Commands MUST NOT emit ANSI color or spinners.
- Markdown-producing commands SHOULD print clean Markdown to stdout.
- Mutating task commands SHOULD append to `ledger.md` when implemented to do so.

Agently remains Bash/filesystem-native. `jq` is allowed only for explicit JSON
validation and read/modify/write surfaces where safe structured mutation is
required, currently the workstream spine manifests and self lifecycle install
manifests. Do not introduce `jq` casually into legacy/simple commands or
human-output formatting.

Agently CLI JSON contracts are the canonical machine interface for future MCP
adapters. Future `agently-mcp` tools SHOULD call Agently commands through
argv-safe subprocess execution, use `--json` where available, and normalize
stdout/stderr/exit status without bypassing Agently or rewriting `.agently/`
state directly.

Future MCP adapters MUST NOT pass large model output as shell arguments. They
SHOULD spool payloads to controlled files and pass file paths to Agently
commands when a file-path intake surface exists. This is planned adapter
doctrine, not a claim that every current command has drop-file support.

## Project And Handle Selection

Agently is filesystem-stateful and session-stateless. Agently core has no current
workstream or current task.

Project discovery may use:

```text
agently --project DIR <command> ...
AGENTLY_PROJECT=DIR agently <command> ...
```

Resolution order is `--project DIR`, then `AGENTLY_PROJECT`, then `$PWD`
git-root discovery. Project discovery never implies workstream or task
selection.

Workflow-targeted operations are handle-addressed:

- project-level commands need only a project;
- workstream-level commands need an explicit workstream handle, either
  positional or `--workstream`;
- task-level commands need `--workstream` and `--task`;
- artifact and spine commands keep their existing explicit artifact handles.

Client-side focus is view state, not workflow authority. Clients must expand
focus into explicit handles before invoking Agently. Hidden session state is
never workflow authority.

`--json` controls output shape only. It does not change authority, handle
requirements, or fallback behavior.

## Slug Behavior

Workstream and task creation/addressing commands validate slugs through
`slugify`.
Invalid slugs fail.

## Init Commands

### `agently init --codex [--serena] [--profile lite|review|edit] [--project DIR|--target DIR] [--name NAME] [--force] [--dry-run] [--allow-non-git]`

Purpose: render installed templates into a target project.

Reads:

- `$AGENTLY_SHARE/templates/**`;
- target Git root, `--project`, or `--target`.

Writes:

- `AGENTS.md`;
- `.agently/**`;
- `.agents/**`;
- `.codex/config.toml.example`.

With `--serena`, also writes:

- `.agently/integrations/serena/**`;
- `.agently/generated/serena/**`.

It MUST NOT create `.serena/`, memories, or global MCP config.

Stdout behavior: no payload contract. Progress and summary go to stderr.

Safety:

- requires Git unless `--allow-non-git`;
- skips existing files by default;
- protects `.agently/config.yml`, `.agently/local.yml`, and
  `.agently/workstreams/**`;
- skips `templates/serena/**` during plain init and renders that subtree only
  when `--serena` is explicitly requested.

`init --project DIR` may target a Git worktree that does not yet contain
`.agently/config.yml`. `--target DIR` remains an init-only alias for selecting
the target path.

### `agently doctor [--codex] [--claude] [--serena] [--fix] [--json]`

Purpose: print install and environment diagnostics.

Reads:

- `AGENTLY_SHARE`;
- templates path;
- Git root if present;
- project config and generated workflow files when present;
- `git`, `bash`, `claude`, `codex`, optional Serena command presence, and
  local tool presence for packet/context/inspect/patch/guard/eval readiness.

Writes: nothing. `--fix` prints suggested setup/fix commands only; it MUST NOT
install tools or mutate project/global config.

Stdout: Markdown report by default, or a stable JSON object with `--json`.

Safety: MUST NOT mutate global Codex, Claude, or Serena config.

## Self Lifecycle Commands

### `agently self status [--json]`

Purpose: inspect the active Agently command, PATH candidates, managed shim,
release/current layout, and lifecycle ghosts such as global stale commands,
shadowed active commands, dangling current pointers, and unmanaged shims.

Reads: PATH, user-local Agently bin path, XDG Agently data/config/state paths,
managed release metadata, and install manifests when present.

Writes: nothing.

Stdout: human status by default, strict JSON with `--json`. Ghosts and warnings
exit 0.

### `agently self install --user --from <repo> --dry-run|--apply [--json]`

Purpose: plan or apply a user-local Agently tool install from a source
repository into the managed release/current layout.

Writes on `--apply`: user-local Agently data releases, the `current` symlink, the
managed proxy shim, and lifecycle state/log files. It MUST NOT mutate project
`.agently` state.

Safety: refuses unmanaged shims, validates staged release manifests, and uses a
lifecycle lock for real apply.

### `agently self uninstall --user --dry-run|--confirm [--json]`

Purpose: plan or confirm removal of the user-local managed Agently tool install.

Writes on `--confirm`: removes only the managed shim and Agently share directory.
It preserves Agently config/state and MUST NOT search for or mutate project
`.agently` state.

Safety: confirmed uninstall requires an interactive exact-path confirmation and
uses the lifecycle lock.

## Status Commands

### `agently status [--workstream <name>] [--json]`

Purpose: summarize project or workstream state, not environment health.

Reads: Git status, selected workstream files when `--workstream` is supplied,
latest handoff/prompt files for that workstream, and configured or inferred test
command.

Writes: nothing.

Stdout: Markdown by default, JSON with `--json`. Without `--workstream`, status
does not infer a workstream or task.

## Workstream Commands

`agently workstream ...` is the agent-tooling workstream namespace. The shorter
`agently ws ...` namespace remains supported for implemented commands.

### `agently workstream list`

Equivalent to `agently ws list`.

### `agently workstream create <name> [branch options]`

Creates `.agently/workstreams/<slug>/` from the workstream template. `agently
workstream new <name> [branch options]` is an alias. New workstreams include the
cockpit surfaces:

```text
README.md
PLAN.md
TASKS.md
DECISIONS.md
HANDOFF.md
CODEX.md
CLAUDE.md
LOG.md
state.yml
```

They also keep the original lowercase workstream files and `tasks/` directory.

Branch options:

```text
--branch
--no-branch
--branch-name <name>
--branch-from <ref>
--allow-dirty
--checkout-existing
```

Agently may create and record a local Git branch for a workstream when project
config or an explicit CLI flag requests it. Git remains the source-control
authority. Agently must not push, merge, delete, reset, rewrite, or publish
branches unless explicitly requested.

Branch config is read from this bounded `.agently/config.yml` subtree:

```yaml
workstreams:
  branch:
    mode: manual
    prefix: workstream/
    checkout_on_create: true
    require_clean_tree: true
    if_exists: fail
    base: current
    push_on_create: false
    set_upstream: false
    delete_on_close: false
```

Supported v1 modes are `off`, `manual`, and `auto`. Public templates MUST default
to `manual`, not `auto`. The Bash reader is intentionally bounded to this exact
subtree shape and is not a generic YAML parser.

Allowed Git mutations in v1 are local branch creation and local branch checkout.
Forbidden in v1: push, upstream configuration, merge, rebase, reset, branch
delete, force-create/reset branch operations, remote mutation, and history
rewrite.

### `agently workstream open <name>`

Prints workstream file paths and portable editor hints. It MUST NOT assume VS Code
unless `code` is detected.

### `agently workstream status <name>`

Prints Markdown status for a named workstream.

### `agently workstream prompt <name> --for codex|claude`

Prints an agent prompt grounded in the named workstream.

### `agently workstream handoff <name> --for codex|claude`

Prints a resume/handoff prompt grounded in `HANDOFF.md`.

### `agently ws list`

Lists workstreams. It does not mark or infer focus.

Reads: `.agently/workstreams/*`.
Writes: nothing.
Stdout: plain list.

### `agently ws new <slug> [branch options]`

Creates a workstream from `.agently/templates/workstream/`.

Reads: workstream template.
Writes: `.agently/workstreams/<slug>/` and optionally a local Git branch when
branch config or CLI flags request one.
Stdout: none by contract; notes go to stderr.

### `agently ws use <slug>`

Removed. The command fails and performs no old behavior. Pass `--workstream
<ws>` to the target command.

### `agently ws current`

Removed. The command fails and performs no old behavior. Pass `--workstream
<ws>` to the target command.

### `agently ws show --workstream <slug>`

Prints the addressed workstream `workstream.md` as Markdown.

### `agently ws show <ALIAS> [--json]`

Prints a workstream spine artifact. Human mode prints artifact content. JSON mode
returns `ok`, `command:"ws_show"`, `ws_id`, `alias`, `path`, `artifact`,
`canonical` when present, and `content`.

### `agently ws path --workstream <slug>`

Prints the absolute addressed workstream path.

## Workstream Spine Commands

Current spine commands operate on uppercase workstream IDs and aliases such as
`W31` and `W31-PLN1`. They require an initialized Git project and use
`.agently/workstreams/<WS_ID>/manifest.json`, `events.jsonl`, and custody
directories `raw/`, `candidates/`, `proposed/`, `canonical/`, and `spool/`.
`jq`, `sha256sum`, and `flock` are required.

Supported artifact types are `scope`, `requirements`, `plan`, `review`,
`synthesis`, `audit`, and `handoff`. Candidate aliases use type codes `SCOPE`,
`REQ`, `PLN`, `REV`, `SYN`, `AUD`, and `HND`.

All `--json` success payloads include `ok:true` and `command`. Failures use the
standard JSON error object on stderr in JSON mode, or `FAIL: ...` on stderr in
human mode.

### `agently ws init <WS_ID> [--absolute-name NAME] [--json]`

Creates an empty spine layout for an uppercase workstream ID, writes an initial
manifest, initializes the event log, and leaves the workstream open. JSON success
returns `command:"ws_init"`, `ws_id`, `state:"open"`, and a message.

### `agently ws status <WS_ID> [--json]`

Reads and validates the manifest. JSON success returns `ws_id`, `state`,
`proposed`, `version`, `event_seq`, `candidate_count`, and `canonical_count`.
Human mode prints a compact status summary.

### `agently ws summary <WS_ID> [--json]`

Summarizes candidate and canonical artifacts. JSON success returns `ws_id`,
`absolute_name`, `state`, `proposed`, `candidates` entries with `alias`, `type`,
and `status`, and `canonical` entries with `alias`, `type`, and
`canonical_path`.

### `agently ws ingest <WS_ID> --type <TYPE> --file <PATH> [--actor VALUE] [--via VALUE] [--json]`

Copies a payload into custody, rejects symlinks and oversized payloads,
quarantines inbound front matter, writes a candidate packet, records hashes, and
updates the manifest and event log. JSON success returns `alias`, `type`,
`status:"candidate"`, raw/content/packet SHA-256 values, and whether front
matter was quarantined.

### `agently ws propose <ALIAS> [--json]`

Moves one candidate into escrow by copying it to `proposed/`, setting
`state:"escrowed"`, and recording the proposed alias. JSON success returns
`ws_id`, `alias`, `state:"escrowed"`, and `status:"proposed"`.

### `agently ws reject <ALIAS> [--reason VALUE] [--json]`

Rejects the currently proposed alias after an explicit interactive typed-alias
confirmation on `/dev/tty`. This is governance friction, not a security
boundary; see [02-authority-model.md](02-authority-model.md) and
[05-workstreams-and-tasks.md](05-workstreams-and-tasks.md). JSON success returns
`ws_id`, `alias`, `state:"open"`, and `status:"rejected"`.

### `agently ws promote <ALIAS> [--json]`

Promotes the currently proposed alias to `canonical/` after the same explicit
interactive typed-alias confirmation. No tool promotes autonomously; promotion
requires a human/governance gate. JSON success returns `ws_id`, `alias`,
`status:"promoted"`, `canonical_path`, and `canonical_sha256`.

### `agently ws doctor <WS_ID> [--verify-hashes] [--json]`

Checks manifest validity, event-log validity, file presence, path containment,
alias counters, state coherence, manifest/event relationships, and optionally
hash validity. JSON success returns `ok`, `ws_id`, `checks`, `errors`, and
`warnings`; JSON failure returns the same check details with an error object.

## Task Commands

### `agently task list --workstream <ws>`

Lists tasks in the addressed workstream and their statuses.

### `agently task new <slug> --workstream <ws>`

Creates a task capsule from `.agently/templates/task/` inside the addressed
workstream and appends a ledger entry.

### `agently task use <slug>`

Removed. The command fails and performs no old behavior. Pass `--workstream
<ws> --task <task>` to the target command.

### `agently task current`

Removed. The command fails and performs no old behavior. Pass `--workstream
<ws> --task <task>` to the target command.

### `agently task show --workstream <ws> --task <task>`

Prints the addressed task `TASK.md` as Markdown.

### `agently task path --workstream <ws> --task <task>`

Prints the absolute addressed task path.

### `agently task status --workstream <ws> --task <task>`

Prints a Markdown status summary from `STATE.yaml` and decision files.

### `agently task docs`

Lists supported task and workstream doc names. It is static and does not require
a current task.

### `agently task set-state <state> --workstream <ws> --task <task>`

Validates and updates `STATE.yaml`, then appends a ledger entry.

## Doc Commands

### `agently docs`

Alias for `agently task docs`.

### `agently doc show <name> --workstream <ws> --task <task>`

Prints a resolved doc to stdout.

### `agently doc path <name> --workstream <ws> --task <task>`

Prints an absolute path to a resolved doc.

### `agently doc edit <name> --workstream <ws> --task <task>`

Runs `$VISUAL` or `$EDITOR` on the doc. If neither is set, prints the path to stderr.

### `agently doc replace <name> --workstream <ws> --task <task> < file.md`

Replaces a resolved doc with stdin. Empty stdin is rejected. `state` replacement is
rejected; use `task set-state`. Ledger side effects use the supplied
`--workstream` and `--task` handles.

## Packet Commands

### `agently packet claude|codex|status|review --workstream <id> [--task <id>]`

Shortcut packet commands build deterministic compiled packets:

```text
agently packet claude --workstream <ws> [--task <task>] -> agently packet --profile claude --workstream <ws> [--task <task>] --budget normal
agently packet codex  --workstream <ws> [--task <task>] -> agently packet --profile codex --workstream <ws> [--task <task>] --budget normal
agently packet status --workstream <ws> [--task <task>] -> agently packet --profile generic --workstream <ws> [--task <task>] --budget normal
agently packet review --workstream <ws> [--task <task>] -> agently packet --profile codex --workstream <ws> [--task <task>] --budget normal
```

Reads: templates, doctrine manifests, `.agently/` workstream/task files, and
context cache summaries when available.
Writes: nothing.
Stdout: Markdown payload only.

### `agently packet --profile claude|codex|generic --workstream <id> [--task <id>] [--budget small|normal|full]`

Builds a deterministic compiled packet. Static content belongs above
`<cache_breakpoint/>`; volatile generated data belongs below it. Workstream
context requires `--workstream`; task sections are included only when `--task` is
explicitly supplied.

Reads: templates, doctrine manifests, `.agently/` workstream/task files, and
context cache summaries when available.
Writes: nothing, except regenerable context cache summaries when needed for
normal-budget structural digests.
Stdout: Markdown payload only.

### `agently packet inspect --workstream <id> [--task <id>] [--json]`

Prints packet size, line, section, and estimated-token diagnostics.

## Context And Compaction Commands

### `agently context budget [--workstream <id> [--task <slug>]] [--budget small|normal|full] [--json]`

Prints deterministic context budget diagnostics. Without `--workstream`, context
scope is project/doctrine only. With `--workstream`, scope is the addressed
workstream. Task docs are included only when `--task` is explicitly supplied.

### `agently context manifest [--workstream <id> [--task <slug>]] [--json]`

Prints a source/summary manifest with sha256 freshness state. Without
`--workstream`, context scope is project/doctrine only. With `--workstream`,
scope is the addressed workstream. Task docs are included only when `--task` is
explicitly supplied.

### `agently compact workstream <id>`

Writes deterministic structural summaries and manifests under `.agently/cache/`.
It MUST NOT modify source documents.

### `agently compact doctrine`

Writes doctrine cache summaries/manifests under `.agently/cache/`.

## Inspection Commands

Inspection commands provide bounded context on demand:

```text
agently inspect symbols <file>
agently inspect skeleton <file>
agently inspect read <file> --start <n> --end <m>
agently inspect read <file> --full
agently inspect grep <pattern> [path]
agently inspect sg <pattern> --lang <lang> [path]
agently inspect tree [path] --depth <n>
agently inspect doc go <package>
```

They MUST NOT dump unbounded files by default. Long output is truncated with a
full log path.

`agently inspect doc go <package>` runs `go doc` for an initialized project,
logs the full output, and emits at most 160 lines by default. Unsupported
languages fail.

## Patch Commands

Patch commands manage diff artifacts:

```text
agently patch propose <patch-file> --workstream <id>
agently patch check <id> --workstream <id>
agently patch check <patch-file>
agently patch list --workstream <id> [--json]
agently patch show <id> --workstream <id>
agently patch explain <id> --workstream <id>
agently patch reject <id> --workstream <id>
agently patch apply <id> --workstream <id> --reviewed
```

Patch IDs are scoped by workstream. Patch commands that operate on artifact IDs
MUST require `--workstream` and MUST NOT silently search all workstreams and pick
the first matching ID. `patch check <patch-file>` may check an explicit file
without an artifact ID.

Only `patch apply <id> --workstream <id> --reviewed` may mutate source. It MUST
check the patch with `git apply --check --whitespace=error`, refuse unreviewed
application, be dirty-aware, apply with `git apply --whitespace=error`, record
status, and never commit.

## Profile Commands

### `agently profile list`

Lists supported profile keys and resolved values.

### `agently profile get [<key>]`

With no key, prints a Markdown profile summary. With a key, prints the resolved
value.

### `agently profile set <key> <value>`

Writes project-local profile preferences to `.agently/config.yml` and ensures
`.agently/local.yml` is gitignored.

Supported keys:

```text
codex.model
codex.reasoning
codex.auto_edit
claude.model
claude.reasoning
serena.enabled
serena.profile
```

`.agently/local.yml` may override supported keys locally and SHOULD NOT be
committed.

`serena.profile` accepts aliases `serena-lite`, `serena-review`, and
`serena-edit`, but stores short values `lite`, `review`, and `edit`.

## Serena Commands

### `agently serena status [--json]`

Prints Serena integration state from local files and simple command/config
detection. It reports Serena command availability/version, pack presence,
`.serena/project.yml`, cache/memory heuristics, memories reviewed state, MCP
state, profile, drift warnings, and generated file state.

### `agently serena create-project [--apply] [--index]`

Without `--apply`, writes only
`.agently/generated/serena/project.yml.example`. With `--apply`, may write
`.serena/project.yml` explicitly, preferring Serena's own generator when
available and backing up existing files.

### `agently serena onboard --client codex|claude-code [--dry-run] [--profile P] [--output PATH]`

Prepares an onboarding prompt. It MUST NOT run onboarding, create Serena
memories, mutate source, or call an LLM.

### `agently serena memories list`

Lists `.serena/memories/*` read-only. If no memories exist, says so.

### `agently serena memories check [--mark-reviewed]`

Compares current memories to the last Agently snapshot where possible, writes
`.agently/reports/serena-onboarding-summary.md`, and may set
`memories_reviewed: true` in Serena pack state with `--mark-reviewed`.

### `agently serena profile [get|set <lite|review|edit>]`

Convenience wrapper around `serena.profile`.

### `agently serena smoke [--output PATH] [--json]`

Verifies the Serena pack without risky mutation. Serena absence is not a failure.
The command MUST NOT mutate project source or `.serena/memories/`.

### `agently serena code-intel`

Deferred until Serena exposes a deterministic non-LLM CLI path.

### `agently serena workflow-report`

Deferred unless it remains a deterministic wrapper over local files and Agently
state.

## MCP Commands

### `agently mcp status [--json]`

Read-only MCP status. Codex detection greps
`${CODEX_HOME:-$HOME/.codex}/config.toml` for `[mcp_servers.serena]`. Claude
Code detection prefers `claude mcp list` when available and otherwise uses
simple project `.mcp.json` grep heuristics.

### `agently mcp add serena --client codex [--profile P] [--apply] [--scope project|user]`

Without `--apply`, writes only
`.agently/generated/serena/codex.config.toml.example` and prints instructions.

With `--apply`, appends an Agently-generated Serena block only if no existing
`[mcp_servers.serena]` block exists. It creates a timestamped backup and prints
rollback instructions. It MUST NOT force-replace existing Codex TOML.

### `agently mcp add serena --client claude-code [--profile P] [--apply] [--scope project|user]`

Without `--apply`, writes only
`.agently/generated/serena/claude-code.commands.sh`. With `--apply`, delegates
to `claude mcp add`. It MUST NOT hand-edit Claude JSON config.

### `agently mcp remove serena --client codex [--apply]`

Without `--apply`, prints manual removal instructions. With `--apply`, removes
only a clearly Agently-generated Codex block and creates a backup.

### `agently mcp remove serena --client claude-code [--apply]`

Without `--apply`, prints manual removal instructions. With `--apply`, delegates
to `claude mcp remove`.

## Evidence Commands

### `agently evidence [--since <base>] [--tests] [--output <path>] [--json]`

Builds a copy/paste-ready evidence pack from local Git state. `--since` compares
against a base ref when it exists. `--tests` runs the configured or inferred test
command when available. `--output` writes the report to a file.

With `--json`, stdout is a compact structured status/meta object. The full
evidence pack remains the Markdown payload printed to stdout or written to the
file specified by `--output`.

Safety: MUST NOT run destructive commands and MUST fail clearly when the base ref
does not exist.

## Prompt Commands

### `agently prompt codex --workstream <name> (--task <task>|--objective <objective>)`

Generates a prompt for the current/default Codex binding with role, objective,
source files, profile preferences, scope boundaries, acceptance criteria, test
command, and handoff format.

### `agently prompt claude --workstream <name> (--task <task>|--objective <objective>)`

Generates a prompt for the current/default Claude binding. It SHOULD bias Claude
toward planning, architecture, review, and risk analysis unless implementation
is explicitly requested.

### `agently prompt review --from <file>`

Wraps an evidence or handoff file in a review prompt.

### `agently prompt review --workstream <name>`

Generates a workstream review prompt from workstream files.

### `agently prompt --output <path> ...`

Writes the generated prompt to a file instead of stdout.

## Claude Commands

### `agently claude config [--model MODEL] [--effort EFFORT]`

Shows resolved Claude config or updates project config. `.agently/config.yml` is
the only project config file.

### `agently claude plan --workstream <ws> --task <task> [--model MODEL] [--effort EFFORT]`

Creates the next Claude request round, prints the packet, attempts Claude, captures
response when successful, writes receipt, updates state, and appends ledger.

### `agently claude followup --workstream <ws> --task <task> [--note TEXT] [--model MODEL] [--effort EFFORT]`

Same handoff behavior as `plan`, with a follow-up note and next round.

Safety: missing or failing Claude does not fail the workflow; it creates manual
mode request and receipt files.

## Eval, Report, Decide

### `agently eval [--changed] [--lang <lang>] [--file <file>] [--strict]`

Runs aggregate local guard checks and diff checks. It returns the first failing
tool status where possible.

### `agently eval patch <id> --workstream <ws> [--strict]`

Checks and evaluates a patch artifact in a throwaway Git worktree. It MUST NOT
touch the live tree.

### `agently eval claude --workstream <ws> --task <task> [--exec]`

Requires a Claude response for the addressed task's selected or latest answered
round. Writes
`handoffs/codex/NNN-eval.md`, prints a review packet, updates state, and appends
ledger. `--exec` remains a manual/TUI scaffold and does not make a real Codex
model call.

### `agently report --workstream <ws> --task <task>`

Requires eval and response files for the addressed task's selected round. Writes
`handoffs/codex/NNN-decision-report.md`, prints the report, updates state, and
appends ledger.

### `agently decide accept|revise|reject --workstream <ws> --task <task> [--note TEXT]`

Writes `decisions/NNN-decision.md`, updates state, appends ledger, and prints
confirmation to stderr. It may also read a reason from stdin.

## Guard Commands

```text
agently guard [--changed] [--file <file>] [--lang bash|python|go|php] [--strict]
agently guard scope
agently guard secret
agently guard artifact
agently guard diff
agently guard doctrine
```

Guard commands run local tools through argv arrays. Missing optional tools are
reported and skipped unless strict mode is requested. Long output is truncated and
logged.

## Version And Help

- `agently version` prints `Agently <version>`.
- `agently help` prints top-level usage.
- `ws --help`, `task --help`, `doc --help`, and `claude --help` are implemented.
