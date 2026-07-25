import {
  apiError,
  enforceRateLimit,
  hasOnlyKeys,
  isPlainObject,
  json,
  preflight,
  readJsonBody,
  rejectDisallowedOrigin,
  stableId,
} from "@/lib/api/http";
import { isSafePublicUrl } from "@/lib/api/safety";

export const dynamic = "force-dynamic";

function isDiscordWebhook(raw: string): boolean {
  if (!isSafePublicUrl(raw)) return false;
  const hostname = new URL(raw).hostname.toLowerCase();
  return hostname === "discord.com" || hostname.endsWith(".discord.com") ||
    hostname === "discordapp.com" || hostname.endsWith(".discordapp.com");
}

export async function POST(request: Request) {
  const originError = rejectDisallowedOrigin(request);
  if (originError) return originError;
  const limited = enforceRateLimit(request, "discord");
  if (limited) return limited;
  const body = await readJsonBody(request, 8 * 1024);
  if (!body.ok) return body.response;
  if (
    !isPlainObject(body.value) ||
    !hasOnlyKeys(body.value, ["schemaVersion", "message", "webhookReference"]) ||
    body.value.schemaVersion !== 1 ||
    typeof body.value.message !== "string" ||
    body.value.message.length < 1 ||
    body.value.message.length > 2_000 ||
    (body.value.webhookReference !== undefined &&
      (typeof body.value.webhookReference !== "string" ||
        !/^[A-Za-z0-9_-]{1,80}$/.test(body.value.webhookReference)))
  ) {
    return apiError(
      request,
      422,
      "validation_failed",
      "Discord receipt request did not match schema version 1.",
    );
  }

  const message = body.value.message;
  const receiptId = stableId("discord", message);
  const webhookUrl = process.env.DISCORD_WEBHOOK_URL;
  if (webhookUrl && isDiscordWebhook(webhookUrl)) {
    try {
      const upstream = await fetch(webhookUrl, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          content: message,
          allowed_mentions: { parse: [] },
        }),
        redirect: "error",
        signal: AbortSignal.timeout(6_000),
      });
      if (upstream.ok) {
        return json(request, {
          schemaVersion: 1,
          receipt: {
            id: receiptId,
            status: "delivered",
            provider: "discord",
            fallback: false,
          },
        });
      }
    } catch {
      // Provider failure is intentionally collapsed into a safe demo fallback.
    }
  }

  return json(
    request,
    {
      schemaVersion: 1,
      receipt: {
        id: receiptId,
        status: "fallback_recorded",
        provider: "local_demo",
        fallback: true,
      },
      warning: "Discord was not configured or unavailable; Signal recorded a demo receipt.",
    },
    { status: 202 },
  );
}

export async function OPTIONS(request: Request) {
  return preflight(request);
}
