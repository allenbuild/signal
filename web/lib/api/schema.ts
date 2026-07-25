import { z } from "zod";
import { ACTION_TYPES, GESTURES, MODES } from "./types";
import { isSafePublicUrl } from "./safety-url";

const Identifier = z.string().min(1).max(64).regex(/^[A-Za-z0-9][A-Za-z0-9._-]*$/);
const BundleIdentifier = z.string().min(3).max(255).regex(/^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$/);
const FailurePolicy = z.enum(["stop", "continue", "ask"]);
const Confirmation = z.object({
  mode: z.enum(["none", "first_run", "every_run"]),
  reason: z.string().max(160),
}).strict();
const SecretReference = z.object({
  id: Identifier,
  provider: z.enum(["discord", "slack", "http_bearer", "http_basic", "http_api_key"]),
  purpose: z.string().min(1).max(120),
  storage: z.literal("keychain_or_server_environment"),
}).strict();

const typedAction = <T extends string, S extends z.ZodType>(
  type: T,
  parameters: S,
) => z.object({ type: z.literal(type), parameters }).strict();

const PublicHTTPSDestination = z.object({
  url: z.string().min(9).max(2048).regex(/^https:\/\/[^\s]+$/),
  networkPolicy: z.literal("public_https_only"),
}).strict().superRefine((value, context) => {
  if (!isSafePublicUrl(value.url)) {
    context.addIssue({ code: "custom", message: "URL must target the public HTTPS internet.", path: ["url"] });
  }
});

const OpenApplicationAction = typedAction("open_application", z.object({
  bundleIdentifier: BundleIdentifier,
  applicationName: z.string().max(120).optional(),
}).strict());
const OpenURLAction = typedAction("open_url", PublicHTTPSDestination);
const OpenDeepLinkAction = typedAction("open_deep_link", z.object({
  scheme: z.enum(["facetime", "macappstore", "mailto", "music", "shortcuts", "spotify"]),
  url: z.string().min(3).max(2048).regex(/^[A-Za-z][A-Za-z0-9+.-]*:/),
}).strict()).superRefine((value, context) => {
  try {
    if (new URL(value.parameters.url).protocol.replace(":", "") !== value.parameters.scheme) {
      context.addIssue({ code: "custom", message: "Deep-link scheme must match.", path: ["parameters", "url"] });
    }
  } catch {
    context.addIssue({ code: "custom", message: "Deep link is invalid.", path: ["parameters", "url"] });
  }
});
const KeyboardShortcutAction = typedAction("keyboard_shortcut", z.object({
  key: z.string().min(1).max(24),
  modifiers: z.array(z.enum(["command", "control", "option", "shift"])).max(4),
}).strict().superRefine((value, context) => {
  if (new Set(value.modifiers).size !== value.modifiers.length) {
    context.addIssue({ code: "custom", message: "Modifiers must be unique.", path: ["modifiers"] });
  }
}));
const TypeTextAction = typedAction("type_text", z.object({
  text: z.string().max(4000),
  containsSensitiveData: z.literal(false),
}).strict());
const WaitAction = typedAction("wait", z.object({
  durationMs: z.number().int().min(0).max(30_000),
}).strict());
const ShowNotificationAction = typedAction("show_notification", z.object({
  title: z.string().min(1).max(120),
  body: z.string().max(500),
}).strict());
const SpeakTextAction = typedAction("speak_text", z.object({
  text: z.string().min(1).max(500),
  voice: z.string().max(80).optional(),
  rate: z.number().min(0.25).max(2).optional(),
}).strict());
const PlaySoundAction = typedAction("play_sound", z.object({
  sound: z.enum([
    "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
    "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
  ]),
}).strict());
const SetClipboardAction = typedAction("set_clipboard", z.object({
  text: z.string().max(10_000),
  containsSensitiveData: z.literal(false),
}).strict());
const ReadClipboardAndTransformAction = typedAction("read_clipboard_and_transform", z.object({
  transform: z.enum(["lowercase", "titlecase", "trim", "uppercase", "url_encode"]),
  destination: z.literal("clipboard"),
  maximumInputCharacters: z.number().int().min(1).max(10_000).optional(),
}).strict());
const RunAppleShortcutAction = typedAction("run_apple_shortcut", z.object({
  shortcutName: z.string().min(1).max(120),
  input: z.string().max(2000).optional(),
}).strict());
const RunAppleScriptTemplateAction = typedAction("run_applescript_template", z.object({
  templateId: z.enum(["activate_application", "create_textedit_document", "open_system_settings_pane"]),
  arguments: z.record(Identifier, z.string().max(500)).refine((value) => Object.keys(value).length <= 8),
}).strict());
const HTTPRequestAction = typedAction("http_request", z.object({
  method: z.enum(["GET", "POST", "PUT", "PATCH", "DELETE"]),
  url: z.string().min(9).max(2048).regex(/^https:\/\/[^\s]+$/),
  networkPolicy: z.literal("public_https_only"),
  headers: z.array(z.object({
    name: z.enum(["Accept", "Content-Type", "User-Agent"]),
    value: z.string().max(200),
  }).strict()).max(8),
  bodyTemplate: z.string().max(16_000).optional(),
  secretRefs: z.array(Identifier).max(4),
  maximumResponseBytes: z.number().int().min(0).max(1_048_576),
}).strict().superRefine((value, context) => {
  if (!isSafePublicUrl(value.url)) {
    context.addIssue({ code: "custom", message: "URL must target the public HTTPS internet.", path: ["url"] });
  }
  if (new Set(value.secretRefs).size !== value.secretRefs.length) {
    context.addIssue({ code: "custom", message: "Secret references must be unique.", path: ["secretRefs"] });
  }
}));
const DiscordWebhookAction = typedAction("discord_webhook", z.object({
  secretRef: Identifier,
  message: z.string().min(1).max(1800),
  fallback: z.literal("local_receipt"),
}).strict());
const SlackWebhookAction = typedAction("slack_webhook", z.object({
  secretRef: Identifier,
  message: z.string().min(1).max(3000),
  fallback: z.literal("local_receipt"),
}).strict());
const MediaControlAction = typedAction("media_control", z.object({
  command: z.enum(["next", "pause", "play", "previous", "toggle_play_pause"]),
}).strict());
const SetVolumeAction = typedAction("set_volume", z.object({
  percent: z.number().int().min(0).max(100),
}).strict());
const ShowOverlayAction = typedAction("show_overlay", z.object({
  title: z.string().max(120),
  body: z.string().max(500),
  durationMs: z.number().int().min(250).max(10_000),
}).strict());
const FocusApplicationAction = typedAction("focus_application", z.object({
  bundleIdentifier: BundleIdentifier,
}).strict());
const ClickScreenPointAction = typedAction("click_screen_point", z.object({
  x: z.number().min(0).max(1),
  y: z.number().min(0).max(1),
  coordinateSpace: z.literal("normalized_active_display"),
}).strict());
const ScrollAmountAction = typedAction("scroll_amount", z.object({
  horizontal: z.number().int().min(-10_000).max(10_000),
  vertical: z.number().int().min(-10_000).max(10_000),
}).strict());
const ZoomStepsAction = typedAction("zoom_steps", z.object({
  steps: z.number().int().min(-20).max(20).refine((value) => value !== 0),
  bundleIdentifier: z.string().max(255).optional(),
}).strict());

