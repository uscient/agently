# Serena Safety Rules

- Serena is optional.
- Serena does not own Agently workflow state.
- Serena is not the Agently workflow MCP adapter.
- Future MCP/TUI clients are clients over Agently CLI contracts, not authority layers.
- Clients must not administer Agently self lifecycle.
- Do not run `agently self install`, `agently self update`, `agently self rollback`, or `agently self uninstall` from Serena, MCP, TUI, or client tooling.
- Clients must not directly mutate `.agently/**`; canonical workflow mutation goes through Agently CLI commands.
- Clients must not promote canonical workflow state autonomously; promotion requires an explicit human/governance gate.
- A future TUI is a separate client over Agently CLI contracts, not embedded in the Bash core.
- Agently does not create Serena memories.
- Agently does not create `.serena/` during init.
- Agently does not mutate source code through Serena commands.
- Agently generates snippets before mutating client config.
- Global or user config changes require explicit `--apply`.
- Codex TOML mutation is append-only in v1 and requires a backup.
- Claude Code MCP mutation delegates to `claude mcp ...`.
- `.serena/project.yml` is Serena-owned operational state once written.

Run:

```bash
agently doctor --serena
agently serena smoke
```
