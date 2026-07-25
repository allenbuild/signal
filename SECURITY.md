# Security

Signal treats camera input, planner output, imported JSON, shared profiles, and
gesture events as untrusted.

- Schema version 1 is strict and bounded; unknown fields and future versions
  are rejected.
- The browser-only allowlist rejects native actions even when they remain valid
  legacy schema members.
- Navigation accepts public HTTPS literal hosts only and rejects credentials,
  localhost, private/reserved literals, and non-HTTPS schemes.
- Plans are previews. The client shows steps and confirmation rules before save;
  external browser permissions are requested through user clicks.
- Integration secret values exist only in the server environment and are never
  portable JSON.
- The planner cannot emit shell, AppleScript, operating-system, or arbitrary
  authorization actions.
- CI validates contracts, source quality, tests, production build, E2E, and
  production dependency audit.

Literal-host validation is not a complete DNS/redirect SSRF defense for future
server-side fetch features. New network executors must resolve and re-check each
destination and redirect before shipping.
