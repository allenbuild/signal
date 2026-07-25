# Signal repository guidance

## Current product boundary

- Signal is one Manifest V3 Chrome extension under `extension/**`. It controls
  ordinary HTTP/HTTPS pages through content scripts and a persistent side-panel
  experience across tabs.
- `web/**` remains the public installation, download, fallback demo, builder,
  profile, planner API, documentation, and deployment surface.
- `macos/**` and native release scripts are legacy source retained for history.
  Do not build, package, link, or present them as part of the current product.
- No current feature may require a native app, Accessibility permission,
  localhost service, native messaging, or operating-system automation.
- Preserve the browser-only fallback at tag `signal-web-fallback` and the
  historical native/web state on `codex/archive-native-web-2026-07-24`.

## Evidence and safety

- The `night-hack-start` tag points to an empty repository. Keep the separate
  HandPilot prior-work disclosure distinct from repository evidence.
- Never claim physical camera, gesture, cross-device, deployment, or production
  behavior without an observed result.
- Camera capture starts only after an explicit click. Frames and landmarks stay
  inside the extension's offscreen document and are never uploaded or stored.
  Teach by Demo records reviewed browser actions, not passwords or video.
- Browser commands must pass the browser-only allowlist. Reject native actions,
  non-public URLs, unknown fields, future schema versions, and inline secrets.
- Plans remain previews until reviewed. External effects require explicit
  browser permissions or configured server-side credentials.

## Verification

Run contract validation plus locked extension and web installs, lint, tests,
typecheck, builds, extension packaging, Playwright, production dependency
audits, forbidden-permission/source scans, and `git diff --check`.
