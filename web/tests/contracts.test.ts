import { describe, expect, it } from "vitest";

import {
  actionPlanSchema,
  hasValidPlannerRequestByteLength,
  plannerRequestSchema,
  plannerResponseSchema,
  profileSchema,
} from "../lib/contracts";
import plannerResponseExample from "../../shared/examples/planner-response.json";
import seededDemoProfile from "../../shared/seeded-demo-profile.json";

const confirmation = {
  mode: "first_run" as const,
  reason: "Show the exact effect before execution.",
};

function notificationAction(label = "Ready") {
  return {
    type: "show_notification" as const,
    parameters: { title: label, body: "" },
  };
}

function step(id: string, action: unknown = notificationAction()) {
  return {
    id,
    action,
    timeoutMs: 1_000,
    onFailure: "stop" as const,
    confirmation,
  };
}

function validPlan() {
  return {
    schemaVersion: 1 as const,
    id: "test.plan",
    name: "Test plan",
    description: "A safe test plan.",
    steps: [step("notify")],
    timeoutMs: 10_000,
    onFailure: "stop" as const,
    confirmation,
    createdSource: "natural_language" as const,
    secretReferences: [],
  };
}

function validProfile() {
  return {
    schemaVersion: 1 as const,
    id: "test.profile",
    name: "Test profile",
    description: "",
    preferredMode: "commands" as const,
    hybridOneBehavior: "pointer" as const,
    mappings: [
      {
        gesture: "thumbs_up" as const,
        enabled: true,
        holdDurationMs: 600,
        cooldownMs: 900,
        activation: "one_shot" as const,
        allowedBundleIdentifiers: [],
        plan: validPlan(),
      },
    ],
    share: { visibility: "private" as const },
  };
}

describe("actionPlanSchema", () => {
  it("accepts a strict frozen v1 plan", () => {
    expect(actionPlanSchema.parse(validPlan())).toEqual(validPlan());
  });

  it("rejects future versions, unknown properties, and unsafe actions", () => {
    expect(
      actionPlanSchema.safeParse({ ...validPlan(), schemaVersion: 2 }).success,
    ).toBe(false);
    expect(
      actionPlanSchema.safeParse({ ...validPlan(), unexpected: true }).success,
    ).toBe(false);
    expect(
      actionPlanSchema.safeParse({
        ...validPlan(),
        steps: [
          step("unsafe", {
            type: "shell_command",
            parameters: { command: "whoami" },
          } as never),
        ],
      }).success,
    ).toBe(false);
  });

  it("rejects duplicate step and secret-reference IDs", () => {
    const duplicateSteps = {
      ...validPlan(),
      steps: [step("same"), step("same")],
    };
    expect(actionPlanSchema.safeParse(duplicateSteps).success).toBe(false);

    const duplicateReferences = {
      ...validPlan(),
      secretReferences: [
        {
          id: "same",
          provider: "discord",
          purpose: "First",
          storage: "keychain_or_server_environment",
        },
        {
          id: "same",
          provider: "slack",
          purpose: "Second",
          storage: "keychain_or_server_environment",
        },
      ],
    };
    expect(actionPlanSchema.safeParse(duplicateReferences).success).toBe(false);
  });

  it("requires declared provider-compatible references", () => {
    const discordStep = step("send", {
      type: "discord_webhook",
      parameters: {
        secretRef: "outbound-hook",
        message: "Done",
        fallback: "local_receipt",
      },
    });
    const undeclared = { ...validPlan(), steps: [discordStep] };
    expect(actionPlanSchema.safeParse(undeclared).success).toBe(false);

    const mismatched = {
      ...undeclared,
      secretReferences: [
        {
          id: "outbound-hook",
          provider: "slack",
          purpose: "Completion receipt",
          storage: "keychain_or_server_environment",
        },
      ],
    };
    expect(actionPlanSchema.safeParse(mismatched).success).toBe(false);

    const matching = {
      ...mismatched,
      secretReferences: [
        { ...mismatched.secretReferences[0], provider: "discord" },
      ],
    };
    expect(actionPlanSchema.safeParse(matching).success).toBe(true);
  });

  it("enforces the effective chosen-branch action budget", () => {
    const branches = Array.from({ length: 10 }, (_, index) =>
      notificationAction(`Nested ${index}`)
    );
    const conditional = {
      type: "conditional" as const,
      parameters: {
        condition: {
          type: "clipboard_is_empty" as const,
          value: "",
        },
        ifTrue: branches,
        ifFalse: [],
      },
    };
    const overBudget = {
      ...validPlan(),
      steps: [
        step("conditional", conditional),
        ...Array.from({ length: 40 }, (_, index) =>
          step(`top-${index}`, notificationAction(`Top ${index}`))
        ),
      ],
    };
    expect(actionPlanSchema.safeParse(overBudget).success).toBe(false);
  });

  it("validates HTTP secret placeholders and duplicate headers", () => {
    const requestStep = step("request", {
      type: "http_request",
      parameters: {
        method: "POST",
        url: "https://example.com/receipt",
        networkPolicy: "public_https_only",
        headers: [
          { name: "Content-Type", value: "application/json" },
          { name: "Content-Type", value: "application/json" },
        ],
        bodyTemplate: '{"value":"${secret:undeclared}"}',
        secretRefs: [],
        maximumResponseBytes: 1_024,
      },
    });
    expect(
      actionPlanSchema.safeParse({ ...validPlan(), steps: [requestStep] }).success,
    ).toBe(false);
  });

  it("requires a deep-link URL to match its declared scheme", () => {
    const mismatched = step("link", {
      type: "open_deep_link",
      parameters: {
        scheme: "mailto",
        url: "facetime:somebody@example.com",
      },
    });
    expect(
      actionPlanSchema.safeParse({ ...validPlan(), steps: [mismatched] }).success,
    ).toBe(false);
  });
});

