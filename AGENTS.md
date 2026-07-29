# Signal repository guidance

## Current product boundary

- The canonical product is one native Swift/SwiftUI macOS menu-bar application
  built from the root `Signal.xcodeproj` and `Signal` scheme.
- The release branch is `signal-native-local`; install and test the exact copy
  at `/Applications/Signal.app`.
- `extension/**`, `web/**`, `shared/**`, and `macos/**` are archived experiments
  and historical source. They are not runtime, build, packaging, or deployment
  dependencies of the canonical app.
- Preserve the browser release at `signal-web-archive` and the historical merge
  on `codex/archive-native-web-2026-07-24`. Do not rewrite published history.
- Signal must not require localhost, a website, a Chrome extension, native
  messaging, a helper executable, or a second application.

## Native invariants

- Signal launches Paused. Control and Commands are mutually exclusive.
- Control posts real native pointer, click, scroll, and application-aware zoom
  output. Commands disables that output.
- Commands exposes exactly One, Two, Three, Four, Thumbs Up, Thumbs Down, C,
  and Fist. There is no Five command.
- Fist is the only configurable card. All saved/imported actions use the
  closed, validated schema; never add arbitrary shell, executable, AppleScript,
  JavaScript, secret, destructive, or private-URL execution.
- Startup construction and XCTest must not start a camera, prompt for TCC,
  install a login item, open a browser, create an event tap, or emit input.
- Every pause, tracking loss, mode transition, error, sleep/lock, termination,
  and emergency stop must cancel activation and release held input.
- Camera frames and landmarks stay local and are never stored or uploaded.
  Teach by Demo is explicit, local, reviewed, and excludes secure input.

## Evidence and verification

- Never claim a physical camera, gesture, permission, browser action, signing,
  install, or production result unless it was directly observed on the exact
  installed build.
- Build and test the root scheme with macOS arm64 and inspect the `.xcresult`.
- Run `scripts/build-native-signal.sh` and
  `scripts/package-native-signal.sh`; packages may contain only `Signal.app`.
- Verify the bundle identifier, architecture, entitlements, signature, payload,
  archive contents, installed path, startup mode, and `git diff --check`.
