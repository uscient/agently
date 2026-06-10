# Serena Lane Separation

Serena serves a separate capability lane in Agently-managed projects:

1. Lane 1 — Agently Workflow Lane
   - Controlled exclusively by Agently CLI commands and Agently-owned files.
   - Agently MAY generate Serena-oriented artifacts, prompts, reports, smoke checks, onboarding guidance, and integration files for future code-lane sessions.
   - Agently does NOT call Serena, drive MCP/LLM sessions, or consume Serena output during workflow-lane execution.

2. Lane 2 — Code-Intelligence Lane
   - Used by code-role agents under explicit authorization, where the agent calls Serena MCP tools directly.
   - This lane is governed by the active task, project doctrine, user permission, and the selected Agently Serena profile.

The lanes MUST NOT merge. Agently may generate Serena guidance and snippets for
future code-lane sessions. Codex may use Serena to work the code when explicitly
allowed.
Serena does not own either lane.

Agently remains the workflow authority.
Serena remains a semantic code-intelligence provider.
Serena is not the Agently workflow MCP adapter.

## Key Boundary

The important split is workflow control plane versus agent code tool plane.
It is not Agently repository versus user project repository.
