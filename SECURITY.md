# Security

Native Signal treats camera observations, gesture candidates, imported JSON,
natural-language drafts, recorded demonstrations, URLs, and browser state as
untrusted.

- Signal starts Paused; Control and Commands are mutually exclusive.
- Emergency Stop, tracking loss, mode change, sleep/lock, termination, and
  runtime failure cancel work and release held input.
- Camera frames and landmarks stay in local memory and are never uploaded.
- Commands use a versioned closed schema and reject unknown versions, secrets,
  private/non-HTTPS URLs, arbitrary shell, executable paths, AppleScript,
  JavaScript, destructive actions, and privilege escalation.
- Seven defaults are immutable. Fist requires review before Test or Save.
- Bolt and Spotify use fixed internal programs with exact origin/tab/control
  checks; there is no generic script execution primitive.
- Teach by Demo starts only after explicit review, redacts secure input, stops
  at 60 seconds, and cannot execute during capture.
- Tests use injected fakes and must not start a camera, prompt TCC, open a
  browser, install login items, create event taps, or post input.
- The native target has no network client, server, localhost bridge, browser
  extension, native messaging host, helper, analytics, or third-party package.

Imported command files remain subject to semantic policy checks after decoding;
schema validity alone is never authorization.
