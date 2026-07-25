# Signal browser-only handoff

Snapshot: 2026-07-24, America/Los_Angeles.

## Product decision

Signal is one public browser application. The earlier native-plus-web merge was
preserved at commit `7ac287ccdd0f15d066854613d6083d6c90d6a966` on
`codex/archive-native-web-2026-07-24`, then `main` moved forward with the
browser-only architecture. Native source remains as legacy history only.

## Implemented in the pivot

- Self-hosted MediaPipe Tasks Vision WASM and Hand Landmarker model.
- Explicit camera start/stop, exact constraints, mirrored preview, 21-point
  overlay, GPU-to-CPU fallback, dropped-frame scheduling, and telemetry.
- Control mode with relative virtual pointer, click transaction, dominant-axis
  scroll/zoom lock, hysteresis, clamping, re-anchor, and loss reset.
- Commands mode with nine deterministic poses, 550 ms hold, 800 ms cooldown,
  single fire, and release/change rearm.
- One-page 4×2 preset layout plus centered Fist editor.
- Natural-language and Teach by Demo plans restricted to browser-safe actions.
- Browser executor, navigation-tab preparation, explicit notification
  permission, safe URL validation, and native-action rejection.
- Builder, profile API, public profile rendering, docs, setup, privacy, and CI
  updated to the browser-only boundary.

## Verification commands

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

Do not report a command as passing until it has run on the final commit. Do not
report a camera gesture or two-computer test without observed physical evidence.

## Deployment

Reuse Sites project `appgprj_6a6422c8db288191a17d8b43fb81efa5`, binding
`d1:DB`, and public URL
<https://signal-hand-control.allenxtech.chatgpt.site>. Save the exact pushed
commit as a version before deploying.

## Remaining external checks

Production camera permission and every gesture must be physically observed.
The explicit two-computer requirement needs a human with a second machine if
only one computer is available to this task.
