# Demo and release checklist

Unchecked means not verified. Add observer, timestamp, artifact commit, and
notes for every physical item; automated tests do not satisfy physical checks.

## Release candidate

- [x] Clean native Release build completed.
- [x] Native tests recorded with executed/failure/skip counts.
- [x] Web locked install, lint/typecheck, tests, and production build completed.
- [x] Shared v1 schemas and fixtures validate in Swift, TypeScript, and AJV.
- [x] Exact `.app`, ZIP, DMG, and SHA-256 recorded.
- [x] Signing/notarization/Gatekeeper status stated accurately.
- [x] Downloaded public artifact checksum and three-second launch smoke verified.
- [x] About version/commit and production HTTPS origin verified.
- [x] Bundle/source scans find no secret or release localhost dependency.

## Physical native matrix

- [ ] Pointer moves relatively with index pose and re-anchors after loss.
- [ ] Quick pinch produces exactly one real click.
- [ ] Held vertical pinch scrolls; release/loss stops; no click follows.
- [ ] Held horizontal pinch zooms both directions; no click follows.
- [ ] `one` command recognizes in Command Mode.
- [ ] `two` recognizes.
- [ ] `three` recognizes.
- [ ] `four` recognizes.
- [ ] `five` recognizes.
- [ ] `fist` recognizes.
- [ ] `thumbs_up` recognizes.
- [ ] `thumbs_down` recognizes.
- [ ] `c_shape` recognizes.
- [ ] Stable hold, cooldown, and release gate prevent repeat triggers.
- [ ] Touch/Command/Hybrid conflicts behave as documented.
- [ ] Control-Option-Command-H immediately pauses and cancels output.
- [ ] Tracking loss, camera stop, sleep/mode change, and relaunch remain safe.
- [ ] Camera denial/recovery and Accessibility identity/recovery work for the
  packaged app.

## Product flows

- [ ] Natural-language preview validates, edits, approves, saves, and runs.
- [ ] Planner-down deterministic fallback is clearly labeled and runs.
- [ ] Visual builder saves a v1 plan.
- [ ] Controlled Teach by Demo records, edits, saves, and replays.
- [ ] Secret values never appear in JSON, logs, receipts, or share UI.
- [ ] Profile export/import and future-version rejection work.
- [ ] Share create/read/revoke works in incognito.
- [ ] External integration and labeled fallback receipts work.

## Public production

- [x] HTTPS landing/setup/privacy/download/seeded-profile pages load.
- [x] Health, planner planned/clarification, and malformed/future-version smoke pass.
- [ ] Hard refresh and second-device/network smoke pass.
- [x] Download link names the exact verified artifact and checksum.
- [x] Public site and native release do not depend on localhost.

User-created profile create succeeded but immediate cross-isolate read failed;
therefore no durable create/read/revoke box is checked. The seeded profile is
the durable judge path.

## Rehearsal

- [ ] Notifications/unrelated apps closed and demo profile preloaded.
- [ ] Offline/API-down, Spotify, Discord, recorder, and profile fallbacks ready.
- [ ] Ninety-second sequence rehearsed three times: ___ / ___ / ___ seconds.
- [ ] Backup video exists only as fallback.
- [ ] Final submission URL and artifact URL opened from a clean session.
