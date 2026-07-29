# Troubleshooting native Signal

These steps apply to the canonical macOS app built from the root
`Signal.xcodeproj` and installed as `/Applications/Signal.app`. They do not
apply to the historical `macos/` source, website, browser extension, server, or
any helper.

Signal starts **Paused**. A quiet app immediately after launch is expected;
choose Control or Commands only after checking status and permissions.

## The build script stops before Xcode runs

- Run the script from a complete repository checkout. The required project is
  `Signal.xcodeproj` at the repository root and the required scheme is
  `Signal`.
- Install the full Xcode application, then select it in Xcode Settings or with
  `xcode-select`.
- Build on macOS. The script intentionally targets macOS `arm64`.
- Do not replace `.derivedData` or `artifacts/native` with symlinks. The scripts
  refuse symlinked or ambiguous output paths.
- Remove or relocate unexpected files from `artifacts/native`. That directory
  is reserved for `Signal.app`, `Signal-local.zip`, and the optional
  `Signal-local.dmg`.

Run a non-mutating preflight when diagnosing path, tool, or environment
validation:

```sh
SIGNAL_DRY_RUN=YES ./scripts/build-native-signal.sh
SIGNAL_DRY_RUN=YES ./scripts/package-native-signal.sh
```

Dry-run success does not compile the app and is not build evidence.

For a fresh derived-data build, quit Xcode and Signal, move the repository's
`.derivedData` directory to the Trash in Finder, then rerun:

```sh
./scripts/build-native-signal.sh
```

## Code signing fails

Unsigned local builds are the default:

```sh
CODE_SIGNING_ALLOWED=NO ./scripts/package-native-signal.sh
```

For an identity already present in the login keychain:

```sh
CODE_SIGNING_ALLOWED=YES \
SIGNAL_SIGN_IDENTITY='Developer ID Application: Example Name (TEAMID)' \
./scripts/package-native-signal.sh
```

Check available identities with:

```sh
security find-identity -v -p codesigning
```

The packaging script does not notarize or staple. A successful archive is not
proof that signing, notarization, or Gatekeeper acceptance will succeed on
another Mac.

## Signal has no Dock window

Signal is a menu-bar application. Look for its hand icon in the macOS menu bar,
then choose **Open Signal…**, **Practice & Gesture Guide…**, or **Open
Settings…**. If no icon appears, verify that only
`/Applications/Signal.app` is running and relaunch it from Finder.

## Camera is unavailable

1. Stay Paused.
2. Open **System Settings → Privacy & Security → Camera**.
3. Enable Signal for the copy at `/Applications/Signal.app`.
4. Quit and relaunch Signal if macOS requests it.
5. Close other software that may exclusively hold the camera.
6. Open Calibration and use **Retry Camera**.

If Signal is absent from the Camera list, use its in-app grant action first.
Device-management policy can restrict access and cannot be bypassed by Signal.
Camera frames are intended to be processed locally in memory; Screen Recording
permission is not a substitute for Camera permission.

## Pointer, click, scroll, or zoom does nothing

1. Confirm Signal is in **Control**, not Paused or Commands.
2. Open **System Settings → Privacy & Security → Accessibility** and enable the
   installed `/Applications/Signal.app`.
3. If an older or differently located Signal entry exists, remove the stale
   entry, add the stable installed app again, and relaunch.
4. Verify that the frontmost application accepts ordinary pointer or zoom
   input and that no secure-input surface or system authorization dialog is
   active.
5. Use Calibration to inspect tracking confidence and the current zoom profile.

Accessibility is required for native input. Optional Automation or Screen
Recording permission does not replace it.

## A command does not activate

Confirm Commands mode and use one of the exact eight poses:

1. One — Rickroll
2. Two — New Gmail
3. Three — Cursor Agents
4. Four — New Google Doc
5. Thumbs Up — Build with Bolt
6. Thumbs Down — Next Spotify Track
7. C — Anthropic on X
8. Fist — Custom Command

There is no Five command.

Hold the pose steadily for about 0.60 seconds by default. After it fires,
release or change the pose, then allow the default 0.90-second cooldown before
trying again. Remaining in the same pose intentionally waits for release
instead of repeatedly firing.

If the command activates but the external result does not occur, check network
access, the default browser, target-app availability, sign-in state, and the
limitations in `AUTOMATION_LIMITATIONS.md`. A visible activation result does
not prove an external service accepted the action.

## Automation or Screen Recording is absent

That can be correct. Camera and Accessibility are the core permissions.
Automation is optional and appears per target app when a feature actually
attempts Apple Events. Screen Recording is not required by this build because
Teach by Demo retains reviewed structured events rather than screen pixels.
Do not grant optional permissions merely to troubleshoot camera recognition.

When a target-specific Automation permission was denied, open **System
Settings → Privacy & Security → Automation**, inspect Signal's target, and
retry only the reviewed workflow. Signal cannot approve the setting itself.

The current Automation target is Google Chrome for the reviewed Bolt and
Spotify Web commands. Confirm Chrome is installed. Chrome may require
**View → Developer → Allow JavaScript from Apple Events**; Signal cannot turn
that setting on. The expected HTTPS tab must already be available, and Signal
fails closed if it cannot verify one unambiguous target field or control.

## The installed build keeps asking for permission

- Quit every Signal copy and run only `/Applications/Signal.app`.
- Avoid launching the Derived Data or unzipped Downloads copy.
- Keep the signing identity consistent between replacements.
- Replace the entire app bundle rather than copying files into an existing
  bundle.
- If macOS retains a stale privacy entry, remove that entry in System Settings,
  relaunch the stable app, and use the in-app permission action again.

Changing path, bundle contents, or signing identity can make macOS treat a
replacement as a different code requirement. Even at the same path and with
the same bundle identifier, an unsigned or differently signed rebuild may not
inherit prior TCC decisions.

## Packaging fails or includes the wrong product

The packager accepts only `artifacts/native/Signal.app` with bundle identifier
`com.allenxu.Signal` and an `arm64` Signal executable. It rejects nested apps,
app extensions, XPC services, and payload names associated with a website,
browser extension, server, or helper. It re-extracts and revalidates the ZIP,
and verifies an optional DMG with `hdiutil`. It creates:

```text
artifacts/native/Signal.app
artifacts/native/Signal-local.zip
```

Set `SIGNAL_CREATE_DMG=YES` only when a local DMG is wanted. The ZIP and DMG
are packaging artifacts, not physical launch or gesture tests.

## Stop or recover from unexpected output

Press Control–Option–Command–H or choose **Emergency Stop** from the Signal
menu. Then:

1. verify the status is Paused or emergency-stopped;
2. move the hand out of frame;
3. close any sensitive target surface;
4. review permissions and activity; and
5. resume only with an explicit mode selection.

Do not report a physical camera, gesture, permission, target-app, signing,
notarization, or installation result unless it was directly observed with the
specific app build and Mac.
