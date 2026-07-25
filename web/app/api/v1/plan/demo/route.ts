import { z } from "zod";

import {
  actionTypeSchema,
  gestureSchema,
  plannerRequestSchema,
  requestIdSchema,
} from "../../../../../lib/contracts";
import { isBrowserSafeActionType } from "../../../../../lib/commands/browser-actions";
import {
  createPlannerResponse,
  rejectUnsafePlannerInstruction,
} from "../../../../../lib/planner";
import {
  apiError,
  getClientIp,
  getRequestId,
  jsonResponse,
  rateLimitHeaders,
  takeRateLimit,
} from "../../../../../lib/rate-limit";

export const runtime = "edge";

const MAX_DEMO_BODY_BYTES = 6 * 1024 * 1024;

const keyframeSchema = z
  .object({
    dataUrl: z
      .string()
      .max(600_000)
      .regex(/^data:image\/(?:jpeg|png|gif|webp);base64,[A-Za-z0-9+/=]+$/),
    timestampMs: z.number().int().min(0).max(60_000),
    width: z.number().int().min(1).max(1024),
    height: z.number().int().min(1).max(1024),
  })
  .strict();

const demoRequestSchema = z
  .object({
    schemaVersion: z.literal(1),
    requestId: requestIdSchema,
    request: z.string().min(1).max(4000),
    targetGesture: gestureSchema,
    actionCatalog: z
      .array(actionTypeSchema)
      .max(32)
      .refine((values) => new Set(values).size === values.length),
    recording: z
      .object({
        durationMs: z.number().int().min(1).max(60_000),
        mimeType: z.string().min(1).max(120).regex(/^video\//),
        sizeBytes: z.number().int().min(1).max(40 * 1024 * 1024),
        keyframes: z.array(keyframeSchema).min(6).max(10),
      })
      .strict(),
  })
  .strict();

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
  const rateLimit = takeRateLimit(`plan-demo:${getClientIp(request)}`, {
    limit: 6,
    windowMs: 60_000,
  });
  const headers = rateLimitHeaders(rateLimit);
  if (!rateLimit.allowed) {
    return apiError(
      "rate_limited",
      "Teach by Demo planning limit exceeded.",
      429,
      requestId,
      headers,
    );
  }

  const raw = await request.text();
  if (new TextEncoder().encode(raw).byteLength > MAX_DEMO_BODY_BYTES) {
    return apiError(
      "payload_too_large",
      "Demo planning context may be at most 6 MiB.",
      413,
      requestId,
      headers,
    );
  }

  let candidate: unknown;
  try {
    candidate = JSON.parse(raw);
  } catch {
    return apiError("invalid_json", "Malformed JSON.", 400, requestId, headers);
  }
  const parsed = demoRequestSchema.safeParse(candidate);
  if (!parsed.success) {
    return apiError(
      "invalid_request",
      "Recording metadata or compressed keyframes are invalid.",
      422,
      requestId,
      headers,
    );
  }
  requestId = parsed.data.requestId;
  if (parsed.data.actionCatalog.some((type) => !isBrowserSafeActionType(type))) {
    return apiError(
      "unsupported_action_catalog",
      "Signal only accepts browser-safe action types.",
      422,
      requestId,
      headers,
    );
  }
  const plannerRequest = plannerRequestSchema.safeParse({
    schemaVersion: parsed.data.schemaVersion,
    requestId,
    request: parsed.data.request,
    targetGesture: parsed.data.targetGesture,
    actionCatalog: parsed.data.actionCatalog,
  });
  if (!plannerRequest.success) {
    return apiError(
      "invalid_request",
      "Description does not match the planner contract.",
      422,
      requestId,
      headers,
    );
  }
  if (rejectUnsafePlannerInstruction(plannerRequest.data.request)) {
    return apiError(
      "unsafe_instruction",
      "Signal cannot generate plans that expose secrets or bypass the safe action catalog.",
      422,
      requestId,
      headers,
    );
  }

  const response = await createPlannerResponse(
    plannerRequest.data,
    parsed.data.recording.keyframes.map((frame) => frame.dataUrl),
  );
  return jsonResponse(response, requestId, { status: 200, headers });
}
