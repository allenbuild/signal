# Native Signal release record

## Product

Signal is one local native macOS menu-bar application for private Vision hand
tracking, real system cursor/click/scroll/application-aware zoom control, eight
programmable command poses, reviewed Fist authoring, and local Teach by Demo.

Canonical installation: `/Applications/Signal.app`

Archived browser release: tag `signal-web-archive`

## Evidence boundary

- `night-hack-start` points to an empty tagged repository; `PRIOR_WORK.md`
  separately discloses the HandPilot foundation.
- Browser/native historical releases remain preserved and are not runtime
  dependencies of this native app.
- Automated tests and package inspection do not count as physical camera,
  gesture, browser-service, permission, signing-stability, or notarization
  results.

## Final evidence

Recorded 2026-07-28 in America/Chicago.

### Source and architecture

- Repository: `/Users/allenxu/Desktop/signal/signal`
- Final source branch: `signal-native-local`
- Native implementation commit:
  `61031af6255997b6caa14e50922d4fdb86dfb0a2`
- Product: the root `Signal.xcodeproj` / `Signal` scheme only.
- Runtime: one AppKit + SwiftUI `LSUIElement` menu-bar app using Apple
  AVFoundation, Vision, Accessibility, Core Graphics, and AppKit APIs.
- Principal native modules: `Signal/App`, `Signal/Gestures`, `Signal/Input`,
  `Signal/Commands`, `Signal/Automation`, `Signal/CustomCommands`, and
  `Signal/Permissions`.
- Historical `web/`, `extension/`, and `macos/` source remains in Git history
  but is not referenced by the native target and is not in the application,
  ZIP, or DMG payload.

### Build, tests, and artifacts

Signed local Release package command:

```sh
CODE_SIGNING_ALLOWED=YES \
SIGNAL_SIGN_IDENTITY='-' \
SIGNAL_CREATE_DMG=YES \
./scripts/package-native-signal.sh
```

Result: **PASS**. Xcode built the Release app for `arm64`; strict bundle,
archive, signature, entitlement, and DMG validation passed.

Full test command:

```sh
xcodebuild test \
  -project Signal.xcodeproj \
  -scheme Signal \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/signal-ci-fix.WhKThG/DerivedData \
  -resultBundlePath /tmp/signal-ci-fix.WhKThG/SignalCIFix.xcresult \
  CODE_SIGNING_ALLOWED=NO
```

Result: **239 executed, 239 passed, 0 failed, 0 skipped**, with result bundle
at `/tmp/signal-ci-fix.WhKThG/SignalCIFix.xcresult`. A separate
fresh CI-parity run also passed 239/239.

Final local artifacts:

| Artifact | Size | SHA-256 |
| --- | ---: | --- |
| `artifacts/native/Signal-local.zip` | 1,254,828 bytes | `ad05b6cee3c7fbb4fdc7642abbc1f853cee1d80208ab6e6779fe2232d705b245` |
| `artifacts/native/Signal-local.dmg` | 1,739,651 bytes | `7f017226b5e1b5c4b04894e319036bd26819caa9a730398610c8048c9a10ecda` |
| `artifacts/native/Signal.app/Contents/MacOS/Signal` | 4,923,648 bytes | `6c341ab267c4d0db997a716008bec7dc0a35ffab40a8555f1dcbe9d8dfa7e71a` |

The source app, extracted ZIP app, and mounted DMG app passed strict code
signature validation. The DMG checksum is valid. Each package contains one
`Signal.app` and no website, extension, server, native-messaging host, helper,
XPC service, second app, or test bundle.

Verified bundle metadata:

- Bundle ID: `com.allenxu.Signal`
- Architecture: `arm64`
- Minimum macOS: `13.0`
- `LSUIElement`: `true`
- Entitlements: Camera and Apple Events Automation only
- Signature: ad hoc, hardened runtime, no Team ID
- Valid Apple code-signing identities on this Mac: `0`
- Notarization: not performed
- Gatekeeper assessment: rejected with exit 3, as expected for this ad-hoc,
  unnotarized local build

