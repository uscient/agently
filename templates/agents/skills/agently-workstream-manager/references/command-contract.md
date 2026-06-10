# Agently Command Contract

## Initialization

- `agently init --codex`
- `agently --project DIR <command> ...`
- `AGENTLY_PROJECT=DIR agently <command> ...`
- `agently init --codex --project DIR`
- `agently init --codex --target DIR`
- `agently init --codex --name NAME`
- `agently init --codex --force`
- `agently init --codex --dry-run`
- `agently init --codex --allow-non-git`
- `agently doctor [--codex] [--claude] [--serena] [--fix] [--json]`
- `agently status [--workstream NAME] [--json]`
- `agently profile list|get|set`
- `agently serena status|create-project|onboard|memories|profile|smoke`
- `agently mcp status|add|remove`
- `agently evidence [--since BASE] [--tests] [--output PATH] [--json]`
- `agently prompt codex|claude|review ...`
- `agently version`
- `agently help`

## Workstreams

- `agently workstream list`
- `agently workstream create <name> [--branch|--no-branch] [--branch-name NAME] [--branch-from REF] [--allow-dirty] [--checkout-existing]`
- `agently workstream new <name> [--branch|--no-branch] [--branch-name NAME] [--branch-from REF] [--allow-dirty] [--checkout-existing]`
- `agently workstream open <name>`
- `agently workstream status <name>`
- `agently workstream prompt <name> --for codex|claude`
- `agently workstream handoff <name> --for codex|claude`
- `agently ws list`
- `agently ws new <slug> [--branch|--no-branch] [--branch-name NAME] [--branch-from REF] [--allow-dirty] [--checkout-existing]`
- `agently ws show --workstream <slug>`
- `agently ws path --workstream <slug>`

## Tasks

- `agently task list --workstream <ws>`
- `agently task new <slug> --workstream <ws>`
- `agently task show --workstream <ws> --task <task>`
- `agently task path --workstream <ws> --task <task>`
- `agently task status --workstream <ws> --task <task>`
- `agently task docs`
- `agently task set-state <state> --workstream <ws> --task <task>`

## Docs And Packets

- `agently docs`
- `agently doc show <name> --workstream <ws> --task <task>`
- `agently doc path <name> --workstream <ws> --task <task>`
- `agently doc edit <name> --workstream <ws> --task <task>`
- `agently doc replace <name> --workstream <ws> --task <task>`
- `agently packet claude --workstream <ws> [--task <task>]` (compiler shortcut)
- `agently packet codex --workstream <ws> [--task <task>]` (compiler shortcut)
- `agently packet status --workstream <ws> [--task <task>]` (compiler shortcut)
- `agently packet review --workstream <ws> [--task <task>]` (compiler shortcut)
- `agently packet --profile claude|codex|generic --workstream NAME [--task NAME] [--budget small|normal|full]`
- `agently packet inspect ... --workstream NAME [--task NAME] [--json]`
- `agently context budget [--workstream NAME [--task NAME]] [--budget small|normal|full] [--json]`
- `agently context manifest [--workstream NAME [--task NAME]] [--json]`
- `agently compact workstream <name>`
- `agently compact doctrine`
- `agently inspect symbols <file>`
- `agently inspect skeleton <file>`
- `agently inspect read <file> --start <n> --end <m>`
- `agently inspect read <file> --full`
- `agently inspect grep <pattern> [path]`
- `agently inspect sg <pattern> --lang <lang> [path]`
- `agently inspect tree [path] --depth <n>`
- `agently patch propose <patch-file> --workstream NAME`
- `agently patch check <id|patch-file> --workstream NAME`
- `agently patch apply <id> --workstream NAME --reviewed`
- `agently patch list --workstream NAME [--json]`
- `agently patch show <id> --workstream NAME`
- `agently patch explain <id> --workstream NAME`
- `agently patch reject <id> --workstream NAME`

## Claude, Eval, Decision

- `agently claude config`
- `agently claude config --model <alias-or-model-name> --effort <level>`
- `agently claude plan --workstream <ws> --task <task>`
- `agently claude followup --workstream <ws> --task <task> --note "<note>"`
- `agently guard [--changed] [--file PATH] [--lang bash|python|go|php] [--strict]`
- `agently guard scope|secret|artifact|diff|doctrine`
- `agently eval`
- `agently eval patch <id> --workstream <ws>`
- `agently eval claude --workstream <ws> --task <task>`
- `agently report --workstream <ws> --task <task>`
- `agently decide accept|revise|reject --workstream <ws> --task <task>`
