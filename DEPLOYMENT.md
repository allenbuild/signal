# Public web deployment

The public Sites deployment is live at
`https://signal-hand-control.allenxtech.chatgpt.site`. Version 2 is sourced from
release commit `4dce63912e6804a813f38159aa610e8e78f25829` and production
environment revision 1 supplies the immutable release URL and evidence shown on
the download page. Exact smoke evidence is recorded in `SUBMISSION.md`.

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

Version 0.1.0 completed the automated and unauthenticated public portions of
these gates. A second physical device/network, permission dialogs, and the full
physical gesture matrix remain unverified. User-created profile persistence is
not a completed gate: per-worker memory can lose a link between requests, so the
seeded profile is the only durable public profile in this release.

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
