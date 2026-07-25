# Signal web

Public product site, versioned planner/profile API, share pages, and local
workflow builder for Signal. The app uses the Cloudflare-compatible vinext
starter and preserves Sites hosting metadata in `.openai/hosting.json`.

```bash
npm install
npm run dev
npm test
npm run lint
```

No browser preview is required for delegated builds. `npm test` performs a
production build and exercises rendered content plus the v1 API through the
compiled worker. See `API.md` and `.env.example` for the public contract and
server-only configuration.
