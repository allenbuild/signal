import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { GET as getHealth } from "../app/api/v1/health/route";
import { POST as createProfile } from "../app/api/v1/profiles/route";
import { GET as getProfile } from "../app/api/v1/profiles/[shareCode]/route";
import { POST as revokeProfile } from "../app/api/v1/profiles/[shareCode]/revoke/route";
import {
  ACTIVE_PROFILE_RETENTION_MS,
  REVOKED_PROFILE_RETENTION_MS,
  readSharedProfile,
  resetProfileStoreForTests,
} from "../lib/profile-store";
import { resetRateLimitsForTests } from "../lib/rate-limit";

type ErrorBody = { error: { code: string } };
type CreatedBody = {
  shareCode: string;
  revokeToken: string;
  profileURL: string;
  schemaVersion: 1;
};

async function responseJson<T>(response: Response): Promise<T> {
  return response.json() as Promise<T>;
}

const validProfile = {
  schemaVersion: 1,
  id: "signal.tests.focus",
  name: "Test focus profile",
  description: "A strict, portable test profile.",
  preferredMode: "commands",
  hybridOneBehavior: "pointer",
  mappings: [],
  share: {
    visibility: "unlisted",
  },
} as const;

function jsonRequest(url: string, body: unknown, headers?: HeadersInit) {
  return new Request(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "cf-connecting-ip": "203.0.113.40",
      ...headers,
    },
    body: JSON.stringify(body),
  });
}

async function createTestShare() {
  const response = await createProfile(
    jsonRequest("http://local.test/api/v1/profiles", {
      profile: validProfile,
    }),
  );
  expect(response.status).toBe(201);
  return (await response.json()) as {
    schemaVersion: number;
    shareCode: string;
    profileURL: string;
    revokeToken: string;
  };
}

beforeEach(() => {
  resetProfileStoreForTests();
  resetRateLimitsForTests();
});

afterEach(() => {
  vi.useRealTimers();
});

