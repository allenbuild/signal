import { z } from "zod";

export const BROWSER_COMMAND_SCHEMA_VERSION = 1 as const;
export const BROWSER_COMMAND_STORAGE_VERSION = 2 as const;

export const BrowserGestureSchema = z.enum([
  "one",
  "two",
  "three",
  "four",
  "five",
  "thumbs_up",
  "thumbs_down",
  "c",
  "fist",
]);

const IdentifierSchema = z
  .string()
  .min(1)
  .max(64)
  .regex(/^[A-Za-z0-9][A-Za-z0-9._-]*$/);

const LOCAL_HOST_SUFFIXES = [
  ".internal",
  ".lan",
  ".local",
  ".localhost",
  ".home",
] as const;

function parseIpv4(hostname: string): number[] | null {
  const parts = hostname.split(".");
  if (parts.length !== 4 || parts.some((part) => !/^\d{1,3}$/.test(part))) {
    return null;
  }
  const numbers = parts.map(Number);
  return numbers.every((part) => part >= 0 && part <= 255) ? numbers : null;
}

function isNonPublicIpv4(hostname: string): boolean {
  const parts = parseIpv4(hostname);
  if (!parts) return false;
  const [first, second, third] = parts;
  return (
    first === 0 ||
    first === 10 ||
    first === 127 ||
    (first === 100 && second >= 64 && second <= 127) ||
    (first === 169 && second === 254) ||
    (first === 172 && second >= 16 && second <= 31) ||
    (first === 192 && second === 168) ||
    (first === 192 && second === 0 && third === 0) ||
    (first === 192 && second === 0 && third === 2) ||
    (first === 198 && second >= 18 && second <= 19) ||
    (first === 198 && second === 51 && third === 100) ||
    (first === 203 && second === 0 && third === 113) ||
    first >= 224
  );
}

function isNonPublicIpv6(hostname: string): boolean {
  const normalized = hostname.replace(/^\[|\]$/g, "").toLowerCase();
  if (!normalized.includes(":")) return false;
  if (normalized === "::" || normalized === "::1") return true;
  if (/^f[cd][0-9a-f]{0,2}:/.test(normalized)) return true;
  if (/^fe[89ab][0-9a-f]?:/.test(normalized)) return true;
  if (/^ff[0-9a-f]{2}:/.test(normalized)) return true;
  const mapped = normalized.match(/::ffff:(\d+\.\d+\.\d+\.\d+)$/);
  return mapped ? isNonPublicIpv4(mapped[1]) : false;
}

/**
 * Performs the browser-side URL checks available before navigation. This does
 * not claim DNS-level SSRF protection; server fetchers must independently
 * resolve and verify every destination and redirect.
 */
export function isSafeBrowserUrl(raw: string): boolean {
  try {
    const parsed = new URL(raw);
    const hostname = parsed.hostname
      .toLowerCase()
      .replace(/\.$/, "")
      .replace(/^\[|\]$/g, "");
    if (parsed.protocol !== "https:" || parsed.username || parsed.password) return false;
    if (!hostname || hostname === "localhost") return false;
    if (LOCAL_HOST_SUFFIXES.some((suffix) => hostname.endsWith(suffix))) return false;
    if (isNonPublicIpv4(hostname) || isNonPublicIpv6(hostname)) return false;
    return true;
  } catch {
    return false;
  }
}

const SafeBrowserUrlSchema = z
  .string()
  .min(9)
  .max(2048)
  .refine(isSafeBrowserUrl, "URL must be a public HTTPS browser destination.");

const SignalPathSchema = z
  .string()
  .min(1)
  .max(240)
  .refine(
    (path) =>
      (path.startsWith("/") && !path.startsWith("//")) ||
      (path.startsWith("#") && !path.startsWith("#/")),
    "Signal navigation must use a root-relative path or page anchor.",
  )
  .refine(
    (path) => !/[\u0000-\u001f\\]/.test(path),
    "Signal navigation contains unsupported characters.",
  );

const NavigateSignalActionSchema = z
  .object({
    type: z.literal("navigate_signal"),
    path: SignalPathSchema,
  })
  .strict();

const OpenUrlActionSchema = z
  .object({
    type: z.literal("open_url"),
    url: SafeBrowserUrlSchema,
    target: z.literal("prepared_action_tab"),
    fallback: z.literal("explicit_same_tab_confirmation"),
  })
  .strict();

const SpeakTextActionSchema = z
  .object({
    type: z.literal("speak_text"),
    text: z.string().min(1).max(500),
    rate: z.number().min(0.5).max(2).optional(),
  })
  .strict();

