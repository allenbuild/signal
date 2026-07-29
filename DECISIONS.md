# Decision log

| ID | Decision | Evidence and consequence |
| --- | --- | --- |
| D-001 | Treat the tagged baseline as an empty repository. | `git ls-tree -r --name-only 7cb7e47` returns zero files. The separate HandPilot disclosure is retained as supplied context, not claimed repo evidence. |
| D-002 | Native macOS app is the release of record. | System-wide pointer and keyboard output cannot be a normal web-page responsibility. Web is public distribution/planning/sharing. |
| D-003 | Freeze portable contracts at `schemaVersion: 1`. | Both Swift and TypeScript reject unknown versions; no best-effort future decode. |
| D-004 | Bound plans to 50 steps, 300 seconds, and 60 seconds per step. | Prevents unbounded generated/imported macros while leaving room for the hero flows. Conditional branches are nonrecursive and at most 10 actions each. |
| D-005 | Keep only a safe default action union in v1. | Raw AppleScript, shell, arbitrary authorization headers, private-network opt-outs, and raw secrets are invalid. Template AppleScript is allowlisted by template ID. |
| D-006 | References, never secret values, cross the portable boundary. | Native resolves Keychain entries; server resolves managed environment secrets. Share pages reveal neither values nor resolution state. |
| D-007 | Require `public_https_only` in network actions and enforce SSRF rules at runtime. | JSON Schema cannot resolve DNS, inspect redirects, or prevent DNS rebinding. Executors block loopback/private/link-local and re-check each hop. |
| D-008 | Use 40-bit unlisted share codes in canonical `SIG1-XXXXXXXX` form. | Eight characters from a 32-symbol ambiguity-free alphabet; codes are read-only identifiers, not authentication. |
| D-009 | Preserve an offline seeded profile. | Planner, Discord, Spotify-app, and profile-service failures must not block the demo. Fallback receipts must be labeled. |
| D-010 | Set project Codex concurrency to three spawned threads. | The observed environment cap is four total slots including the primary. The prompt's proposed 32 is not valid for this session. |
| D-011 | Use `gpt-5.6-sol`, `xhigh`, priority service, and stable multi-agent/fast flags in project config. | Installed Codex is `0.145.0`; current user config confirms the model/tier, and the current manual identifies the project config and stable feature keys. |
| D-012 | Do not treat schema validation as authorization. | A shape-valid plan still needs policy checks, preview, confirmation, output gates, cancellation, and typed receipts. |
| D-013 | Supersede D-002: Signal is one public browser application. | The exact merged native/web state is preserved on `codex/archive-native-web-2026-07-24`. Current `main`, CI, navigation, camera tracking, controls, command execution, and deployment are browser-only; native source is legacy history. |
| D-014 | Supersede D-013: Signal is one Manifest V3 Chrome extension with a public install/fallback/API site. | The browser fallback is preserved at tag `signal-web-fallback`. Cross-tab control uses one offscreen camera runtime, a service worker, and page content scripts; no native app, localhost process, Accessibility permission, native messaging, or OS cursor movement is required. |
| D-015 | Supersede D-014: Signal is one local native macOS application. | Browser and extension work remain preserved in repository history, including `signal-web-archive`, `archive-native-web-2026-07-24`, and `signal-web-fallback`. The root `Signal.xcodeproj`, `Signal` scheme, and packaged `Signal.app` are the canonical product, build, runtime, and distribution path. The native app has no required website, extension, server, localhost bridge, or native-messaging dependency. |

Add dated entries rather than rewriting history when a decision changes.