describe("profile sharing API", () => {
  it("creates an unlisted profile with server-generated capabilities", async () => {
    const response = await createProfile(
      jsonRequest(
        "http://local.test/api/v1/profiles",
        { profile: validProfile },
        { "x-request-id": "profile_create_test" },
      ),
    );
    const body = await responseJson<CreatedBody>(response);

    expect(response.status).toBe(201);
    expect(response.headers.get("x-request-id")).toBe("profile_create_test");
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(response.headers.get("x-content-type-options")).toBe("nosniff");
    expect(body).toMatchObject({
      schemaVersion: 1,
      profileURL: expect.stringContaining("/p/SIG1-"),
    });
    expect(body.shareCode).toMatch(
      /^SIG1-[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$/,
    );
    expect(body.revokeToken).toMatch(/^SRV1_[0-9a-f]{64}$/);
  });

  it("reads case-insensitively without returning the revoke token", async () => {
    const created = await createTestShare();
    const response = await getProfile(
      new Request(
        `http://local.test/api/v1/profiles/${created.shareCode.toLowerCase()}`,
        { headers: { "cf-connecting-ip": "203.0.113.41" } },
      ),
      { params: { shareCode: created.shareCode.toLowerCase() } },
    );
    const profile = await response.json();

    expect(response.status).toBe(200);
    expect(profile).toMatchObject({
      schemaVersion: 1,
      id: validProfile.id,
      share: {
        visibility: "unlisted",
        shareCode: created.shareCode,
      },
    });
    expect(JSON.stringify(profile)).not.toContain(created.revokeToken);
  });

  it("uses the same nondisclosing 404 for absent and unauthorized revocation", async () => {
    const created = await createTestShare();
    const wrongTokenResponse = await revokeProfile(
      jsonRequest(
        `http://local.test/api/v1/profiles/${created.shareCode}/revoke`,
        { revokeToken: "wrong" },
        { "cf-connecting-ip": "203.0.113.42" },
      ),
      { params: Promise.resolve({ shareCode: created.shareCode }) },
    );
    const absentResponse = await getProfile(
      new Request("http://local.test/api/v1/profiles/SIG1-ABCDEFGH", {
        headers: { "cf-connecting-ip": "203.0.113.43" },
      }),
      { params: { shareCode: "SIG1-ABCDEFGH" } },
    );

    expect(wrongTokenResponse.status).toBe(404);
    expect(absentResponse.status).toBe(404);
    expect((await responseJson<ErrorBody>(wrongTokenResponse)).error.code).toBe(
      "profile_not_found",
    );
    expect((await responseJson<ErrorBody>(absentResponse)).error.code).toBe("profile_not_found");
  });

  it("revokes with the create-only token and immediately hides the profile", async () => {
    const created = await createTestShare();
    const revoked = await revokeProfile(
      new Request(
        `http://local.test/api/v1/profiles/${created.shareCode}/revoke`,
        {
          method: "POST",
          headers: {
            "cf-connecting-ip": "203.0.113.44",
            "x-revoke-token": created.revokeToken,
          },
        },
      ),
      { params: { shareCode: created.shareCode } },
    );
    expect(revoked.status).toBe(200);
    expect(await revoked.json()).toEqual({
      schemaVersion: 1,
      revoked: true,
    });

    const readAfterRevoke = await getProfile(
      new Request(
        `http://local.test/api/v1/profiles/${created.shareCode}`,
        { headers: { "cf-connecting-ip": "203.0.113.45" } },
      ),
      { params: { shareCode: created.shareCode } },
    );
    expect(readAfterRevoke.status).toBe(404);
  });

  it("rejects unknown fields and client-chosen share codes", async () => {
    const unknownField = await createProfile(
      jsonRequest("http://local.test/api/v1/profiles", {
        profile: { ...validProfile, rawToken: "do-not-store" },
      }),
    );
    expect(unknownField.status).toBe(400);
    expect((await responseJson<ErrorBody>(unknownField)).error.code).toBe("invalid_profile");

    resetRateLimitsForTests();
    const clientCode = await createProfile(
      jsonRequest("http://local.test/api/v1/profiles", {
        profile: {
          ...validProfile,
          share: {
            visibility: "unlisted",
            shareCode: "SIG1-ABCDEFGH",
          },
        },
      }),
    );
    expect(clientCode.status).toBe(400);
    expect((await responseJson<ErrorBody>(clientCode)).error.code).toBe("invalid_profile");

    resetRateLimitsForTests();
    const rawSecret = await createProfile(
      jsonRequest("http://local.test/api/v1/profiles", {
        profile: {
          ...validProfile,
          description:
            "Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        },
      }),
    );
    expect(rawSecret.status).toBe(400);
    expect((await responseJson<ErrorBody>(rawSecret)).error.code).toBe("invalid_profile");
  });

  it("rejects profiles containing legacy native actions", async () => {
    const response = await createProfile(
      jsonRequest("http://local.test/api/v1/profiles", {
        profile: {
          ...validProfile,
          mappings: [
            {
              gesture: "fist",
              activation: "hold",
              holdDurationMs: 550,
              plan: {
                schemaVersion: 1,
                id: "legacy.native",
                name: "Legacy native command",
                description: "",
                steps: [
                  {
                    id: "step-1",
                    action: {
                      type: "open_application",
                      parameters: {
                        applicationName: "TextEdit",
                        bundleIdentifier: "com.apple.TextEdit",
                      },
                    },
                    timeoutMs: 5_000,
                    onFailure: "stop",
                    confirmation: { mode: "none", reason: "" },
                  },
                ],
                timeoutMs: 8_000,
                onFailure: "stop",
                confirmation: { mode: "none", reason: "" },
                createdSource: "import",
                secretReferences: [],
              },
            },
          ],
        },
      }),
    );
    expect(response.status).toBe(400);
    expect((await responseJson<ErrorBody>(response)).error.code).toBe(
      "invalid_profile",
    );
  });

  it("enforces the explicit 365-day active and 30-day revoked retention policy", async () => {
    expect(ACTIVE_PROFILE_RETENTION_MS).toBe(365 * 24 * 60 * 60 * 1000);
    expect(REVOKED_PROFILE_RETENTION_MS).toBe(30 * 24 * 60 * 60 * 1000);
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-01-01T00:00:00.000Z"));
    const created = await createTestShare();

    vi.setSystemTime(
      new Date(Date.now() + ACTIVE_PROFILE_RETENTION_MS + 1),
    );
    await expect(readSharedProfile(created.shareCode)).resolves.toBeNull();
  });
});

describe("health API", () => {
  it("returns deterministic non-secret state with security headers", async () => {
    const first = getHealth(new Request("http://local.test/api/v1/health"));
    const second = getHealth(new Request("http://local.test/api/v1/health"));

    expect(await first.json()).toEqual(await second.json());
    expect(first.headers.get("cache-control")).toBe("no-store");
    expect(first.headers.get("x-request-id")).toBeTruthy();
    expect(first.status).toBe(200);
  });
});
