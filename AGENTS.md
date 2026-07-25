# Signal repository guidance

## Start with evidence

- The kickoff commit is `7cb7e47cc83ae4c0c542bde652827bbb02c55d78`.
- The annotated `night-hack-start` tag points to that commit.
- That commit has zero tracked files. Do not describe HandPilot source as present
  in this repository baseline. `PRIOR_WORK.md` keeps the separate
  organizer/team disclosure distinct from repository evidence.
- Treat release claims as unverified until a command result or a human physical
  check records them. Never infer camera, gesture, signing, deployment, or
  production status from generated source alone.

## Ownership and coordination

- Native owners write `macos/**`; web/cloud owners write `web/**`.
- Before the contract freeze, the integration owner writes `shared/**`. After
  freeze, only that owner changes it; requests go in `HANDOFF.md`.
- Only one owner changes the Xcode project file, native release packaging, web
  dependency manifests/lockfiles, or shared schemas at a time.
- Do not edit another worktree. Confirm `pwd`, branch, and `git status` before
  writing. Preserve unrelated user changes.
- Commit bounded work before handoff. Return summary, files, interfaces,
  commands/tests, risks, and commit hash.
- The effective session cap observed at kickoff is four total threads. Keep at
  most three subagents active beneath one primary; do not copy an unsupported
  cap of 32 into project config.

## Contract invariants

- Version 1 is defined by `shared/*.schema.json`; reject future versions.
- Enforce all size, action-count, and timeout maxima at decode and execution.
- Portable profiles contain secret references only, never secret values.
- HTTPS syntax is necessary but insufficient. Executors must reject localhost
  and non-public destinations after DNS resolution and on every redirect, as
  specified in `shared/README.md` and `SECURITY.md`.
- AI plans are previews. Validate server-side and client-side, display every
  effect, and require approval before save or first run.
- The v1 safe union excludes raw AppleScript, shell commands, arbitrary
  authorization headers, private-network opt-outs, and raw secrets.

## Safety and release rules

- Output starts paused. Emergency stop must synchronously close output gates,
  release held events, cancel pinch/activation/macros, and require explicit
  re-enable.
- Camera frames remain memory-only; no telemetry by default.
- Native release must not require localhost. Production API configuration is
  public HTTPS only, with an offline seeded-profile fallback.
- Never claim physical verification, signing, notarization, packaging,
  deployment, or public smoke testing unless it was actually observed.
- Feature freeze is 10:35 PM; the hacking deadline is 11:45 PM.

## Verification

Run focused checks before handoff:

```sh
node scripts/validate-shared-contracts.mjs
npx --yes ajv-cli@5 compile --spec=draft2020 -s shared/action-plan.schema.json
npx --yes ajv-cli@5 compile --spec=draft2020 -s shared/profile.schema.json -r shared/action-plan.schema.json
npx --yes ajv-cli@5 compile --spec=draft2020 -s shared/planner-response.schema.json -r shared/action-plan.schema.json
npx --yes ajv-cli@5 validate --spec=draft2020 -s shared/profile.schema.json -r shared/action-plan.schema.json -d shared/seeded-demo-profile.json
npx --yes ajv-cli@5 validate --spec=draft2020 -s shared/planner-response.schema.json -r shared/action-plan.schema.json -d shared/examples/planner-response.json
git diff --check
```

Native and web owners add their exact build/test commands here only after the
scaffolds exist and commands have been run successfully.
