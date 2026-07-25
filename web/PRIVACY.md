# Web privacy model

This document describes the implemented data flows in `web/`. It does not
replace a reviewed public privacy policy or prove the behavior of a deployed
provider, reverse proxy, native build, or third-party service.

## Core boundary

The website has no camera endpoint and does not receive native camera frames,
hand landmarks, or raw gesture video. The native companion is expected to
process camera input locally and send only normalized gesture state when it
embeds or drives the web UI.

Teach by Demo is different: the user explicitly asks the browser to capture a
screen, window, or tab. The raw screen recording remains in browser memory, but
compressed keyframes can be sent to the planner service and, conditionally, to
Anthropic. Screen recordings can reveal highly sensitive information; choose a
narrow surface and close unrelated content before recording.

## Data inventory

| Data | Location and lifetime | Network behavior |
| --- | --- | --- |
| Normalized gesture events | React state only | Not sent by this UI |
| Saved Fist command | Browser local storage key `signal.fist-command.v1` until reset/site data clear | Not sent automatically |
| Imported/exported Fist JSON | User-selected local file | Not sent automatically |
| Raw Teach by Demo video | Browser-memory Blob/object URL until reset, modal teardown, or page close | Never uploaded by this code |
| Demo keyframes | Browser memory, then request memory | Posted to `/api/v1/plan/demo`; may go to Anthropic |
| Planner text, target gesture, action catalog, request ID | Request memory | Posted to the Signal planner; may go to Anthropic |
| Unlisted profile | D1 sanitized JSON until operator deletion; revocation only hides it | Readable by anyone with its share code |
| Revoke token | Create response/client memory; only SHA-256 stored | Returned once by profile create |
| Client IP | In-memory rate-limit key until bucket expiry/pruning | Not intentionally logged by application code |
| Discord message | Request memory | Sent to configured Discord webhook only after typed approval |
| Provider secrets | Managed server environment | Used server-side; never returned in portable JSON |
| Release metadata | Public environment variables | Rendered publicly when configured |

## One-page command data

The primary `/` interface loads and saves only the editable Fist command. Eight
other preset cards are source-defined. A saved Fist envelope contains:

- version, ID, gesture, name, description, source, enabled state, timestamps;
- the complete strict action plan;
- no raw screen recording;
- no integration value or revoke token.

Local storage is scoped to the browser profile and origin. Other users of that
browser profile, browser extensions, injected same-origin script, or local
device compromise may be able to read it. Do not put passwords, tokens,
sensitive clipboard content, or private typed text in a saved plan.

Import accepts a strict version 1 Fist command and export downloads the same
envelope. These are explicit user actions. Importing, exporting, or saving does
not execute the command.

## Teach by Demo

The browser requests screen-sharing permission only after **Start recording**.
Audio capture is disabled. The code recommends a 30-second recording, stops at
60 seconds, and rejects raw video over 40 MiB.

When the user chooses **Use recording**, the browser extracts 6–10 compressed,
evenly spaced keyframes (8 by default) at a maximum 1024-pixel longest side.
The planner request includes:

- instruction text or a generic clarification request;
- duration, MIME type, and raw byte count;
- compressed base64 image keyframes.

The raw video Blob is not serialized or uploaded. The route does not persist
keyframes. However, if deterministic parsing cannot handle the instruction and
`ANTHROPIC_API_KEY` is configured, the instruction and keyframes are sent to
Anthropic for structured plan generation. Third-party processing then follows
the account and provider terms configured by the deployer.

There is no automatic visual redaction. Users must avoid secrets, notifications,
private tabs, password managers, messages, and unrelated windows.

## Planner requests

The planner can process a request locally on the server with its deterministic
parser. Recognized requests do not call Anthropic and responses state
`usedDeterministicFallback: true`.

Unrecognized requests can be sent to Anthropic only when the server has
`ANTHROPIC_API_KEY`. The provider receives request text, target gesture,
advertised action catalog, and, for demo requests, compressed keyframes.
Provider errors become a clarification. Application code adds no planner
request logging, analytics, or persistence, but platform/provider logs and
retention must be reviewed before production.

## Profile sharing and revocation

Publishing is explicit and accepts only strict, unlisted, secret-free version 1
profiles. The service stores:

- canonical share code;
- profile ID;
- sanitized profile JSON;
- SHA-256 revoke-token hash;
- creation and optional revocation timestamps.

Anyone with the 40-bit share code can view the profile. "Unlisted" is not
"private" and share codes are not authentication. Sensitive profiles should not
be published.

Revocation immediately makes reads return the same not-found response as an
unknown code, but the database row is retained with `revoked_at_ms`. No
automatic deletion or retention schedule exists yet. A production policy,
operator purge procedure, and user-accessible revocation flow are required.

The API returns a revoke capability only on create. At this snapshot the legacy
browser profile publisher does not preserve or display that token, so its users
cannot revoke without another client capturing the raw create response. This is
a known release gap, not a privacy control.

## Integrations

Portable plans carry only a secret reference such as `discord.demo`. The actual
Discord webhook URL lives in the server environment. When configured and
explicitly invoked with `approved: true`, the typed message is sent to Discord.
Discord then receives the message and normal request metadata.

Without a valid configured webhook the endpoint returns a `simulated` receipt
and makes no provider request. Receipt IDs are generated for the response and
are not persisted by application code.

## Cookies, accounts, analytics, and telemetry

The one-page command experience requires no account and adds no application
cookie, analytics SDK, crash reporter, or telemetry pipeline. The repository
contains optional ChatGPT sign-in helpers, but the primary page and documented
APIs do not call them.

Hosting providers can still produce access, firewall, build, and function logs.
No production provider configuration has been verified. Before release, record
what is logged, who can access it, retention, deletion, region, and redaction.

## User controls

- **Reset fist** removes the saved Fist local-storage entry.
- Browser site-data controls can remove all origin-local state.
- **Retake** discards the current recording and releases its object URL.
- Closing the editor/page stops capture tracks and releases in-memory media.
- Export gives the user a portable copy; deleting it is the user's
  responsibility.
- Profile revocation requires the create-only token.

## Production privacy work still open

Before public release:

- publish a reviewed operator identity, privacy contact, and policy;
- verify provider logging and retention for hosting, D1, Anthropic, and Discord;
- implement/publish D1 retention and deletion procedures;
- make the profile revoke capability usable without exposing it;
- inspect the production bundle and environment for secrets;
- verify no raw recording is transmitted and that keyframe disclosure is clear;
- confirm the native app keeps camera frames and landmarks memory-only;
- confirm analytics and telemetry remain off unless explicitly disclosed and
  consented to.
