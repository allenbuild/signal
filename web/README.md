# Signal web application

This directory is the complete Signal product: browser camera tracking,
MediaPipe hand landmarks, Control and Commands modes, Fist command creation,
builder, planner and profile APIs, D1 storage, documentation, and tests.

## Development

```sh
pnpm install --frozen-lockfile
pnpm dev
```

Open the shown local URL for development only. Production is the public HTTPS
Sites deployment and has no localhost dependency.

## Verification

```sh
pnpm lint
pnpm test
pnpm typecheck
pnpm build
pnpm exec playwright install chromium
pnpm test:e2e
pnpm audit --prod --audit-level=high
```

MediaPipe runtime files and the Hand Landmarker model are self-hosted under
`public/mediapipe/`.
