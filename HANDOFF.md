# Signal project handoff

Snapshot: 2026-07-24, America/Los_Angeles.

## Overall project status

The web/cloud implementation is release-ready in source. The primary `/` route
is the requested polished one-page gesture command interface, and the existing
planner, sharing, Discord, release, privacy, and security work is preserved.
The code passed its local build, unit/integration, and desktop/mobile browser
acceptance gates.

The work was developed on `partner/web-cloud` and is being fast-forwarded and
pushed as `human/actions-cloud` for handoff.

There is not yet a live production URL. Sites project
`appgprj_6a6427e53dd081919929ed91bee95fc9` is persisted in
`web/.openai/hosting.json`, but the current connector identity receives
`404 project_not_found` for that exact ID. No source version can be saved or
deployed until ownership/access is restored. Vercel authentication remains
unavailable, so no Vercel deployment is claimed.

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
- Sites project ID persisted:
  `appgprj_6a6427e53dd081919929ed91bee95fc9`; access by the current connector
  identity is blocked with `404 project_not_found`.

## Verification

Run from `web/`:

```text
pnpm test          PASS — 10 files, 104 tests
pnpm typecheck     PASS
pnpm lint          PASS
pnpm build         PASS
pnpm test:e2e      PASS — 16/16 desktop/mobile Chromium tests
git diff --check   PASS
```

The final E2E run used the repository-pinned Playwright Chromium against the
Signal dev server on `http://localhost:3100` because an unrelated local service
occupied port 3000. Manual in-app browser QA from the preceding source commit
also verified fallback generation, plan review, save/reload persistence, mobile
full-screen modal behavior, Escape/focus restoration, and a clean console.

## Features partially completed or intentionally deferred

- Sites project ownership/access must be restored before saved versions,
  deployment state, environment values, or a production URL can be managed.
- Vercel CLI/auth/project linking was unavailable; Vinext/Cloudflare/D1 on
  Vercel still needs validation if Vercel is mandatory.
- Anthropic and Discord production secrets were not configured; fallback and
  simulation remain functional.
- Native retrieval is currently JSON export/import; there is no live
  WebView/native command transport.
- No native artifact, signing/notarization, physical gesture, second-device,
  or real HTTPS screen-picker recording test is claimed.
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

1. Restore the current connector identity's access to persisted Sites project
   `appgprj_6a6427e53dd081919929ed91bee95fc9`.
2. Build/package the exact verified commit, push it to the configured Sites source
   repository, save a version, deploy it publicly, and poll to success.
3. Set `NEXT_PUBLIC_SITE_URL` to the returned URL and redeploy the environment
   revision.
4. Apply and verify `web/drizzle/0000_careful_tarantula.sql` on production D1.
5. Smoke-test `/`, health, fallback planning, profile create/read/revoke, hard
   refresh, incognito, and mobile against production.
6. Manually test the real HTTPS screen picker and recording lifecycle; mocked
   coverage must not be presented as a hardware test.
7. Configure live Anthropic/Discord only if needed, without exposing values.
8. Choose a native command retrieval transport; JSON import is the current
   supported mechanism.
9. Schedule and verify `web/db/purge-expired-profiles.sql` at least daily.
10. If Vercel is mandatory, authenticate/link it and adapt/validate the
    Vinext/Cloudflare/D1 runtime before claiming a Vercel URL.

## Bugs and known issues

- No live deployment URL yet.
- The persisted Sites project is not visible to the current connector identity.
- The production D1 migration and daily retention schedule are not yet
  verifiable.
- Per-IP rate limits are in-memory and reset across isolates/deploys.
- Keyframes can contain sensitive content; the UI/docs disclose this risk.
- Historical supporting routes remain even though `/` is the only primary page.

## Exact next steps

```sh
git switch human/actions-cloud
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
