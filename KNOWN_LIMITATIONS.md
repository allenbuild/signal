# Known limitations

- Physical camera FPS, gesture recognition, cursor motion, click, cross-app
  scroll, and zoom require observation on the exact installed Mac.
- macOS Camera, Accessibility, and Automation grants depend on app identity,
  signature, path, system policy, and user approval.
- An ad-hoc signature is valid for local execution but is not Developer-ID
  distribution, notarization, or a stable TCC identity across rebuilds.
- Zoom shortcuts vary by frontmost application; unsupported apps may use the
  documented fallback or ignore the shortcut.
- Bolt and Spotify automation is fixed to reviewed Chrome origins and page
  structure. UI changes, missing sign-in/playback, permission denial, or
  disabled “JavaScript from Apple Events” fail closed.
- The current Teach by Demo recorder retains reviewed structured events, not
  screen pixels. Generic clicks, typed text, key combos, and waits remain
  visibly unsupported unless they map to the closed executable schema.
- The current constrained natural-language planner is deterministic and local;
  no Anthropic API/Keychain planner is required or included.
- Signal does not control login windows, lock screens, secure fields,
  protected system surfaces, or arbitrary applications through scripts.
- The source checkout contains archived web/extension code, but none of it is
  embedded in or required by `Signal.app`.
