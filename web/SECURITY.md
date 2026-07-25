# Browser security boundary

- Only browser-safe actions may be planned, saved, shared, imported, or run.
- Public navigation must be HTTPS and pass literal-host validation.
- Unknown fields, future versions, private literals, credential-like text, and
  native actions are rejected.
- Camera access requires a click and tracks are stopped on Stop/unmount.
- Planner output is validated data, never executable code.
- Integration secrets remain server-side.

See the repository `SECURITY.md` for release-wide policy.
