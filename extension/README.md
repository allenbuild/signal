# Signal Chrome extension

Signal is a Manifest V3 Chrome extension that turns local hand landmarks into
controls for ordinary HTTP and HTTPS websites. It does not install a native
application, run localhost software, move the operating-system pointer, or
upload camera frames.

## Install the packaged build

1. Expand `signal-extension.zip`.
2. Open `chrome://extensions` in current desktop Chrome.
3. Enable **Developer mode**.
4. Choose **Load unpacked** and select the expanded `signal-extension` folder.
5. Open Signal from the toolbar to show its side panel.
6. Choose **Start Signal** and approve the one-time camera request.
7. Switch to an ordinary website. Point to move the virtual cursor, quick-pinch
   to click, hold and move vertically to scroll, or hold and move horizontally
   to change real tab zoom.

Chrome protects internal pages, the Web Store, settings, extension management,
permission prompts, DevTools, and operating-system UI from content scripts.
Signal reports these pages visibly and resumes on a supported tab.

## Build and verify

```sh
pnpm install --frozen-lockfile
pnpm lint
pnpm test
pnpm typecheck
pnpm package
pnpm test:browser
```

`pnpm test:browser` launches the built unpacked extension in Chromium and
verifies service-worker startup, content injection, overlay singleton behavior,
navigation reset, side-panel messaging, and a safe page action.
