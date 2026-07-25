# Five-hour team plan

## Ownership

Team A owns native control and final integration. Team B owns public web, cloud,
sharing, deployment operations, and second-device checks. `TEAM_A.md`,
`TEAM_B.md`, and `HANDOFF.md` define the write boundary.

## Schedule

| Time | Exit criterion |
| --- | --- |
| 7:00–7:10 PM | Baseline inspected, disclosure written, `night-hack-start` verified, credentials/signing inventory recorded without values |
| 7:10–7:25 PM | Version 1 contracts frozen; native/web scaffolds build; feature flags and ownership set |
| 7:25–8:20 PM | Four touch paths, nine-command geometry/modes, mapping UI, planner/public site/profile preview implemented in parallel |
| 8:20–9:20 PM | Action/macro engine, plan review, controlled recorder, seeded workflows, import/export, and sharing implemented |
| 9:20–10:05 PM | First full merge; production preview connected; focused tests; first package/download candidate |
| 10:05–10:35 PM | Adversarial gesture, lifecycle, permissions, public incognito, and UI reliability pass |
| 10:35 PM | Feature freeze; only release-blocking fixes |
| 10:35–11:15 PM | Clean native build/tests, production web build/deploy, package/checksum/upload, production smoke |
| 11:15–11:35 PM | Three 90-second rehearsals, seeded/offline/API-down/emergency fallbacks |
| 11:35–11:45 PM | Final freeze, evidence capture, submission |

## Integration gates

1. Contract gate: all shared fixtures validate in draft 2020-12.
2. Focused gate: each owner runs tests for its touched modules before handoff.
3. Merge gate: shared versions, endpoint origins, and generated models agree.
4. Release-candidate gate: clean native build/test and web build/test pass.
5. Distribution gate: downloaded artifact checksum matches; launch/setup tested.
6. Demo gate: a human records physical observations and three timed rehearsals.

## Cut order

Cut mobile browser camera, optional sign-in, cloud sync, global recorder, raw
automation stretch work, DMG polish, browser simulator, then animation. Do not
cut the four touch controls, nine command gestures, visual builder, one
natural-language path, one controlled recorder path, public HTTPS site,
shareable app artifact, emergency pause, or touch-state tests.
