# Security

## Trust model

Treat camera/tracking data, imported profiles, shared profiles, planner output,
recorded actions, URLs, frontmost-application state, clipboard content, and
network responses as untrusted. A schema-valid action is data to review, not
authorization to execute.

The native process has high impact after Accessibility permission. Reduce risk
with a paused-by-default output gate, exact previews, confirmation, cancellation,
short timeouts, bounded plans, safe action allowlists, and typed receipts.

## Non-negotiable runtime invariants

- Output starts disabled and never automatically re-enables.
- Control-Option-Command-H synchronously closes output gates, releases held
  events, cancels pinch state, command activation, and macros, visibly pauses,
  and requires explicit re-enable.
- Pause, mode change, tracking loss, camera stop, sleep, termination, and errors
  release held state. A cancelled pinch never clicks.
- Planner responses are validated server-side and independently client-side.
- The UI displays every effect and requires approval before save or first run;
  externally visible/network/destructive effects may require every-run approval.
- Future schema versions, unknown actions, unknown properties, duplicate step
  IDs, duplicate gesture mappings, and limit violations are rejected.

## Secret handling

Portable JSON contains only `secretRef` identifiers and descriptors. Native
secrets live in Keychain. Server secrets live in managed environment storage.
Never put values in source, environment examples, share codes, URLs, profiles,
planner prompts, receipts, logs, screenshots, crash reports, or analytics.

Do not accept arbitrary HTTP headers. V1 allows only `Accept`, `Content-Type`,
and `User-Agent`; authentication is injected by a typed secret reference after
approval. Never forward credentials after an origin change.

## Localhost/private-network block

Every production network action is `https` with
`networkPolicy: public_https_only`. Before every connection and redirect:

1. Parse with a standards-compliant URL parser. Reject user-info, fragments
   containing credentials, invalid IDNs, unsupported ports, and non-HTTPS.
2. Reject hostnames `localhost`, `.localhost`, `.local`, `.internal`, and
   single-label names. Canonicalize case and trailing dot first.
3. Reject literal and all resolved IPv4/IPv6 loopback, private, link-local,
   unspecified, multicast, carrier-grade NAT, benchmark, documentation, and
   other non-global ranges, including IPv4-mapped IPv6.
4. Resolve DNS, pin the validated answer for the connection (or use equivalent
   rebinding-resistant transport), and reject mixed public/private answer sets.
5. Re-parse and re-resolve each redirect, at most five hops. Strip credentials
   on any origin change and never downgrade.

At minimum block IPv4 `0.0.0.0/8`, `10/8`, `100.64/10`, `127/8`,
`169.254/16`, `172.16/12`, `192.0.0.0/24`, `192.0.2/24`, `192.168/16`,
`198.18/15`, `198.51.100/24`, `203.0.113/24`, multicast, and reserved ranges;
and IPv6 unspecified/loopback, `fc00::/7`, `fe80::/10`, documentation,
multicast, and mapped blocked IPv4. Prefer a maintained global-unicast policy
library plus adversarial tests over a handcrafted allowlist alone.

Schema validation cannot implement these checks. Test literal encodings, mixed
DNS answers, rebinding, redirects to private hosts, credential redirects, and
IPv4-mapped IPv6.

## Action safety

V1 excludes `raw_applescript`, `shell_command`, arbitrary HTTP headers,
private-network overrides, and raw secrets. AppleScript support is limited to
allowlisted templates and arguments; shortcuts are named user-owned Shortcuts.
Conditional branches do not recurse. Runtime action count includes both chosen
branch actions and top-level steps and cannot exceed 50.

Click coordinates are normalized to the active display and require preview.
Keyboard, typed text, clipboard reads, webhooks, DELETE/PATCH requests, and app
automation deserve higher confirmation based on actual effect.

## Web service

- HTTPS/HSTS in production; secure, same-site cookies if auth is added.
- Strict validation, 16 KiB planner request cap, 4,000-character prompt cap,
  rate limits by multiple signals, and bounded model/server timeouts.
- CORS limited to the deployed web origin and the deliberate native-app
  strategy; CORS is not authentication.
- Share codes use CSPRNG output, rate-limited lookup, nondisclosing 404s,
  revocation, and redaction.
- No camera endpoints, arbitrary code execution, raw planner code, detailed
  health internals, or secret values in logs.
- Dependencies and deployment permissions follow least privilege.

## Reporting

Before public release, add a monitored security contact. Do not publish
credentials or exploit details in an issue; rotate exposed credentials
immediately and revoke affected share codes.
