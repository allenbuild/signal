# Signal

Signal is one public browser application for hand control and programmable
gestures. Open the HTTPS site, click **Start Signal**, allow the camera, and use
either:

- **Control** — relative virtual cursor, pinch click, held vertical scroll, and
  held horizontal zoom inside the Signal page.
- **Commands** — nine deterministic poses with stable-hold, cooldown, and
  release-to-rearm behavior.

Camera frames are processed locally with the self-hosted MediaPipe Hand
Landmarker. Natural-language commands, Teach by Demo, profiles, planner APIs,
and typed integrations remain in the same web product. Browser execution is
restricted to reviewed browser-safe actions.

The historical native prototype is preserved on
`codex/archive-native-web-2026-07-24` and under `macos/`, but it is not built,
deployed, linked, or required by the current product.

## Verify

```sh
node scripts/validate-shared-contracts.mjs
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
