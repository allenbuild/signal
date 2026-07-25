import { z } from "zod";

import { actionSchema, requestIdSchema } from "../../../../../lib/contracts";
import {
  apiError,
  getClientIp,
  getRequestId,
  jsonResponse,
  rateLimitHeaders,
  takeRateLimit,
} from "../../../../../lib/rate-limit";

export const runtime = "edge";

const requestSchema = z
  .object({
    schemaVersion: z.literal(1),
    requestId: requestIdSchema,
    approved: z.literal(true),
    action: actionSchema.refine(
      (action) => action.type === "discord_webhook",
      "A Discord webhook action is required.",
    ),
  })
  .strict();

function configuredWebhook(): string | null {
  const candidate = process.env.DISCORD_WEBHOOK_URL?.trim();
  if (!candidate) return null;
  try {
    const parsed = new URL(candidate);
    const validHost =
      parsed.hostname === "discord.com" || parsed.hostname === "discordapp.com";
    return parsed.protocol === "https:" &&
      validHost &&
      parsed.pathname.startsWith("/api/webhooks/") &&
      !parsed.username &&
      !parsed.password
      ? candidate
      : null;
  } catch {
    return null;
  }
}

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

  const limit = takeRateLimit(`discord:${getClientIp(request)}`, {
    limit: 10,
    windowMs: 60_000,
  });
  const headers = rateLimitHeaders(limit);
  if (!limit.allowed) {
    return apiError(
      "rate_limited",
      "Discord integration request limit exceeded.",
      429,
      requestId,
      headers,
    );
  }

  const raw = await request.text();
  if (new TextEncoder().encode(raw).byteLength > 8 * 1024) {
    return apiError(
      "payload_too_large",
      "Integration requests may be at most 8 KiB.",
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
  const parsed = requestSchema.safeParse(candidate);
  if (!parsed.success || parsed.data.action.type !== "discord_webhook") {
    return apiError(
      "invalid_request",
      "Request must contain one approved Discord action.",
      422,
      requestId,
      headers,
    );
  }
  requestId = parsed.data.requestId;

  const action = parsed.data.action;
  if (action.parameters.secretRef !== "discord.demo") {
    return apiError(
      "integration_unavailable",
      "This Discord connection is not configured on the service.",
      404,
      requestId,
      headers,
    );
  }

  const webhook = configuredWebhook();
  if (!webhook) {
    return jsonResponse(
      {
        schemaVersion: 1,
        requestId,
        provider: "discord",
        status: "simulated",
        receiptId: `mock-${crypto.randomUUID()}`,
        message: "No Discord credential is configured; no message was sent.",
      },
      requestId,
      { status: 200, headers },
    );
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 6_000);
  try {
    const response = await fetch(webhook, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        content: action.parameters.message,
        allowed_mentions: { parse: [] },
      }),
      redirect: "error",
      signal: controller.signal,
    });
    if (!response.ok) {
      return apiError(
        "integration_failed",
        "Discord did not accept the reviewed message.",
        502,
        requestId,
        headers,
      );
    }
    return jsonResponse(
      {
        schemaVersion: 1,
        requestId,
        provider: "discord",
        status: "sent",
        receiptId: `discord-${crypto.randomUUID()}`,
      },
      requestId,
      { status: 200, headers },
    );
  } catch {
    return apiError(
      "integration_failed",
      "Discord delivery timed out or failed.",
      502,
      requestId,
      headers,
    );
  } finally {
    clearTimeout(timeout);
  }
}
