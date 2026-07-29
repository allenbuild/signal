# Native automation limitations

The canonical Signal product is the macOS app built from the root
`Signal.xcodeproj`. Signal is safety-first: it launches in **Paused** mode, and
the user must explicitly select **Control** or **Commands** before output is
allowed.

## Permission boundary

Signal's two core permissions are:

- **Camera**, for local hand tracking and gesture recognition; and
- **Accessibility**, for native pointer, click, scroll, zoom, and other
  permitted input events.

Two other macOS privacy permissions are optional and feature-dependent:

- **Automation** consent is granted separately for each target application.
  The current build requests it only for reviewed Chrome automation used by
  the Bolt and Spotify Web actions. macOS normally presents it only when an app
  first attempts or explicitly preflights an Apple Event. Signal cannot
  pre-grant it, approve its own prompt, or assume that consent for Chrome
  applies to another application.
- **Screen Recording** is not required by the current build. Teach by Demo
  records reviewed structured events and Accessibility metadata, not screen
  pixels. A future optional visual-preview implementation would require its
  own explicit permission flow and release verification.

Do not grant optional permissions preemptively. Their absence is not a defect
when the active workflow does not need them.

## Closed command catalog

Commands mode exposes exactly these eight mappings:

| Order | Gesture | Default command |
| ---: | --- | --- |
| 1 | One | Rickroll |
| 2 | Two | New Gmail |
| 3 | Three | Cursor Agents |
| 4 | Four | New Google Doc |
| 5 | Thumbs Up | Build with Bolt |
| 6 | Thumbs Down | Next Spotify Track |
| 7 | C | Anthropic on X |
| 8 | Fist | Custom Command |

There is no Five command. Five must not be registered, displayed, or described
as a ninth command.

The native command model has a closed action vocabulary: reviewed HTTPS URL
opening, the typed Bolt prompt action, and the typed Spotify-next action. It is
not a general shell, AppleScript, JavaScript, arbitrary HTTP, or background
agent runner. A command card's edit control opens editing; opening the editor
does not execute the command.

The default activation policy requires a stable pose hold, fires at most once
for that hold, waits for release or a gesture change to rearm, and applies a
global cooldown. Recognition or progress UI is not proof that the target
application accepted the resulting action.

## What native automation cannot guarantee

- Accessibility does not override macOS secure input, authorization dialogs,
  login screens, lock screens, protected system surfaces, or another app's
  own security policy.
- A browser or target app can change its UI, focus behavior, shortcuts, media
  state, sign-in requirements, or automation support.
- Chrome must be installed for the reviewed Bolt and Spotify automation paths.
  Chrome may also require **Allow JavaScript from Apple Events** to be enabled.
  Signal does not enable that setting.
- The reviewed Bolt and Spotify actions require an expected HTTPS tab and a
  uniquely verified target control. A missing tab, changed origin, ambiguous
  control, or changed page structure fails closed rather than clicking an
  unverified element.
- Opening Gmail, Google Docs, X, Cursor Agents, Bolt, Spotify, or a video may
  require network access, an installed/default browser, an authenticated
  session, and service-specific consent.
- Media commands can be ignored when there is no active player or when the
  service does not expose the expected control.
- Screen Recording permission does not itself provide Accessibility control,
  and Accessibility permission does not itself allow screen capture.
- Automation approval for one installed copy of Signal may not transfer to a
  differently signed, rebuilt, or relocated copy. The same path and bundle
  identifier do not guarantee the same macOS code requirement.
- Signal cannot dismiss its own macOS privacy prompts or silently repair a
  denied permission.

## Safety and recovery

Remain in **Paused** while configuring commands or permissions. Use
Control–Option–Command–H or the menu-bar **Emergency Stop** action to revoke
output. After an emergency stop, inspect status and permissions before
deliberately enabling a mode again.

The app and scripts do not package a website, extension, server, native
messaging host, or helper. No packaging result is evidence that physical
gestures or external automation succeeded; those outcomes require direct,
recorded observation.
