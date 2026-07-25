import {
  hasValidPlannerRequestByteLength,
  plannerRequestSchema,
} from "../../../../lib/contracts";
import {
  createPlannerResponse,
  rejectUnsafePlannerInstruction,
} from "../../../../lib/planner";
import {
  apiError,
  getClientIp,
  getRequestId,
  jsonResponse,
  rateLimitHeaders,
  takeRateLimit,
} from "../../../../lib/rate-limit";

export const runtime = "edge";

export async function POST(request: Request) {
  let requestId = getRequestId(request);
  if (!request.headers.get("content-type")?.toLowerCase().includes("application/json")) {
    return apiError(
      "unsupported_media_type",
      "Use application/json.",
      415,
      requestId,
    );
  }

  const limit = takeRateLimit(`plan:${getClientIp(request)}`, {
    limit: 20,
    windowMs: 60_000,
  });
  const limitHeaders = rateLimitHeaders(limit);
  if (!limit.allowed) {
    return apiError(
      "rate_limited",
      "Planner request limit exceeded.",
      429,
      requestId,
      limitHeaders,
    );
  }

  const serialized = await request.text();
  if (!hasValidPlannerRequestByteLength(serialized)) {
    return apiError(
      "payload_too_large",
      "Planner requests may be at most 16 KiB.",
      413,
      requestId,
      limitHeaders,
    );
  }

  let candidate: unknown;
  try {
    candidate = JSON.parse(serialized);
  } catch {
    return apiError("invalid_json", "Malformed JSON.", 400, requestId, limitHeaders);
  }

  if (
    typeof candidate === "object" &&
    candidate !== null &&
    "schemaVersion" in candidate &&
    (candidate as { schemaVersion?: unknown }).schemaVersion !== 1
  ) {
    return apiError(
      "unsupported_schema_version",
      "Only schema version 1 is supported.",
      422,
      requestId,
      limitHeaders,
    );
  }

  const parsed = plannerRequestSchema.safeParse(candidate);
  if (!parsed.success) {
    return apiError(
      "invalid_request",
      "Request does not match the Signal planner contract.",
      422,
      requestId,
      limitHeaders,
    );
  }
  requestId = parsed.data.requestId;

  if (rejectUnsafePlannerInstruction(parsed.data.request)) {
    return apiError(
      "unsafe_instruction",
      "Signal cannot generate plans that expose secrets or bypass the safe action catalog.",
      422,
      requestId,
      limitHeaders,
    );
  }

  const response = await createPlannerResponse(parsed.data);
  return jsonResponse(response, requestId, {
    status: 200,
    headers: limitHeaders,
  });
}
