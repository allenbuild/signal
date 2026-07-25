import { z } from "zod";

import {
  checkPublicHttpsLiteralHost,
  findSecretMaterial,
} from "./security";

export const SCHEMA_VERSION = 1 as const;
export const MAX_PLAN_ACTIONS = 50;
export const MAX_PLANNER_REQUEST_BYTES = 16 * 1024;

export const gestureValues = [
  "one",
  "two",
  "three",
  "four",
  "five",
  "fist",
  "thumbs_up",
  "thumbs_down",
  "c_shape",
] as const;

export const actionTypeValues = [
  "open_application",
  "open_url",
  "open_deep_link",
  "keyboard_shortcut",
  "type_text",
  "wait",
  "show_notification",
  "speak_text",
  "play_sound",
  "set_clipboard",
  "read_clipboard_and_transform",
  "run_apple_shortcut",
  "run_applescript_template",
  "http_request",
  "discord_webhook",
  "slack_webhook",
  "media_control",
  "set_volume",
  "show_overlay",
  "focus_application",
  "click_screen_point",
  "scroll_amount",
  "zoom_steps",
  "conditional",
] as const;

const identifierPattern = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const bundleIdentifierPattern = /^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$/;
const publicHttpsPattern = /^https:\/\/[^\s]+$/;
const shareCodePattern = /^SIG1-[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$/;

export const identifierSchema = z.string().min(1).max(64).regex(identifierPattern);
export const requestIdSchema = identifierSchema;
export const gestureSchema = z.enum(gestureValues);
export const actionTypeSchema = z.enum(actionTypeValues);

const failurePolicySchema = z.enum(["stop", "continue", "ask"]);
const confirmationSchema = z
  .object({
    mode: z.enum(["none", "first_run", "every_run"]),
    reason: z.string().max(160),
  })
  .strict();

export const secretReferenceSchema = z
  .object({
    id: identifierSchema,
    provider: z.enum([
      "discord",
      "slack",
      "http_bearer",
      "http_basic",
      "http_api_key",
    ]),
    purpose: z.string().min(1).max(120),
    storage: z.literal("keychain_or_server_environment"),
  })
  .strict();

const publicHttpsDestinationSchema = z
  .object({
    url: z.string().min(9).max(2048).regex(publicHttpsPattern),
    networkPolicy: z.literal("public_https_only"),
  })
  .strict();

const action = <T extends string, S extends z.ZodTypeAny>(
  type: T,
  parameters: S,
) =>
  z
    .object({
      type: z.literal(type),
      parameters,
    })
    .strict();

const openApplicationActionSchema = action(
  "open_application",
  z
    .object({
      bundleIdentifier: z
        .string()
        .min(3)
        .max(255)
        .regex(bundleIdentifierPattern),
      applicationName: z.string().max(120).optional(),
    })
    .strict(),
);

const openUrlActionSchema = action(
  "open_url",
  publicHttpsDestinationSchema,
);

const openDeepLinkActionSchema = action(
  "open_deep_link",
  z
    .object({
      scheme: z.enum([
        "facetime",
        "macappstore",
        "mailto",
        "music",
        "shortcuts",
        "spotify",
      ]),
      url: z
        .string()
        .min(3)
        .max(2048)
        .regex(/^[A-Za-z][A-Za-z0-9+.-]*:/),
    })
    .strict()
    .superRefine((parameters, ctx) => {
      const parsedScheme = parameters.url.slice(0, parameters.url.indexOf(":"));
      if (parsedScheme.toLowerCase() !== parameters.scheme) {
        ctx.addIssue({
          code: "custom",
          path: ["url"],
          message: "URL scheme must match the declared allowlisted scheme",
        });
      }
    }),
);

const keyboardShortcutActionSchema = action(
  "keyboard_shortcut",
  z
    .object({
      key: z.string().min(1).max(24),
      modifiers: z
        .array(z.enum(["command", "control", "option", "shift"]))
        .max(4)
        .refine((items) => new Set(items).size === items.length, {
          message: "Modifier values must be unique",
        }),
    })
    .strict(),
);

const typeTextActionSchema = action(
  "type_text",
  z
    .object({
      text: z.string().max(4000),
      containsSensitiveData: z.literal(false),
    })
    .strict(),
);

const waitActionSchema = action(
  "wait",
  z.object({ durationMs: z.number().int().min(0).max(30_000) }).strict(),
);

const showNotificationActionSchema = action(
  "show_notification",
  z
    .object({
      title: z.string().min(1).max(120),
      body: z.string().max(500),
    })
    .strict(),
);

const speakTextActionSchema = action(
  "speak_text",
  z
    .object({
      text: z.string().min(1).max(500),
      voice: z.string().max(80).optional(),
      rate: z.number().min(0.25).max(2).optional(),
    })
    .strict(),
);

const playSoundActionSchema = action(
  "play_sound",
  z
    .object({
      sound: z.enum([
        "Basso",
        "Blow",
        "Bottle",
        "Frog",
        "Funk",
        "Glass",
        "Hero",
        "Morse",
        "Ping",
        "Pop",
        "Purr",
        "Sosumi",
        "Submarine",
        "Tink",
      ]),
    })
    .strict(),
);

const setClipboardActionSchema = action(
  "set_clipboard",
  z
    .object({
      text: z.string().max(10_000),
      containsSensitiveData: z.literal(false),
    })
    .strict(),
);

const readClipboardAndTransformActionSchema = action(
  "read_clipboard_and_transform",
  z
    .object({
      transform: z.enum([
        "lowercase",
        "titlecase",
        "trim",
        "uppercase",
        "url_encode",
      ]),
      destination: z.literal("clipboard"),
      maximumInputCharacters: z.number().int().min(1).max(10_000).optional(),
    })
    .strict(),
);

const runAppleShortcutActionSchema = action(
  "run_apple_shortcut",
  z
    .object({
      shortcutName: z.string().min(1).max(120),
      input: z.string().max(2000).optional(),
    })
    .strict(),
);

const runAppleScriptTemplateActionSchema = action(
  "run_applescript_template",
  z
    .object({
      templateId: z.enum([
        "activate_application",
        "create_textedit_document",
        "open_system_settings_pane",
      ]),
      arguments: z
        .record(identifierSchema, z.string().max(500))
        .refine((value) => Object.keys(value).length <= 8, {
          message: "At most 8 template arguments are allowed",
        }),
    })
    .strict(),
);

const httpRequestActionSchema = action(
  "http_request",
  z
    .object({
      method: z.enum(["GET", "POST", "PUT", "PATCH", "DELETE"]),
      url: z.string().min(9).max(2048).regex(publicHttpsPattern),
      networkPolicy: z.literal("public_https_only"),
      headers: z
        .array(
          z
            .object({
              name: z.enum(["Accept", "Content-Type", "User-Agent"]),
              value: z.string().max(200),
            })
            .strict(),
        )
        .max(8),
      bodyTemplate: z.string().max(16_000).optional(),
      secretRefs: z
        .array(identifierSchema)
        .max(4)
        .refine((items) => new Set(items).size === items.length, {
          message: "HTTP secret references must be unique",
        }),
      maximumResponseBytes: z.number().int().min(0).max(1_048_576),
    })
    .strict()
    .superRefine((parameters, ctx) => {
      const headerNames = parameters.headers.map((header) => header.name);
      if (new Set(headerNames).size !== headerNames.length) {
        ctx.addIssue({
          code: "custom",
          path: ["headers"],
          message: "Duplicate HTTP header names are not allowed",
        });
      }
    }),
);

const discordWebhookActionSchema = action(
  "discord_webhook",
  z
    .object({
      secretRef: identifierSchema,
      message: z.string().min(1).max(1800),
      fallback: z.literal("local_receipt"),
    })
    .strict(),
);

const slackWebhookActionSchema = action(
  "slack_webhook",
  z
    .object({
      secretRef: identifierSchema,
      message: z.string().min(1).max(3000),
      fallback: z.literal("local_receipt"),
    })
    .strict(),
);

const mediaControlActionSchema = action(
  "media_control",
  z
    .object({
      command: z.enum([
        "next",
        "pause",
        "play",
        "previous",
        "toggle_play_pause",
      ]),
    })
    .strict(),
);

const setVolumeActionSchema = action(
  "set_volume",
  z.object({ percent: z.number().int().min(0).max(100) }).strict(),
);

const showOverlayActionSchema = action(
  "show_overlay",
  z
    .object({
      title: z.string().max(120),
      body: z.string().max(500),
      durationMs: z.number().int().min(250).max(10_000),
    })
    .strict(),
);

const focusApplicationActionSchema = action(
  "focus_application",
  z
    .object({
      bundleIdentifier: z
        .string()
        .min(3)
        .max(255)
        .regex(bundleIdentifierPattern),
    })
    .strict(),
);

const clickScreenPointActionSchema = action(
  "click_screen_point",
  z
    .object({
      x: z.number().min(0).max(1),
      y: z.number().min(0).max(1),
      coordinateSpace: z.literal("normalized_active_display"),
    })
    .strict(),
);

const scrollAmountActionSchema = action(
  "scroll_amount",
  z
    .object({
      horizontal: z.number().int().min(-10_000).max(10_000),
      vertical: z.number().int().min(-10_000).max(10_000),
    })
    .strict(),
);

const zoomStepsActionSchema = action(
  "zoom_steps",
  z
    .object({
      steps: z
        .number()
        .int()
        .min(-20)
        .max(20)
        .refine((value) => value !== 0, { message: "Zoom steps cannot be zero" }),
      bundleIdentifier: z.string().max(255).optional(),
    })
    .strict(),
);

export const nonConditionalActionSchema = z.discriminatedUnion("type", [
  openApplicationActionSchema,
  openUrlActionSchema,
  openDeepLinkActionSchema,
  keyboardShortcutActionSchema,
  typeTextActionSchema,
  waitActionSchema,
  showNotificationActionSchema,
  speakTextActionSchema,
  playSoundActionSchema,
  setClipboardActionSchema,
  readClipboardAndTransformActionSchema,
  runAppleShortcutActionSchema,
  runAppleScriptTemplateActionSchema,
  httpRequestActionSchema,
  discordWebhookActionSchema,
  slackWebhookActionSchema,
  mediaControlActionSchema,
  setVolumeActionSchema,
  showOverlayActionSchema,
  focusApplicationActionSchema,
  clickScreenPointActionSchema,
  scrollAmountActionSchema,
  zoomStepsActionSchema,
]);

const conditionalActionSchema = action(
  "conditional",
  z
    .object({
      condition: z
        .object({
          type: z.enum([
            "application_is_frontmost",
            "clipboard_is_empty",
            "network_reachable",
          ]),
          value: z.string().max(2048),
        })
        .strict(),
      ifTrue: z.array(nonConditionalActionSchema).max(10),
      ifFalse: z.array(nonConditionalActionSchema).max(10),
    })
    .strict(),
);

export const actionSchema = z.discriminatedUnion("type", [
  ...nonConditionalActionSchema.options,
  conditionalActionSchema,
]);

const stepSchema = z
  .object({
    id: identifierSchema,
    action: actionSchema,
    timeoutMs: z.number().int().min(100).max(60_000),
    onFailure: failurePolicySchema,
    confirmation: confirmationSchema,
  })
  .strict();

const actionPlanShapeSchema = z
  .object({
    schemaVersion: z.literal(SCHEMA_VERSION),
    id: identifierSchema,
    name: z.string().min(1).max(80),
    description: z.string().max(500),
    steps: z.array(stepSchema).min(1).max(MAX_PLAN_ACTIONS),
    timeoutMs: z.number().int().min(100).max(300_000),
    onFailure: failurePolicySchema,
    confirmation: confirmationSchema,
    createdSource: z.enum([
      "visual",
      "natural_language",
      "demo_recording",
      "import",
    ]),
    secretReferences: z.array(secretReferenceSchema).max(20),
  })
  .strict();

type Action = z.infer<typeof actionSchema>;

function actionsWithPaths(plan: z.infer<typeof actionPlanShapeSchema>) {
  const entries: Array<{ action: Action; path: (string | number)[] }> = [];
  plan.steps.forEach((step, stepIndex) => {
    const path = ["steps", stepIndex, "action"];
    entries.push({ action: step.action, path });
    if (step.action.type === "conditional") {
      const conditional = step.action as z.infer<typeof conditionalActionSchema>;
      (["ifTrue", "ifFalse"] as const).forEach((branch) => {
        conditional.parameters[branch].forEach((nestedAction, nestedIndex) => {
          entries.push({
            action: nestedAction,
            path: [
              ...path,
              "parameters",
              branch,
              nestedIndex,
            ],
          });
        });
      });
    }
  });
  return entries;
}

function addSecretIssues(
  value: unknown,
  ctx: z.RefinementCtx,
  pathPrefix: (string | number)[] = [],
) {
  for (const finding of findSecretMaterial(value)) {
    ctx.addIssue({
      code: "custom",
      path: [...pathPrefix, ...finding.path],
      message: `Portable JSON contains forbidden ${finding.kind}`,
    });
  }
}

export const actionPlanSchema = actionPlanShapeSchema.superRefine((plan, ctx) => {
  const stepIds = new Set<string>();
  plan.steps.forEach((step, index) => {
    if (stepIds.has(step.id)) {
      ctx.addIssue({
        code: "custom",
        path: ["steps", index, "id"],
        message: "Step IDs must be unique",
      });
    }
    stepIds.add(step.id);
  });

  const references = new Map<string, (typeof plan.secretReferences)[number]>();
  plan.secretReferences.forEach((reference, index) => {
    if (references.has(reference.id)) {
      ctx.addIssue({
        code: "custom",
        path: ["secretReferences", index, "id"],
        message: "Secret reference IDs must be unique",
      });
    }
    references.set(reference.id, reference);
  });

  let maximumChosenActionCount = plan.steps.length;
  for (const step of plan.steps) {
    if (step.action.type === "conditional") {
      maximumChosenActionCount += Math.max(
        step.action.parameters.ifTrue.length,
        step.action.parameters.ifFalse.length,
      );
    }
  }
  if (maximumChosenActionCount > MAX_PLAN_ACTIONS) {
    ctx.addIssue({
      code: "custom",
      path: ["steps"],
      message: "Top-level and chosen conditional actions may not exceed 50",
    });
  }

  for (const entry of actionsWithPaths(plan)) {
    const { action: currentAction, path } = entry;
    if (
      currentAction.type === "open_url" ||
      currentAction.type === "http_request"
    ) {
      const destination = checkPublicHttpsLiteralHost(
        currentAction.parameters.url,
      );
      if (!destination.ok) {
        ctx.addIssue({
          code: "custom",
          path: [...path, "parameters", "url"],
          message: `Unsafe public HTTPS destination: ${destination.reason}`,
        });
      }
    }

    if (
      currentAction.type === "discord_webhook" ||
      currentAction.type === "slack_webhook"
    ) {
      const expectedProvider = currentAction.type === "discord_webhook"
        ? "discord"
        : "slack";
      const reference = references.get(currentAction.parameters.secretRef);
      if (!reference) {
        ctx.addIssue({
          code: "custom",
          path: [...path, "parameters", "secretRef"],
          message: "Action uses an undeclared secret reference",
        });
      } else if (reference.provider !== expectedProvider) {
        ctx.addIssue({
          code: "custom",
          path: [...path, "parameters", "secretRef"],
          message: `Secret reference provider must be ${expectedProvider}`,
        });
      }
    }

    if (currentAction.type === "http_request") {
      for (const [index, referenceId] of currentAction.parameters.secretRefs.entries()) {
        const reference = references.get(referenceId);
        if (!reference) {
          ctx.addIssue({
            code: "custom",
            path: [...path, "parameters", "secretRefs", index],
            message: "HTTP action uses an undeclared secret reference",
          });
        } else if (!reference.provider.startsWith("http_")) {
          ctx.addIssue({
            code: "custom",
            path: [...path, "parameters", "secretRefs", index],
            message: "HTTP action requires an HTTP secret-reference provider",
          });
        }
      }

      const template = currentAction.parameters.bodyTemplate;
      if (template?.includes("${secret:")) {
        const validPlaceholders = new Set<string>();
        const placeholderPattern = /\$\{secret:([^}]*)\}/g;
        let match: RegExpExecArray | null;
        while ((match = placeholderPattern.exec(template)) !== null) {
          const referenceId = match[1];
          if (!identifierPattern.test(referenceId)) {
            ctx.addIssue({
              code: "custom",
              path: [...path, "parameters", "bodyTemplate"],
              message: "Secret placeholder contains an invalid reference ID",
            });
          } else {
            validPlaceholders.add(referenceId);
          }
        }
        const withoutPlaceholders = template.replace(placeholderPattern, "");
        if (withoutPlaceholders.includes("${secret:")) {
          ctx.addIssue({
            code: "custom",
            path: [...path, "parameters", "bodyTemplate"],
            message: "Secret placeholder is malformed",
          });
        }
        for (const referenceId of validPlaceholders) {
          if (!currentAction.parameters.secretRefs.includes(referenceId)) {
            ctx.addIssue({
              code: "custom",
              path: [...path, "parameters", "bodyTemplate"],
              message: "Body template uses a secret not listed by this action",
            });
          }
        }
      }
    }
  }

  addSecretIssues(plan, ctx);
});

