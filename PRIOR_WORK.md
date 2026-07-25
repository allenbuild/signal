# Prior work and kickoff evidence

## Repository evidence

The inspected kickoff commit is
`7cb7e47cc83ae4c0c542bde652827bbb02c55d78`, tagged
`night-hack-start`. `git ls-tree -r --name-only` reports **0 tracked files** at
that commit. Therefore this repository does not itself contain or substantiate
the HandPilot files or behavior described below. Signal implementation,
packaging, and deployment must be measured from this empty tagged state.

Use these commands when producing final after-tag evidence:

```sh
git rev-parse night-hack-start^{}
git ls-tree -r --name-only night-hack-start | wc -l
git log --oneline night-hack-start..HEAD
git diff --stat night-hack-start..HEAD
git diff --shortstat night-hack-start..HEAD
```

## Organizer/team-supplied prior-work disclosure

The following disclosure was supplied in the master build prompt. It concerns a
separate native macOS experiment and is preserved as a team/organizer statement,
not as a claim verified by this repository:

> Before Night Hack, the team built a separate native macOS experiment named
> HandPilot. The disclosed baseline included camera capture, Apple Vision hand
> landmark tracking, a deterministic gesture engine, macOS input event
> generation, permissions and safety handling, calibration diagnostics, and
> touchless pointer, click, scroll, and zoom controls. During Night Hack, the
> team created Signal as a substantial new capability layer and product: nine
> programmable gestures, natural-language workflow creation, Teach by Demo
> recording, an editable macro engine, action integrations, profiles, sharing,
> optional sign-in and cloud sync, a redesigned command-centered experience,
> public deployment, and distributable release packaging. The night-hack-start
> tag marks the complete pre-event baseline. Only commits after that tag are
> claimed as Night Hack work.

The future-tense/outcome portion of that supplied paragraph must be reconciled
with actual final evidence before publication. Do not claim optional sign-in,
cloud sync, deployment, packaging, physical gesture behavior, or any other
outcome unless it was completed and verified.

## Release disclosure rule

The submission should show both facts together:

1. The team disclosed a separate pre-event HandPilot prototype and its stated
   capabilities.
2. The actual tagged Signal repository baseline inspected at kickoff contains
   zero tracked files.

Do not imply the empty repository disproves the disclosure, and do not imply the
disclosure proves files or runtime behavior were in this repository.
