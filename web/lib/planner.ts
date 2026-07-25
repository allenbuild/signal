import Anthropic from "@anthropic-ai/sdk";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import { z } from "zod";

import {
  actionPlanSchema,
  type ActionPlan,
  type PlannerRequest,
  type PlannerResponse,
  plannerResponseSchema,
} from "./contracts";
import {
  isBrowserSafeActionType,
  isBrowserSafePlan,
} from "./commands/browser-actions";
import { checkPublicHttpsLiteralHost } from "./security";

const aiEnvelopeSchema = z
  .object({
    plan: actionPlanSchema,
    warnings: z.array(z.string().max(240)).max(10),
  })
  .strict();

const unsafeInstructionPattern =
  /\b(?:reveal|print|dump|exfiltrate|ignore\s+(?:all\s+)?(?:previous|system)|system\s+prompt|api\s*key|environment\s+variables?|shell\s+command|terminal\s+command|raw\s+applescript|curl\s+localhost|metadata\s+(?:service|ip))\b/i;

const durationWords: Record<string, number> = {
  one: 1,
  two: 2,
  three: 3,
  four: 4,
  five: 5,
  six: 6,
  seven: 7,
  eight: 8,
  nine: 9,
  ten: 10,
  fifteen: 15,
  twenty: 20,
  thirty: 30,
};

const confirmationNone = { mode: "none" as const, reason: "" };
const confirmationEveryRun = {
  mode: "every_run" as const,
  reason: "This action sends data to an external service.",
};

function makeStep(
  index: number,
  action: ActionPlan["steps"][number]["action"],
  confirmation: ActionPlan["steps"][number]["confirmation"] = confirmationNone,
): ActionPlan["steps"][number] {
  const waitDuration =
    action.type === "wait" ? action.parameters.durationMs : undefined;
  return {
    id: `step-${index + 1}`,
    action,
    timeoutMs: Math.min(60_000, Math.max(1_000, (waitDuration ?? 7_000) + 1_000)),
    onFailure: "stop",
    confirmation,
  };
}

function makePlan(
  request: PlannerRequest,
  steps: ActionPlan["steps"],
  secretReferences: ActionPlan["secretReferences"] = [],
): ActionPlan {
  const timeoutMs = Math.min(
    300_000,
    Math.max(5_000, steps.reduce((sum, step) => sum + step.timeoutMs, 0) + 3_000),
  );
  return actionPlanSchema.parse({
    schemaVersion: 1,
    id: `plan-${request.requestId}`.slice(0, 64),
    name: "Generated gesture workflow",
    description: `Reviewed preview for ${request.targetGesture.replaceAll("_", " ")}`,
    steps,
    timeoutMs,
    onFailure: "stop",
    confirmation: {
      mode: secretReferences.length > 0 ? "first_run" : "none",
      reason: secretReferences.length > 0
        ? "Review external integrations before the first run."
        : "",
    },
    createdSource: "natural_language",
    secretReferences,
  });
}

function responseForPlan(
  request: PlannerRequest,
  plan: ActionPlan,
  warnings: string[],
  usedDeterministicFallback: boolean,
): PlannerResponse {
  return plannerResponseSchema.parse({
    schemaVersion: 1,
    requestId: request.requestId,
    status: "planned",
    plan,
    warnings,
    usedDeterministicFallback,
  });
}

function clarification(
  request: PlannerRequest,
  question: string,
  missingFields: string[],
): PlannerResponse {
  return plannerResponseSchema.parse({
    schemaVersion: 1,
    requestId: request.requestId,
    status: "needs_clarification",
    question,
    missingFields,
  });
}

function actionAvailable(request: PlannerRequest, actionType: string) {
  return request.actionCatalog.includes(
    actionType as PlannerRequest["actionCatalog"][number],
  );
}

export type FallbackResult =
  | { handled: true; response: PlannerResponse }
  | { handled: false };

