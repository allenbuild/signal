# Signal

Signal is a native macOS menu-bar application for local camera hand tracking,
system pointer control, and programmable gesture commands. The canonical
product is `Signal.app`, built from the root `Signal.xcodeproj` with the shared
`Signal` scheme.

Signal supports macOS 13 or later on Apple Silicon (`arm64`). It does not
require a website, browser extension, server, localhost process, native
messaging host, or helper application.

## Modes

Signal starts in **Paused** and never restores output merely because it
launched.

- **Paused** blocks pointer and command output and releases input owned by
  Signal. Opening Calibration may run the camera for local observation without
  enabling output.
- **Control** uses one reliable tracked hand for relative system-pointer
  movement. A thumb–index pinch transaction provides one quick-release click,
  held vertical scroll, or held horizontal application zoom. Programmable
  commands are disabled.
- **Commands** disables and releases Control output, then recognizes One, Two,
  Three, Four, Thumbs Up, Thumbs Down, C, and Fist. A stable hold shows
  progress, fires once, and requires release or pose change before rearming.

There is no Five command in the native command catalog.

Tracking loss, permission loss, camera interruption, sleep, session
deactivation, display changes, mode changes, and Emergency Stop reset or
quiesce the relevant runtime state. Emergency Stop is available from the menu
bar and through Control–Option–Command–H when the monitor is available.

## Commands

The command document is a closed, versioned JSON schema. The seven preset
commands are fixed; only Fist is configurable. Runtime actions are limited to:

- opening a policy-approved public HTTPS URL;
- submitting one reviewed built-in prompt to Bolt; and
- advancing Spotify Web by one verified track.

Signal does not accept shell commands, arbitrary AppleScript or JavaScript,
arbitrary selectors, executable paths, inline secrets, localhost targets, IP
literals, or unsafe URL schemes. Bolt and Spotify automation use fixed programs
embedded in `Signal.app`, exact HTTPS origins, and fail-closed target checks.

The Fist editor requires review before save. Teach by Demo currently produces
structured proposals; unsupported generic clicks, text entry, key combinations,
and waits cannot enter the closed runtime schema.

## Privacy

Camera frames are processed locally in memory with AVFoundation and Vision.
Frames and landmarks are not saved, uploaded, or sent to an analytics service.
Signal contains no direct network client. Typed commands can deliberately open
external HTTPS pages, and the reviewed Bolt and Spotify actions direct Google
Chrome to communicate with those services.

Settings and the validated command document persist locally. See
[Privacy](PRIVACY.md) for the exact data and permission boundaries.

## Build and install

Use the full Xcode application and its command-line tools:

```sh
./scripts/build-native-signal.sh
./scripts/package-native-signal.sh
```

The guarded outputs are:

```text
artifacts/native/Signal.app
artifacts/native/Signal-local.zip
artifacts/native/Signal-local.dmg  # optional
```

See [Native installation](NATIVE_INSTALLATION.md) for dry runs, signing,
packaging, and the stable `/Applications/Signal.app` install path. The scripts
do not notarize, staple, upload, or establish that the app launched
successfully on another Mac.

## Documentation

- [Architecture](ARCHITECTURE.md)
- [Privacy](PRIVACY.md)
- [Native installation](NATIVE_INSTALLATION.md)
- [Gesture guide](GESTURE_GUIDE.md)
- [Automation limitations](AUTOMATION_LIMITATIONS.md)
- [Native troubleshooting](TROUBLESHOOTING_NATIVE.md)

## Archived source

`extension/`, `web/`, `shared/`, and the older `macos/` implementation remain
only as repository history. They are not linked into `Signal.app`, are not
packaged, and are not an alternate runtime or installation path for the
canonical product.

## Evidence boundary

Compilation, unit tests, ZIP/DMG creation, or code inspection do not prove
physical-camera behavior, gesture accuracy, Accessibility or Automation
approval, target-site compatibility, signing identity, notarization,
Gatekeeper acceptance, or installation on a particular Mac. Record those
outcomes only after observing the exact build and machine.
