# Signal gesture guide

This guide describes the canonical native macOS application. Signal opens in
**Paused** mode. Camera recognition alone never authorizes output: deliberately
choose **Control** or **Commands** only when you are ready.

## Before practicing

1. Run the installed app from the stable path
   `/Applications/Signal.app`.
2. Grant Camera and Accessibility for that exact app when needed.
3. Open **Calibration** from the Signal menu-bar hand.
4. Face the palm toward the camera with the whole hand visible.
5. Use one hand, steady lighting, and a plain background when possible.
6. Keep the hand far enough from the camera that fingertips and wrist remain
   inside the preview.

Calibration is for observation and tuning. It does not bypass the Paused gate.

## Modes

- **Paused** — safe default. Pointer output and command activation are blocked.
- **Control** — maps a tracked hand to native pointer, click, vertical scroll,
  and horizontal zoom output.
- **Commands** — recognizes the eight command poses below. Control-mode pointer
  and pinch output is not used for command activation.

If more than one hand is visible, tracking is uncertain, or required landmarks
are missing, return to one clear hand rather than trying to force activation.

## Control gestures

### Point and move

Extend the index finger and fold the other fingers. Move the hand gradually to
move the pointer. Start with small motion; sensitivity and dead-zone settings
can be adjusted in Calibration.

### Click

Bring the thumb and **index fingertip** together, then release promptly while
keeping the hand otherwise still. A qualifying quick pinch-and-release emits
one left click. The pointer remains frozen during the pinch episode.

### Scroll

Hold the thumb-to-index pinch and move vertically:

- move up to scroll up;
- move down to scroll down; and
- stop moving or release to stop scrolling.

The gesture locks to a dominant axis. Begin with a clearly vertical motion
rather than a diagonal movement.

### Zoom

Hold the thumb-to-index pinch and move horizontally:

- move right to zoom in;
- move left to zoom out; and
- stop moving or release to stop zooming.

Zoom uses application-specific keyboard shortcuts. Results can differ by the
frontmost application and its configured zoom profile.

## Commands gestures

Commands mode contains exactly eight commands in a fixed two-by-four order:

| Order | Pose | How to form it | Default command |
| ---: | --- | --- | --- |
| 1 | One | Index extended; middle, ring, and little folded | Rickroll |
| 2 | Two | Index and middle extended; ring and little folded | New Gmail |
| 3 | Three | Index, middle, and ring extended; little folded | Cursor Agents |
| 4 | Four | Four fingers extended; thumb folded | New Google Doc |
| 5 | Thumbs Up | Thumb vertical up; four fingers folded | Build with Bolt |
| 6 | Thumbs Down | Thumb vertical down; four fingers folded | Next Spotify Track |
| 7 | C | Curve fingers and thumb into a visible C with separated tips | Anthropic on X |
| 8 | Fist | Fold all fingers into a closed fist | Custom Command |

There is no Five command. An open five-finger hand must not be taught,
displayed, or relied on as a command.

By default, hold a clear command pose steadily for about 0.60 seconds. The
progress indicator can reset when confidence falls or the pose changes. After
one activation:

1. release the pose or change to a neutral hand;
2. wait for the command to rearm; and
3. form the next pose after the global cooldown (0.90 seconds by default).

Continuing to hold the same pose does not intentionally repeat-fire it.

Fist is the configurable command slot. Review and save its allowed action
before relying on it. Opening a command editor does not execute the command.

## Permission notes

Camera and Accessibility are the core permissions for native gesture control.
Automation consent is optional and currently used only for the reviewed
Chrome-based Bolt and Spotify Web actions. Screen Recording is not required,
requested, or used: Teach by Demo records bounded structured event and
Accessibility proposals, not screen pixels. Grant Automation only when a
reviewed Chrome action is deliberately used.

## Stop immediately

Choose **Paused**, use **Emergency Stop** from the menu bar, or press
Control–Option–Command–H. Move away from the camera and verify the status before
resuming.

## Evidence boundary

The pose descriptions and timing above come from the deterministic
classification and activation configuration. They are not a claim that
physical gestures have been tested with a particular camera, user, lighting
condition, target app, or packaged build. Record a physical result only after
observing that exact setup.
