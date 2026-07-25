# Privacy

- Camera capture begins only after the user clicks Start Signal.
- Camera frames and hand landmarks used for gesture recognition stay in the
  extension offscreen document and are not uploaded or stored.
- Stop, pause, teardown, and capture failure close tracks and clear live state.
- Teach by Demo is a separate explicit workflow that captures reviewed browser
  actions—not video, camera frames, passwords, or sensitive field values.
- Draft commands and profiles remain in `chrome.storage.local` until exported or
  published.
- Public profiles are unlisted and redacted. They contain secret references,
  never secret values.
- Planner text is sent only when Generate is chosen. Browser commands are
  previewed and validated before save or execution.
- Approved protected Discord or Claude workflow inputs are sent only to the
  typed public Signal endpoint selected by a stored configuration reference;
  live camera frames and landmarks are never included.