const gestureMappingSchema = z
  .object({
    gesture: gestureSchema,
    enabled: z.boolean(),
    holdDurationMs: z.number().int().min(250).max(3000),
    cooldownMs: z.number().int().min(0).max(10_000),
    activation: z.enum(["one_shot", "repeat"]),
    repeatIntervalMs: z.number().int().min(500).max(10_000).optional(),
    allowedBundleIdentifiers: z
      .array(
        z.string().min(3).max(255).regex(bundleIdentifierPattern),
      )
      .max(20)
      .refine((items) => new Set(items).size === items.length, {
        message: "Allowed bundle identifiers must be unique",
      }),
    preferredMode: z.enum(["commands", "hybrid"]).optional(),
    plan: actionPlanSchema,
  })
  .strict()
  .superRefine((mapping, ctx) => {
    if (mapping.activation === "repeat" && mapping.repeatIntervalMs === undefined) {
      ctx.addIssue({
        code: "custom",
        path: ["repeatIntervalMs"],
        message: "Repeat mappings require repeatIntervalMs",
      });
    }
    if (mapping.activation === "one_shot" && mapping.repeatIntervalMs !== undefined) {
      ctx.addIssue({
        code: "custom",
        path: ["repeatIntervalMs"],
        message: "One-shot mappings cannot define repeatIntervalMs",
      });
    }
  });

