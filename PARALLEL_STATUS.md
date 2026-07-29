# Parallel status

> Historical integration board. The native/web and browser-only work it records
> remains preserved in repository history. Decision D-015 makes the local native
> `Signal.app` canonical; current release work is on `signal-native-local`.

This is the coordination board, not proof of release completion. Owners update a
row with branch, commit, evidence, and handoff state. The effective environment
allows one primary plus three spawned threads.

## Contract-freeze checkpoint

| State | Work | Owner/path | Evidence or next action |
| --- | --- | --- | --- |
| Complete | Baseline evidence | Integration / top level | `7cb7e47` and `night-hack-start`; zero tracked files |
| Integrated | Version 1 shared contracts | `codex/contracts-docs` / `shared/**` | Source `e5bcfde`; integrated and pushed on `codex/release-integration` as `75bc042` |
| Integrated | Native application | Team A / `allen/native-signal` / `macos/**` | Release commit `4dce639`; 41 tests and release build pass |
| Integrated | Web/cloud service | Team B / `partner/web-cloud` / `web/**` | Public Sites version 2; 12 tests, lint/typecheck/build pass |
| Complete | Native integration audit | Integration | CI run `30141064910` all green on macOS 14 / Swift 5.10 |
| Complete | Public production smoke | Integration | Landing, download, health, planner, rejection, seeded profile and artifact pass |
| Complete | Packaging/signing audit | Integration | ZIP/DMG checksums, ad-hoc signature, app icon/provenance, launch smoke recorded |
| Queued | Physical verification | Human on demo Mac | Four touch controls, nine commands, planner, recorder, pause |
| Limited | Durable user profile storage | Web / hosting | Per-worker memory failed immediate cross-isolate read; seeded profile is durable |
| Limited | Signing/notarization | Human account credentials | No Developer ID identity; release is ad-hoc and not notarized |
| Rejected | Unsupported 32-agent project cap | Integration | Use the observed four-slot cap |

## Current native release track

- The production graph is the root `Signal.xcodeproj` and `Signal` scheme.
- The shipping modes are Paused, Control, and Commands.
- Commands contains exactly eight poses: One, Two, Three, Four, Thumbs Up,
  Thumbs Down, C, and Fist. Five is not a command.
- Browser, extension, web, cloud, and older `macos/` work are retained as
  history, not included in the native package or required at runtime.
- Final automated results, package provenance, and physical observations belong
  in `HANDOFF.md`; this historical board is not release evidence.

## State definitions

- `Queued`: independent task is ready but no slot/owner is active.
- `Active`: an owner has the task and its exclusive paths are recorded.
- `Blocked`: a concrete credential, permission, external state, or repeated
  technical blocker prevents progress.
- `Complete`: owner committed and returned evidence; not yet merged.
- `Rejected`: intentionally excluded or unsafe scope.
- `Integrated`: merged and reverified on the integration branch.

Never mark generated code as integrated and never mark a physical item complete
from unit tests.
