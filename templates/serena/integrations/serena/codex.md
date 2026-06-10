# Codex MCP Notes For Serena

Codex MCP wiring uses Serena context `codex`.

Recommended generated snippet:

```toml
[mcp_servers.serena]
startup_timeout_sec = 15
command = "serena"
args = ["start-mcp-server", "--project-from-cwd", "--context=codex"]
```

Generate or refresh it with:

```bash
agently mcp add serena --client codex
```

Apply conservatively with:

```bash
agently mcp add serena --client codex --apply
```

Agently appends only when no existing `[mcp_servers.serena]` block is found.
If a Serena block exists, Agently refuses and prints manual instructions.