const StartTimerActionSchema = z
  .object({
    type: z.literal("start_timer"),
    label: z.string().min(1).max(120),
    durationSeconds: z.number().int().min(1).max(86_400),
  })
  .strict();

const SaveNoteActionSchema = z
  .object({
    type: z.literal("save_note"),
    text: z.string().min(1).max(4_000),
  })
  .strict();

const WaitActionSchema = z
  .object({
    type: z.literal("wait"),
    durationMs: z.number().int().min(0).max(10_000),
  })
  .strict();

export const BrowserActionSchema = z.discriminatedUnion("type", [
  NavigateSignalActionSchema,
  OpenUrlActionSchema,
  SpeakTextActionSchema,
  StartTimerActionSchema,
  SaveNoteActionSchema,
  WaitActionSchema,
]);

export const BrowserCommandStepSchema = z
  .object({
    id: IdentifierSchema,
    action: BrowserActionSchema,
    onFailure: z.enum(["stop", "continue"]).default("stop"),
  })
  .strict();

export const BrowserCommandSchema = z
  .object({
    schemaVersion: z.literal(BROWSER_COMMAND_SCHEMA_VERSION),
    id: IdentifierSchema,
    name: z.string().min(1).max(80),
    description: z.string().max(500),
    gesture: BrowserGestureSchema,
    steps: z.array(BrowserCommandStepSchema).min(1).max(12),
    createdSource: z.enum(["preset", "natural_language", "teach_by_demo", "import"]),
  })
  .strict()
  .superRefine((command, context) => {
    const ids = command.steps.map((step) => step.id);
    if (new Set(ids).size !== ids.length) {
      context.addIssue({
        code: "custom",
        message: "Command step identifiers must be unique.",
        path: ["steps"],
      });
    }
  });

export type BrowserGesture = z.infer<typeof BrowserGestureSchema>;
export type BrowserAction = z.infer<typeof BrowserActionSchema>;
export type BrowserCommandStep = z.infer<typeof BrowserCommandStepSchema>;
export type BrowserCommand = z.infer<typeof BrowserCommandSchema>;

export function validateBrowserCommand(
  value: unknown,
):
  | { ok: true; command: BrowserCommand }
  | { ok: false; fields: string[]; message: string } {
  const result = BrowserCommandSchema.safeParse(value);
  if (result.success) return { ok: true, command: result.data };
  return {
    ok: false,
    fields: [
      ...new Set(
        result.error.issues.map(
          (issue) => issue.path.map(String).join(".") || "command",
        ),
      ),
    ],
    message: "Command did not match Signal browser-command schema version 1.",
  };
}

const ApprovedKeyframeSchema = z
  .object({
    mediaType: z.enum(["image/jpeg", "image/webp"]),
    data: z.string().min(16).max(500_000),
    timestampMs: z.number().int().min(0).max(60_000),
  })
  .strict();

export const BrowserPlannerRequestSchema = z
  .object({
    schemaVersion: z.literal(BROWSER_COMMAND_SCHEMA_VERSION),
    requestId: IdentifierSchema,
    request: z.string().min(1).max(2_000),
    targetGesture: z.literal("fist").default("fist"),
    source: z.enum(["natural_language", "teach_by_demo"]).default("natural_language"),
    approvedKeyframes: z.array(ApprovedKeyframeSchema).min(6).max(10).optional(),
    keyframeConsent: z.literal(true).optional(),
  })
  .strict()
  .superRefine((request, context) => {
    const hasFrames = Boolean(request.approvedKeyframes?.length);
    if (hasFrames && request.source !== "teach_by_demo") {
      context.addIssue({
        code: "custom",
        message: "Approved keyframes are only accepted for Teach by Demo.",
        path: ["source"],
      });
    }
    if (hasFrames && request.keyframeConsent !== true) {
      context.addIssue({
        code: "custom",
        message: "Explicit keyframe approval is required.",
        path: ["keyframeConsent"],
      });
    }
    if (request.source === "teach_by_demo" && !hasFrames) {
      context.addIssue({
        code: "custom",
        message: "Teach by Demo requires 6 to 10 approved keyframes.",
        path: ["approvedKeyframes"],
      });
    }
  });

export type BrowserPlannerRequest = z.infer<typeof BrowserPlannerRequestSchema>;

export type BrowserPlannerResponse =
  | {
      schemaVersion: 1;
      requestId: string;
      status: "planned";
      command: BrowserCommand;
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
