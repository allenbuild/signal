# Known limitations

- Browser control is intentionally scoped to the Signal page. A normal website
  cannot control the operating-system pointer or unrelated native apps.
- Opening a public URL requires the user to prepare a reusable action tab,
  because browsers block popups that are not created directly by a click.
- Notification, speech, audio, camera, and autoplay behavior depends on browser
  support and explicit user permission.
- Gesture reliability varies with lighting, framing, handedness, occlusion, and
  camera quality; automated landmark fixtures are not physical evidence.
- Teach by Demo may send disclosed compressed keyframes to the planner when the
  user explicitly requests planning. Raw recordings are not uploaded.
- Anthropic and Discord actions need optional server-side configuration;
  deterministic planning and labeled fallbacks remain available without it.
- Share codes are unlisted identifiers, not authentication. D1 deployment and
  retention scheduling must be verified for each production environment.
- Per-IP rate limits are isolate-local and are not a global distributed quota.
- A second-computer camera test cannot be inferred from Playwright or a single
  local browser session.
