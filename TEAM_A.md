# Team A: native control and integration

> Historical workstream record. Native work is archived and is not part of the
> current Signal product, CI, or deployment.

## Exclusive write scope

- Native app source, tests, Xcode project, entitlements, fixtures, and app assets
- `shared/**` through contract freeze, then through the designated integration
  owner only
- Native packaging scripts and release artifact generation
- Top-level documents while integrating final evidence

Do not write `web/**` or its dependency manifests.

## Required outcomes

- Preserve real system-wide pointer, click, vertical pinch scroll, and
  horizontal pinch zoom with public macOS APIs.
- Implement Touch, Command, and Hybrid modes and all nine deterministic command
  gestures with confidence, stable hold, cooldown, and release gating.
- Validate/import/save v1 profiles and plans; preview and confirm AI output.
- Implement a cancellable safe action executor and controlled Teach by Demo
  recorder; keep global capture experimental if it risks release.
- Start output paused, implement synchronous emergency stop, and release all
  held state on every safety transition.
- Ship a Release `.app`, ZIP, optional reliable DMG, checksum, About commit, and
  honest signing/notarization status.

## Handoff to integration

Return:

- branch and commit hash;
- files/modules changed and public Swift interfaces;
- exact `xcodebuild` build and test commands with result counts;
- fixture and physical checks separately;
- bundle ID, minimum macOS version, signing identity class (never credentials);
- packaged artifact paths/checksums;
- known risks, permission steps, and rollback/recovery command.
