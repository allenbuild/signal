# Signal repository guidance

## Current product boundary

- Signal is one public browser application under `web/**`.
- `macos/**` and native release scripts are legacy source retained for history.
  Do not build, package, link, or present them as part of the current product.
- No current feature may require an installed app, Accessibility permission,
  localhost service, browser extension, or operating-system automation.
- Preserve the historical merged state on
  `codex/archive-native-web-2026-07-24`.

## Evidence and safety

- The `night-hack-start` tag points to an empty repository. Keep the separate
  HandPilot prior-work disclosure distinct from repository evidence.
- Never claim physical camera, gesture, cross-device, deployment, or production
  behavior without an observed result.
- Camera capture starts only after an explicit click. Frames and landmarks stay
  in browser memory; Teach by Demo sends only disclosed compressed keyframes.
- Browser commands must pass the browser-only allowlist. Reject native actions,
  non-public URLs, unknown fields, future schema versions, and inline secrets.
- Plans remain previews until reviewed. External effects require explicit
  browser permissions or configured server-side credentials.

## Verification

Run contract validation plus locked web install, lint, tests, typecheck, build,
Playwright, production dependency audit, and `git diff --check`. CI is web-only.
