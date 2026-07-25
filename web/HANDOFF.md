# Web integration and release handoff

Snapshot date: 2026-07-24 (America/Los_Angeles).

This handoff records the integrated source behavior and known gaps. A public
Sites project exists, but this exact merged commit is not claimed as deployed.
No live provider call or production D1 migration is claimed.

## Product delivered in source

The primary route `/` is a one-page command surface:

- eight source-defined preset gestures;
- one editable Fist gesture;
- natural-language and Teach by Demo composition;
- strict version 1 plan preview and step review;
- deterministic planner fallback before optional Anthropic generation;
- local Fist save, strict import, export, and reset;
- normalized `signal:gesture` display bridge;
- explicit browser/native boundary and zero browser system effects.

The browser does not execute a command when a gesture fires. The intended
handoff is an exported strict Fist command envelope that the native app
revalidates, previews, and approves.

## Interface contracts

### Gesture input

Event name:

```text
signal:gesture
```

Detail:

```ts
{
  gesture: "one" | "two" | "three" | "four" | "five"
    | "thumbs_up" | "thumbs_down" | "c_shape" | "fist";
  confidence: number; // 0...1
  phase: "detected" | "holding" | "recognized" | "fired" | "released";
  progress?: number;  // 0...1
  timestamp?: number; // epoch ms
}
```

`window.signalGestureBridge.emit(detail)` is installed while the page is
mounted. Invalid details are ignored by the listener. `recognized` and `fired`
are cooled down for 900 ms per gesture. The editor disables bridge handling.
This interface is presentation input only and conveys no execution authority.

### Fist command handoff

- Local-storage key: `signal.fist-command.v1`
- Storage envelope: `{ storageVersion: 1, command: SignalCommand }`
- Required command gesture: `fist`
- Export: full envelope as JSON
- Import: envelope or bare command, maximum 256 KiB
- Validation: strict `signalCommandSchema` and embedded
  `actionPlanSchema`

Native integration must reject future versions and unknown fields, validate the
action plan independently, and show every effect before save or first run.

### Teach by Demo

- Raw capture: browser memory only, audio off, 60-second/40-MiB hard limits
- Network payload: metadata plus 6–10 compressed keyframes, maximum 6 MiB JSON
- Route: `POST /api/v1/plan/demo`
- AI disclosure: keyframes are sent to Anthropic only when deterministic
  parsing does not handle the request and `ANTHROPIC_API_KEY` is configured
- Persistence: no application database write

### HTTP routes

| Method | Route | Success contract |
| --- | --- | --- |
| `GET` | `/api/v1/health` | `{schemaVersion:1,status:"ok"}` |
| `POST` | `/api/v1/plan` | `planned` or `needs_clarification` v1 |
| `POST` | `/api/v1/plan/demo` | same planner response |
| `POST` | `/api/v1/profiles` | share code, URL, create-only revoke token |
| `GET` | `/api/v1/profiles/:shareCode` | strict redacted v1 profile |
| `POST` | `/api/v1/profiles/:shareCode/revoke` | `{schemaVersion:1,revoked:true}` |
| `POST` | `/api/v1/integrations/discord` | typed `sent` or `simulated` receipt |

Errors use:

```json
{
  "error": {
    "code": "stable_machine_code",
    "message": "Human-readable summary.",
    "requestId": "correlation-id"
  }
}
```

The same ID is in `x-request-id`. See `README.md` for all codes, examples,
limits, CORS behavior, and native payloads.

## Environment names

Server-only:

- `ANTHROPIC_API_KEY`
- `ANTHROPIC_MODEL`
- `DISCORD_WEBHOOK_URL`

Public build/runtime metadata:

- `NEXT_PUBLIC_SITE_URL`
- `NEXT_PUBLIC_RELEASE_DOWNLOAD_URL`
- `NEXT_PUBLIC_RELEASE_VERSION`
- `NEXT_PUBLIC_RELEASE_COMMIT`
- `NEXT_PUBLIC_RELEASE_SHA256`
- `NEXT_PUBLIC_RELEASE_MINIMUM_MACOS`
- `NEXT_PUBLIC_RELEASE_SIGNING_STATUS`
- `NEXT_PUBLIC_RELEASE_FILENAME`

Test-only:

- `PLAYWRIGHT_BASE_URL`
- `BASE_URL`
- `CI`

Secret values do not belong in `.env.example`, source, portable JSON, command
history, screenshots, or handoff text.

## Storage and migration

`.openai/hosting.json` declares the logical D1 binding `DB`.

Generated migration:

```text
drizzle/0000_careful_tarantula.sql
```

It creates `shared_profiles` with sanitized JSON, a hashed revoke capability,
and revocation timestamp. Production fails closed if D1 is absent. Development
and tests can use the process-memory fallback.

Before deployment, confirm the platform packages and applies this migration.
After deployment, verify create/read/revoke and query the schema through the
provider. Active shares expire after 365 days and revoked rows after 30 days.
API activity purges opportunistically; schedule
`db/purge-expired-profiles.sql` at least daily to bound a completely idle D1
database.

## Security decisions

- Schema version 1 only; unknown fields and unsafe actions rejected.
- Planner output is preview data and never executes in the web service.
- Raw secret fields and credential-shaped strings are rejected.
- HTTPS syntax and literal-host checks are defense-in-depth; the native
  executor still needs DNS, rebinding, redirect, and credential-forwarding
  enforcement.
