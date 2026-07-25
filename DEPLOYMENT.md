# Extension and site deployment

The configured Sites project is
`appgprj_6a6422c8db288191a17d8b43fb81efa5` and the public URL is
<https://signal-hand-control.allenxtech.chatgpt.site>.

## Release gates

1. Validate shared schema fixtures.
2. Install the exact extension and web lockfiles.
3. Run extension lint, deterministic tests, typecheck, build, package, and
   forbidden-capability scan.
4. Run web lint, unit/component tests, typecheck, production build, Playwright,
   and the production dependency audit.
5. Copy the extension ZIP and checksum into `web/public/downloads/`.
6. Scan source and output for secrets, private destinations, native product
   links, and production localhost dependencies.
7. Commit and push the exact verified source.
8. Publish the exact ZIP/checksum and save that commit as a Sites version.
   Deploy only the saved version.
9. Smoke `/`, `/setup`, the ZIP/checksum, MediaPipe assets, health, planner, profile flows,
   hard refresh, mobile layout, camera permission, Control, and Commands on the
   production HTTPS URL.
10. Load the unpacked artifact in current Chrome and test Wikipedia, GitHub,
    Google, a nested scrolling page, and a React app. Record a second-computer
    physical result separately. Automation does not
   count as two-computer hardware evidence.

## Environment

Optional server-only values are `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL`, and
`DISCORD_WEBHOOK_URL`. `NEXT_PUBLIC_SITE_URL` is the canonical public HTTPS
origin. D1 is injected through the `DB` binding. The extension stores only
settings, tuning, and reviewed profiles in Chrome storage. No native release
variables are used.

## Rollback

Keep the preceding Sites version immutable. If production smoke fails, redeploy
that saved version and report which browser gate failed.
