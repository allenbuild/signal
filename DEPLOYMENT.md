# Browser deployment

The configured Sites project is
`appgprj_6a6422c8db288191a17d8b43fb81efa5` and the public URL is
<https://signal-hand-control.allenxtech.chatgpt.site>.

## Release gates

1. Validate shared schema fixtures.
2. Install the exact `web/pnpm-lock.yaml`.
3. Run lint, unit/component tests, typecheck, production build, Playwright, and
   the production dependency audit.
4. Scan source and output for secrets, private destinations, native product
   links, and production localhost dependencies.
5. Commit and push the exact verified source.
6. Save that commit as a Sites version and deploy only the saved version.
7. Smoke `/`, MediaPipe model/WASM assets, health, planner, profile flows,
   hard refresh, mobile layout, camera permission, Control, and Commands on the
   production HTTPS URL.
8. Record a second-computer physical result separately. Automation does not
   count as two-computer hardware evidence.

## Environment

Optional server-only values are `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL`, and
`DISCORD_WEBHOOK_URL`. `NEXT_PUBLIC_SITE_URL` is the canonical public HTTPS
origin. D1 is injected through the `DB` binding. No native release variables are
used.

## Rollback

Keep the preceding Sites version immutable. If production smoke fails, redeploy
that saved version and report which browser gate failed.
