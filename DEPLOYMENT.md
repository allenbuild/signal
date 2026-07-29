# Native Signal distribution

The canonical Signal product has no website or server dependency or deployment
step. Its release is the local native app built from the root
`Signal.xcodeproj`.

## Release flow

1. Run the root arm64 build and full XCTest suite.
2. Run `SIGNAL_CREATE_DMG=YES ./scripts/package-native-signal.sh`.
3. Verify bundle ID, architecture, entitlements, signature, and payload.
4. Verify the ZIP and DMG each recover one `Signal.app`.
5. Copy the app to `/Applications/Signal.app`.
6. Launch that exact path and grant Camera and Accessibility only to it.
7. Record physical behavior separately from automated evidence.
8. Commit and push the exact verified source and publish only artifacts built
   from that commit.

The current machine may use an ad-hoc “Sign to Run Locally” signature. Public
distribution requires an installed Developer ID identity, hardened-runtime
signature, notarization, and stapling. Never disable Gatekeeper globally.

The Sites project and Chrome extension remain historical, noncanonical release
records. They are not linked from, packaged with, or required by native Signal.
Their present hosting or store availability is outside this native release
claim; this document does not assert that either is online or offline.
