# Known limitations

- Signal controls ordinary HTTP/HTTPS pages only. It cannot control
  `chrome://` pages, the Chrome Web Store, browser settings, extension
  management, new-tab/internal pages, permission prompts, DevTools, or
  operating-system UI.
- The virtual cursor is an extension overlay; the operating-system cursor does
  not move.
- Some site actions require transient trusted user activation and cannot be
  synthesized by a hand gesture.
- Interaction is intentionally routed to the active tab's top frame. Embedded
  cross-origin frame controls are not targeted directly.
- Hand accuracy varies with lighting, framing, occlusion, handedness, and
  camera quality.
- Natural-language planning needs the public Signal planner. A deterministic
  fallback handles supported common instructions when Claude is unavailable.
- Protected webhook and Claude workflow actions require an authenticated,
  user-scoped integration service and are rejected when none is configured.
- `show_notification` is rendered as a Signal page overlay in this minimal
  permission release; it is not an operating-system notification.
- Hackathon installation uses **Load unpacked**; Chrome Web Store publication is
  not claimed.
