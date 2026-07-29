# Signal privacy

This policy describes the canonical native macOS `Signal.app` built from the
root `Signal.xcodeproj`.

## Camera and hand tracking

- Camera access is requested only through an explicit user action.
- Camera capture runs only when demanded by Control, Commands, or the visible
  Calibration experience.
- AVFoundation frames are passed to Apple's Vision hand-pose request and
  processed locally in memory.
- Camera frames, hand landmarks, gesture metrics, and the camera preview are
  not written to disk, uploaded, or sent to a server.
- Stop, permission loss, camera failure, interruption, and teardown stop or
  invalidate capture and clear current tracking state.
- Live diagnostics such as confidence, frame rate, dropped-frame count, and
  latency are local operational values. They are displayed in the app and are
  not analytics.

The native target contains no upload, analytics, advertising, account, remote
logging, crash-reporting, socket, or `URLSession` client.

## macOS permissions

Signal cannot grant or repair its own macOS privacy permissions.

- **Camera** is required for hand tracking and gesture recognition.
- **Accessibility** is required for native pointer, click, scroll, and zoom
  output. It is also relevant to global input monitoring and reviewed
  accessibility context used by local Teach by Demo components.
- **Automation** is optional and requested only for Google Chrome when the user
  enables the reviewed Bolt or Spotify Web actions. Approval for Chrome does
  not approve another application.
- **Screen Recording** is not required by this build. The production Teach by
  Demo authoring surface records reviewed structured proposals and does not
  capture or retain screen pixels.

Permission prompts are not issued during object construction. Camera,
Accessibility, and Automation requests are tied to visible user actions.
Device-management policy may still deny access.

macOS TCC decisions depend on the app's code requirement and other system
state. Keeping `/Applications/Signal.app` as the stable path helps avoid
duplicate entries, but the same path and bundle identifier do not guarantee
that permissions survive an unsigned or differently signed rebuild.

## Local persistence

Signal stores only local configuration needed by the native application:

- the validated command catalog at
  `~/Library/Application Support/Signal/Commands/active-v1.json`;
- gesture tuning, zoom profiles, and the screen-zoom preference in
  `UserDefaults` under `Signal.settings.v1`; and
- a local flag recording whether the optional Chrome Automation request was
  attempted.

Command saves and exports use atomic, sorted JSON after closed-schema
validation. Imports are limited to regular non-symbolic-link files of at most
1 MiB. The runtime activity list and live tracking diagnostics are in memory
and are not a durable history.

Signal does not store camera video, landmark recordings, passwords, API keys,
browser cookies, or external-service credentials. The command schema rejects
inline secrets and has no generic secret field or keychain integration.

## Teach by Demo

Teach by Demo is proposal authoring, not automatic execution:

- capture must be explicitly started;
- capture is visibly active and bounded to the selected 30- or 60-second limit;
- only structured proposals are retained in memory for review;
- screen pixels and camera frames are never captured by the recorder;
- secure fields and secure-input events are omitted and counted as
  redactions;
- secret-like or prohibited text is rejected;
- every proposal must be reviewed, and proposals can be reordered or deleted,
  before one is applied; and
- proposals outside the current runtime schema remain visibly unsupported and
  cannot be saved as executable steps.

The production Fist editor is wired to the bounded local event/Accessibility
recorder. The current closed runtime can save a reviewed public HTTPS proposal.
Generic accessibility clicks, typed text, key combinations, and waits are not
currently executable command actions.

## External effects and network disclosure

Signal itself does not upload data or call a Signal server. A user-approved
command can nevertheless cause another application to use the network:

- an `open_url` action opens a validated public HTTPS URL in the user's default
  browser without browser automation;
- the built-in Bolt action opens `https://bolt.new/` and submits the fixed,
  reviewed Signal prompt through Chrome automation; and
- the Spotify action opens `https://open.spotify.com/`, invokes one verified
  next-track control, and checks that the track identity changed.

Those websites receive ordinary browser traffic under their own privacy
policies. Signal does not attach camera frames, landmarks, settings, or the
command document. If Bolt automation fails, Signal may place only the fixed
reviewed Bolt prompt on the system clipboard for manual paste; other
applications with clipboard access may observe it.

## No bundled web runtime

`Signal.app` contains no website, browser extension, server, localhost bridge,
native messaging host, or helper executable. Archived `extension/`, `web/`,
`shared/`, and `macos/` directories in a source checkout are not runtime
components and are not alternate installation paths.

## Limits of this document

Source inspection and automated tests do not establish what a physical camera,
managed Mac, browser, target website, signing identity, or future macOS release
will do. Permission grants, physical gesture performance, and external-service
results must be observed on the exact installed build.