describe("profileSchema", () => {
  it("accepts the frozen seeded demo profile", () => {
    expect(profileSchema.safeParse(seededDemoProfile).success).toBe(true);
  });

  it("accepts one-shot and repeat mappings with matching timing shape", () => {
    expect(profileSchema.safeParse(validProfile()).success).toBe(true);
    const repeating = structuredClone(validProfile());
    repeating.mappings[0].activation = "repeat" as never;
    (repeating.mappings[0] as typeof repeating.mappings[0] & {
      repeatIntervalMs: number;
    }).repeatIntervalMs = 1_000;
    expect(profileSchema.safeParse(repeating).success).toBe(true);
  });

  it("rejects missing/extraneous repeat timing and duplicate gestures", () => {
    const missingRepeat = structuredClone(validProfile());
    missingRepeat.mappings[0].activation = "repeat" as never;
    expect(profileSchema.safeParse(missingRepeat).success).toBe(false);

    const extraneousRepeat = {
      ...validProfile(),
      mappings: [
        { ...validProfile().mappings[0], repeatIntervalMs: 1_000 },
      ],
    };
    expect(profileSchema.safeParse(extraneousRepeat).success).toBe(false);

    const duplicateGesture = {
      ...validProfile(),
      mappings: [
        validProfile().mappings[0],
        { ...validProfile().mappings[0], plan: validPlan() },
      ],
    };
    expect(profileSchema.safeParse(duplicateGesture).success).toBe(false);
  });

  it("never permits a private profile to carry a share code", () => {
    const profile = {
      ...validProfile(),
      share: {
        visibility: "private",
        shareCode: "SIG1-H7K3M9Q2",
      },
    };
    expect(profileSchema.safeParse(profile).success).toBe(false);
  });
});

describe("planner request and response envelopes", () => {
  it("accepts the frozen planner response example", () => {
    expect(plannerResponseSchema.safeParse(plannerResponseExample).success).toBe(
      true,
    );
  });

  it("strictly validates requests and the 16 KiB transport cap", () => {
    const request = {
      schemaVersion: 1,
      requestId: "request-1",
      request: "Show a notification.",
      targetGesture: "thumbs_up",
      actionCatalog: ["show_notification"],
    };
    expect(plannerRequestSchema.safeParse(request).success).toBe(true);
    expect(
      plannerRequestSchema.safeParse({
        ...request,
        actionCatalog: ["show_notification", "show_notification"],
      }).success,
    ).toBe(false);
    expect(
      plannerRequestSchema.safeParse({ ...request, ignored: true }).success,
    ).toBe(false);
    expect(hasValidPlannerRequestByteLength("x".repeat(16 * 1024))).toBe(true);
    expect(hasValidPlannerRequestByteLength("x".repeat(16 * 1024 + 1))).toBe(
      false,
    );
  });

  it("accepts only one complete planner response variant", () => {
    const planned = {
      schemaVersion: 1,
      requestId: "request-1",
      status: "planned",
      plan: validPlan(),
      warnings: [],
      usedDeterministicFallback: false,
    };
    expect(plannerResponseSchema.safeParse(planned).success).toBe(true);
    expect(
      plannerResponseSchema.safeParse({
        ...planned,
        status: "needs_clarification",
        question: "Which application?",
        missingFields: ["application"],
      }).success,
    ).toBe(false);
  });

  it("rejects credential material before a planner call", () => {
    expect(
      plannerRequestSchema.safeParse({
        schemaVersion: 1,
        requestId: "request-1",
        request:
          "Send https://discord.com/api/webhooks/123456789/very-secret-token",
        targetGesture: "thumbs_up",
        actionCatalog: ["discord_webhook"],
      }).success,
    ).toBe(false);
  });
});
