# Browser demo checklist

Unchecked means not physically verified.

## Automated release gates

- [ ] Shared contracts validate.
- [ ] Locked extension and web installs succeed.
- [ ] Extension lint, deterministic tests, typecheck, build, and package pass.
- [ ] Web lint, unit/component tests, typecheck, and production build pass.
- [ ] Chromium E2E passes with the fake camera stream.
- [ ] Production dependency audit has no high/critical finding.
- [ ] Manifest/source scan finds no forbidden permission, secret, native product link, or production
      localhost dependency.

## Physical production matrix

- [ ] One side-panel Start action grants camera access.
- [ ] Tracking continues after changing between ordinary tabs.
- [ ] Camera approval reports nonzero local landmark FPS.
- [ ] Stop Signal closes the camera indicator and resets state.
- [ ] Relative virtual cursor moves and re-anchors after hand loss.
- [ ] Quick pinch produces exactly one click on another website.
- [ ] Held vertical pinch scrolls that website and does not click on release.
- [ ] Held horizontal pinch changes actual tab zoom and does not click on release.
- [ ] All nine command poses recognize.
- [ ] Hold/cooldown/release gate prevents repeated command firing.
- [ ] Camera denial, recovery, visibility pause, and tracking loss are safe.
- [ ] Natural-language Fist command saves and runs.
- [ ] Teach by Demo captures reviewed actions without sensitive values.
- [ ] Restricted pages fail visibly and safely.
- [ ] Wikipedia, GitHub, Google, nested scroll, and a React app are tested.
- [ ] Commands persist after a Chrome restart.
- [ ] The packaged extension is tested on a second computer.
- [ ] A backup demo video is recorded.
