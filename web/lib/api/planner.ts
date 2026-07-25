import type { ActionPlan, Gesture } from "./types";
import type { Tool } from "@anthropic-ai/sdk/resources/messages";
import { ACTION_TYPES, SCHEMA_VERSION } from "./types";
import { PlannerRequestSchema, PlannerResponseSchema } from "./schema";
import { validatePlan } from "./safety";

export interface PlannerInput {
  schemaVersion: 1;
  requestId: string;
  request: string;
  targetGesture?: Gesture;
  actionCatalog: (typeof ACTION_TYPES)[number][];
}

export type PlannerResponse =
  | {
      schemaVersion: 1;
      requestId: string;
      status: "planned";
      plan: ActionPlan;
      warnings: string[];
      usedDeterministicFallback: boolean;
    }
  | {
      schemaVersion: 1;
      requestId: string;
      status: "needs_clarification";
      question: string;
      missingFields: string[];
    };

function planActionTypes(plan: ActionPlan): Set<string> {
  const types = new Set<string>();
  const visit = (action: ActionPlan["steps"][number]["action"]) => {
    types.add(action.type);
    if (action.type === "conditional") {
      const parameters = action.parameters as {
        ifTrue?: ActionPlan["steps"][number]["action"][];
        ifFalse?: ActionPlan["steps"][number]["action"][];
      };
      parameters.ifTrue?.forEach(visit);
      parameters.ifFalse?.forEach(visit);
    }
  };
  plan.steps.forEach((step) => visit(step.action));
  return types;
}

function allowedByCatalog(plan: ActionPlan, catalog: string[]): boolean {
  const allowed = new Set(catalog);
  return [...planActionTypes(plan)].every((type) => type !== "http_request" && allowed.has(type));
}

const confirmation = (
  mode: "none" | "first_run" | "every_run",
  reason: string,
) => ({ mode, reason });

function focusPlan(): ActionPlan {
  return {
    schemaVersion: SCHEMA_VERSION,
    id: "signal.seed.focus-mode",
    name: "Focus mode",
    description: "Open a focus playlist, speak a local cue, and send a configured Discord receipt.",
    steps: [
      {
        id: "open-playlist",
        action: {
          type: "open_url",
          parameters: {
            url: "https://open.spotify.com/genre/0JQ5DAqbMKFAXlCG6QvYQ4",
            networkPolicy: "public_https_only",
          },
        },
        timeoutMs: 10_000,
        onFailure: "continue",
        confirmation: confirmation("first_run", "Opens the displayed public URL."),
      },
      {
        id: "speak-cue",
        action: {
          type: "speak_text",
          parameters: { text: "Focus mode" },
        },
        timeoutMs: 10_000,
        onFailure: "continue",
        confirmation: confirmation("none", "Local speech only."),
      },
      {
        id: "send-receipt",
        action: {
          type: "discord_webhook",
          parameters: {
            secretRef: "demo-discord-webhook",
            message: "Demo complete",
            fallback: "local_receipt",
          },
        },
        timeoutMs: 10_000,
        onFailure: "continue",
        confirmation: confirmation(
          "every_run",
          "Sends the displayed message to an external Discord webhook.",
        ),
      },
    ],
    timeoutMs: 35_000,
    onFailure: "continue",
    confirmation: confirmation(
      "first_run",
      "AI plans are previews and require approval before save or first run.",
    ),
    createdSource: "natural_language",
    secretReferences: [
      {
        id: "demo-discord-webhook",
        provider: "discord",
        purpose: "Optional demo completion receipt",
        storage: "keychain_or_server_environment",
      },
    ],
  };
}

function demoPlan(): ActionPlan {
  return {
    schemaVersion: SCHEMA_VERSION,
    id: "signal.seed.demo-replay",
    name: "Replay recorded note",
    description: "Open TextEdit, create a document, and type a short Signal demo line.",
    steps: [
      {
        id: "open-textedit",
        action: {
          type: "open_application",
          parameters: {
            bundleIdentifier: "com.apple.TextEdit",
            applicationName: "TextEdit",
          },
        },
        timeoutMs: 10_000,
        onFailure: "stop",
        confirmation: confirmation("first_run", "Opens a local application."),
      },
      {
        id: "new-document",
        action: {
          type: "keyboard_shortcut",
          parameters: { key: "n", modifiers: ["command"] },
        },
        timeoutMs: 5_000,
        onFailure: "stop",
        confirmation: confirmation(
          "first_run",
          "Sends Command-N to the frontmost application.",
        ),
      },
      {
        id: "type-demo-text",
        action: {
          type: "type_text",
          parameters: {
            text: "Signal replayed this workflow with a hand gesture.",
            containsSensitiveData: false,
          },
        },
        timeoutMs: 10_000,
        onFailure: "stop",
        confirmation: confirmation(
          "first_run",
          "Types the displayed non-sensitive text.",
        ),
      },
    ],
    timeoutMs: 30_000,
    onFailure: "stop",
    confirmation: confirmation(
      "first_run",
      "Review keyboard and text-entry effects before first run.",
    ),
    createdSource: "demo_recording",
    secretReferences: [],
  };
}

