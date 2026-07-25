# Signal extension 0.2.3

- Uses a visible, one-time camera setup page so Chrome cannot strand Signal in
  an unresolved hidden permission request.
- Automatically starts tracking after permission is granted and closes the
  setup tab.
- Times out camera permission and MediaPipe initialization with a recoverable
  error instead of displaying `STARTING` forever.

- Drives offscreen MediaPipe inference with a reliable bounded timer because
  Chrome can throttle video-frame callbacks in hidden extension documents.
- Fails the built-extension smoke test unless the synthetic camera produces a
  positive processed-frame rate.

- Keeps tracking frames synchronized with Chrome's real active tab even when
  tab-activation events arrive out of order.
- Allows command gestures to open their configured tabs from protected Chrome
  pages while continuing to block page-level cursor injection there.

- Manifest V3 side-panel product for Chrome on macOS, Windows, and Linux.
- One offscreen, local-only camera and self-hosted MediaPipe runtime.
- Active-tab routing with navigation, tab-change, hand-loss, pause, stop, and
  service-worker-restart resets.
- Shadow DOM virtual cursor plus pinch click, nested scroll, and real Chrome tab
  zoom.
- Eight active command poses with stable hold, progress, one-shot firing,
  cooldown, and release/change rearm. Five is not registered or displayed.
- Exact Rickroll, Gmail compose, Cursor Agents, Google Doc, Bolt, Spotify Web,
  Anthropic-on-X, and configurable Fist mappings.
- Editable Fist command, natural-language planner, semantic Teach by Demo,
  profiles, tuning, import, and export.
- Strict schema and URL validation rejecting native, shell, script, credential,
  password, inline-secret, and future-schema inputs.
- Packaged ZIP, unpacked directory, SHA-256 checksum, deterministic unit tests,
  and a built-extension Chromium smoke.

The Chrome Web Store is not required for this release. Install with Chrome
Developer mode and **Load unpacked**.
