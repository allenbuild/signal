# Team A: native control and integration

> Originally an integration workstream record. Decision D-015 reactivates the
> native product as the canonical Signal release. Current production source is
> the root `Signal/` target and `Signal.xcodeproj`; the older `macos/` tree
> remains archived history.

## Exclusive write scope

- Root native app source, tests, Xcode project, entitlements, fixtures, and app
  assets
- `shared/**` through contract freeze, then through the designated integration
  owner only
- Native packaging scripts and release artifact generation
- Top-level documents while integrating final evidence

Do not write `web/**` or its dependency manifests.

## Required outcomes

- Preserve real system-wide pointer, click, vertical pinch scroll, and
  horizontal pinch zoom with public macOS APIs.
- Implement Paused, Control, and Commands modes and exactly eight deterministic
  command gestures with confidence, stable hold, cooldown, and release gating.
  Five is intentionally absent.
- Validate, import, export, and atomically save the closed local command
  document; keep only Fist configurable.
- Implement a cancellable typed action executor and production-wired,
  structured Teach by Demo authoring flow. Capture must be explicit, bounded,
  review-first, secure-field redacting, and pixel-free.
- Start output paused, implement synchronous emergency stop, and release all
  held state on every safety transition.
- Ship a Release `.app`, ZIP, optional reliable DMG, release-record SHA-256
  checksums, and honest signing/notarization status.

## Handoff to integration

Return:

- branch and commit hash;
- files/modules changed and public Swift interfaces;
- exact `xcodebuild` build and test commands with result counts;
- fixture and physical checks separately;
- bundle ID, minimum macOS version, signing identity class (never credentials);
- packaged artifact paths/checksums;
- known risks, permission steps, and rollback/recovery command.