export const NonConditionalActionSchema = z.discriminatedUnion("type", [
  OpenApplicationAction,
  OpenURLAction,
  OpenDeepLinkAction,
  KeyboardShortcutAction,
  TypeTextAction,
  WaitAction,
  ShowNotificationAction,
  SpeakTextAction,
  PlaySoundAction,
  SetClipboardAction,
  ReadClipboardAndTransformAction,
  RunAppleShortcutAction,
  RunAppleScriptTemplateAction,
  HTTPRequestAction,
  DiscordWebhookAction,
  SlackWebhookAction,
  MediaControlAction,
  SetVolumeAction,
  ShowOverlayAction,
  FocusApplicationAction,
  ClickScreenPointAction,
  ScrollAmountAction,
  ZoomStepsAction,
]);

const ConditionalAction = typedAction("conditional", z.object({
  condition: z.object({
    type: z.enum(["application_is_frontmost", "clipboard_is_empty", "network_reachable"]),
    value: z.string().max(2048),
  }).strict(),
  ifTrue: z.array(NonConditionalActionSchema).max(10),
  ifFalse: z.array(NonConditionalActionSchema).max(10),
}).strict());

export const ActionSchema = z.union([NonConditionalActionSchema, ConditionalAction]);
export const StepSchema = z.object({
  id: Identifier,
  action: ActionSchema,
  timeoutMs: z.number().int().min(100).max(60_000),
  onFailure: FailurePolicy,
  confirmation: Confirmation,
}).strict();

