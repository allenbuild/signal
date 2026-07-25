# Public web deployment

This is the deployment procedure, not a claim that deployment has occurred.
Record provider, project, URLs, commit, timestamps, and smoke evidence in
`SUBMISSION.md` only after observing them.

## Environment contract

Use provider-managed secrets; document names only:

- planner model API key;
- profile storage connection/credentials if storage is external;
- Discord integration secret if enabled;
- public canonical origin;
- exact native release download URL;
- optional rate-limit store credentials.

Preview and production must use HTTPS. The release native configuration contains
only the production HTTPS origin; development localhost settings stay in
debug-only configuration and cannot ship in the archive.

## Deployment gates

1. Validate the frozen shared fixtures.
2. Run locked dependency install, lint/typecheck, tests, and production build.
3. Inspect the generated bundle/config for secrets and localhost/private hosts.
4. Deploy a preview and smoke health, planner planned/clarification/fallback,
   profile create/read/revoke, hard refresh, error pages, and download link.
5. Promote the exact tested commit with production environment variables.
6. Repeat smoke tests from incognito and a second device/network.
7. Verify HTTPS certificate, redirects, headers, CORS, rate limits, log
   redaction, and that health reveals no dependency details.
8. Fetch the published native artifact, verify checksum, and test documented
   setup on the intended Mac before linking it from the landing page.

## Required production smoke evidence

```text
Production URL:
Deployment commit:
Deployment timestamp/time zone:
GET /api/v1/health:
POST /api/v1/plan planned:
POST /api/v1/plan clarification:
Deterministic fallback:
Profile create/read/revoke:
Malformed/future-version rejection:
Rate-limit behavior:
Incognito hard refresh:
Second device/network:
Download status/checksum:
Secrets/localhost scan:
Rollback target:
```

## Rollback

Keep the previous known-good deployment immutable. If production smoke fails,
roll back the web deployment, leave the native seeded offline fallback
available, mark external integrations unavailable in the UI, and do not change
the frozen schema to patch a deployment-only problem.
