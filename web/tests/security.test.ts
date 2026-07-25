import { describe, expect, it } from "vitest";

import {
  REDACTED_VALUE,
  checkPublicHttpsLiteralHost,
  containsSecretMaterial,
  findSecretMaterial,
  generateShareCode,
  isValidShareCode,
  normalizeShareCode,
  sanitizeSecrets,
} from "../lib/security";

describe("secret detection and sanitization", () => {
  it("finds forbidden fields recursively without returning values", () => {
    const payload = {
      profile: {
        metadata: [
          { api_key: "do-not-log-this" },
          { "client-secret": "also-do-not-log-this" },
        ],
      },
    };
    const findings = findSecretMaterial(payload);
    expect(findings).toContainEqual({
      path: ["profile", "metadata", 0, "api_key"],
      kind: "raw-secret field",
    });
    expect(findings).toContainEqual({
      path: ["profile", "metadata", 1, "client-secret"],
      kind: "raw-secret field",
    });
    expect(JSON.stringify(findings)).not.toContain("do-not-log-this");
  });

  it.each([
    "Bearer a-very-secret-bearer-token",
    "https://discord.com/api/webhooks/123456789/a-secret-webhook-token",
    "https://example.com/callback?access_token=a-secret-value",
    "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signature123",
    "-----BEGIN PRIVATE KEY-----\nsecret\n-----END PRIVATE KEY-----",
    "https://user:password@example.com/",
  ])("detects credential-like string material: %s", (value) => {
    expect(containsSecretMaterial({ value })).toBe(true);
  });

  it("does not mistake typed references or placeholders for values", () => {
    expect(
      containsSecretMaterial({
        secretRefs: ["service-credential"],
        bodyTemplate: '{"token":"${secret:service-credential}"}',
        provider: "http_api_key",
      }),
    ).toBe(false);
  });

  it("returns a detached redacted structure without mutating input", () => {
    const source = {
      authorization: "Bearer a-very-secret-bearer-token",
      nested: {
        url: "https://example.com/?token=secret-value",
      },
    };
    const sanitized = sanitizeSecrets(source) as typeof source;
    expect(sanitized.authorization).toBe(REDACTED_VALUE);
    expect(sanitized.nested.url).toContain(REDACTED_VALUE);
    expect(sanitized.nested.url).not.toContain("secret-value");
    expect(source.authorization).toContain("a-very-secret");
  });

  it("redacts truncated private-key material rather than only detecting it", () => {
    expect(
      sanitizeSecrets("-----BEGIN PRIVATE KEY-----\ntruncated") as string,
    ).toBe(REDACTED_VALUE);
  });
});

describe("public HTTPS literal-host checks", () => {
  it.each([
    "http://example.com/",
    "https://localhost/",
    "https://LOCALHOST./",
    "https://service.internal/",
    "https://printer.local/",
    "https://single-label/",
    "https://127.0.0.1/",
    "https://127.1/",
    "https://0x7f000001/",
    "https://10.1.2.3/",
    "https://100.64.0.1/",
    "https://169.254.169.254/latest/meta-data/",
    "https://192.0.2.1/",
    "https://198.51.100.2/",
    "https://203.0.113.3/",
    "https://224.0.0.1/",
    "https://[::1]/",
    "https://[fc00::1]/",
    "https://[fe80::1]/",
    "https://[2001:db8::1]/",
    "https://[::ffff:127.0.0.1]/",
    "https://user:password@example.com/",
    "https://example.com:8443/",
    "https://example.com/#access_token=secret",
  ])("rejects unsafe destinations: %s", (url) => {
    expect(checkPublicHttpsLiteralHost(url).ok).toBe(false);
  });

  it("distinguishes public literal IPs from hostnames requiring DNS checks", () => {
    expect(checkPublicHttpsLiteralHost("https://8.8.8.8/")).toMatchObject({
      ok: true,
      requiresDnsResolution: false,
    });
    expect(checkPublicHttpsLiteralHost("https://Example.COM./path")).toMatchObject(
      {
        ok: true,
        hostname: "example.com",
        requiresDnsResolution: true,
      },
    );
  });

  it("does not present hostname syntax validation as DNS authorization", () => {
    const result = checkPublicHttpsLiteralHost("https://public.example/");
    expect(result).toMatchObject({
      ok: true,
      requiresDnsResolution: true,
    });
  });
});

describe("share-code helpers", () => {
  it("normalizes case while preserving the frozen alphabet", () => {
    expect(normalizeShareCode(" sig1-h7k3m9q2 ")).toBe("SIG1-H7K3M9Q2");
    expect(isValidShareCode("SIG1-H7K3M9Q2")).toBe(true);
    expect(normalizeShareCode("SIG1-H7K3M9O2")).toBeNull();
    expect(normalizeShareCode("SIG1-H7K3M9Q0")).toBeNull();
  });

  it("maps exactly 40 random bits into the eight-symbol payload", () => {
    const code = generateShareCode(
      () => new Uint8Array([0, 1, 2, 3, 4, 5, 30, 31]),
    );
    expect(code).toBe("SIG1-ABCDEF89");
    expect(isValidShareCode(code)).toBe(true);
  });

  it("rejects random sources with the wrong byte count", () => {
    expect(() => generateShareCode(() => new Uint8Array(7))).toThrow(
      /exactly 8 bytes/,
    );
  });
});
