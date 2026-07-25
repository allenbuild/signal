# Known limitations

## Release evidence boundary

The inspected `night-hack-start` repository baseline is empty. Version 0.1.0 is
published from commit `4dce63912e6804a813f38159aa610e8e78f25829`;
its build, tests, archive integrity, public APIs, download, and short process
launch are automated evidence. They do not prove physical camera gestures,
permissions, real input effects, or Gatekeeper acceptance.

## Designed version 1 limits

- Only schema version 1 is accepted; future versions are rejected rather than
  partially decoded.
- Plans have at most 50 top-level steps, 300 seconds total, and 60 seconds per
  step. Conditional branches are nonrecursive and at most 10 actions each.
- Raw AppleScript, shell commands, arbitrary authorization headers,
  private-network overrides, and raw secret values are not supported.
- AppleScript is limited to allowlisted template IDs. Shortcuts must already
  exist on the user's Mac.
- Share codes are unlisted read-only identifiers, not authentication. Do not
  share sensitive profiles.
- The native planner is pinned to the production HTTPS endpoint and rejects a
  redirected response. Generic HTTP actions are disabled. This is not a
  general-purpose SSRF defense for future configurable network integrations.
- The seeded Discord action needs a configured secret reference; otherwise it
  produces a local receipt explicitly labeled fallback.
- The Spotify seed uses a public URL so it can fall back when the desktop app is
  absent.

## Release-specific limitations

- The artifact requires macOS 13+ and Apple Silicon (`arm64`); Intel is not
  included.
- Gesture reliability across lighting, skin tones, handedness, occlusion, and
  camera placement has not been physically measured.
- Teach by Demo is a controlled, explicitly started, reviewable timeline; no
  global input recorder ships.
- The artifact is ad-hoc signed, not Developer ID signed or notarized.
  `spctl` rejects it; the download page documents Control-click -> Open.
- Anthropic and Discord credentials are not configured. The deterministic
  planner and local Discord receipt fallbacks are visibly labeled.
- User-created profile links use per-worker memory and can fail between
  requests; only seeded `SIG1-SGNL2626` is durable. Revocation, sign-in, and
  cloud sync are not shipped.
- Accessibility permission identity after replacing or updating the app.
- Physical verification results for all four touch controls and nine commands.
