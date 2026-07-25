# Shared contract freeze: schema version 1

These files are the language-neutral boundary between the native client and the
public service. JSON Schema dialect is draft 2020-12. Producers must emit
`schemaVersion: 1`; consumers must reject any other value with an
`unsupported_schema_version` error instead of guessing or partially decoding.

## Limits

| Item | Version 1 maximum |
| --- | ---: |
| Plan steps | 50 |
| Nested actions in either conditional branch | 10 |
| Whole-plan timeout | 300,000 ms |
| Step timeout | 60,000 ms |
| Wait action | 30,000 ms |
| Gesture mappings per profile | 9 |
| Secret references per plan | 20 |
| HTTP response body | 1,048,576 bytes |

The runtime must also count conditional branch actions toward the 50-action
execution budget. It must stop a plan at its timeout even if individual step
timeouts would sum to more.

## API endpoints

| Method | Path | Contract |
| --- | --- | --- |
| `POST` | `/api/v1/plan` | Request example in `examples/planner-request.json`; response validates against `planner-response.schema.json`. |
| `POST` | `/api/v1/profiles` | Body example in `examples/profile-create-request.json`; embedded profile validates against `profile.schema.json`. |
| `GET` | `/api/v1/profiles/:shareCode` | Returns a version 1 profile; `404 profile_not_found` must not distinguish absent from private. |
| `POST` | `/api/v1/integrations/discord` | Server-side secret only; request is derived from an approved `discord_webhook` action. |
| `GET` | `/api/v1/health` | Deterministic non-secret status; no dependency details. |

Planner requests are UTF-8 JSON, at most 16 KiB, with a request string at most
4,000 characters and at most 32 advertised action-catalog entries. These request
limits are enforced server-side because a request schema is not part of the
portable v1 response contract.

Production endpoints are HTTPS only. Native release configuration must not
contain a localhost fallback.

## Share-code format

The canonical code is `SIG1-XXXXXXXX`.

- `SIG1` identifies profile/share-contract version 1.
- The payload is exactly eight symbols from
  `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`; ambiguous `I`, `O`, `0`, and `1` are
  excluded.
- Generation uses a cryptographically secure random source. The payload is
  case-insensitive on input and canonicalized to uppercase.
- Servers rate-limit lookup attempts and never use sequential codes. A
  collision is retried; clients never invent a replacement.
- Codes grant read-only access to an unlisted, redacted profile. They do not
  authorize editing, secret retrieval, or integration execution.
- Private profiles never return a share code. Removing sharing invalidates the
  current code.

The eight-symbol payload carries 40 random bits. This is an unlisted sharing
identifier, not authentication; sensitive profiles must remain private.

## Secret and network rules

Portable JSON may contain a reference identifier and metadata, never a token,
password, webhook URL, cookie, or authorization value. Native implementations
resolve references from Keychain; server implementations resolve them from
environment/managed secret storage. Share serialization may keep the reference
ID for configuration UX but must redact whether a reference currently resolves.

`open_url` and `http_request` carry
`networkPolicy: "public_https_only"`. Schema validation enforces HTTPS syntax.
The executor must additionally:

1. Reject literal and resolved loopback, link-local, private, carrier-grade NAT,
   multicast, unspecified, and documentation/test-network addresses for IPv4
   and IPv6.
2. Resolve DNS before connecting and repeat the policy check for every redirect.
3. Pin the approved resolved address for the connection or use equivalent
   rebinding-resistant transport behavior.
4. Reject user-info in URLs, non-HTTPS redirects, unsupported ports, and more
   than five redirects.
5. Never forward credentials across an origin change.

This runtime check is mandatory because JSON Schema cannot evaluate DNS or
redirect targets. A syntactically valid payload is not authorization to connect.

## Safe action union

Version 1 accepts only the actions enumerated by
`action-plan.schema.json`. `raw_applescript`, `shell_command`, arbitrary
headers, private-network opt-outs, and raw secret values are not valid v1
actions. Future advanced actions require a new schema version, an explicit
advanced-mode design, and migration/rejection tests.

All AI results are previews. The server validates output; the client validates
again, shows every step, and requires approval before save or first run.
