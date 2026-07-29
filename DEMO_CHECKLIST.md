# Native Signal verification checklist

Unchecked means not physically observed on the exact installed application.

## Automated release gates

- [ ] Root `Signal` arm64 build succeeds.
- [ ] Full XCTest suite passes and the `.xcresult` count is recorded.
- [ ] Release `Signal.app` is strict-code-signature valid.
- [ ] ZIP and DMG each contain exactly one `Signal.app`.
- [ ] Bundle is `com.allenxu.Signal`, macOS 13+, arm64, and `LSUIElement`.
- [ ] No test bundle, website, extension, server, helper, or second app is embedded.
- [ ] Exactly eight command gestures exist and Five is absent.
- [ ] `git diff --check` and the native CI definition pass.

## Physical production matrix

- [ ] `/Applications/Signal.app` launches as a menu-bar app and starts Paused.
- [ ] Camera and Accessibility permission work for this exact installed identity.
- [ ] Camera runs near 30 FPS with visible landmarks.
- [ ] Control moves the real cursor and reanchors without jumping.
- [ ] Quick thumb-index pinch produces one click.
- [ ] Held vertical pinch scrolls Chrome and another app.
- [ ] Held horizontal pinch zooms the frontmost supported app.
- [ ] Commands disables pointer/click/scroll/zoom output.
- [ ] One, Two, Three, Four, Thumbs Up, Thumbs Down, and C perform their exact defaults once.
- [ ] Reviewed Fist Test, Save, and execution work without changing fixed cards.
- [ ] Teach by Demo redacts secure input and saves only reviewed supported steps.
- [ ] Emergency Stop works during Control, command execution, and recording.
- [ ] Closing windows leaves Signal in the menu bar; Quit releases all input.

Do not check a physical item from unit tests, source inspection, process
presence, or a synthetic landmark fixture.
