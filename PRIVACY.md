# Privacy

## Default data behavior

- Camera frames are processed in memory by the native app and are not uploaded,
  persisted, included in telemetry, or used for model training by Signal.
- Hand landmarks and gesture state remain local unless a user explicitly
  exports a profile; exported profiles contain mappings and plans, not frames.
- Telemetry is off by default. The release must document any crash-reporting
  service before enabling it.
- Signal requests no microphone permission.
- Controlled Teach by Demo stores only the supported semantic actions the user
  explicitly adds. Experimental global recording starts only after an explicit
  countdown and visible red indicator.

## Sensitive input

Global recording must warn before text capture, avoid secure-input contexts when
detectable, provide masking/deletion before save, and never upload raw event
streams. Clipboard and typed-text actions show exact content before approval.
Portable profiles reject text explicitly marked sensitive.

Secrets such as webhook URLs, API tokens, cookies, and passwords are never
stored in profile JSON. Profiles carry reference IDs; the native app resolves
them from Keychain and the server from managed environment secrets. Receipts
and logs record the reference ID and outcome, never the value or resolution
metadata.

## Network data

The planner request includes the user's text, requested gesture, and an
allowlisted action catalog. It does not include camera frames, landmarks,
clipboard content, secret values, arbitrary application history, or recorded
events. Server logs redact request text where configured and must never log
authorization material.

Unlisted profile pages are accessible to anyone who has the share code. They
are read-only, redacted, and should contain no sensitive content. Share codes
are not authentication. Users can keep profiles private or revoke a code.

## User controls

The product must expose:

- Pause/Enable and a synchronous emergency stop;
- profile export/import and local deletion;
- sharing enable/revoke state;
- clear permission instructions for Camera and Accessibility;
- recorder Start, Stop, Cancel, masking, and deletion controls;
- no automatic re-enable after pause or emergency stop.

Before release, replace any placeholder privacy contact and describe deployed
storage retention/deletion behavior based on the actual provider configuration.
