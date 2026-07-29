# Native Signal installation

The macOS application built from the root `Signal.xcodeproj` and `Signal`
scheme is the canonical Signal product. The website, browser extension,
server, historical `macos/` source, and any helper are not part of the native
application or its package.

Signal supports macOS 13 or later on Apple Silicon (`arm64`). Building requires
the full Xcode application and its command-line tools.

## Build and package

From the repository root:

```sh
./scripts/build-native-signal.sh
./scripts/package-native-signal.sh
```

Both scripts use:

- `Signal.xcodeproj` at the repository root;
- the shared `Signal` scheme;
- the macOS generic destination and `arm64` architecture;
- `.derivedData/` at the repository root; and
- `artifacts/native/` as the fixed, guarded output directory.

To validate paths, arguments, tools, and the exact planned outputs without
running Xcode or writing any file:

```sh
SIGNAL_DRY_RUN=YES ./scripts/build-native-signal.sh
SIGNAL_DRY_RUN=YES ./scripts/package-native-signal.sh
SIGNAL_DRY_RUN=YES SIGNAL_CREATE_DMG=YES \
  ./scripts/package-native-signal.sh
```

The scripts accept only `YES` or `NO` for `SIGNAL_DRY_RUN`,
`CODE_SIGNING_ALLOWED`, and `SIGNAL_CREATE_DMG`. A dry run performs preflight
validation but does not prove that compilation or packaging will succeed.

The build script produces exactly the canonical app at:

```text
artifacts/native/Signal.app
```

The package script rebuilds that app and produces:

```text
artifacts/native/Signal.app
artifacts/native/Signal-local.zip
```

To also create `artifacts/native/Signal-local.dmg`:

```sh
SIGNAL_CREATE_DMG=YES ./scripts/package-native-signal.sh
```

The DMG is optional. Running the packager later with
`SIGNAL_CREATE_DMG=NO` removes a stale local DMG so the directory reflects the
requested output.

Output paths and payload membership are deterministic: the packager always
rebuilds from the root project, stages fixed names, verifies the ZIP by
extracting it, and rejects anything except the root `Signal.app` before
publishing the archive.
ZIP/DMG bytes are not promised to be reproducible across Xcode versions,
signatures, build timestamps, or host systems.

### Build without or with code signing

Local builds default to `CODE_SIGNING_ALLOWED=NO`. To ask Xcode to sign with a
keychain identity:

```sh
CODE_SIGNING_ALLOWED=YES \
SIGNAL_SIGN_IDENTITY='Developer ID Application: Example Name (TEAMID)' \
./scripts/package-native-signal.sh
```

`SIGNAL_SIGN_IDENTITY` is passed to the root Xcode build; the packaging step
does not re-sign or modify the built bundle. The scripts do not notarize,
staple, upload, or assert that an identity is suitable for distribution.
`CODE_SIGNING_ALLOWED=NO` is for a known local development checkout, not for
shipping the resulting archive to other users.

## Install at one stable path

Use `/Applications/Signal.app` for normal operation. macOS privacy decisions
are tied to an app's identity and can also be affected by its location and
signature. Repeatedly launching copies from Derived Data, Downloads, or
different build folders can create confusing permission entries.

1. Quit every running copy of Signal.
2. If `/Applications/Signal.app` already exists, move that existing app to the
   Trash in Finder. Do not merge a new bundle into it.
3. Copy `artifacts/native/Signal.app` to the top level of `/Applications`.
4. Launch `/Applications/Signal.app` from Finder.
5. Keep using that path for later launches.

For a local build that macOS identifies as coming from an unverified developer,
Control-click the app in Finder and choose **Open** only after verifying that
it is the build you produced from the intended checkout. Do not disable
Gatekeeper globally. Do not use this workaround as a distribution strategy.
Distribution outside the development machine requires an appropriate
Developer ID signature and the normal Apple notarization workflow; these
scripts do not perform that workflow.

## First launch and permissions

Signal starts in **Paused** mode. It does not begin pointer output or command
execution merely because the app launched.

Grant only the permissions required for the feature you intend to use:

- **Camera** — required for local hand-landmark and gesture recognition.
- **Accessibility** — required for posting native pointer, click, scroll, and
  zoom input.
- **Automation** — optional and target-specific. The current native build uses
  it only for the reviewed Chrome-based Bolt and Spotify Web actions.
- **Screen Recording** — not required by this build. Teach by Demo records
  reviewed structured events and Accessibility metadata; it does not capture
  or retain screen pixels.

Camera and Accessibility are the core native permissions. Optional permissions
may never appear in System Settings if no enabled workflow requests them.

After the core permissions show as granted, open Signal from its menu-bar hand
icon, use Calibration to check framing, then deliberately choose **Control** or
**Commands**. Use **Paused** whenever output is not wanted.

## Canonical command catalog

Commands mode has exactly eight command cards, in this fixed order:

1. One — Rickroll
2. Two — New Gmail
3. Three — Cursor Agents
4. Four — New Google Doc
5. Thumbs Up — Build with Bolt
6. Thumbs Down — Next Spotify Track
7. C — Anthropic on X
8. Fist — Custom Command

There is no command named **Five**, and Five must not be displayed or
registered as a command.

## Evidence boundary

Building, type-checking, unit testing, creating a ZIP, or creating a DMG does
not prove that a physical camera, permissions, gestures, target applications,
code signing, notarization, or installation worked on a particular Mac.
Record those results only after observing them on the actual machine and build.
macOS TCC decisions can change when the app's signature, code requirement,
bundle contents, or installation identity changes; a stable path alone cannot
guarantee that permissions carry across rebuilds.
