# Known limitations

## Contract-freeze checkpoint

At the version 1 contract checkpoint, the tagged repository baseline is empty
and the contracts/documents alone do not prove a native build, gesture runtime,
website, deployment, package, signature, or physical behavior. Replace this
checkpoint section with integration evidence before submission; do not simply
delete unresolved items.

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
- HTTPS schema syntax does not prevent SSRF; the runtime DNS/redirect policy in
  `SECURITY.md` is required.
- The seeded Discord action needs a configured secret reference; otherwise it
  produces a local receipt explicitly labeled fallback.
- The Spotify seed uses a public URL so it can fall back when the desktop app is
  absent.

## Release-specific items to resolve honestly

- Exact minimum macOS version and supported hardware.
- Gesture reliability across lighting, skin tones, handedness, occlusion, and
  camera placement, based on actual tests.
- Whether global Teach by Demo is shipped or remains experimental; controlled
  recording is the required path.
- Signing identity, notarization, and external Gatekeeper experience.
- Production planner/provider availability, storage retention, rate-limit
  behavior, and share revocation.
- Accessibility permission identity after replacing or updating the app.
- Physical verification results for all four touch controls and nine commands.
