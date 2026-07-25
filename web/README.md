# Signal web

Signal's primary web experience is a one-page command surface at `/`. It shows
eight fixed gesture presets and one editable Fist command. The browser can
compose, validate, preview, save, import, and export command data. It does not
control macOS or execute a saved action plan; system-wide effects belong to the
native companion after a second validation and approval boundary.

This directory also contains the version 1 planner, profile-sharing APIs,
unlisted profile pages, and a narrowly typed Discord integration.

## Current status

The source, local tests, generated D1 migration, and a local `dist/` directory
are present. Generated output is not evidence of a clean build from the final
commit, public deployment, or release. At this snapshot:

- no production URL or public release artifact is recorded;
- Vercel CLI authentication is unavailable on this machine;
- `.openai/hosting.json` declares the D1 binding name `DB` but has no Sites
  `project_id`;
- production D1 migration, HTTPS smoke tests, provider calls, second-device
  checks, native artifact download, signing, and notarization remain unverified.

See [HANDOFF.md](./HANDOFF.md) for the release checklist and known gaps.

## Product boundary

The one-page UI implements this flow:

1. A normalized `signal:gesture` browser event highlights a gesture and reports
   hold/fire state.
2. Selecting Fist opens the custom-command editor.
3. A user describes a workflow, records a short demonstration, or combines
   both.
4. The planner returns either a strict version 1 preview or a clarification.
5. The user reviews, reorders, or removes steps and saves the command locally.
6. Exported JSON is the explicit browser-to-native handoff. Importing or saving
   never runs the plan.

The event bridge is input and display state only. A `recognized` or `fired`
event does not execute browser code, call an integration, or run the saved Fist
plan. The native companion remains responsible for loading a validated command,
showing its effects, obtaining approval, and executing it safely.

## Requirements and commands

- Node.js `>=22.13.0`
- pnpm `10.29.3` via Corepack

```sh
cd web
corepack enable
pnpm install --frozen-lockfile
pnpm run dev
```

The local site defaults to `http://127.0.0.1:3000`. Other useful commands:

```sh
pnpm test
pnpm run typecheck
pnpm run lint
pnpm run build
pnpm run test:e2e
pnpm run db:generate
```

`test:e2e` starts the development server unless `PLAYWRIGHT_BASE_URL` points to
an existing preview. Re-run every command against the exact release commit;
do not reuse a prior `dist/` directory as release evidence.

Copy `.env.example` to an ignored local environment file only when needed.
Never commit populated values.

## Fist command persistence and handoff

The browser stores one strict command envelope in local storage under:

```text
signal.fist-command.v1
```

Its shape is:

```json
{
  "storageVersion": 1,
  "command": {
    "schemaVersion": 1,
    "id": "fist-example",
    "gesture": "fist",
    "name": "My fist command",
    "description": "Open Spotify and wait one second.",
    "source": "natural_language",
    "plan": {},
    "createdAt": "2026-07-25T00:00:00.000Z",
    "updatedAt": "2026-07-25T00:00:00.000Z",
    "enabled": true
  }
}
```

The abbreviated `plan` above must be a complete `actionPlanSchema` value in a
real file. Exports contain the full envelope. Imports accept either the
envelope or its bare `command`, reject files over 256 KiB, require gesture
`fist`, and strictly validate schema version 1.

Local storage is browser-profile-specific and is not a durable native handoff.
The supported retrieval path is:

1. choose **Export fist JSON**;
2. transfer the resulting JSON file to the Mac app;
3. validate `storageVersion`, `signalCommandSchema`, and the embedded action
   plan again;
4. show every step and require the applicable approval before saving or
   running it.

A native WebView may add an explicit message bridge to retrieve the same
envelope, but the current `signal:gesture` bridge does not expose local storage
or command JSON.

## Teach by Demo

Teach by Demo uses the browser's screen picker and `MediaRecorder`:

- video only; audio is disabled;
- suggested maximum is 30 seconds and hard stop is 60 seconds;
- recordings larger than 40 MiB are rejected;
- the raw video `Blob` and preview object URL remain in browser memory and are
  released when reset or unmounted;
- the browser extracts 6–10 evenly spaced image keyframes (8 by default),
  scales their longest side to at most 1024 pixels, and compresses them as WebP;
- only metadata and compressed keyframes are posted to
  `POST /api/v1/plan/demo`; the raw video is never uploaded by this code.

The demo endpoint accepts at most 6 MiB of JSON, 6–10 keyframes, and 60 seconds
of recording metadata. It does not persist the request. If the deterministic
planner handles the text, no AI provider is called. Otherwise, when
`ANTHROPIC_API_KEY` is configured, the written instruction and keyframes are
sent to Anthropic. Users must avoid recording secrets or unrelated content.

## Gesture event bridge

