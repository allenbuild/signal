# Known limitations

- Signal controls ordinary HTTP/HTTPS pages through an extension virtual
  cursor. It does not move the operating-system pointer or control native apps.
- Signal cannot run on `chrome://` pages, the Chrome Web Store, browser
  settings, extension management, new-tab/internal pages, permission prompts,
  DevTools, or operating-system UI.
- Some page actions that require transient user activation (including certain
  popups, clipboard, media, payment, and fullscreen operations) cannot be
  synthesized by an extension gesture.
- Extension `show_notification` actions use an in-page Signal overlay in the
  minimal-permission release. Speech, media, camera, and autoplay behavior
  still depends on browser support and user permission.
- Gesture reliability varies with lighting, framing, handedness, occlusion, and
  camera quality; automated landmark fixtures are not physical evidence.
- Teach by Demo records reviewed browser actions; it excludes passwords,
  sensitive values, camera frames, and raw video.
- Anthropic and Discord actions need optional server-side configuration;
  deterministic planning and labeled fallbacks remain available without it.
- Share codes are unlisted identifiers, not authentication. D1 deployment and
  retention scheduling must be verified for each production environment.
- Per-IP rate limits are isolate-local and are not a global distributed quota.
- A second-computer camera test cannot be inferred from Playwright or a single
  local browser session.
