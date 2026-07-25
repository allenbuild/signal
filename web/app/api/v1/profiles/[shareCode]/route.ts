import {
  ProfileStoreUnavailableError,
  readSharedProfile,
} from "../../../../../lib/profile-store";
import {
  apiError,
  getClientIp,
  getRequestId,
  jsonResponse,
  rateLimitHeaders,
  takeRateLimit,
} from "../../../../../lib/rate-limit";

const LOOKUP_LIMIT = 60;
const LOOKUP_WINDOW_MS = 60_000;

type RouteContext = {
  params: Promise<{ shareCode: string }> | { shareCode: string };
};

export async function GET(request: Request, context: RouteContext) {
  const requestId = getRequestId(request);
  const rateLimit = takeRateLimit(
    `profiles:read:${getClientIp(request)}`,
    { limit: LOOKUP_LIMIT, windowMs: LOOKUP_WINDOW_MS },
  );
  const limitHeaders = rateLimitHeaders(rateLimit);
  if (!rateLimit.allowed) {
    return apiError(
      "rate_limited",
      "Too many profile lookup requests.",
      429,
      requestId,
      limitHeaders,
    );
  }

  const { shareCode } = await context.params;
  try {
    const profile = await readSharedProfile(shareCode);
    if (!profile) {
      return apiError(
        "profile_not_found",
        "Profile not found.",
        404,
        requestId,
        limitHeaders,
      );
    }
    return jsonResponse(profile, requestId, {
      status: 200,
      headers: limitHeaders,
    });
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