export function planWithDeterministicFallback(
  request: PlannerRequest,
): FallbackResult {
  const instruction = request.request.trim();
  const lower = instruction.toLowerCase();
  const planned: Array<{
    position: number;
    action: ActionPlan["steps"][number]["action"];
    confirmation?: ActionPlan["steps"][number]["confirmation"];
  }> = [];
  const requiredActions = new Set<string>();
  let usesDiscord = false;
  const queue = (
    position: number,
    action: ActionPlan["steps"][number]["action"],
    confirmation?: ActionPlan["steps"][number]["confirmation"],
  ) => {
    planned.push({ position, action, confirmation });
  };

  const isSeededDemo =
    lower.includes("thumbs up") &&
    lower.includes("focus playlist") &&
    lower.includes("focus mode") &&
    lower.includes("discord");

  if (isSeededDemo || lower.includes("focus playlist")) {
    requiredActions.add("open_url");
    queue(
      Math.max(0, lower.indexOf("focus playlist")),
      {
        type: "open_url",
        parameters: {
          url: "https://open.spotify.com/",
          networkPolicy: "public_https_only",
        },
      },
    );
  }

  const urlMatch = instruction.match(/https:\/\/[^\s,;"')]+/i);
  if (urlMatch && !planned.some((step) => step.action.type === "open_url")) {
    const check = checkPublicHttpsLiteralHost(urlMatch[0]);
    if (!check.ok) {
      return {
        handled: true,
        response: clarification(
          request,
          "Which public HTTPS URL should Signal open?",
          ["publicUrl"],
        ),
      };
    }
    requiredActions.add("open_url");
    queue(
      urlMatch.index ?? 0,
      {
        type: "open_url",
        parameters: {
          url: check.canonicalUrl,
          networkPolicy: "public_https_only",
        },
      },
    );
  }

  if (/\bopen\b/i.test(instruction) && !urlMatch && !lower.includes("focus playlist")) {
    return {
      handled: true,
      response: clarification(
        request,
        "Which public HTTPS URL should Signal open?",
        ["publicUrl"],
      ),
    };
  }

  const sayMatch = instruction.match(
    /\b(?:say|speak)\s+["“']?(.+?)(?:["”']?\s*(?:,?\s+and\s+|,?\s+then\s+|$))/i,
  );
  if (sayMatch) {
    const text = sayMatch[1].replace(/[,"”']+$/, "").trim();
    if (text) {
      requiredActions.add("speak_text");
      queue(
        sayMatch.index ?? 0,
        {
          type: "speak_text",
          parameters: { text: text.slice(0, 500) },
        },
      );
    }
  }

  const notificationMatch = instruction.match(
    /\b(?:show|display)\s+(?:a\s+)?notification(?:\s+(?:saying|with))?\s+["“']?(.+?)(?:["”']?\s*$)/i,
  );
  if (notificationMatch) {
    requiredActions.add("show_notification");
    queue(
      notificationMatch.index ?? 0,
      {
        type: "show_notification",
        parameters: {
          title: "Signal",
          body: notificationMatch[1].replace(/["”']+$/, "").trim().slice(0, 500),
        },
      },
    );
  }

  const waitMatch = instruction.match(
    /\bwait\s+(?:for\s+)?(\d+(?:\.\d+)?|one|two|three|four|five|six|seven|eight|nine|ten|fifteen|twenty|thirty)\s*(milliseconds?|ms|seconds?|secs?|minutes?|mins?)\b/i,
  );
  if (waitMatch) {
    const amount =
      durationWords[waitMatch[1].toLowerCase()] ?? Number(waitMatch[1]);
    const unit = waitMatch[2].toLowerCase();
    const multiplier = unit.startsWith("m") && unit !== "ms"
      ? 60_000
      : unit.startsWith("s")
        ? 1_000
        : 1;
    const durationMs = Math.round(amount * multiplier);
    if (durationMs > 30_000) {
      return {
        handled: true,
        response: clarification(
          request,
          "Version 1 waits can be at most 30 seconds. What shorter wait should Signal use?",
          ["waitDuration"],
        ),
      };
    }
    requiredActions.add("wait");
    queue(
      waitMatch.index ?? 0,
      {
        type: "wait",
        parameters: { durationMs },
      },
    );
  }

  const discordMatch = instruction.match(
    /\b(?:send|post)\s+["“']?(.+?)["”']?\s+(?:to|on)\s+Discord\b/i,
  );
  if (discordMatch || (isSeededDemo && lower.includes("demo complete"))) {
    const message = discordMatch?.[1]
      .replace(/^a\s+(?:message\s+)?(?:saying\s+)?/i, "")
      .replace(/["”']+$/, "")
      .trim() ?? "Demo complete";
    requiredActions.add("discord_webhook");
    usesDiscord = true;
    queue(
      discordMatch?.index ?? Math.max(0, lower.indexOf("discord")),
      {
        type: "discord_webhook",
        parameters: {
          secretRef: "discord.demo",
          message: message.slice(0, 1800),
          fallback: "local_receipt",
        },
      },
      confirmationEveryRun,
    );
  }

  if (planned.length === 0) return { handled: false };

  const unavailable = [...requiredActions].filter(
    (actionType) => !actionAvailable(request, actionType),
  );
  if (unavailable.length > 0) {
    return {
      handled: true,
      response: clarification(
        request,
        `The current action catalog does not advertise: ${unavailable.join(", ")}.`,
        ["actionCatalog"],
      ),
    };
  }

  const steps = planned
    .toSorted((left, right) => left.position - right.position)
    .slice(0, 50)
    .map((entry, index) =>
      makeStep(index, entry.action, entry.confirmation ?? confirmationNone),
    );
  const plan = makePlan(
    request,
    steps,
    usesDiscord
      ? [{
          id: "discord.demo",
          provider: "discord",
          purpose: "Send the reviewed workflow message",
          storage: "keychain_or_server_environment",
        }]
      : [],
  );
  return {
    handled: true,
    response: responseForPlan(
      request,
      plan,
      ["Built with Signal’s deterministic fallback; no AI provider was used."],
      true,
    ),
  };
}

export function rejectUnsafePlannerInstruction(instruction: string): boolean {
  return unsafeInstructionPattern.test(instruction);
}

export async function planWithAnthropic(
  request: PlannerRequest,
  imageDataUrls: string[] = [],
): Promise<PlannerResponse | null> {
  const apiKey = process.env.ANTHROPIC_API_KEY?.trim();
  if (!apiKey) return null;

  const client = new Anthropic({
    apiKey,
    maxRetries: 0,
    timeout: 12_000,
  });
  const prompt = JSON.stringify({
    request: request.request,
    targetGesture: request.targetGesture,
    actionCatalog: request.actionCatalog,
    platform: "browser",
    schemaVersion: 1,
    recordingContext:
      imageDataUrls.length > 0
        ? "Compressed, evenly spaced browser-recording keyframes follow. Infer only visible evidence; ask for clarification when intent is ambiguous."
        : undefined,
  });
  const imageBlocks: Anthropic.ImageBlockParam[] = imageDataUrls.flatMap(
    (dataUrl) => {
      const match = dataUrl.match(
        /^data:(image\/(?:jpeg|png|gif|webp));base64,([A-Za-z0-9+/=]+)$/,
      );
      return match
        ? [{
            type: "image",
            source: {
              type: "base64",
              media_type: match[1] as
                | "image/jpeg"
                | "image/png"
                | "image/gif"
                | "image/webp",
              data: match[2],
            },
          }]
        : [];
    },
  );
  const content: Anthropic.MessageParam["content"] =
    imageBlocks.length > 0
      ? [{ type: "text", text: prompt }, ...imageBlocks]
      : prompt;

  const response = await client.messages.parse({
    model: process.env.ANTHROPIC_MODEL?.trim() || "claude-opus-5",
    max_tokens: 6_000,
    system: [
      "You are Signal's browser-safe action-plan compiler.",
      "Return only a schema-valid version 1 plan preview and concise warnings.",
      "Use only action types advertised in actionCatalog.",
      "Never emit native-app, operating-system, shell, raw AppleScript, arbitrary-auth-header, secret-value, localhost, private-network, or non-HTTPS navigation actions.",
      "Emit no more than 50 actions.",
      "Plans are previews and are never executed by this service.",
      "Use secretRef identifiers only. For externally visible effects, require every_run confirmation.",
    ].join(" "),
    messages: [
      {
        role: "user",
        content,
      },
    ],
    output_config: {
      format: zodOutputFormat(aiEnvelopeSchema),
    },
  });

  if (response.stop_reason === "refusal" || !response.parsed_output) {
    return null;
  }
  const { plan, warnings } = response.parsed_output;
  const usedTypes = new Set(plan.steps.map((step) => step.action.type));
  if (
    [...usedTypes].some((type) => !request.actionCatalog.includes(type)) ||
    !isBrowserSafePlan(plan)
  ) {
    return null;
  }
  return responseForPlan(request, plan, warnings, false);
}

export async function createPlannerResponse(
  request: PlannerRequest,
  imageDataUrls: string[] = [],
): Promise<PlannerResponse> {
  if (request.actionCatalog.some((type) => !isBrowserSafeActionType(type))) {
    return clarification(
      request,
      "Signal only accepts browser-safe action types.",
      ["actionCatalog"],
    );
  }
  const fallback = planWithDeterministicFallback(request);
  if (fallback.handled) return fallback.response;

  try {
    const planned = await planWithAnthropic(request, imageDataUrls);
    if (planned) return planned;
  } catch {
    // Provider failures deliberately fall through to a safe clarification.
  }

  return clarification(
    request,
    "What should Signal open, say, show, wait for, or send to Discord?",
    ["supportedActionDetails"],
  );
}
