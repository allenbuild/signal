# Contract and integration handoff

## Frozen boundary

Schema version 1 is frozen by source commit
`e5bcfde8b051e5e7348e3c8bb48368ff9789f290` on
`codex/contracts-docs`, integrated and pushed as
`75bc042c81fe51a1c5aa45441a1db5d1cc82d6e9` on
`codex/release-integration`. It includes:

- `shared/action-plan.schema.json`
- `shared/profile.schema.json`
- `shared/planner-response.schema.json`
- `shared/seeded-demo-profile.json`
- `shared/examples/**`
- `shared/README.md`

After freeze, only the integration owner edits those files. A changed schema
must update fixtures, Swift/TypeScript decoding, validation tests, contract
documentation, and the version policy. A breaking meaning or shape change
increments `schemaVersion`; do not silently broaden version 1.

## Change request template

Append requests here without editing the schema:

```text
Requester / branch:
Date:
Contract and exact path:
Current behavior:
Requested behavior:
Why existing v1 shape cannot represent it:
Backward compatibility:
Native impact:
Web impact:
Fixtures/tests proposed:
Security/privacy impact:
Deadline / fallback if rejected:
```

The integration owner records accepted/rejected status and evidence in
`DECISIONS.md`.

## Integration checklist

- [ ] Both sides use `schemaVersion: 1` and reject other versions.
- [ ] Swift and TypeScript action discriminators exactly match the v1 union.
- [ ] Seed and planner example validate in both runtimes.
- [ ] Duplicate gesture mappings and step IDs are rejected semantically.
- [ ] Conditional actions are nonrecursive and count toward the 50-action
  execution budget.
- [ ] Secret reference resolution never serializes a secret into profiles,
  receipts, logs, screenshots, or URLs.
- [ ] Production base URL is HTTPS and not localhost.
- [ ] Runtime network policy checks literal host, DNS answers, redirects, and
  origin-changing credential forwarding.
- [ ] AI plan remains preview-only until approval.
- [ ] API errors use stable codes and do not leak storage/provider details.

API examples and share-code rules live in `shared/README.md`.
