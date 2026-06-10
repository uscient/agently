# Agently Serena Capability Pack

Serena is optional in this Agently-managed project.

Agently remains the workflow authority. Serena is a semantic code-intelligence
provider that may help Codex or Claude Code inspect symbols, references,
structure, onboarding memories, and semantic edits when explicitly allowed.
Serena is not the Agently workflow MCP adapter.

## Start Here

1. Read `lane-separation.md`.
2. Review `profiles.md` and confirm the active profile.
3. Use `agently serena status` before relying on Serena.
4. Use generated snippets under `.agently/generated/serena/` for MCP setup.

## Commands

```bash
agently serena status
agently mcp status
agently mcp add serena --client codex
agently mcp add serena --client claude-code
agently serena onboard --client codex
agently serena memories check
agently serena smoke
```

Plain Agently workflows continue to work when Serena is absent.