- API security headers and no-store caching are set.
- No browser cross-origin allowlist or OPTIONS handlers are implemented;
  browser API use is same-origin.
- Per-IP rate limits are in-memory per process/isolate, not distributed.
- Discord accepts one approved typed action, an allowlisted secret reference,
  an allowlisted webhook host/path, no redirects, no mentions, and a six-second
  timeout.

See `SECURITY.md` and `PRIVACY.md` for the full threat/data model.

## Known gaps and risks

1. The one-page Fist UI saves the generated command but does not execute or
   transmit it to native. Export/import is the only implemented retrieval
   handoff.
2. The profile publisher keeps `revokeToken` only in open-page memory. Users
   must copy it before reload if they may need to revoke later.
3. Raw Teach by Demo video remains local, but compressed keyframes can contain
   sensitive data and can leave the browser.
4. Rate limiting resets across isolates and process restarts.
5. Retention purge logic exists, but the daily D1 operator schedule remains a
   deployment requirement.
6. The public URL currently points to a pre-merge Sites version; the integrated
   commit, production D1 migration, and live integrations remain unverified.
7. The native app builds and its automated suite passes. Signing, notarization,
   Gatekeeper, and physical-gesture evidence still require release validation.

## Verification commands

Run from `web/` against the exact intended commit:

```sh
corepack enable
pnpm install --frozen-lockfile
pnpm test
pnpm run typecheck
pnpm run lint
pnpm run build
pnpm run test:e2e
```

Current local verification against the integrated source:

```text
shared contract validation PASS
native release build       PASS
native Swift tests         PASS — 41 tests
pnpm test          PASS — 10 files, 104 tests
pnpm run typecheck PASS
pnpm run lint      PASS
pnpm run build     PASS
pnpm run test:e2e  PASS — 16/16 desktop/mobile Chromium tests
```

These local commands are useful evidence, but they are not a production smoke
test. Re-run the complete sequence from a clean locked install after the final
commit.

Required browser checks:

- desktop and mobile rendering of `/`;
- keyboard focus trap/return in the Fist editor;
- natural-language fallback and clarification;
- recording denied, unsupported, retake, 30-second warning, 60-second stop, and
  40-MiB rejection;
- keyframe payload disclosure and no raw video request;
- review/reorder/remove/test/save;
- local-storage reload, strict import, export, and reset;
- valid/invalid/replayed `signal:gesture` phases and 900-ms cooldown;
- health, profile create/read/revoke, and Discord simulated receipt;
- hard refresh, incognito, and second device.

## Deployment handoff

### Sites

Sites is the intended full-stack target because the current build is
Vinext/Cloudflare and the profile store uses D1. The accessible public Sites
project `appgprj_6a6422c8db288191a17d8b43fb81efa5` is persisted with logical
D1 binding `DB`. Its current URL is
<https://signal-hand-control.allenxtech.chatgpt.site>. The current production
version predates this merge, so it is not evidence for the integrated commit.

The release owner must:

1. run the complete verification sequence;
2. reuse the persisted Sites project ID; do not create a second project or
   substitute another opaque ID;
3. configure managed environment values;
4. push the exact validated source and use that branch-head SHA;
5. package the validated `dist/`, hosting metadata, and D1 migration;
6. save a version, deploy the saved version, and poll to success;
7. record the returned URL here and repeat all production smoke checks.

If deployment completes, add the exact URL, commit, timestamp, access policy,
D1 migration evidence, and rollback target. Do not merely change this document
to "deployed."

### Vercel

Current blockers:

- Vercel CLI is not installed;
- no usable Vercel token/auth session exists;
- no `.vercel/project.json` link exists;
- the Vinext/Cloudflare/D1 runtime has not been adapted or validated for
  Vercel.

Do not use the development memory store as a production substitute. After a
Vercel-compatible build and durable storage adapter exist, use:

```sh
cd web
pnpm install --frozen-lockfile
pnpm test
pnpm run typecheck
pnpm run lint
pnpm run build
pnpm dlx vercel@latest login
pnpm dlx vercel@latest link
pnpm dlx vercel@latest env add ANTHROPIC_API_KEY
pnpm dlx vercel@latest env add ANTHROPIC_MODEL
pnpm dlx vercel@latest env add DISCORD_WEBHOOK_URL
pnpm dlx vercel@latest env add NEXT_PUBLIC_SITE_URL
pnpm dlx vercel@latest deploy
pnpm dlx vercel@latest logs <preview-url>
pnpm dlx vercel@latest deploy --prod
```

Add the release metadata variables interactively if a verified artifact exists.
The preview must pass production-equivalent smoke before `--prod`.

## Production and release evidence template

```text
Web commit:
Locked install:
Unit/component tests:
Typecheck:
Lint:
Production build:
E2E desktop/mobile:
Sites or Vercel project:
Preview URL:
Production URL:
Deployment timestamp/time zone:
D1 migration applied:
Health:
Text planner fallback/clarification/provider:
Demo planner/keyframe disclosure:
Profile create/read/revoke:
Discord simulated/live:
CORS and headers:
Incognito/second device:
Secrets and localhost scan:
Rollback target/result:
Native release URL:
Native SHA-256:
Signing/notarization/Gatekeeper:
```

All fields are currently pending unless supported by command or human
observation recorded after this snapshot.
