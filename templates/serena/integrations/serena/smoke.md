# Serena Smoke Checks

`agently serena smoke` verifies Agently's Serena integration without risky
mutation.

It checks:

- Serena pack files exist;
- generated MCP snippets can be rendered;
- profile value is valid;
- Serena command discovery is non-fatal;
- repo root resolves;
- Git status and `.serena/memories/` do not change.

Serena being absent is a warning or skip, not a failure.