export function parseSeededPlan(input: PlannerInput): PlannerResponse | null {
  const normalized = input.request.toLowerCase().replace(/[^a-z0-9+]+/g, " ").trim();
  const focusIntent =
    (normalized.includes("focus") || normalized.includes("spotify") || normalized.includes("playlist")) &&
    (normalized.includes("thumb") || input.targetGesture === "thumbs_up" || normalized.includes("discord"));
  if (focusIntent) {
    const plan = focusPlan();
    if (!allowedByCatalog(plan, input.actionCatalog)) return null;
    return {
      schemaVersion: SCHEMA_VERSION,
      requestId: input.requestId,
      status: "planned",
      plan,
      warnings: [
        "Discord uses a local receipt fallback until the secret reference is configured.",
      ],
      usedDeterministicFallback: true,
    };
  }

  const demoIntent =
    normalized.includes("teach") ||
    normalized.includes("record") ||
    normalized.includes("textedit") ||
    input.targetGesture === "c_shape";
  if (demoIntent) {
    const plan = demoPlan();
    if (!allowedByCatalog(plan, input.actionCatalog)) return null;
    return {
      schemaVersion: SCHEMA_VERSION,
      requestId: input.requestId,
      status: "planned",
      plan,
      warnings: [],
      usedDeterministicFallback: true,
    };
  }
  return null;
}

const planTool: Tool = {
  name: "return_signal_plan",
  description: "Return one safe, reviewable Signal v1 action plan. Never return code or secrets.",
  input_schema: {
    type: "object",
    additionalProperties: false,
    required: [
      "schemaVersion", "id", "name", "description", "steps", "timeoutMs",
      "onFailure", "confirmation", "createdSource", "secretReferences",
    ],
    properties: {
      schemaVersion: { const: 1 },
      id: { type: "string", pattern: "^[A-Za-z0-9][A-Za-z0-9._-]*$", maxLength: 64 },
      name: { type: "string", minLength: 1, maxLength: 80 },
      description: { type: "string", maxLength: 500 },
      timeoutMs: { type: "integer", minimum: 100, maximum: 300000 },
      onFailure: { enum: ["stop", "continue", "ask"] },
      confirmation: {
        type: "object",
        additionalProperties: false,
        required: ["mode", "reason"],
        properties: {
          mode: { enum: ["none", "first_run", "every_run"] },
          reason: { type: "string", maxLength: 160 },
        },
      },
      createdSource: { const: "natural_language" },
      secretReferences: { type: "array", maxItems: 20 },
      steps: {
        type: "array",
        minItems: 1,
        maxItems: 50,
        items: {
          type: "object",
          additionalProperties: false,
          required: ["id", "action", "timeoutMs", "onFailure", "confirmation"],
          properties: {
            id: { type: "string" },
            action: {
              type: "object",
              additionalProperties: false,
              required: ["type", "parameters"],
              properties: {
                type: { enum: ACTION_TYPES.filter((type) => type !== "conditional") },
                parameters: { type: "object" },
              },
            },
            timeoutMs: { type: "integer", minimum: 100, maximum: 60000 },
            onFailure: { enum: ["stop", "continue", "ask"] },
            confirmation: {
              type: "object",
              additionalProperties: false,
              required: ["mode", "reason"],
              properties: {
                mode: { enum: ["none", "first_run", "every_run"] },
                reason: { type: "string", maxLength: 160 },
              },
            },
          },
        },
      },
    },
  },
};

export async function makePlan(input: PlannerInput): Promise<PlannerResponse> {
  const seeded = parseSeededPlan(input);
  if (seeded) return seeded;

  const apiKey = process.env.ANTHROPIC_API_KEY;
  const model = process.env.ANTHROPIC_MODEL;
  if (apiKey && model) {
    try {
      const { default: Anthropic } = await import("@anthropic-ai/sdk");
      const client = new Anthropic({ apiKey });
      const response = await client.messages.create({
        model,
        max_tokens: 3_000,
        temperature: 0,
        system:
          "You plan macOS actions for Signal. Use only the advertised safe catalog. " +
          "Plans are previews and require approval. Never emit shell, raw AppleScript, secret values, " +
          "private-network URLs, arbitrary authorization headers, or executable code.",
        messages: [{
          role: "user",
          content: JSON.stringify({
            request: input.request,
            targetGesture: input.targetGesture,
            actionCatalog: input.actionCatalog,
          }),
        }],
        tools: [planTool],
        tool_choice: { type: "tool", name: "return_signal_plan" },
      });
      const toolUse = response.content.find((block) => block.type === "tool_use");
      const checked = validatePlan(toolUse?.type === "tool_use" ? toolUse.input : null);
      if (checked.ok && allowedByCatalog(checked.plan, input.actionCatalog)) {
        const result: PlannerResponse = {
          schemaVersion: SCHEMA_VERSION,
          requestId: input.requestId,
          status: "planned",
          plan: checked.plan,
          warnings: ["Review every step before saving or running this plan."],
          usedDeterministicFallback: false,
        };
        if (PlannerResponseSchema.safeParse(result).success) return result;
      }
    } catch {
      // Provider details can contain sensitive data. Fall through to a stable response.
    }
  }

  return {
    schemaVersion: SCHEMA_VERSION,
    requestId: input.requestId,
    status: "needs_clarification",
    question: "Which supported app or public HTTPS URL should Signal open, and what should happen next?",
    missingFields: ["target", "steps"],
  };
}

export function validatePlannerInput(
  value: unknown,
): { ok: true; value: PlannerInput } | { ok: false; fields: string[] } {
  const result = PlannerRequestSchema.safeParse(value);
  return result.success
    ? { ok: true, value: result.data as PlannerInput }
    : {
        ok: false,
        fields: [...new Set(result.error.issues.map((issue) => issue.path.map(String).join(".") || "body"))],
      };
}