export const profileSchema = z
  .object({
    schemaVersion: z.literal(SCHEMA_VERSION),
    id: identifierSchema,
    name: z.string().min(1).max(80),
    description: z.string().max(500),
    preferredMode: z.enum(["touch", "commands", "hybrid"]),
    hybridOneBehavior: z.enum(["pointer", "command"]),
    mappings: z.array(gestureMappingSchema).max(9),
    share: z
      .object({
        visibility: z.enum(["private", "unlisted"]),
        shareCode: z.string().regex(shareCodePattern).optional(),
      })
      .strict(),
  })
  .strict()
  .superRefine((profile, ctx) => {
    const gestures = new Set<string>();
    profile.mappings.forEach((mapping, index) => {
      if (gestures.has(mapping.gesture)) {
        ctx.addIssue({
          code: "custom",
          path: ["mappings", index, "gesture"],
          message: "Gesture mappings must be unique",
        });
      }
      gestures.add(mapping.gesture);
    });
    if (profile.share.visibility === "private" && profile.share.shareCode) {
      ctx.addIssue({
        code: "custom",
        path: ["share", "shareCode"],
        message: "Private profiles cannot contain or return a share code",
      });
    }
    addSecretIssues(profile, ctx);
  });

export const plannerRequestSchema = z
  .object({
    schemaVersion: z.literal(SCHEMA_VERSION),
    requestId: requestIdSchema,
    request: z.string().min(1).max(4000),
    targetGesture: gestureSchema,
    actionCatalog: z
      .array(actionTypeSchema)
      .max(32)
      .refine((items) => new Set(items).size === items.length, {
        message: "Advertised action-catalog entries must be unique",
      }),
  })
  .strict()
  .superRefine((request, ctx) => addSecretIssues(request, ctx));

