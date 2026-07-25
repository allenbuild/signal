# Signal project handoff

Snapshot: 2026-07-24, America/Los_Angeles.

## Overall project status

`main` now integrates the native macOS product and the complete web/cloud
product. The native app retains camera tracking, pointer, click, scroll, zoom,
gesture recognition, programmable profiles, safety controls, and the packaged
macOS application. The web app retains the gesture command surface, builder,
planner, profile sharing and revocation, Discord integration, release pages,
documentation, D1 storage, and automated tests.

The merge of `origin/human/actions-cloud` into `main` was resolved by
consolidating the overlapping web implementations. The D1-backed cloud routes
and command UI are canonical; native release metadata, setup guidance, project
links, security dependency pins, and the existing public Sites project were
carried forward.

The configured public Sites project is
`appgprj_6a6422c8db288191a17d8b43fb81efa5`, and its current production URL is
<https://signal-hand-control.allenxtech.chatgpt.site>. That deployment predates
this merge. The integrated source must be saved and deployed as a new Sites
version before the live URL can be claimed to run this exact commit.

## Features completed

- Exact lowercase `signal` one-page UI with eight desktop 4×2 preset cards and
  one centered Fist card; responsive two-column mobile layout.
- Locked preset previews and a Fist-only modal editor.
- Natural-language command planning with strict Zod v1 validation, optional
  server-side Anthropic, and an honest deterministic fallback.
- Numeric and word-form waits, including the documented “one second” prompt.
- Teach by Demo with explicit `getDisplayMedia`, `MediaRecorder`, timer,
  permission/error recovery, 30/60-second limits, 40-MiB limit, preview,
  retake, complete track cleanup, and blob URL revocation.
- Local 6–10 frame extraction, 1024-pixel maximum longest side, WebP
  compression, and metadata/keyframe-only planning requests.
- Human-readable plan review, rename, reorder, remove, simulated test, and save.
- Versioned localStorage Fist persistence, strict JSON import/export, and reset.
- Validated `signal:gesture` bridge with progress, fire state, per-gesture
  cooldown, and editor suppression.
- Strict action/profile/planner contracts with unknown-action, private literal
  URL, and inline-secret rejection.
- D1 unlisted profile create/read/revoke APIs plus generated migration.
- One-page-memory revoke-capability handling with explicit copy and confirmed
  revoke controls; the capability never enters profile JSON or local storage.
- Defined D1 retention: active shares expire after 365 days, revoked rows after
  30 days, API access purges opportunistically, and
  `web/db/purge-expired-profiles.sql` is supplied for the required daily
  production schedule.
- Typed Discord integration, server-side secrets, defensive headers, privacy
  and security documentation, and generated social artwork.
- Sites project ID and D1 binding persisted:
  `appgprj_6a6422c8db288191a17d8b43fb81efa5` and `DB`.
- Native camera tracking and execution paths remain compiled and covered by
  the Swift test suite.

## Verification

Run from `web/`:

```text
node scripts/validate-shared-contracts.mjs  PASS
scripts/build-macos.sh                      PASS
swift test --package-path macos             PASS — 41 tests
pnpm test          PASS — 10 files, 104 tests
pnpm typecheck     PASS
pnpm lint          PASS
pnpm build         PASS
pnpm test:e2e      PASS — 16/16 desktop/mobile Chromium tests
```

The final E2E run used the repository-pinned Playwright Chromium against the
Signal development server on `http://localhost:3100`.

## Features partially completed or intentionally deferred

- The public Sites project is accessible, but the integrated commit has not yet
  been deployed as a new version.
- Vercel CLI/auth/project linking was unavailable; Vinext/Cloudflare/D1 on
  Vercel still needs validation if Vercel is mandatory.
- Anthropic and Discord production secrets were not configured; fallback and
  simulation remain functional.
- Browser-created Fist commands currently use JSON export/import; there is no
  live WebView/native command transport.
- Local native builds and tests are verified. Signing/notarization, physical
  gesture hardware, second-device, and real HTTPS screen-picker recording are
  not claimed by these automated gates.
- D1 production migration and the daily retention schedule are unverified.

## Files modified

The implementation is concentrated under `web/`:

- composition/config: `app/*`, `components/signal/*`,
  `config/gestureCommands.ts`, `next.config.ts`
- contracts/runtime: `lib/contracts.ts`, `lib/security.ts`, `lib/planner.ts`,
  `lib/commands/*`, `lib/gestures/*`, `lib/recording/*`
- APIs/storage: `app/api/v1/**`, `lib/profile-store.ts`, `db/*`, `drizzle/*`,
  `worker/*`
- supporting pages: `app/p/*`, `app/docs/*`, `app/download/*`,
  `app/privacy/*`, `app/security/*`
- verification: `tests/**`, `e2e/signal.spec.ts`, Vitest/Playwright config
- deployment/docs: `.openai/hosting.json`, `.env.example`, `README.md`,
  `HANDOFF.md`, `SECURITY.md`, `PRIVACY.md`, `vite.config.ts`,
  `build/sites-vite-plugin.ts`, package and lock files, `public/og.png`

