# Signal web API — version 1

The implementation in `lib/api/` duplicates the frozen v1 contract in
TypeScript/Zod. Producers emit `schemaVersion: 1`; a future version receives
`unsupported_schema_version`.

## Endpoints

- `GET /api/v1/health` returns deterministic, non-secret service capability
  data. It never checks Anthropic or Discord over the network.
- `POST /api/v1/plan` accepts the frozen planner request shape:
  `{schemaVersion, requestId, request, targetGesture?, actionCatalog}`. The
  response is either `status: "planned"` with a fully validated action plan or
  `status: "needs_clarification"`. The seeded focus and Teach by Demo phrases
  work without a provider key.
- `POST /api/v1/profiles` accepts `{profile}` where `profile` is the frozen v1
  profile. Only `share.visibility: "unlisted"` is publishable. It returns
  `{schemaVersion, shareCode, profileURL}`.
- `GET /api/v1/profiles/:shareCode` returns the v1 profile directly.
  `SIG1-SGNL2626` is the always-available seeded profile.
- `POST /api/v1/integrations/discord` accepts
  `{schemaVersion:1,message,webhookReference?}`. It uses only the fixed
  server-side `DISCORD_WEBHOOK_URL`; without one, it returns a clearly marked
  deterministic fallback receipt.

Canonical share codes are `SIG1-XXXXXXXX`, using eight cryptographically random
symbols from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`.

## Safety and deployment notes

JSON bodies are limited to 16 KiB for planning, 48 KiB for profiles, and 8 KiB
for Discord receipts. Strict schemas reject unknown fields, raw secrets,
unsupported actions, duplicate step/secret IDs, undeclared secret references,
and unsafe literal URLs. Planner output must be a subset of the caller’s action
catalog. Generic `http_request` is disabled in planner output and public
profiles because production-grade DNS pinning and redirect revalidation are not
implemented. Discord egress is restricted to a configured Discord HTTPS host
with redirects disabled.

Rate limiting and profile storage are bounded in-memory fallbacks. Therefore
newly published profiles can expire when a worker instance restarts. The seeded
demo profile is compiled into the worker and always available. Replace the
profile map with D1 before promising durable user-created shares; the API
contract does not need to change.

CORS permits requests without an Origin header (native `URLSession`), same-origin
web requests, and exact origins listed in `SIGNAL_ALLOWED_ORIGINS`. Production
hosting terminates HTTPS; native release configuration must use the public HTTPS
base URL and never localhost.
