# Native Signal packaging

The canonical outputs are:

```text
artifacts/native/Signal.app
artifacts/native/Signal-local.zip
artifacts/native/Signal-local.dmg  # optional
```

Build and package from the repository root:

```sh
./scripts/build-native-signal.sh
SIGNAL_CREATE_DMG=YES ./scripts/package-native-signal.sh
```

For a local ad-hoc hardened-runtime signature when no Apple identity is
installed:

```sh
CODE_SIGNING_ALLOWED=YES \
SIGNAL_SIGN_IDENTITY='-' \
SIGNAL_CREATE_DMG=YES \
./scripts/package-native-signal.sh
```

The scripts validate `com.allenxu.Signal`, arm64, package membership, and reject
nested apps, extensions, XPC services, XCTest payload, websites, servers, and
helpers. The ZIP and DMG contain one application. Packaging does not prove
notarization, permission grants, launch behavior, or physical gestures.

See [Native installation](NATIVE_INSTALLATION.md) for the stable install path
and first-run permission flow.
