import {
  ProfileStoreUnavailableError,
  revokeSharedProfile,
} from "../../../../../../lib/profile-store";
import {
  apiError,
  getClientIp,
  getRequestId,
  jsonResponse,
  rateLimitHeaders,
  takeRateLimit,
} from "../../../../../../lib/rate-limit";

const REVOKE_LIMIT = 10;
const REVOKE_WINDOW_MS = 60_000;
const MAX_REVOKE_BODY_BYTES = 4 * 1024;

type RouteContext = {
  params: Promise<{ shareCode: string }> | { shareCode: string };
};

async function readRevokeToken(request: Request): Promise<string | null> {
  const headerToken = request.headers.get("x-revoke-token")?.trim();
  if (headerToken) return headerToken;

  const contentType = request.headers.get("content-type")?.toLowerCase() ?? "";
  if (!contentType.startsWith("application/json")) return null;

  const declaredLength = Number(request.headers.get("content-length"));
  if (
    Number.isFinite(declaredLength) &&
    declaredLength > MAX_REVOKE_BODY_BYTES
  ) {
    return null;
  }

  try {
    const serialized = await request.text();
    if (
      new TextEncoder().encode(serialized).byteLength > MAX_REVOKE_BODY_BYTES
    ) {
      return null;
    }
    const payload = JSON.parse(serialized) as unknown;
    if (
      !payload ||
      typeof payload !== "object" ||
      Array.isArray(payload) ||
      Object.keys(payload).length !== 1 ||
      !("revokeToken" in payload) ||
      typeof payload.revokeToken !== "string"
    ) {
      return null;
    }
    return payload.revokeToken;
  } catch {
    return null;
  }
}

export async function POST(request: Request, context: RouteContext) {
  const requestId = getRequestId(request);
  const rateLimit = takeRateLimit(
    `profiles:revoke:${getClientIp(request)}`,
    { limit: REVOKE_LIMIT, windowMs: REVOKE_WINDOW_MS },
  );
  const limitHeaders = rateLimitHeaders(rateLimit);
  if (!rateLimit.allowed) {
    return apiError(
      "rate_limited",
      "Too many profile revocation requests.",
      429,
      requestId,
      limitHeaders,
    );
  }

  const { shareCode } = await context.params;
  const revokeToken = await readRevokeToken(request);
  if (!revokeToken) {
    return apiError(
      "profile_not_found",
      "Profile not found.",
      404,
      requestId,
      limitHeaders,
    );
  }

  try {
    const revoked = await revokeSharedProfile(shareCode, revokeToken);
    if (!revoked) {
      return apiError(
        "profile_not_found",
        "Profile not found.",
        404,
        requestId,
        limitHeaders,
      );
    }
    return jsonResponse(
      { schemaVersion: 1, revoked: true },
      requestId,
      { status: 200, headers: limitHeaders },
    );
  } catch (error) {
    if (error instanceof ProfileStoreUnavailableError) {
      return apiError(
        "storage_unavailable",
        "Profile storage is temporarily unavailable.",
        503,
        requestId,
        limitHeaders,
      );
    }
    return apiError(
      "storage_unavailable",
      "Profile storage is temporarily unavailable.",
      503,
      requestId,
      limitHeaders,
    );
  }
}
