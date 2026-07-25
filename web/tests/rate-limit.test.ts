import { afterEach, describe, expect, it } from "vitest";

import {
  getClientIp,
  getRequestId,
  resetRateLimitsForTests,
  takeRateLimit,
} from "../lib/rate-limit";

afterEach(() => {
  resetRateLimitsForTests();
});

describe("takeRateLimit", () => {
  it("allows the configured count and then returns a stable retry window", () => {
    const first = takeRateLimit("lookup:203.0.113.4", {
      limit: 2,
      windowMs: 10_000,
      now: 1_000,
    });
    const second = takeRateLimit("lookup:203.0.113.4", {
      limit: 2,
      windowMs: 10_000,
      now: 2_000,
    });
    const denied = takeRateLimit("lookup:203.0.113.4", {
      limit: 2,
      windowMs: 10_000,
      now: 2_500,
    });

    expect(first).toMatchObject({ allowed: true, remaining: 1 });
    expect(second).toMatchObject({ allowed: true, remaining: 0 });
    expect(denied).toMatchObject({
      allowed: false,
      remaining: 0,
      resetAt: 11_000,
      retryAfterSeconds: 9,
    });
  });

  it("isolates keys and starts a fresh bucket after reset", () => {
    takeRateLimit("create:first", { limit: 1, windowMs: 100, now: 0 });
    expect(
      takeRateLimit("create:first", { limit: 1, windowMs: 100, now: 1 }),
    ).toMatchObject({ allowed: false });
    expect(
      takeRateLimit("create:second", { limit: 1, windowMs: 100, now: 1 }),
    ).toMatchObject({ allowed: true });
    expect(
      takeRateLimit("create:first", { limit: 1, windowMs: 100, now: 100 }),
    ).toMatchObject({ allowed: true, remaining: 0 });
  });
});

describe("request identity helpers", () => {
  it("prefers the Cloudflare client address and never returns a long value", () => {
    const request = new Request("https://signal.example", {
      headers: {
        "cf-connecting-ip": " 2001:DB8::1 ",
        "x-forwarded-for": "198.51.100.2, 198.51.100.3",
      },
    });
    expect(getClientIp(request)).toBe("2001:db8::1");

    const longRequest = new Request("https://signal.example", {
      headers: { "cf-connecting-ip": "a".repeat(129) },
    });
    expect(getClientIp(longRequest)).toBe("unknown");
  });

  it("accepts only a bounded safe caller request ID", () => {
    const supplied = new Request("https://signal.example", {
      headers: { "x-request-id": "request_test-123" },
    });
    expect(getRequestId(supplied)).toBe("request_test-123");

    const rejected = new Request("https://signal.example", {
      headers: { "x-request-id": "bad id" },
    });
    expect(getRequestId(rejected)).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
    );
  });
});
