# Native packaging

This document defines release gates. It does not state that an artifact,
signature, notarization, or physical test currently exists.

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
