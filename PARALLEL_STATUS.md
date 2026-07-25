# Parallel status

This is the coordination board, not proof of release completion. Owners update a
row with branch, commit, evidence, and handoff state. The effective environment
allows one primary plus three spawned threads.

## Contract-freeze checkpoint

| State | Work | Owner/path | Evidence or next action |
| --- | --- | --- | --- |
| Complete | Baseline evidence | Integration / top level | `7cb7e47` and `night-hack-start`; zero tracked files |
| Integrated | Version 1 shared contracts | `codex/contracts-docs` / `shared/**` | Source `e5bcfde`; integrated and pushed on `codex/release-integration` as `75bc042` |
| Active | Native application | Team A / `allen/native-signal` / `macos/**` | Report build/tests and commit before integration |
| Active | Web/cloud service | Team B / `partner/web-cloud` / `web/**` | Report build/tests, preview URL, and commit |
| Queued | Native integration audit | Integration | Run full build/test after branch merge |
| Queued | Public production smoke | Team B + independent reviewer | Production URL, health, incognito profile, download |
| Queued | Packaging/signing audit | Team A + independent reviewer | App/ZIP/optional DMG, checksum, identity, Gatekeeper |
| Queued | Physical verification | Human on demo Mac | Four touch controls, nine commands, planner, recorder, pause |
| Blocked | Credentials/account actions | Human only if needed | Record one exact action; continue independent work |
| Rejected | Unsupported 32-agent project cap | Integration | Use the observed four-slot cap |

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
