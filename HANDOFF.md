# Signal native handoff

Snapshot: 2026-07-28, America/Chicago.

## Product decision

Signal is one local native macOS menu-bar app based on the verified HandPilot
implementation. Build the root `Signal.xcodeproj` / `Signal` scheme on
`signal-native-local`, package one `Signal.app`, and install the exact build at
`/Applications/Signal.app`. The app has no website, extension, localhost,
native-messaging, helper, or second-app runtime dependency.

The browser-only release remains preserved at tag `signal-web-archive`
(`76cf02c1…`). The historical native/web merge remains preserved at
`archive-native-web-2026-07-24` / commit `7ac287cc…`.

## Native architecture and behavior

- AppKit + SwiftUI menu-bar lifecycle; no normal Dock icon.
- AVFoundation camera and Vision hand-pose processing stay local.
- Hand association, filtering, adaptive freshness, 150 ms hard stale ceiling,
  safe reanchoring, and fail-closed lifecycle behavior come from HandPilot.
- Paused is the startup/default safety mode.
- Control provides relative native pointer, one thumb-index pinch transaction
  for click/scroll/zoom, and application-aware native zoom shortcuts.
- Commands disables Control output and recognizes exactly eight stable poses:
  One, Two, Three, Four, Thumbs Up, Thumbs Down, C, and Fist.
- The fixed catalog opens the exact reviewed URLs; Bolt and Spotify use embedded
  fixed Chrome automation. Fist alone supports local reviewed customization.
- Teach by Demo is an explicit, local structured recorder with a visible
  recording state, 60-second hard stop, secure-input redaction, pre-capture
  review, and review-before-save. The current composition does not capture or
  retain screen pixels, so Screen Recording is not required.
- Emergency Stop is Control–Option–Command–H and synchronously returns to
  Paused, cancels command/recording work, and releases input.

## Build, test, and package

```sh
xcodebuild -project Signal.xcodeproj \
  -scheme Signal \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derivedData \
  build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Signal.xcodeproj \
  -scheme Signal \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derivedData \
  test CODE_SIGNING_ALLOWED=NO

./scripts/build-native-signal.sh
./scripts/package-native-signal.sh
```

Inspect the final `.xcresult`; verify `artifacts/native/Signal.app` and
`artifacts/native/Signal-local.zip` contain no test bundle, website, extension,
server, native messaging host, helper, or second app.

## Permissions and evidence boundary

Camera and Accessibility are required for tracking and system control.
Automation is optional and limited to the embedded Chrome workflows. The
current structured Teach by Demo recorder does not need Screen Recording.

No valid Apple signing identity is guaranteed by source. Use an available
stable Apple Development or Developer ID identity for repeated TCC testing;
otherwise report the local unsigned/ad-hoc state honestly.

Automated tests never prove camera FPS, physical gestures, TCC approval,
external website state, signing stability, or browser automation. Report those
only after direct observation on the exact `/Applications/Signal.app` build.

## Verified release evidence

The final native implementation is
`fc5170931d81a0a0b925c8d2069c3542b55056d2` on
`signal-native-local`.

- Full native suite: 239/239 passed, 0 failed, 0 skipped.
- Signed local Release package: PASS for `arm64`, macOS 13.0 minimum,
  `com.allenxu.Signal`, and `LSUIElement=true`.
- ZIP:
  `9ea0a07b2691cce27bf9ccfdf6c5f777aaa99b5f8c5eafad97ef6f1fa29f60cc`
- DMG:
  `8e24de37faa7e91ecf3154217fd3675f9567a0535e5ba011acc045f25f389678`
- App binary:
  `6c341ab267c4d0db997a716008bec7dc0a35ffab40a8555f1dcbe9d8dfa7e71a`
- Source app, extracted ZIP app, and mounted DMG app passed strict code-sign
  validation; the DMG checksum passed.
- The exact binary is installed and was directly observed running from
  `/Applications/Signal.app` as a non-frontmost menu-bar `UIElement` process.
- The signature is ad hoc with hardened runtime. There is no Team ID, valid
  Apple signing identity, or notarization; Gatekeeper therefore rejects this
  local artifact.

Automated coverage proves the native catalog, exactly-once command gating,
Control input logic, Fist authoring/Test/Save paths, structured Teach by Demo
logic, and synchronous safety shutdown paths. It does not prove physical
camera FPS/landmarks, cursor/click/scroll/zoom, gesture recognition on camera,
external command outcomes, Fist macro execution, a live Teach session, or the
emergency chord during live output. Those remain explicitly **not run** on
this final artifact. See `SUBMISSION.md` for the command-by-command evidence
record, artifact sizes, install steps, and first-run procedure.