### Installation and first run

The exact packaged binary is installed at
`/Applications/Signal.app/Contents/MacOS/Signal`; its SHA-256 matches the
artifact binary above. The installed application was directly observed
running as PID 25712 from that exact path. Launch Services reported bundle ID
`com.allenxu.Signal` and application type `UIElement`; the process remained
alive and did not become frontmost or create a normal application window.

Exact installation:

1. Quit every running Signal process.
2. Drag `Signal.app` from `Signal-local.dmg` to `/Applications`, replacing the
   old bundle as one unit, or copy `artifacts/native/Signal.app` there.
3. Control-click `/Applications/Signal.app` and choose **Open** for this known
   local ad-hoc build. Do not disable Gatekeeper globally.
4. Keep launching the app from `/Applications/Signal.app`.

Exact first run:

1. Open Signal from its menu-bar icon; startup mode is Paused by source and
   automated lifecycle tests.
2. Grant Camera and Accessibility in System Settings when requested.
3. Grant optional Chrome Automation only if using the Bolt or Spotify fixed
   commands. Screen Recording is not required by the pixel-free structured
   recorder.
4. Relaunch Signal if macOS requests it after a permission change.
5. Open Calibration to check framing, then deliberately select Control or
   Commands. Use Control–Option–Command–H or Paused to stop output.

### Capability results and observation boundary

The following results are deliberately split between automated evidence and
physical observation:

- Camera / FPS / landmarks — the AVFoundation/Vision pipeline and its
  lifecycle tests pass; **physical camera FPS and landmark output were not
  observed on this final build**.
- Pointer / click / scroll / application-aware zoom — geometry, gesture,
  input, stale-frame, and coordinator tests pass; **physical output was not
  observed on this final build**.
- One — fixed Rickroll URL and exactly-once activation tests pass; **external
  navigation was not physically run**.
- Two — fixed Gmail compose URL to `allenjxu07@gmail.com` and exactly-once
  activation tests pass; **external navigation was not physically run**.
- Three — fixed `https://cursor.com/agents` URL and exactly-once activation
  tests pass; **external navigation was not physically run**.
- Four — fixed `https://doc.new` URL and exactly-once activation tests pass;
  **external navigation was not physically run**.
- Thumbs Up — fixed Bolt prompt
  `i want to build a website for my hand signal app`, unique-field
  verification, exactly one Enter, cancellation, and fail-closed tests pass;
  **the Chrome/Bolt workflow was not physically run**.
- Thumbs Down — exactly one Spotify Next, optional one Play only when paused,
  changed-track verification, cancellation, and fail-closed tests pass;
  **the Chrome/Spotify workflow was not physically run**.
- C — fixed `https://x.com/AnthropicAI?lang=en` URL and exactly-once
  activation tests pass; **external navigation was not physically run**.
- Fist — import/export, constrained authoring, review, Test-without-save,
  save, validation, cancellation, and execution-path tests pass; **a physical
  Fist gesture and external macro execution were not run**.
- Teach by Demo — explicit capture, 60-second cutoff, secure-field redaction,
  review/reorder/delete, validation, and cancellation tests pass; **a physical
  recording session was not run**.
- Emergency Stop — menu and global shortcut integration, synchronous
  quiescence, input release, command cancellation, recorder cancellation, and
  health-revocation tests pass; **the physical keyboard chord during live
  motion or a live command was not run**.

### Known release limits

- A stable Apple Development or Developer ID identity and notarization are
  still required for distribution and repeatable TCC identity. This Mac has
  no valid signing identity, so that requirement could not be completed.
- Chrome Automation depends on Chrome, target-page structure, sign-in state,
  network access, and Bolt/Spotify service behavior. It fails closed when its
  reviewed preconditions cannot be verified.
- Physical camera, gesture, Accessibility/TCC, browser-service, and emergency
  scenarios above remain required before claiming field validation or a full
  production Definition of Done.
