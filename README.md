# Signal

Signal is one Manifest V3 Chrome extension for cross-tab hand control and
programmable gestures. Load the extension, open its side panel, click **Start
Signal**, allow the camera once, and use either:

- **Control** — relative virtual cursor, pinch click, held vertical scroll, and
  held horizontal real Chrome tab zoom on ordinary HTTP/HTTPS websites.
- **Commands** — eight active deterministic poses with stable-hold, cooldown, and
  release-to-rearm behavior.

Camera frames are processed locally in one extension offscreen document with
the self-hosted MediaPipe Hand Landmarker. Natural-language commands, Teach by
Demo, profiles, planner APIs, and typed integrations remain available through
the extension and public site. Browser execution is restricted to reviewed
browser-safe actions.

The public website remains the installation/download surface and a single-tab
fallback demo. The extension does not move the operating-system cursor and
cannot control protected Chrome pages or native applications.

The historical native prototype is preserved on
`codex/archive-native-web-2026-07-24` and under `macos/`, but it is not built,
deployed, linked, or required by the current product.

## Verify

```sh
node scripts/validate-shared-contracts.mjs
cd extension
pnpm install --frozen-lockfile
pnpm verify

cd web
pnpm install --frozen-lockfile
pnpm lint
pnpm test
pnpm typecheck
pnpm build
pnpm test:e2e
pnpm audit --prod --audit-level=high
```

Production: <https://signal-hand-control.allenxtech.chatgpt.site>
