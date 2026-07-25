import { profileCreateRequestSchema } from "../../../../lib/contracts";
import {
  createSharedProfile,
  ProfileStoreUnavailableError,
} from "../../../../lib/profile-store";
import {
  apiError,
  getClientIp,
  getRequestId,
  jsonResponse,
  rateLimitHeaders,
  takeRateLimit,
} from "../../../../lib/rate-limit";

const MAX_PROFILE_REQUEST_BYTES = 256 * 1024;
const CREATE_LIMIT = 10;
const CREATE_WINDOW_MS = 60_000;

function byteLength(value: string) {
  return new TextEncoder().encode(value).byteLength;
}

function publicProfileUrl(request: Request, shareCode: string): string {
  const configuredOrigin = process.env.NEXT_PUBLIC_SITE_URL?.trim();
  const origin = new URL(configuredOrigin || request.url);
  if (
    process.env.NODE_ENV === "production" &&
    origin.protocol !== "https:"
  ) {
    throw new ProfileStoreUnavailableError();
  }
  return new URL(`/p/${shareCode}`, origin.origin).toString();
}

export async function POST(request: Request) {
  const requestId = getRequestId(request);
  const rateLimit = takeRateLimit(
    `profiles:create:${getClientIp(request)}`,
    { limit: CREATE_LIMIT, windowMs: CREATE_WINDOW_MS },
  );
  const limitHeaders = rateLimitHeaders(rateLimit);
  if (!rateLimit.allowed) {
    return apiError(
      "rate_limited",
      "Too many profile creation requests.",
      429,
      requestId,
      limitHeaders,
    );
  }

  const contentType = request.headers.get("content-type")?.toLowerCase() ?? "";
  if (!contentType.startsWith("application/json")) {
    return apiError(
      "unsupported_media_type",
      "Content-Type must be application/json.",
      415,
      requestId,
      limitHeaders,
    );
  }

  const declaredLength = Number(request.headers.get("content-length"));
  if (
    Number.isFinite(declaredLength) &&
    declaredLength > MAX_PROFILE_REQUEST_BYTES
  ) {
    return apiError(
      "payload_too_large",
      "Profile request body is too large.",
      413,
      requestId,
      limitHeaders,
    );
  }

  let serialized: string;
  try {
    serialized = await request.text();
  } catch {
    return apiError(
      "invalid_json",
      "Request body must be valid JSON.",
      400,
      requestId,
      limitHeaders,
    );
  }
  if (byteLength(serialized) > MAX_PROFILE_REQUEST_BYTES) {
    return apiError(
      "payload_too_large",
      "Profile request body is too large.",
      413,
      requestId,
      limitHeaders,
    );
  }

  let payload: unknown;
  try {
    payload = JSON.parse(serialized);
  } catch {
    return apiError(
      "invalid_json",
      "Request body must be valid JSON.",
      400,
      requestId,
      limitHeaders,
    );
  }

  const parsed = profileCreateRequestSchema.safeParse(payload);
  if (
    !parsed.success ||
    parsed.data.profile.share.visibility !== "unlisted" ||
    parsed.data.profile.share.shareCode !== undefined
  ) {
    return apiError(
      "invalid_profile",
      "Profile must be a strict unlisted schema-version 1 profile without a client-supplied share code or secret values.",
      400,
      requestId,
      limitHeaders,
    );
  }

  try {
    const created = await createSharedProfile(parsed.data.profile);
    const profileURL = publicProfileUrl(request, created.shareCode);
    return jsonResponse(
      {
        schemaVersion: 1,
        shareCode: created.shareCode,
        profileURL,
        revokeToken: created.revokeToken,
      },
      requestId,
      {
        status: 201,
        headers: new Headers({
          ...Object.fromEntries(limitHeaders),
          location: profileURL,
        }),
      },
    );
  } catch (error) {
    if (
      error instanceof ProfileStoreUnavailableError ||
      error instanceof TypeError
    ) {
      return apiError(
        error instanceof TypeError
          ? "invalid_profile"
          : "storage_unavailable",
        error instanceof TypeError
          ? "Profile cannot be shared."
          : "Profile storage is temporarily unavailable.",
        error instanceof TypeError ? 400 : 503,
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