The bridge listens for a `CustomEvent` named `signal:gesture`:

```ts
type SignalGestureEventDetail = {
  gesture:
    | "one"
    | "two"
    | "three"
    | "four"
    | "five"
    | "thumbs_up"
    | "thumbs_down"
    | "c_shape"
    | "fist";
  confidence: number; // 0...1
  phase: "detected" | "holding" | "recognized" | "fired" | "released";
  progress?: number; // 0...1
  timestamp?: number; // epoch milliseconds
};
```

A native WebView or browser harness can emit:

```js
window.signalGestureBridge?.emit({
  gesture: "fist",
  confidence: 0.97,
  phase: "holding",
  progress: 0.72,
  timestamp: Date.now()
});
```

The listener validates gesture, phase, confidence, and progress. `recognized`
and `fired` update the UI at most once per gesture per 900 ms. `released`
clears active progress. The bridge is disabled while the editor modal is open.
Treat events as untrusted display input; they are not authorization.

## Planner behavior

Both planner routes accept strict schema version 1 requests. The normal route
is limited to 16 KiB; request text is limited to 4,000 characters and the
advertised action catalog to 32 unique entries.

`createPlannerResponse` tries the deterministic parser first. Recognized
instructions can safely create allowlisted open-app, public-URL, deep-link,
speech, notification, wait, and Discord preview steps without an AI call.
Responses mark this with `usedDeterministicFallback: true`.

If the deterministic parser cannot handle the request and an Anthropic key is
configured, the service requests structured output from the configured model
(default `claude-opus-5`) with a 12-second SDK timeout. Provider failure,
refusal, invalid output, or an unavailable key returns a safe
`needs_clarification` response rather than executing or guessing.

All returned plans are strict version 1 data. The service never executes them.

## HTTP API

| Method | Path | Purpose | Limit |
| --- | --- | --- | --- |
| `GET` | `/api/v1/health` | Deterministic non-secret readiness envelope | none |
| `POST` | `/api/v1/plan` | Text-to-plan preview or clarification | 20/IP/min; 16 KiB |
| `POST` | `/api/v1/plan/demo` | Text/keyframes-to-plan preview | 6/IP/min; 6 MiB |
| `POST` | `/api/v1/profiles` | Create a redacted unlisted profile | 10/IP/min; 256 KiB |
| `GET` | `/api/v1/profiles/:shareCode` | Read an unlisted profile | 60/IP/min |
| `POST` | `/api/v1/profiles/:shareCode/revoke` | Revoke with create-only token | 10/IP/min; 4 KiB JSON |
| `POST` | `/api/v1/integrations/discord` | Send one approved typed action | 10/IP/min; 8 KiB; 6 s |

Rate limits are process-memory buckets keyed by the edge-provided client IP.
They are not globally durable across isolates and are defense-in-depth, not a
complete production abuse-control system.

API responses set `Cache-Control: no-store`, a request ID, JSON content type,
and defensive browser headers. No route currently opts into cross-origin
browser access: there are no CORS allow-origin or preflight handlers. Browser
clients should use same-origin requests; a native `URLSession` client is not
governed by browser CORS.

### Stable error envelope

Errors use:

```json
{
  "error": {
    "code": "invalid_request",
    "message": "Request does not match the Signal planner contract.",
    "requestId": "native.request-0001"
  }
}
```

The same request ID is returned in `x-request-id`. Stable codes are:

| Code | Typical status | Meaning |
| --- | ---: | --- |
| `unsupported_media_type` | 415 | JSON content type required |
| `invalid_json` | 400 | JSON could not be decoded |
| `payload_too_large` | 413 | Route byte limit exceeded |
| `unsupported_schema_version` | 422 | Version is not 1 |
| `invalid_request` | 422 | Strict request contract failed |
| `unsafe_instruction` | 422 | Prompt requests a forbidden capability |
| `invalid_profile` | 400 | Strict/share-safe profile contract failed |
| `profile_not_found` | 404 | Absent, private, revoked, or unauthorized |
| `rate_limited` | 429 | In-memory per-IP budget exceeded |
| `storage_unavailable` | 503 | Production D1 is unavailable |
| `integration_unavailable` | 404 | Typed secret reference is not configured |
| `integration_failed` | 502 | Provider rejected, timed out, or failed |
| `planner_unavailable` | 503 | Reserved for a future explicit planner failure |
| `planner_timeout` | 504 | Reserved for a future explicit planner timeout |

The current planner converts provider failures into a successful clarification,
so the two reserved planner error codes are not currently emitted.

## Native request and response examples

### Deterministic planner

```http
POST /api/v1/plan
Content-Type: application/json
```

```json
{
  "schemaVersion": 1,
  "requestId": "native.request-0001",
  "request": "Open Safari",
  "targetGesture": "fist",
  "actionCatalog": ["open_application"]
}
```

