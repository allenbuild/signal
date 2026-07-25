# Browser demo checklist

Unchecked means not physically verified.

## Automated release gates

- [ ] Shared contracts validate.
- [ ] Locked install succeeds.
- [ ] Lint, unit/component tests, typecheck, and production build pass.
- [ ] Chromium E2E passes with the fake camera stream.
- [ ] Production dependency audit has no high/critical finding.
- [ ] Source/output scan finds no secret, native product link, or production
      localhost dependency.

## Physical production matrix

- [ ] Public HTTPS page requests no camera before Start Signal.
- [ ] Camera approval shows mirrored video and 21-point landmark overlay.
- [ ] Stop Signal closes the camera indicator and resets state.
- [ ] Relative virtual cursor moves and re-anchors after hand loss.
- [ ] Quick pinch produces exactly one in-page click.
- [ ] Held vertical pinch scrolls and does not click on release.
- [ ] Held horizontal pinch zooms and does not click on release.
- [ ] All nine command poses recognize.
- [ ] Hold/cooldown/release gate prevents repeated command firing.
- [ ] Camera denial, recovery, visibility pause, and tracking loss are safe.
- [ ] Natural-language Fist command saves and runs.
- [ ] Teach by Demo records, reviews, and saves.
- [ ] Hard refresh and responsive layout work.
- [ ] The same production URL is tested on a second computer.
