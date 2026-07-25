# Browser security boundary

- Only extension browser-safe actions may be planned, saved, shared, imported, or run.
- Public navigation must be HTTPS and pass literal-host validation.
- Unknown fields, future versions, private literals, credential-like text, and
  native actions are rejected.
- Extension camera access requires an explicit click and tracks are stopped on
  Stop, pause teardown, or failure.
- Planner output is validated data, never executable code.
- Integration secrets remain server-side.
- The extension rejects protected Chrome pages, `javascript:` URLs, native
  actions, inline secrets, password values, and unknown/future schemas.

See the repository `SECURITY.md` for release-wide policy.