The current deterministic response is a complete preview:

```json
{
  "schemaVersion": 1,
  "requestId": "native.request-0001",
  "status": "planned",
  "plan": {
    "schemaVersion": 1,
    "id": "plan-native.request-0001",
    "name": "Generated gesture workflow",
    "description": "Reviewed preview for fist",
    "steps": [
      {
        "id": "step-1",
        "action": {
          "type": "open_application",
          "parameters": {
            "bundleIdentifier": "com.apple.Safari",
            "applicationName": "Safari"
          }
        },
        "timeoutMs": 8000,
        "onFailure": "stop",
        "confirmation": { "mode": "none", "reason": "" }
      }
    ],
    "timeoutMs": 11000,
    "onFailure": "stop",
    "confirmation": { "mode": "none", "reason": "" },
    "createdSource": "natural_language",
    "secretReferences": []
  },
  "warnings": [
    "Built with Signal’s deterministic fallback; no AI provider was used."
  ],
  "usedDeterministicFallback": true
}
```

### Approved Discord action

```json
{
  "schemaVersion": 1,
  "requestId": "native.discord-0001",
  "approved": true,
  "action": {
    "type": "discord_webhook",
    "parameters": {
      "secretRef": "discord.demo",
      "message": "Demo complete",
      "fallback": "local_receipt"
    }
  }
}
```

When no credential is configured, the endpoint honestly simulates:

```json
{
  "schemaVersion": 1,
  "requestId": "native.discord-0001",
  "provider": "discord",
  "status": "simulated",
  "receiptId": "mock-generated-uuid",
  "message": "No Discord credential is configured; no message was sent."
}
```

With a valid managed webhook, `status` is `sent`. The endpoint accepts only
secret reference `discord.demo`; the webhook URL never appears in portable JSON.

### Profile create and revoke

Create returns a CSPRNG 40-bit share code and a separate 256-bit revoke
capability:

```json
{
  "schemaVersion": 1,
  "shareCode": "SIG1-ABCDEFGH",
  "profileURL": "https://configured-origin.example/p/SIG1-ABCDEFGH",
  "revokeToken": "SRV1_create-only-capability"
}
```

The displayed values above are illustrative, not working credentials. Capture
the real `revokeToken` once; only its SHA-256 hash is stored. Revoke with:

```http
POST /api/v1/profiles/SIG1-ABCDEFGH/revoke
x-revoke-token: <create-only token>
```

Absent codes, bad tokens, and already revoked profiles all return the same
`profile_not_found` envelope.

## D1 storage

Production profile storage uses the Cloudflare D1 binding `DB`. The generated
migration is `drizzle/0000_careful_tarantula.sql`; it creates
`shared_profiles`, stores sanitized profile JSON and a revoke-token hash, and
marks revocation with `revoked_at_ms`.

In development and tests only, a process-memory fallback is used when D1 is
unavailable. Production fails closed with `storage_unavailable`. Revocation
hides a row but does not physically delete it; no automatic retention job is
implemented.

## Deployment

### Intended Sites path

This project is built with Vinext and the Cloudflare Vite plugin, and its
profile API depends on D1. Sites is therefore the intended full-stack path.
Before publishing, the release owner must create/reuse the Sites project,
persist its opaque `project_id` in `.openai/hosting.json`, apply the generated
migration, configure managed environment values, save the exact tested commit
as a version, deploy that version, and poll to a successful status.

At this snapshot no `project_id` or deployed Sites URL is recorded. If a Sites
deployment completes, record the exact URL and smoke evidence in
`HANDOFF.md`; do not infer success from `dist/`.

### Vercel path and current blocker

The current machine has no installed Vercel CLI and no usable Vercel token.
No Vercel project link or deployment URL exists. In addition, the current
Vinext/Cloudflare/D1 runtime is not a verified Vercel target. Before using
Vercel, add and test a Vercel-compatible build and durable profile-store
adapter; do not silently replace D1 with process memory in production.

After that compatibility work, the exact CLI sequence is:

```sh
cd web
corepack enable
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

Add the optional release metadata variables the same way. Enter secret values
interactively; do not put them in commands, source, or remote URLs. Smoke the
preview before `--prod`, then repeat health, planner, profile, hard-refresh,
incognito, second-device, header, and download checks against production.

Vercel's current CLI flow is documented in its
[CLI guide](https://vercel.com/docs/cli) and
[deploy-from-CLI guide](https://vercel.com/docs/projects/deploy-from-cli).

## More detail

- [SECURITY.md](./SECURITY.md)
- [PRIVACY.md](./PRIVACY.md)
- [HANDOFF.md](./HANDOFF.md)
- frozen portable contracts in `../shared/`
