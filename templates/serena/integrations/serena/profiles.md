# Agently Serena Profiles

Agently Serena profiles are advisory policy bundles, not native Serena contexts
and not hard sandboxes.

## `lite`

Default. Safe-ish semantic inspection:

- symbol search;
- references;
- project structure;
- onboarding only when explicitly requested;
- memory creation minimized except through onboarding prompt;
- no project source mutation.

## `review`

Read-heavy review/audit mode:

- architecture inspection;
- dependency mapping;
- find usages;
- codebase review;
- no mutation.

## `edit`

Mutation-capable:

- semantic edits/refactors may be used by Codex or Claude Code;
- only when the agent is already authorized to edit project files;
- doctor warns when this profile is active.

## Context Rule

Serena context follows the MCP client:

```text
Codex       -> codex
Claude Code -> claude-code
```

Agently profile follows the intended authority level.
