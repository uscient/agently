# Agently Patch {{PATCH_ID}}

- workstream: {{WORKSTREAM_SLUG}}
- status: proposed
- format: {{PATCH_FORMAT}}
- created_at: {{DATETIME}}
- base_commit: {{BASE_COMMIT}}
- patch_sha256: {{PATCH_SHA256}}

Review `patch.diff`, run `agently patch check {{PATCH_ID}}`, then apply only with:

```bash
agently patch apply {{PATCH_ID}} --reviewed
```
