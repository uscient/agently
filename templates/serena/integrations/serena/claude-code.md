# Claude Code MCP Notes For Serena

Claude Code MCP wiring uses Serena context `claude-code`.

Project-scoped command:

```bash
claude mcp add serena -- serena start-mcp-server --context claude-code --project "$(pwd)"
```

User-scoped command:

```bash
claude mcp add --scope user serena -- serena start-mcp-server --context claude-code --project-from-cwd
```

Generate the command script with:

```bash
agently mcp add serena --client claude-code
```

Apply through the Claude CLI with:

```bash
agently mcp add serena --client claude-code --apply
```

Agently does not hand-edit Claude Code JSON config.
