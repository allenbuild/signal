# Web security model

This document describes controls present in `web/`. It is not evidence of a
production security review, public penetration test, deployed header check, or
native execution audit.

## Trust boundaries

Treat all of the following as untrusted:

- natural-language planner requests and AI output;
- Teach by Demo keyframes and recording metadata;
- imported Fist command JSON and portable profiles;
- `signal:gesture` events injected by a browser harness or native WebView;
- share codes, revoke attempts, request IDs, forwarded client addresses, URLs,
  and integration messages;
- D1 rows and every value returned by an external provider.

The browser is a composition and preview surface. It does not have authority to
perform system-wide effects. The native companion must independently validate
the exact version 1 plan, show every effect, enforce confirmation and network
policy, and keep output paused until explicitly enabled.

## Implemented controls

### Strict version 1 contracts

Zod schemas reject unknown properties, future versions, duplicate gesture or
step IDs, undeclared secret references, invalid timing, and actions outside the
version 1 allowlist. Limits include:

- 50 plan actions including the chosen conditional branch;
- 10 actions in either conditional branch;
- 300-second plan, 60-second step, and 30-second wait maxima;
- 20 secret references, 9 gesture mappings, and 32 advertised planner actions;
- typed request and response envelopes.

Version 1 excludes shell commands, raw AppleScript, arbitrary authorization
headers, raw secrets, and private-network opt-outs.

### Secret rejection and redaction

Portable data may contain typed secret reference IDs and descriptors, never the
corresponding token, webhook, password, cookie, private key, or authorization
value. Recursive detection rejects known secret fields and common credential
shapes before planner/profile acceptance. Error messages and findings identify
categories and paths, not values.

Server secrets are read only from managed environment values:

- `ANTHROPIC_API_KEY`
- `DISCORD_WEBHOOK_URL`

Never use a `NEXT_PUBLIC_*` variable for a secret.

### Planner boundary

Planner output is schema-validated data, not executable code. The deterministic
parser runs first and produces only typed allowlisted actions. The optional
Anthropic call uses structured output, has no retries, and has a 12-second SDK
timeout. Refusal, provider failure, invalid output, or an unadvertised action
falls back to a clarification.

The unsafe-instruction filter rejects common attempts to expose system prompts,
environment variables, secrets, shell commands, raw AppleScript, localhost, or
metadata services. This filter is defense-in-depth; the strict schema and native
runtime remain authoritative.

### Teach by Demo boundary

Screen capture requires an explicit browser picker. Audio is disabled. The raw
video is held as a browser-memory `Blob`, capped at 40 MiB and 60 seconds, and
is not included in the network request. Object URLs and tracks are released on
reset/unmount.

The browser extracts 6–10 compressed image keyframes and sends those, duration,
MIME type, and size metadata to `/api/v1/plan/demo`. The route validates each
data URL, caps the JSON body at 6 MiB, and does not persist it. Keyframes can
still contain sensitive screen content and may be sent to Anthropic when the
deterministic parser cannot handle the request. "Raw video remains local" must
never be presented as "nothing from the recording leaves the browser."

### Gesture bridge

`signal:gesture` accepts only the nine known gesture IDs, bounded confidence
and progress, and five known phases. Invalid events are ignored. Recognized
events are cooled down per gesture for 900 ms and the bridge is disabled while
the editor is open.

The event updates UI state only. It does not carry a plan, fetch local storage,
call an integration, or execute an effect. Do not expand it into an execution
bridge without authenticated message framing, replay protection, origin
checking, explicit plan identity, and a separate native approval design.

### Fist command persistence

Only a strict version 1 Fist command can be stored at
`signal.fist-command.v1`. Imports are capped at 256 KiB and accept no unknown
fields. Saving, importing, exporting, and the in-page test receipt perform zero
native actions.

Local storage is same-origin browser state, not a secret vault. Do not store
integration values, revoke capabilities, or sensitive typed text in a command.
Native import must revalidate the exported envelope.

### Unlisted profiles

Share codes contain 40 CSPRNG bits in the canonical
`SIG1-XXXXXXXX` alphabet. Codes are unlisted locators, not authentication.
Create requests must be strict, redacted, unlisted profiles and cannot choose
their own code.

The separate 256-bit revoke token is returned only by create. D1 stores its
SHA-256 hash and compares fixed-length hashes without early exit. Missing,
revoked, malformed, and unauthorized lookups use nondisclosing
`profile_not_found` responses.

Revocation currently marks rather than deletes a D1 row. A production retention
and purge policy is still required.

### Discord integration

The route accepts one strict `discord_webhook` action, requires
`approved: true`, and recognizes only secret reference `discord.demo`.
Configured webhook URLs must be HTTPS on `discord.com` or `discordapp.com` and
under `/api/webhooks/`, with no user info. Redirects are rejected, mentions are
disabled, and the outbound request is aborted after six seconds.

Without a configured credential the route returns an explicit `simulated`
receipt and sends nothing.

### HTTP and browser controls

JSON API responses set no-store caching, CSP `default-src 'none'`, HSTS,
nosniff, frame denial, restrictive permissions policy, referrer policy, and a
request ID. Page responses add their own CSP and defensive headers.

There are no browser CORS allow-origin or preflight handlers. Same-origin
browser use is supported. Native clients can call production HTTPS directly
because browser CORS does not apply to them.

All mutating routes require JSON except revocation via `x-revoke-token`.
Explicit body limits and in-memory per-IP rate limits are:

| Route | Per-IP limit | Body/timeout |
| --- | ---: | --- |
| text planner | 20/min | 16 KiB; provider 12 s |
| demo planner | 6/min | 6 MiB |
| profile create | 10/min | 256 KiB |
| profile read | 60/min | no body |
| profile revoke | 10/min | 4 KiB JSON |
| Discord | 10/min | 8 KiB; outbound 6 s |

These rate limits are per process/isolate and can reset or diverge across a
distributed deployment. Add provider-level or durable multi-signal controls
before treating them as production abuse prevention.

## Network-action caveat

The security helper rejects obvious non-public literal destinations, user-info,
unsupported ports, local suffixes, credential fragments, and blocked IPv4/IPv6
ranges. Schema validation also requires HTTPS for portable network actions.

That is not a complete SSRF defense. Before native or server execution, resolve
DNS, reject mixed or non-global answers, pin the approved address, and repeat
validation for every redirect. Never forward credentials across origins. The
current browser planner does not execute network actions, so this enforcement
belongs to the eventual executor and any future server proxy.

## Production verification still required

Before public release, record evidence for all of the following:

- clean locked install, tests, typecheck, lint, and production build;
- deployed HTTPS, certificate, HSTS, CSP, CORS/preflight behavior, and hard
  refresh;
- D1 migration application, create/read/revoke, rollback, and retention purge;
- distributed rate limiting and spoofed-forwarded-address behavior;
- prompt/keyframe and application-log redaction;
- live Anthropic timeout/refusal/invalid-output behavior;
- live Discord success, failure, timeout, redirect rejection, and no-mention
  behavior;
- incognito and second-device profile access;
- native plan validation, DNS/rebinding/redirect defense, approval, emergency
  stop, and physical gesture matrix;
- published artifact checksum, signing, notarization, Gatekeeper, and download
  verification.

None of those production or native checks should be inferred from local source
or generated output. A monitored security contact is also required before
release; none is configured in this document.
