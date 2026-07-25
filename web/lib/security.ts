export const REDACTED_VALUE = "[REDACTED]";
export const SHARE_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
export const SHARE_CODE_PATTERN =
  /^SIG1-[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$/;

const forbiddenSecretKeys = new Set([
  "token",
  "password",
  "apikey",
  "api_key",
  "authorization",
  "cookie",
  "webhookurl",
  "webhook_url",
  "secretvalue",
  "secret_value",
  "accesstoken",
  "access_token",
  "refreshtoken",
  "refresh_token",
  "clientsecret",
  "client_secret",
]);

const secretValueDetectors: ReadonlyArray<{
  kind: string;
  pattern: RegExp;
}> = [
  {
    kind: "webhook URL",
    pattern:
      /https:\/\/(?:(?:discord(?:app)?\.com)\/api\/webhooks|hooks\.slack\.com\/services)\/[^\s"'<>]+/i,
  },
  {
    kind: "authorization value",
    pattern: /\b(?:Bearer|Basic)\s+[A-Za-z0-9._~+/=-]{8,}/i,
  },
  {
    kind: "private key",
    pattern: /-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----/,
  },
  {
    kind: "JSON Web Token",
    pattern:
      /\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/,
  },
  {
    kind: "provider credential",
    pattern:
      /\b(?:gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{16,}|AKIA[0-9A-Z]{16})\b/,
  },
  {
    kind: "credential query parameter",
    pattern:
      /[?&](?:access[_-]?token|token|api[_-]?key|password|secret|authorization)=[^&#\s]+/i,
  },
  {
    kind: "URL user-info credential",
    pattern: /[A-Za-z][A-Za-z0-9+.-]*:\/\/[^/\s:@]+:[^/\s@]+@/,
  },
];

export interface SecretFinding {
  path: Array<string | number>;
  kind: string;
}

function isForbiddenSecretKey(key: string) {
  const lower = key.toLowerCase();
  const compact = lower.replace(/[-_\s]/g, "");
  return forbiddenSecretKeys.has(lower) || forbiddenSecretKeys.has(compact);
}

function detectedSecretKinds(value: string) {
  return secretValueDetectors
    .filter(({ pattern }) => pattern.test(value))
    .map(({ kind }) => kind);
}

/**
 * Returns paths and categories only. It deliberately never includes the
 * offending value, so callers can safely attach findings to validation logs.
 */
export function findSecretMaterial(value: unknown): SecretFinding[] {
  const findings: SecretFinding[] = [];
  const seen = new WeakSet<object>();

  const visit = (current: unknown, path: Array<string | number>) => {
    if (typeof current === "string") {
      for (const kind of detectedSecretKinds(current)) {
        findings.push({ path, kind });
      }
      return;
    }
    if (current === null || typeof current !== "object") return;
    if (seen.has(current)) return;
    seen.add(current);

    if (Array.isArray(current)) {
      current.forEach((item, index) => visit(item, [...path, index]));
      return;
    }

    for (const [key, child] of Object.entries(current)) {
      const childPath = [...path, key];
      if (isForbiddenSecretKey(key)) {
        findings.push({ path: childPath, kind: "raw-secret field" });
      }
      visit(child, childPath);
    }
  };

  visit(value, []);
  return findings;
}

export function containsSecretMaterial(value: unknown) {
  return findSecretMaterial(value).length > 0;
}

export function assertNoSecretMaterial(value: unknown): void {
  if (containsSecretMaterial(value)) {
    throw new Error("Portable value contains forbidden secret material");
  }
}

function redactString(value: string) {
  return value
    .replace(
      /https:\/\/(?:(?:discord(?:app)?\.com)\/api\/webhooks|hooks\.slack\.com\/services)\/[^\s"'<>]+/gi,
      REDACTED_VALUE,
    )
    .replace(
      /\b(?:Bearer|Basic)\s+[A-Za-z0-9._~+/=-]{8,}/gi,
      REDACTED_VALUE,
    )
    .replace(
      /-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----[\s\S]*?(?:-----END (?:[A-Z ]+ )?PRIVATE KEY-----|$)/g,
      REDACTED_VALUE,
    )
    .replace(
      /\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/g,
      REDACTED_VALUE,
    )
    .replace(
      /\b(?:gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{16,}|AKIA[0-9A-Z]{16})\b/g,
      REDACTED_VALUE,
    )
    .replace(
      /([?&](?:access[_-]?token|token|api[_-]?key|password|secret|authorization)=)[^&#\s]+/gi,
      `$1${REDACTED_VALUE}`,
    )
    .replace(
      /([A-Za-z][A-Za-z0-9+.-]*:\/\/)[^/\s:@]+:[^/\s@]+@/g,
      `$1${REDACTED_VALUE}@`,
    );
}

/**
 * Produces a detached, logging-safe copy. Forbidden fields are retained with a
 * redaction marker so operators can understand shape without learning values.
 */
export function sanitizeSecrets(value: unknown): unknown {
  const seen = new WeakMap<object, unknown>();

  const sanitize = (current: unknown): unknown => {
    if (typeof current === "string") return redactString(current);
    if (current === null || typeof current !== "object") return current;
    const prior = seen.get(current);
    if (prior) return "[Circular]";

    if (Array.isArray(current)) {
      const copy: unknown[] = [];
      seen.set(current, copy);
      current.forEach((item) => copy.push(sanitize(item)));
      return copy;
    }

    const copy: Record<string, unknown> = {};
    seen.set(current, copy);
    for (const [key, child] of Object.entries(current)) {
      copy[key] = isForbiddenSecretKey(key)
        ? REDACTED_VALUE
        : sanitize(child);
    }
    return copy;
  };

  return sanitize(value);
}

export type PublicHttpsLiteralFailure =
  | "invalid_url"
  | "https_required"
  | "user_info_forbidden"
  | "credential_fragment_forbidden"
  | "unsupported_port"
  | "invalid_hostname"
  | "local_hostname_forbidden"
  | "non_global_ip_forbidden";

export type PublicHttpsLiteralCheck =
  | {
      ok: true;
      canonicalUrl: string;
      hostname: string;
      requiresDnsResolution: boolean;
    }
  | { ok: false; reason: PublicHttpsLiteralFailure };

function parseIPv4(hostname: string): number[] | null {
  const pieces = hostname.split(".");
  if (pieces.length !== 4) return null;
  const octets = pieces.map((piece) => {
    if (!/^\d{1,3}$/.test(piece)) return Number.NaN;
    return Number(piece);
  });
  return octets.every((octet) => Number.isInteger(octet) && octet <= 255)
    ? octets
    : null;
}

function ipv4InRange(
  octets: number[],
  base: [number, number, number, number],
  prefix: number,
) {
  const value = (
    ((octets[0] << 24) >>> 0) +
    (octets[1] << 16) +
    (octets[2] << 8) +
    octets[3]
  ) >>> 0;
  const baseValue = (
    ((base[0] << 24) >>> 0) +
    (base[1] << 16) +
    (base[2] << 8) +
    base[3]
  ) >>> 0;
  const mask = prefix === 0 ? 0 : (0xffffffff << (32 - prefix)) >>> 0;
  return (value & mask) === (baseValue & mask);
}

const blockedIPv4Ranges: ReadonlyArray<{
  base: [number, number, number, number];
  prefix: number;
}> = [
  { base: [0, 0, 0, 0], prefix: 8 },
  { base: [10, 0, 0, 0], prefix: 8 },
  { base: [100, 64, 0, 0], prefix: 10 },
  { base: [127, 0, 0, 0], prefix: 8 },
  { base: [169, 254, 0, 0], prefix: 16 },
  { base: [172, 16, 0, 0], prefix: 12 },
  { base: [192, 0, 0, 0], prefix: 24 },
  { base: [192, 0, 2, 0], prefix: 24 },
  { base: [192, 88, 99, 0], prefix: 24 },
  { base: [192, 168, 0, 0], prefix: 16 },
  { base: [198, 18, 0, 0], prefix: 15 },
  { base: [198, 51, 100, 0], prefix: 24 },
  { base: [203, 0, 113, 0], prefix: 24 },
  { base: [224, 0, 0, 0], prefix: 4 },
  { base: [240, 0, 0, 0], prefix: 4 },
];

function isBlockedIPv4(octets: number[]) {
  return blockedIPv4Ranges.some(({ base, prefix }) =>
    ipv4InRange(octets, base, prefix)
  );
}

function parseIPv6(input: string): number[] | null {
  const hostname = input.startsWith("[") && input.endsWith("]")
    ? input.slice(1, -1)
    : input;
  if (hostname.includes("%") || !hostname.includes(":")) return null;

  let expanded = hostname.toLowerCase();
  const lastColon = expanded.lastIndexOf(":");
  const possibleIPv4 = expanded.slice(lastColon + 1);
  if (possibleIPv4.includes(".")) {
    const octets = parseIPv4(possibleIPv4);
    if (!octets) return null;
    const high = ((octets[0] << 8) | octets[1]).toString(16);
    const low = ((octets[2] << 8) | octets[3]).toString(16);
    expanded = `${expanded.slice(0, lastColon)}:${high}:${low}`;
  }

  const halves = expanded.split("::");
  if (halves.length > 2) return null;
  const left = halves[0] ? halves[0].split(":") : [];
  const right = halves.length === 2 && halves[1] ? halves[1].split(":") : [];
  const validPart = (part: string) => /^[0-9a-f]{1,4}$/.test(part);
  if (!left.every(validPart) || !right.every(validPart)) return null;

  if (halves.length === 1 && left.length !== 8) return null;
  const omitted = 8 - left.length - right.length;
  if (halves.length === 2 && omitted < 1) return null;
  const parts = [
    ...left.map((part) => Number.parseInt(part, 16)),
    ...Array.from({ length: omitted }, () => 0),
    ...right.map((part) => Number.parseInt(part, 16)),
  ];
  return parts.length === 8 ? parts : null;
}

function isBlockedIPv6(parts: number[]) {
  const allZero = parts.every((part) => part === 0);
  const loopback =
    parts.slice(0, 7).every((part) => part === 0) && parts[7] === 1;
  const uniqueLocal = (parts[0] & 0xfe00) === 0xfc00;
  const linkLocal = (parts[0] & 0xffc0) === 0xfe80;
  const deprecatedSiteLocal = (parts[0] & 0xffc0) === 0xfec0;
  const multicast = (parts[0] & 0xff00) === 0xff00;
  const documentation = parts[0] === 0x2001 && parts[1] === 0x0db8;
  const discardOnly =
    parts[0] === 0x0100 &&
    parts[1] === 0 &&
    parts[2] === 0 &&
    parts[3] === 0;
  const orchid =
    parts[0] === 0x2001 &&
    ((parts[1] & 0xfff0) === 0x0010 || (parts[1] & 0xfff0) === 0x0020);
  const teredo = parts[0] === 0x2001 && parts[1] === 0;

  const firstSixZero = parts.slice(0, 6).every((part) => part === 0);
  const mappedIPv4 =
    parts.slice(0, 5).every((part) => part === 0) && parts[5] === 0xffff;
  if (firstSixZero || mappedIPv4) {
    const embedded = [
      parts[6] >> 8,
      parts[6] & 0xff,
      parts[7] >> 8,
      parts[7] & 0xff,
    ];
    return mappedIPv4 ? isBlockedIPv4(embedded) : true;
  }

  const sixToFour = parts[0] === 0x2002;
  if (sixToFour) {
    const embedded = [
      parts[1] >> 8,
      parts[1] & 0xff,
      parts[2] >> 8,
      parts[2] & 0xff,
    ];
    if (isBlockedIPv4(embedded)) return true;
  }

  return (
    allZero ||
    loopback ||
    uniqueLocal ||
    linkLocal ||
    deprecatedSiteLocal ||
    multicast ||
    documentation ||
    discardOnly ||
    orchid ||
    teredo
  );
}

function hasCredentialFragment(hash: string) {
  if (!hash) return false;
  let fragment = hash;
  try {
    fragment = decodeURIComponent(hash);
  } catch {
    return true;
  }
  return /(?:^|[?&#;,])(?:access[_-]?token|token|api[_-]?key|password|secret|authorization|cookie)=/i
    .test(fragment) ||
    /\b(?:Bearer|Basic)\s+[A-Za-z0-9._~+/=-]{8,}/i.test(fragment);
}

/**
 * Performs all checks possible without network access. A hostname result with
 * `requiresDnsResolution: true` is not authorization to connect; the caller
 * must still resolve, reject mixed/non-global answers, pin, and repeat on every
 * redirect.
 */
export function checkPublicHttpsLiteralHost(
  input: string,
): PublicHttpsLiteralCheck {
  if (typeof input !== "string" || /\s/.test(input)) {
    return { ok: false, reason: "invalid_url" };
  }

  let parsed: URL;
  try {
    parsed = new URL(input);
  } catch {
    return { ok: false, reason: "invalid_url" };
  }
  if (parsed.protocol !== "https:") {
    return { ok: false, reason: "https_required" };
  }
  if (parsed.username || parsed.password) {
    return { ok: false, reason: "user_info_forbidden" };
  }
  if (hasCredentialFragment(parsed.hash)) {
    return { ok: false, reason: "credential_fragment_forbidden" };
  }
  if (parsed.port && parsed.port !== "443") {
    return { ok: false, reason: "unsupported_port" };
  }

  let hostname = parsed.hostname.toLowerCase();
  if (hostname.endsWith(".")) hostname = hostname.slice(0, -1);
  if (!hostname || hostname.length > 253) {
    return { ok: false, reason: "invalid_hostname" };
  }

  const ipv4 = parseIPv4(hostname);
  if (ipv4) {
    return isBlockedIPv4(ipv4)
      ? { ok: false, reason: "non_global_ip_forbidden" }
      : {
          ok: true,
          canonicalUrl: parsed.toString(),
          hostname,
          requiresDnsResolution: false,
        };
  }

  const ipv6 = parseIPv6(hostname);
  if (ipv6) {
    return isBlockedIPv6(ipv6)
      ? { ok: false, reason: "non_global_ip_forbidden" }
      : {
          ok: true,
          canonicalUrl: parsed.toString(),
          hostname,
          requiresDnsResolution: false,
        };
  }
  if (hostname.includes(":")) {
    return { ok: false, reason: "invalid_hostname" };
  }

  const labels = hostname.split(".");
  if (
    labels.length < 2 ||
    hostname === "localhost" ||
    hostname.endsWith(".localhost") ||
    hostname.endsWith(".local") ||
    hostname.endsWith(".internal")
  ) {
    return { ok: false, reason: "local_hostname_forbidden" };
  }
  if (
    labels.some(
      (label) =>
        !/^[a-z0-9-]{1,63}$/.test(label) ||
        label.startsWith("-") ||
        label.endsWith("-") ||
        (label.startsWith("xn--") && label.length <= 4),
    )
  ) {
    return { ok: false, reason: "invalid_hostname" };
  }

  return {
    ok: true,
    canonicalUrl: parsed.toString(),
    hostname,
    requiresDnsResolution: true,
  };
}

export function assertPublicHttpsLiteralHost(input: string): void {
  const result = checkPublicHttpsLiteralHost(input);
  if (!result.ok) {
    throw new Error(`Unsafe public HTTPS destination: ${result.reason}`);
  }
}

export function normalizeShareCode(input: string): string | null {
  const normalized = input.trim().toUpperCase();
  return SHARE_CODE_PATTERN.test(normalized) ? normalized : null;
}

export function isValidShareCode(input: string) {
  return normalizeShareCode(input) !== null;
}

export type RandomBytes = (length: number) => Uint8Array;

function cryptographicRandomBytes(length: number) {
  if (!globalThis.crypto?.getRandomValues) {
    throw new Error("Cryptographically secure randomness is unavailable");
  }
  return globalThis.crypto.getRandomValues(new Uint8Array(length));
}

export function generateShareCode(
  randomBytes: RandomBytes = cryptographicRandomBytes,
) {
  const bytes = randomBytes(8);
  if (!(bytes instanceof Uint8Array) || bytes.byteLength !== 8) {
    throw new Error("Share-code random source must return exactly 8 bytes");
  }
  let payload = "";
  for (const byte of bytes) {
    payload += SHARE_CODE_ALPHABET[byte & 31];
  }
  return `SIG1-${payload}`;
}
