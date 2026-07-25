import type { Tool } from "@anthropic-ai/sdk/resources/messages";
import {
  BROWSER_COMMAND_SCHEMA_VERSION,
  BrowserCommandSchema,
  BrowserPlannerRequestSchema,
  type BrowserAction,
  type BrowserCommand,
  type BrowserPlannerRequest,
  type BrowserPlannerResponse,
} from "./schema";

const KNOWN_DESTINATIONS: ReadonlyArray<[RegExp, string, string]> = [
  [/\bspotify(?:\s+web)?\b/i, "Spotify Web", "https://open.spotify.com/"],
  [/\bgmail\b/i, "Gmail", "https://mail.google.com/"],
  [/\bgithub\b/i, "GitHub", "https://github.com/"],
  [
    /\b(?:google\s+)?calendar\b/i,
    "Google Calendar",
    "https://calendar.google.com/",
  ],
];

const DANGEROUS_REQUEST =
  /\b(?:shell|terminal|powershell|cmd\.exe|applescript|sudo|ssh|local(?:host)?|private\s+network)\b|(?:javascript|data|file|vbscript):/i;

function stableId(prefix: string, input: string): string {
  let hash = 2166136261;
  for (let index = 0; index < input.length; index += 1) {
    hash ^= input.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return `${prefix}.${(hash >>> 0).toString(36).padStart(7, "0")}`;
}

function trimSpokenText(value: string): string {
  return value
    .replace(/^["'\s]+|["'\s.]+$/g, "")
    .replace(/\s+/g, " ")
    .slice(0, 500);
}

function durationSeconds(text: string): number | null {
  const match = text.match(
    /\b(?:for\s+)?(\d+|one|two|three|five|ten|fifteen|twenty|thirty|sixty)\s*(second|minute|hour)s?\b/i,
  );
  if (!match) return null;
  const words: Record<string, number> = {
    one: 1,
    two: 2,
    three: 3,
    five: 5,
    ten: 10,
    fifteen: 15,
    twenty: 20,
    thirty: 30,
    sixty: 60,
  };
  const amount = Number(match[1]) || words[match[1].toLowerCase()];
  const unit = match[2].toLowerCase();
  return Math.min(
    86_400,
    amount * (unit === "hour" ? 3_600 : unit === "minute" ? 60 : 1),
  );
}

function explicitUrl(request: string): string | null {
  const match = request.match(/https:\/\/[^\s,;)"']+/i);
  return match?.[0]?.replace(/[.!?]+$/, "") ?? null;
}

function fallbackActions(request: string): BrowserAction[] {
  const actions: BrowserAction[] = [];
  const foundUrl = explicitUrl(request);
  const known = KNOWN_DESTINATIONS.find(([pattern]) => pattern.test(request));
  if (/\b(?:open|launch|go to|visit|navigate)\b/i.test(request)) {
    if (foundUrl) {
      actions.push({
        type: "open_url",
        url: foundUrl,
        target: "prepared_action_tab",
        fallback: "explicit_same_tab_confirmation",
      });
    } else if (known) {
      actions.push({
        type: "open_url",
        url: known[2],
        target: "prepared_action_tab",
        fallback: "explicit_same_tab_confirmation",
      });
    }
  }

  const waitMatch = request.match(
    /\bwait\s+(?:for\s+)?(\d+|one|two|three|five|ten)\s*seconds?\b/i,
  );
  if (waitMatch) {
    const seconds = durationSeconds(waitMatch[0]);
    if (seconds !== null) actions.push({ type: "wait", durationMs: seconds * 1_000 });
  }

  const timerClause = request.match(
    /\b(?:start|set)\s+(?:a\s+)?timer(?:\s+for)?\s+[^,;.]+/i,
  );
  if (timerClause) {
    const seconds = durationSeconds(timerClause[0]);
    if (seconds !== null) {
      actions.push({
        type: "start_timer",
        label: /focus/i.test(request) ? "Focus timer" : "Signal timer",
        durationSeconds: seconds,
      });
    }
  }

  const speakMatch = request.match(
    /\b(?:say|speak|announce)\s+(?:the\s+(?:words?|phrase)\s+)?["']?([^,;.]+)["']?/i,
  );
  if (speakMatch) {
    const text = trimSpokenText(speakMatch[1]);
    if (text) actions.push({ type: "speak_text", text });
  }

  const noteMatch = request.match(
    /\b(?:save|write|remember)\s+(?:a\s+)?note(?:\s+(?:that|saying|with))?\s+["']?([^,;.]+)["']?/i,
  );
  if (noteMatch) {
    const text = trimSpokenText(noteMatch[1]);
    if (text) actions.push({ type: "save_note", text });
  }

  const signalPath = request.match(
    /\b(?:show|navigate to|go to)\s+(?:the\s+)?(commands?|gestures?|settings?|activity)\b/i,
  );
  if (signalPath) {
    const anchor = signalPath[1].toLowerCase().replace(/s$/, "");
    actions.push({ type: "navigate_signal", path: `#${anchor}` });
  }

  return actions.slice(0, 12);
}

function commandName(request: string, actions: BrowserAction[]): string {
  const known = KNOWN_DESTINATIONS.find(([pattern]) => pattern.test(request));
  if (known) return `Open ${known[1]}`;
  if (actions[0]?.type === "start_timer") return actions[0].label;
  if (actions[0]?.type === "save_note") return "Save note";
  if (actions[0]?.type === "speak_text") return "Speak message";
  return "Custom fist command";
}

export function parseBrowserCommandFallback(
  input: BrowserPlannerRequest,
): BrowserPlannerResponse {
  if (DANGEROUS_REQUEST.test(input.request)) {
    return {
      schemaVersion: BROWSER_COMMAND_SCHEMA_VERSION,
      requestId: input.requestId,
      status: "needs_clarification",
      question:
        "Signal only runs browser-safe actions. What public HTTPS site or Signal action should the fist trigger?",
      missingFields: ["browserSafeAction"],
    };
  }

  const actions = fallbackActions(input.request);
  const candidate: BrowserCommand = {
    schemaVersion: BROWSER_COMMAND_SCHEMA_VERSION,
    id: stableId("signal.fist", input.request.toLowerCase().trim()),
    name: commandName(input.request, actions),
    description: `Browser-safe fist command: ${input.request.trim()}`.slice(0, 500),
    gesture: "fist",
    steps: actions.map((action, index) => ({
      id: `step-${index + 1}`,
      action,
      onFailure: "stop",
    })),
    createdSource: input.source,
  };
  const checked = BrowserCommandSchema.safeParse(candidate);
  if (!checked.success) {
    return {
      schemaVersion: BROWSER_COMMAND_SCHEMA_VERSION,
      requestId: input.requestId,
      status: "needs_clarification",
      question:
        "Which public HTTPS site, timer, spoken message, note, or Signal section should the fist command use?",
      missingFields: ["supportedAction"],
    };
  }
  return {
    schemaVersion: BROWSER_COMMAND_SCHEMA_VERSION,
    requestId: input.requestId,
    status: "planned",
    command: checked.data,
    warnings: [
      "Review and approve every step before saving or running this command.",
      ...(input.source === "teach_by_demo"
        ? [
            "Screen keyframes can omit clicks and keystrokes; confirm the proposed actions.",
          ]
        : []),
    ],
    usedDeterministicFallback: true,
  };
}

const browserCommandTool: Tool = {
  name: "return_browser_command",
  description:
    "Return one constrained Signal browser command. Never return code, secrets, local-app actions, or unsafe URLs.",
  input_schema: {
    type: "object",
    additionalProperties: false,
    required: [
      "schemaVersion",
      "id",
      "name",
      "description",
      "gesture",
      "steps",
      "createdSource",
    ],
    properties: {
      schemaVersion: { const: 1 },
      id: {
        type: "string",
        pattern: "^[A-Za-z0-9][A-Za-z0-9._-]*$",
        maxLength: 64,
      },
      name: { type: "string", minLength: 1, maxLength: 80 },
      description: { type: "string", maxLength: 500 },
      gesture: { const: "fist" },
      createdSource: {
        enum: ["natural_language", "teach_by_demo"],
      },
      steps: {
        type: "array",
        minItems: 1,
        maxItems: 12,
        items: {
          type: "object",
          additionalProperties: false,
          required: ["id", "action", "onFailure"],
          properties: {
            id: { type: "string", maxLength: 64 },
            onFailure: { enum: ["stop", "continue"] },
            action: {
              oneOf: [
                {
                  type: "object",
                  additionalProperties: false,
                  required: ["type", "path"],
                  properties: {
                    type: { const: "navigate_signal" },
                    path: { type: "string", maxLength: 240 },
                  },
                },
                {
                  type: "object",
                  additionalProperties: false,
                  required: ["type", "url", "target", "fallback"],
                  properties: {
                    type: { const: "open_url" },
                    url: { type: "string", maxLength: 2048 },
                    target: { const: "prepared_action_tab" },
                    fallback: { const: "explicit_same_tab_confirmation" },
                  },
                },
                {
                  type: "object",
                  additionalProperties: false,
                  required: ["type", "text"],
                  properties: {
                    type: { const: "speak_text" },
                    text: { type: "string", maxLength: 500 },
                    rate: { type: "number", minimum: 0.5, maximum: 2 },
                  },
                },
                {
                  type: "object",
                  additionalProperties: false,
                  required: ["type", "label", "durationSeconds"],
                  properties: {
                    type: { const: "start_timer" },
                    label: { type: "string", maxLength: 120 },
                    durationSeconds: {
                      type: "integer",
                      minimum: 1,
                      maximum: 86400,
                    },
                  },
                },
                {
                  type: "object",
                  additionalProperties: false,
                  required: ["type", "text"],
                  properties: {
                    type: { const: "save_note" },
                    text: { type: "string", maxLength: 4000 },
                  },
                },
                {
                  type: "object",
                  additionalProperties: false,
                  required: ["type", "durationMs"],
                  properties: {
                    type: { const: "wait" },
                    durationMs: {
                      type: "integer",
                      minimum: 0,
                      maximum: 10000,
                    },
                  },
                },
              ],
            },
          },
        },
      },
    },
  },
};

function imageContent(input: BrowserPlannerRequest) {
  return (input.approvedKeyframes ?? []).map((frame) => ({
    type: "image" as const,
    source: {
      type: "base64" as const,
      media_type: frame.mediaType,
      data: frame.data,
    },
  }));
}

export async function makeBrowserPlan(
  input: BrowserPlannerRequest,
): Promise<BrowserPlannerResponse> {
  const fallback = parseBrowserCommandFallback(input);
  const apiKey = process.env.ANTHROPIC_API_KEY;
  const model = process.env.ANTHROPIC_MODEL;
  if (!apiKey || !model) return fallback;

  try {
    const { default: Anthropic } = await import("@anthropic-ai/sdk");
    const client = new Anthropic({ apiKey });
    const content = [
      {
        type: "text" as const,
        text: JSON.stringify({
          request: input.request,
          source: input.source,
          targetGesture: "fist",
          note:
            "Any attached images are explicitly approved local keyframes, not a raw recording.",
        }),
      },
      ...imageContent(input),
    ];
    const response = await client.messages.create({
      model,
      max_tokens: 2_500,
      temperature: 0,
      system:
        "Plan actions only inside Signal or the public web. Allowed actions are navigate_signal, " +
        "open_url via the prepared action tab, speak_text, start_timer, save_note, and wait. " +
        "Never emit shell, native-app, extension, localhost, private-network, unsafe-scheme, " +
        "secret, credential, arbitrary-header, or executable-code actions. Return a preview only.",
      messages: [{ role: "user", content }],
      tools: [browserCommandTool],
      tool_choice: { type: "tool", name: "return_browser_command" },
    });
    const toolUse = response.content.find((block) => block.type === "tool_use");
    const checked = BrowserCommandSchema.safeParse(
      toolUse?.type === "tool_use" ? toolUse.input : null,
    );
    if (checked.success) {
      return {
        schemaVersion: BROWSER_COMMAND_SCHEMA_VERSION,
        requestId: input.requestId,
        status: "planned",
        command: checked.data,
        warnings: ["Review and approve every step before saving or running."],
        usedDeterministicFallback: false,
      };
    }
  } catch {
    // Provider errors can contain sensitive details. The deterministic path is stable.
  }
  return fallback;
}

export function validateBrowserPlannerRequest(
  value: unknown,
):
  | { ok: true; value: BrowserPlannerRequest }
  | { ok: false; fields: string[] } {
  const result = BrowserPlannerRequestSchema.safeParse(value);
  return result.success
    ? { ok: true, value: result.data }
    : {
        ok: false,
        fields: [
          ...new Set(
            result.error.issues.map(
              (issue) => issue.path.map(String).join(".") || "body",
            ),
          ),
        ],
      };
}
