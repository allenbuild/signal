# Submission record

## Identity and links

```text
Product: Signal
Submission/public site: https://signal-hand-control.allenxtech.chatgpt.site
Production/release commit: 4dce63912e6804a813f38159aa610e8e78f25829
Public health URL: https://signal-hand-control.allenxtech.chatgpt.site/api/v1/health
Durable profile demo: https://signal-hand-control.allenxtech.chatgpt.site/p/SIG1-SGNL2626
Download URL: https://github.com/allenbuild/signal/releases/download/v0.1.0/Signal-0.1.0-macOS.zip
Release page: https://github.com/allenbuild/signal/releases/tag/v0.1.0
Version/build: 0.1.0 (1)
Bundle identifier: app.signal.hand
Minimum/supported binary: macOS 13+, Apple Silicon arm64
```

## Kickoff and after-tag evidence

```text
Kickoff commit/tag: 7cb7e47cc83ae4c0c542bde652827bbb02c55d78 / night-hack-start
Kickoff tracked-file count: 0
Release commit/tag: 4dce63912e6804a813f38159aa610e8e78f25829 / v0.1.0
Commits after kickoff tag: 13
Diff shortstat after kickoff tag: 112 files changed, 21,523 insertions
Prior-work disclosure: PRIOR_WORK.md preserves the supplied HandPilot statement
and separately states that this repository's inspected baseline has zero files.
```

## Verification completed

```text
Native: swift test --package-path macos -> 41 executed, 0 failures, 0 skips
Native release: SIGNAL_BUILD_CONFIGURATION=Release ./scripts/build-macos.sh -> pass
Web: npm test + tsc --noEmit + npm run lint -> build pass, 12/12 tests, typecheck/lint pass
Shared: node scripts/validate-shared-contracts.mjs -> 3 schemas, 4 examples,
        3 seeded mappings, negative version and duplicate tests pass
GitHub Actions: https://github.com/allenbuild/signal/actions/runs/30141064910
                shared 11s, native 47s, web 32s; all pass
Production: landing/download/health/planned/clarification/future-version rejection/
            seeded-profile/API fallback smokes pass over public HTTPS
Artifact ZIP SHA-256: f72bf27e21d25ccec6bd4498aa212183ae27a132c661b0abb85908456677814f
Artifact DMG SHA-256: abf54f45680f896b0d248c7596635b20e3ef22f194a2b85ee0ed7a9d7638781f
Downloaded ZIP checksum: exact match
Bundle launch smoke: process remained alive for 3 seconds; stdout/stderr empty
Signing: ad-hoc; codesign --verify --deep --strict passes; no TeamIdentifier
Notarization/stapling: not performed
Gatekeeper: spctl rejects the ad-hoc build (exit 3); use the documented
            Control-click -> Open per-artifact flow, never disable Gatekeeper
```

## Explicitly unverified or limited

- No human physical matrix has been recorded for camera gestures, Camera or
  Accessibility permission dialogs, sleep/relaunch behavior, or real external
  action effects.
- Production user-created profile links use per-worker memory. A create request
  succeeded, but the immediate read returned 404 after routing to another
  isolate. Only the seeded `SIG1-SGNL2626` profile is durable in version 0.1.0.
- The Anthropic and Discord secrets are not configured. Planning uses the
  labeled deterministic fallback, and Discord uses the labeled local receipt.
- Incognito and a second physical device/network were not observed.
- Rehearsal times and one-command physical recovery remain human checks.

## Judge-facing summary

Signal 0.1.0 ships a native SwiftUI macOS control app with deterministic gesture
engines, safety-gated Quartz output, programmable reviewed actions, profiles,
and a controlled Teach by Demo timeline; automated behavior is verified, while
physical gesture behavior remains explicitly unobserved. The public planner
produces the seeded focus workflow through a labeled deterministic fallback,
and the permanent profile demonstrates its two mappings without exposing
secrets. Judges can inspect the public site, download the immutable release,
and compare its published SHA-256 above.
