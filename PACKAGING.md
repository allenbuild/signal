# Extension packaging

Signal is packaged as:

- `extension/dist/signal-extension/` — canonical load-unpacked directory.
- `extension/dist/signal-extension.zip` — canonical distributable archive.
- `extension/dist/signal-extension.zip.sha256` — canonical SHA-256 checksum.

Run `cd extension && pnpm package`. The build rejects forbidden manifest
capabilities and production localhost/native references. Copy the ZIP and
checksum to `web/public/downloads/` before saving the public Sites release.
The same artifacts are mirrored under `extension/release/` for compatibility.

The Chrome Web Store is not required for the hackathon release. Installation
uses Chrome Developer mode and **Load unpacked**.

Historical macOS packaging source and release evidence remain in git history and
on `codex/archive-native-web-2026-07-24`; they are not part of the current
product, navigation, CI, or deployment.
