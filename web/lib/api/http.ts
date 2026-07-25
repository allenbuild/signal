import { SCHEMA_VERSION, type ApiErrorBody } from "./types";

const DEFAULT_LIMIT = 24 * 1024;
const RATE_WINDOW_MS = 60_000;
const RATE_LIMIT = 40;
const rateBuckets = new Map<string, { count: number; resetAt: number }>();

function corsOrigin(request: Request): string | null {
  const origin = request.headers.get("origin");
  if (!origin) return null;

  const requestOrigin = new URL(request.url).origin;
  const configured = (process.env.SIGNAL_ALLOWED_ORIGINS ?? "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);

  return origin === requestOrigin || configured.includes(origin) ? origin : null;
}

export function corsHeaders(request: Request): Headers {
  const headers = new Headers({
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  });
  const origin = corsOrigin(request);
  if (origin) headers.set("Access-Control-Allow-Origin", origin);
  return headers;
}

export function preflight(request: Request): Response {
  const origin = request.headers.get("origin");
  if (origin && !corsOrigin(request)) {
    return apiError(request, 403, "origin_not_allowed", "This origin is not allowed.");
  }
  return new Response(null, { status: 204, headers: corsHeaders(request) });
}

export function json(request: Request, body: unknown, init: ResponseInit = {}): Response {
  const headers = new Headers(init.headers);
  headers.set("content-type", "application/json; charset=utf-8");
  headers.set("cache-control", "no-store");
  for (const [key, value] of corsHeaders(request)) headers.set(key, value);
  return new Response(JSON.stringify(body), { ...init, headers });
}

export function apiError(
  request: Request,
  status: number,
  code: string,
  message: string,
  fields?: string[],
): Response {
  const body: ApiErrorBody = {
    schemaVersion: SCHEMA_VERSION,
    error: { code, message, ...(fields?.length ? { fields } : {}) },
  };
  return json(request, body, { status });
}

export function rejectDisallowedOrigin(request: Request): Response | null {
  const origin = request.headers.get("origin");
  return origin && !corsOrigin(request)
    ? apiError(request, 403, "origin_not_allowed", "This origin is not allowed.")
    : null;
}

export function enforceRateLimit(request: Request, scope: string): Response | null {
  const now = Date.now();
  const forwarded = request.headers.get("cf-connecting-ip") ??
    request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
    "local";
  const key = `${scope}:${forwarded}`;
  const current = rateBuckets.get(key);
  const bucket = !current || current.resetAt <= now
    ? { count: 0, resetAt: now + RATE_WINDOW_MS }
    : current;
  bucket.count += 1;
  rateBuckets.set(key, bucket);

  if (rateBuckets.size > 2_000) {
    for (const [bucketKey, value] of rateBuckets) {
      if (value.resetAt <= now) rateBuckets.delete(bucketKey);
    }
  }

  if (bucket.count > RATE_LIMIT) {
    const response = apiError(
      request,
      429,
      "rate_limited",
      "Too many requests. Try again shortly.",
    );
    response.headers.set("retry-after", String(Math.ceil((bucket.resetAt - now) / 1_000)));
    return response;
  }
  return null;
}

export async function readJsonBody(
  request: Request,
  maxBytes = DEFAULT_LIMIT,
): Promise<{ ok: true; value: unknown } | { ok: false; response: Response }> {
  if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json")) {
    return {
      ok: false,
      response: apiError(
        request,
        415,
        "unsupported_media_type",
        "Content-Type must be application/json.",
      ),
    };
  }

  const declaredLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > maxBytes) {
    return {
      ok: false,
      response: apiError(request, 413, "request_too_large", "Request body is too large."),
    };
  }

  const body = await request.text();
  if (new TextEncoder().encode(body).byteLength > maxBytes) {
    return {
      ok: false,
      response: apiError(request, 413, "request_too_large", "Request body is too large."),
    };
  }

  try {
    return { ok: true, value: JSON.parse(body) };
  } catch {
    return {
      ok: false,
      response: apiError(request, 400, "invalid_json", "Request body is not valid JSON."),
    };
  }
}

export function isPlainObject(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

export function hasOnlyKeys(value: Record<string, unknown>, keys: string[]): boolean {
  const allowed = new Set(keys);
  return Object.keys(value).every((key) => allowed.has(key));
}

export function stableId(prefix: string, input: string): string {
  let hash = 2166136261;
  for (let index = 0; index < input.length; index += 1) {
    hash ^= input.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return `${prefix}_${(hash >>> 0).toString(36).padStart(7, "0")}`;
}
