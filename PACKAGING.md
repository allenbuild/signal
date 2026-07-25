# Native packaging

This document defines release gates and records the automated evidence for the
published version 0.1.0 artifacts. It does not turn automated evidence into a
claim of physical gesture, permission, notarization, or Gatekeeper success.

## Release identity

Record the final product name `Signal`, semantic version/build number, bundle
identifier, minimum macOS version, integration commit, signing identity class,
entitlements, and API production origin. About must show version and commit.

The exact artifact used for physical verification is the artifact uploaded and
linked publicly. Do not rebuild between verification and checksum/upload.

## Procedure

1. Clean and run the full test suite with production side effects disabled in
   XCTest.
2. Archive a Release build with a stable signing identity when available.
3. Export and inspect the `.app`: bundle ID, version, executable, entitlements,
   signing chain, hardened runtime if applicable, and production HTTPS origin.
4. Confirm no localhost/private host, secret, debug entitlement, raw recording
   fixture, or development path appears in the bundle.
5. Launch the exported app, verify Camera and Accessibility identity against
   that exact bundle, relaunch, and run the physical matrix.
6. Create a ZIP preserving the bundle. Create a DMG only if it is reliable
   within the timebox.
7. Compute SHA-256 for every published artifact.
8. If Developer ID and credentials exist, notarize and staple, then validate
   Gatekeeper. If only Apple Development signing exists, state that. If
   unsigned/ad hoc, document honest Gatekeeper steps and limitations.
9. Upload immutable assets to the public release, download again, compare
   checksum, and repeat launch/setup smoke.

## Evidence template

```text
Release commit:
Version/build:
Bundle identifier:
Minimum macOS:
Archive/export commands and result:
Test command/count/failures/skips:
Signing identity class:
codesign verification:
Notarization/stapling:
Gatekeeper assessment:
.app path:
.zip URL / SHA-256:
.dmg URL / SHA-256 (or omitted):
Downloaded checksum:
Physical-verification artifact match:
Recovery/install instructions:
```

Never recommend disabling Gatekeeper globally. Prefer a properly signed build;
for an unsigned fallback, document the narrow per-artifact user action and
clearly label the limitation.

## Version 0.1.0 evidence

```text
Release commit: 4dce63912e6804a813f38159aa610e8e78f25829
Version/build: 0.1.0 (1)
Bundle/minimum/architecture: app.signal.hand / macOS 13.0 / arm64
Packaging: SIGNAL_ADHOC_SIGN=1 SIGNAL_CREATE_DMG=1 ./scripts/package-macos.sh
Tests: 41 executed, 0 failures, 0 skips
Signing: ad-hoc; codesign deep/strict verification passed; no TeamIdentifier
Notarization/stapling: not performed
Gatekeeper: spctl rejected the ad-hoc build (exit 3)
ZIP: https://github.com/allenbuild/signal/releases/download/v0.1.0/Signal-0.1.0-macOS.zip
ZIP SHA-256: f72bf27e21d25ccec6bd4498aa212183ae27a132c661b0abb85908456677814f
DMG: https://github.com/allenbuild/signal/releases/download/v0.1.0/Signal-0.1.0-macOS.dmg
DMG SHA-256: abf54f45680f896b0d248c7596635b20e3ef22f194a2b85ee0ed7a9d7638781f
Downloaded ZIP checksum: matched
Launch smoke: alive after 3 seconds; stdout/stderr empty
Physical artifact verification: not performed
```

Recovery/install instructions are deliberately narrow: download the ZIP, move
Signal to Applications, then Control-click Signal and choose Open if macOS
blocks the first launch. Do not disable Gatekeeper or remove quarantine
globally.