export const ActionPlanSchema = z.object({
  schemaVersion: z.literal(1),
  id: Identifier,
  name: z.string().min(1).max(80),
  description: z.string().max(500),
  steps: z.array(StepSchema).min(1).max(50),
  timeoutMs: z.number().int().min(100).max(300_000),
  onFailure: FailurePolicy,
  confirmation: Confirmation,
  createdSource: z.enum(["visual", "natural_language", "demo_recording", "import"]),
  secretReferences: z.array(SecretReference).max(20),
}).strict().superRefine((value, context) => {
  const stepIds = value.steps.map((step) => step.id);
  if (new Set(stepIds).size !== stepIds.length) {
    context.addIssue({ code: "custom", message: "Step identifiers must be unique.", path: ["steps"] });
  }
  const secretIds = value.secretReferences.map((reference) => reference.id);
  if (new Set(secretIds).size !== secretIds.length) {
    context.addIssue({ code: "custom", message: "Secret reference identifiers must be unique.", path: ["secretReferences"] });
  }
  const declared = new Set(secretIds);
  const checkAction = (action: z.infer<typeof ActionSchema>, path: PropertyKey[]) => {
    const parameters = action.parameters as Record<string, unknown>;
    const referenced = [
      ...(typeof parameters.secretRef === "string" ? [parameters.secretRef] : []),
      ...(Array.isArray(parameters.secretRefs)
        ? parameters.secretRefs.filter((item): item is string => typeof item === "string")
        : []),
    ];
    for (const reference of referenced) {
      if (!declared.has(reference)) {
        context.addIssue({
          code: "custom",
          message: "Action uses an undeclared secret reference.",
          path: [...path, "parameters", "secretRef"],
        });
      }
    }
    if (action.type === "conditional") {
      action.parameters.ifTrue.forEach((nested, index) => checkAction(nested, [...path, "parameters", "ifTrue", index]));
      action.parameters.ifFalse.forEach((nested, index) => checkAction(nested, [...path, "parameters", "ifFalse", index]));
    }
  };
  value.steps.forEach((step, index) => checkAction(step.action, ["steps", index, "action"]));
});

export const GestureMappingSchema = z.object({
  gesture: z.enum(GESTURES),
  enabled: z.boolean(),
  holdDurationMs: z.number().int().min(250).max(3_000),
  cooldownMs: z.number().int().min(0).max(10_000),
  activation: z.enum(["one_shot", "repeat"]),
  repeatIntervalMs: z.number().int().min(500).max(10_000).optional(),
  allowedBundleIdentifiers: z.array(BundleIdentifier).max(20),
  preferredMode: z.enum(["commands", "hybrid"]).optional(),
  plan: ActionPlanSchema,
}).strict().superRefine((value, context) => {
  if (new Set(value.allowedBundleIdentifiers).size !== value.allowedBundleIdentifiers.length) {
    context.addIssue({ code: "custom", message: "Allowed bundle identifiers must be unique.", path: ["allowedBundleIdentifiers"] });
  }
  if (value.activation === "repeat" && value.repeatIntervalMs === undefined) {
    context.addIssue({ code: "custom", message: "Repeat mappings require repeatIntervalMs.", path: ["repeatIntervalMs"] });
  }
});

export const ShareMetadataSchema = z.object({
  visibility: z.enum(["private", "unlisted"]),
  shareCode: z.string().regex(/^SIG1-[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$/).optional(),
}).strict();

export const ProfileSchema = z.object({
  schemaVersion: z.literal(1),
  id: Identifier,
  name: z.string().min(1).max(80),
  description: z.string().max(500),
  preferredMode: z.enum(MODES),
  hybridOneBehavior: z.enum(["pointer", "command"]),
  mappings: z.array(GestureMappingSchema).max(9),
  share: ShareMetadataSchema,
}).strict().superRefine((value, context) => {
  const gestures = value.mappings.map((mapping) => mapping.gesture);
  if (new Set(gestures).size !== gestures.length) {
    context.addIssue({ code: "custom", message: "Each gesture may be mapped once.", path: ["mappings"] });
  }
});

export const PlannerRequestSchema = z.object({
  schemaVersion: z.literal(1),
  requestId: Identifier,
  request: z.string().min(3).max(4_000),
  targetGesture: z.enum(GESTURES).optional(),
  actionCatalog: z.array(z.enum(ACTION_TYPES)).max(32),
}).strict();

export const PlannedResponseSchema = z.object({
  schemaVersion: z.literal(1),
  requestId: Identifier,
  status: z.literal("planned"),
  plan: ActionPlanSchema,
  warnings: z.array(z.string().max(240)).max(10),
  usedDeterministicFallback: z.boolean(),
}).strict();

export const ClarificationResponseSchema = z.object({
  schemaVersion: z.literal(1),
  requestId: Identifier,
  status: z.literal("needs_clarification"),
  question: z.string().min(1).max(300),
  missingFields: z.array(z.string().min(1).max(80)).min(1).max(10),
}).strict();

export const PlannerResponseSchema = z.union([
  PlannedResponseSchema,
  ClarificationResponseSchema,
]);
