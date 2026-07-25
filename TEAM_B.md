# Team B: public web, cloud, sharing, and release operations

## Exclusive write scope

- `web/**`, its package/lock files, public assets, tests, server routes, storage,
  and deployment configuration
- Production environment setup and secret names (never secret values)
- Public URL, profile/share, health, download-link, and incognito verification
- GitHub Release or equivalent public download page

Do not write `macos/**`, the Xcode project, or frozen `shared/**`. Request
contract changes through `HANDOFF.md`.

## Required outcomes

- Public HTTPS landing/setup/privacy/download/profile pages.
- `POST /api/v1/plan` with request/rate limits, structured output, server-side
  validation, secret-redacted logs, and deterministic seeded fallback.
- Profile create/read with v1 validation, unlisted 40-bit share codes,
  revocation, redaction, and nondisclosing errors.
- Deterministic `/api/v1/health`; optional Discord proxy using server-side
  secrets only.
- Production deployment, hard-refresh/incognito/second-device checks, and exact
  release artifact link.

## Handoff to integration

Return:

- branch and commit hash;
- routes, environment variable names, storage assumptions, and error codes;
- exact lint/test/build commands and counts;
- preview and production URLs;
- CORS/rate-limit/SSRF/log-redaction decisions;
- health, planner fallback, profile create/read/revoke, incognito, and download
  smoke results;
- known risks and rollback procedure.
