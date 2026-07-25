const DEFAULT_WINDOW_MS = 60_000;
const MAX_BUCKETS = 20_000;

type Bucket = {
  count: number;
  resetAt: number;
};

export type RateLimitOptions = {
  limit: number;
  windowMs?: number;
  now?: number;
};

export type RateLimitResult = {
  allowed: boolean;
  limit: number;
  remaining: number;
  resetAt: number;
  retryAfterSeconds: number;
};

export type ApiErrorCode =
  | "integration_failed"
  | "integration_unavailable"
  | "invalid_json"
  | "invalid_profile"
  | "invalid_request"
  | "payload_too_large"
  | "planner_timeout"
  | "planner_unavailable"
  | "profile_not_found"
  | "rate_limited"
  | "storage_unavailable"
  | "unsafe_instruction"
  | "unsupported_action_catalog"
  | "unsupported_schema_version"
  | "unsupported_media_type";

const buckets = new Map<string, Bucket>();

function pruneExpiredBuckets(now: number) {
  if (buckets.size < MAX_BUCKETS) return;

  for (const [key, bucket] of buckets) {
    if (bucket.resetAt <= now) buckets.delete(key);
  }

  if (buckets.size < MAX_BUCKETS) return;

  const overflow = buckets.size - MAX_BUCKETS + 1;
  let removed = 0;
  for (const key of buckets.keys()) {
    buckets.delete(key);
    removed += 1;
    if (removed >= overflow) break;
  }
}

export function takeRateLimit(
  key: string,
  { limit, windowMs = DEFAULT_WINDOW_MS, now = Date.now() }: RateLimitOptions,
): RateLimitResult {
  if (!Number.isSafeInteger(limit) || limit < 1) {
    throw new TypeError("Rate-limit limit must be a positive integer.");
  }
  if (!Number.isSafeInteger(windowMs) || windowMs < 1) {
    throw new TypeError("Rate-limit window must be a positive integer.");
  }

  pruneExpiredBuckets(now);

  const current = buckets.get(key);
  const bucket =
    !current || current.resetAt <= now
      ? { count: 0, resetAt: now + windowMs }
      : current;

  bucket.count += 1;
  buckets.set(key, bucket);

  const allowed = bucket.count <= limit;
  return {
    allowed,
    limit,
    remaining: Math.max(0, limit - bucket.count),
    resetAt: bucket.resetAt,
    retryAfterSeconds: allowed
      ? 0
      : Math.max(1, Math.ceil((bucket.resetAt - now) / 1_000)),
  };
}

export function getClientIp(request: Request): string {
  const candidate =
    request.headers.get("cf-connecting-ip") ??
    request.headers.get("x-forwarded-for")?.split(",", 1)[0] ??
    request.headers.get("x-real-ip") ??
    "unknown";

  const normalized = candidate.trim().toLowerCase();
  return normalized && normalized.length <= 128 ? normalized : "unknown";
}

export function getRequestId(request?: Request): string {
  const supplied = request?.headers.get("x-request-id")?.trim();
  if (supplied && /^[A-Za-z0-9._:-]{8,128}$/.test(supplied)) {
    return supplied;
  }
  return crypto.randomUUID();
}

export function apiHeaders(
  requestId: string,
  extra?: HeadersInit,
): Headers {
  const headers = new Headers(extra);
  headers.set("cache-control", "no-store");
  headers.set("content-type", "application/json; charset=utf-8");
  headers.set("content-security-policy", "default-src 'none'; frame-ancestors 'none'");
  headers.set("permissions-policy", "camera=(), microphone=(), geolocation=()");
  headers.set("referrer-policy", "no-referrer");
  headers.set("strict-transport-security", "max-age=31536000; includeSubDomains");
  headers.set("x-content-type-options", "nosniff");
  headers.set("x-frame-options", "DENY");
  headers.set("x-request-id", requestId);
  return headers;
}

export function jsonResponse(
  body: unknown,
  requestId: string,
  init: Omit<ResponseInit, "headers"> & { headers?: HeadersInit } = {},
): Response {
  return Response.json(body, {
    ...init,
    headers: apiHeaders(requestId, init.headers),
  });
}

export function apiError(
  code: ApiErrorCode,
  message: string,
  status: number,
  requestId: string,
  headers?: HeadersInit,
): Response {
  return jsonResponse(
    { error: { code, message, requestId } },
    requestId,
    { status, headers },
  );
}

export function rateLimitHeaders(result: RateLimitResult): Headers {
  const headers = new Headers({
    "ratelimit-limit": String(result.limit),
    "ratelimit-remaining": String(result.remaining),
    "ratelimit-reset": String(Math.ceil(result.resetAt / 1_000)),
  });
  if (!result.allowed) {
    headers.set("retry-after", String(result.retryAfterSeconds));
  }
  return headers;
}

export function resetRateLimitsForTests() {
  buckets.clear();
}
