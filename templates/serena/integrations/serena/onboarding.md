# Serena Onboarding

Agently prepares onboarding prompts. It does not run onboarding.

Use:

```bash
agently serena onboard --client codex
agently serena onboard --client claude-code
```

Then run the generated prompt inside the selected MCP client.

After the client-side onboarding finishes, run:

```bash
agently serena memories check
```

Review `.serena/memories/` before relying on any generated memories.