const plannedResponseSchema = z
  .object({
    schemaVersion: z.literal(SCHEMA_VERSION),
    requestId: requestIdSchema,
    status: z.literal("planned"),
    plan: actionPlanSchema,
    warnings: z.array(z.string().max(240)).max(10),
    usedDeterministicFallback: z.boolean(),
  })
  .strict();

const clarificationResponseSchema = z
  .object({
    schemaVersion: z.literal(SCHEMA_VERSION),
    requestId: requestIdSchema,
    status: z.literal("needs_clarification"),
    question: z.string().min(1).max(300),
    missingFields: z
      .array(z.string().min(1).max(80))
      .min(1)
      .max(10)
      .refine((items) => new Set(items).size === items.length, {
        message: "Missing fields must be unique",
      }),
  })
  .strict();

export const plannerResponseSchema = z
  .discriminatedUnion("status", [
    plannedResponseSchema,
    clarificationResponseSchema,
  ])
  .superRefine((response, ctx) => addSecretIssues(response, ctx));

export const profileCreateRequestSchema = z
  .object({ profile: profileSchema })
  .strict();

export const profileCreateResponseSchema = z
  .object({
    schemaVersion: z.literal(SCHEMA_VERSION),
    shareCode: z.string().regex(shareCodePattern),
    profileURL: z.string().url().max(2048).regex(publicHttpsPattern),
  })
  .strict();

export function hasValidPlannerRequestByteLength(serializedBody: Uint8Array | string) {
  const byteLength = typeof serializedBody === "string"
    ? new TextEncoder().encode(serializedBody).byteLength
    : serializedBody.byteLength;
  return byteLength <= MAX_PLANNER_REQUEST_BYTES;
}

export type ActionPlan = z.infer<typeof actionPlanSchema>;
export type Profile = z.infer<typeof profileSchema>;
export type PlannerRequest = z.infer<typeof plannerRequestSchema>;
export type PlannerResponse = z.infer<typeof plannerResponseSchema>;
