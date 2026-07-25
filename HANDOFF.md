# Signal extension handoff

Snapshot: 2026-07-24, America/Los_Angeles.

## Product decision

Signal is one Manifest V3 Chrome extension with a public install/fallback/API
site. The browser-only fallback is preserved at tag `signal-web-fallback`. The
earlier native-plus-web merge remains at commit
`7ac287ccdd0f15d066854613d6083d6c90d6a966` on
`codex/archive-native-web-2026-07-24`. Native source remains legacy only.

## Preserved from the browser fallback

- Self-hosted MediaPipe Tasks Vision WASM and Hand Landmarker model.
- Explicit camera start/stop, exact constraints, mirrored preview, 21-point
  overlay, GPU-to-CPU fallback, dropped-frame scheduling, and telemetry.
- Control mode with relative virtual pointer, click transaction, dominant-axis
  scroll/zoom lock, hysteresis, clamping, re-anchor, and loss reset.
- Commands mode with eight active deterministic poses, 550 ms hold, 800 ms cooldown,
  single fire, and release/change rearm.
- One-page 4×2 preset layout plus centered Fist editor.
- Natural-language and Teach by Demo plans restricted to browser-safe actions.
- Browser-safe executor, navigation-tab preparation, safe URL validation, and
  native-action rejection.
- Builder, profile API, public profile rendering, docs, setup, privacy, and CI
  remain deployable.

## Extension runtime

- `extension/manifest.json` declares MV3 storage, scripting, tabs, offscreen,
  sidePanel, and HTTP/HTTPS host access without nativeMessaging or debugger.
- One offscreen camera/MediaPipe runtime sends versioned tracking frames to the
  service worker; frames never leave the device.
- The service worker recovers after suspension, routes only to the active
  supported tab, resets stale interactions, and owns tab zoom and command
  execution.
- Content scripts render an isolated overlay and implement relative cursor,
  pinch click, held scroll, and zoom intent without moving the OS cursor.
- The side panel exposes camera lifecycle, Control/Commands modes, eight command
  cards, editable Fist, natural-language planning, Teach by Demo, tuning, and
  profile import/export.

## Verification commands

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

Do not report a command as passing until it has run on the final commit. Do not
report a camera gesture or two-computer test without observed physical
evidence. Loading an unpacked extension or an automated fixture is not a
physical two-computer result.

## Deployment

Reuse Sites project `appgprj_6a6422c8db288191a17d8b43fb81efa5`, binding
`d1:DB`, and public URL
<https://signal-hand-control.allenxtech.chatgpt.site>. Save the exact pushed
commit as a version before deploying.

## Remaining external checks

Production camera permission and every gesture must be physically observed.
The explicit two-computer requirement needs a human with a second machine if
only one computer is available to this task.