The prior builder/demo commit is preserved.

## Current architecture and important decisions

- Next.js App Router compiled by Vinext/Vite for Cloudflare/Sites.
- React client gesture UI and recorder; route handlers under `app/api/v1`.
- Strict Zod schemas at every network, planner, import/export, and persistence
  boundary; schema v1 rejects unknown fields and future versions.
- Drizzle plus D1 binding `DB` for shared profiles.
- Deterministic parsing runs before the optional server-only Anthropic SDK.
- Planner output is reviewable data and never executes in the web service.
- No arbitrary shell or raw model-generated AppleScript.
- Raw recording stays in browser memory; only compressed keyframes/metadata can
  reach the demo planner.
- Secret values use references and server environment variables, never
  portable JSON.
- Anonymous/local operation is the baseline; no sign-in dependency.
- Gesture events are display input only. The native companion independently
  validates, previews, approves, and executes system effects.

## APIs and endpoints created

- `GET /api/v1/health`
- `POST /api/v1/plan`
- `POST /api/v1/plan/demo`
- `POST /api/v1/profiles`
- `GET /api/v1/profiles/:shareCode`
- `POST /api/v1/profiles/:shareCode/revoke`
- `POST /api/v1/integrations/discord`
- `GET /p/:shareCode`

API errors use `{error:{code,message,requestId}}` and `x-request-id`.

## Environment variables required

Optional server-only:

- `ANTHROPIC_API_KEY`
- `ANTHROPIC_MODEL` (defaults to `claude-opus-5`)
- `DISCORD_WEBHOOK_URL`

Public deployment/release metadata:

- `NEXT_PUBLIC_SITE_URL`
- `NEXT_PUBLIC_RELEASE_DOWNLOAD_URL`
- `NEXT_PUBLIC_RELEASE_VERSION`
- `NEXT_PUBLIC_RELEASE_COMMIT`
- `NEXT_PUBLIC_RELEASE_SHA256`
- `NEXT_PUBLIC_RELEASE_MINIMUM_MACOS`
- `NEXT_PUBLIC_RELEASE_SIGNING_STATUS`
- `NEXT_PUBLIC_RELEASE_FILENAME`

Test-only: `PLAYWRIGHT_BASE_URL`, `BASE_URL`, `CI`.

## Remaining TODOs in priority order

1. Save and deploy the exact verified `main` commit to the existing Sites
   project, then poll the deployment to success.
2. Confirm `NEXT_PUBLIC_SITE_URL` is the production URL in the deployed
   environment.
3. Apply and verify `web/drizzle/0000_careful_tarantula.sql` on production D1.
4. Smoke-test `/`, health, fallback planning, profile create/read/revoke, hard
   refresh, incognito, and mobile against production.
5. Manually test the real HTTPS screen picker and recording lifecycle; mocked
   coverage must not be presented as a hardware test.
6. Configure live Anthropic/Discord only if needed, without exposing values.
7. Choose a native command retrieval transport; JSON import is the current
   supported mechanism.
8. Schedule and verify `web/db/purge-expired-profiles.sql` at least daily.
9. If Vercel is mandatory, authenticate/link it and adapt/validate the
    Vinext/Cloudflare/D1 runtime before claiming a Vercel URL.

## Bugs and known issues

- The live URL currently serves an earlier Sites version, not this merged
  commit.
- The production D1 migration and daily retention schedule are not yet
  verifiable.
- Per-IP rate limits are in-memory and reset across isolates/deploys.
- Keyframes can contain sensitive content; the UI/docs disclose this risk.
- Historical supporting routes remain even though `/` is the only primary page.

## Exact next steps

```sh
git switch main
node scripts/validate-shared-contracts.mjs
scripts/build-macos.sh
swift test --package-path macos
cd web
corepack enable
pnpm install --frozen-lockfile
pnpm test
pnpm typecheck
pnpm lint
pnpm build
pnpm test:e2e
```

Then follow `web/HANDOFF.md` and `web/README.md` for deployment, production
smoke tests, the gesture contract, Fist export format, and D1 migration.

## Frozen contract boundary

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

- [x] Both sides use `schemaVersion: 1` and reject other versions.
- [x] Swift and TypeScript action discriminators exactly match the v1 union.
- [x] Seed and planner example validate in both runtimes.
- [x] Duplicate gesture mappings and step IDs are rejected semantically.
- [x] Conditional actions are nonrecursive and count toward the 50-action
  execution budget.
- [x] Secret reference resolution never serializes a secret into profiles,
  receipts, logs, screenshots, or URLs.
- [x] Production base URL is HTTPS and not localhost.
- [x] Native planning is pinned to that endpoint and redirected responses are
  rejected; generic network actions are disabled.
- [x] AI plan remains preview-only until approval.
- [x] API errors use stable codes and do not leak storage/provider details.

API examples and share-code rules live in `shared/README.md`.
