# Serena Workflow Lane

The workflow lane is controlled by Agently commands and Agently-owned files.

Agently may:

- render integration guidance;
- generate MCP snippets;
- prepare onboarding prompts;
- write status, smoke, and memory review reports;
- compare local Serena memory file snapshots;
- warn about drift between profile, MCP, and `.serena/` state.

Agently must not:

- run an LLM onboarding session;
- create Serena memories;
- mutate source code through Serena;
- silently edit global Codex, Claude Code, or Serena config;
- treat Serena output as workflow doctrine.
