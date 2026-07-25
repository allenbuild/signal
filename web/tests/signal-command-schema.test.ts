import { describe, expect, it, vi } from "vitest";

import {
  gestureCommands,
  gestureIds,
  type GestureId,
} from "../config/gestureCommands";
import {
  FIST_COMMAND_STORAGE_KEY,
  loadSavedFistCommand,
  saveFistCommand,
  signalCommandSchema,
  type SignalCommand,
} from "../lib/commands/schema";
import type { ActionPlan, PlannerRequest } from "../lib/contracts";
import { planWithDeterministicFallback } from "../lib/planner";

const now = "2026-07-24T20:00:00.000Z";

function planFor(
  action: ActionPlan["steps"][number]["action"] = {
    type: "show_notification",
    parameters: { title: "Signal", body: "Ready" },
  },
): ActionPlan {
  return {
    schemaVersion: 1,
    id: "signal.test.plan",
    name: "Test plan",
    description: "A reviewed test plan.",
    steps: [
      {
        id: "step-1",
        action,
        timeoutMs: 5_000,
        onFailure: "stop",
        confirmation: { mode: "first_run", reason: "Review before use." },
      },
    ],
    timeoutMs: 8_000,
    onFailure: "stop",
    confirmation: { mode: "first_run", reason: "Review before use." },
    createdSource: "import",
    secretReferences: [],
  };
}

function commandFor(
  gesture: GestureId,
  plan: ActionPlan = planFor(),
): SignalCommand {
  return {
    schemaVersion: 1,
    id: `signal.command.${gesture}`,
    gesture,
    name: `${gesture} command`,
    description: "Strict version 1 command.",
    source: gesture === "fist" ? "natural_language" : "preset",
    plan,
    createdAt: now,
    updatedAt: now,
    enabled: true,
  };
}

describe("configured command contract", () => {
  it("configures exactly one valid command card for all nine gestures", () => {
    expect(gestureIds).toHaveLength(9);
    expect(gestureCommands.map((command) => command.gesture)).toEqual(
      gestureIds,
    );
    expect(new Set(gestureCommands.map((command) => command.gesture)).size).toBe(
      9,
    );

    for (const gesture of gestureIds) {
      expect(
        signalCommandSchema.safeParse(commandFor(gesture)).success,
        `${gesture} should be accepted`,
      ).toBe(true);
    }
  });

  it("rejects unknown actions through the embedded ActionPlan", () => {
    const candidate = commandFor("fist") as unknown as Record<string, unknown>;
    const command = candidate as unknown as SignalCommand;
    command.plan.steps[0].action = {
      type: "shell_command",
      parameters: { command: "open -a Calculator" },
    } as never;

    expect(signalCommandSchema.safeParse(command).success).toBe(false);
  });

  it("rejects a private-network URL through the embedded ActionPlan", () => {
    const command = commandFor(
      "fist",
      planFor({
        type: "open_url",
        parameters: {
          url: "https://127.0.0.1/admin",
          networkPolicy: "public_https_only",
        },
      }),
    );
    expect(signalCommandSchema.safeParse(command).success).toBe(false);
  });

  it("rejects raw credential values through the embedded ActionPlan", () => {
    const unsafe = commandFor("fist", {
      ...planFor(),
      description:
        "Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    });
    expect(signalCommandSchema.safeParse(unsafe).success).toBe(false);
  });
});

describe("fist command persistence", () => {
  it("round-trips a strict fist command in the versioned local envelope", () => {
    const values = new Map<string, string>();
    const storage = {
      getItem: vi.fn((key: string) => values.get(key) ?? null),
      setItem: vi.fn((key: string, value: string) => {
        values.set(key, value);
      }),
    };
    const command = commandFor("fist");

    saveFistCommand(storage, command);

    expect(storage.setItem).toHaveBeenCalledTimes(1);
    expect(JSON.parse(values.get(FIST_COMMAND_STORAGE_KEY) ?? "{}")).toEqual({
      storageVersion: 1,
      command,
    });
    expect(loadSavedFistCommand(storage)).toEqual(command);
  });

  it("returns null for malformed, future, or non-fist saved values", () => {
    const getItem = vi.fn();

    getItem.mockReturnValueOnce("{bad json");
    expect(loadSavedFistCommand({ getItem })).toBeNull();

    getItem.mockReturnValueOnce(
      JSON.stringify({
        storageVersion: 2,
        command: commandFor("fist"),
      }),
    );
    expect(loadSavedFistCommand({ getItem })).toBeNull();

    getItem.mockReturnValueOnce(
      JSON.stringify({
        storageVersion: 1,
        command: commandFor("one"),
      }),
    );
    expect(loadSavedFistCommand({ getItem })).toBeNull();
  });
});

describe("fallback planner compatibility", () => {
  it("survives the planner-to-fist-command schema boundary unchanged", () => {
    const request: PlannerRequest = {
      schemaVersion: 1,
      requestId: "fist-fallback-test",
      request:
        "When I give a thumbs up, open my focus playlist, say Focus mode, and send Demo complete to Discord.",
      targetGesture: "fist",
      actionCatalog: [
        "open_deep_link",
        "speak_text",
        "discord_webhook",
      ],
    };
    const result = planWithDeterministicFallback(request);
    expect(result.handled).toBe(true);
    if (!result.handled || result.response.status !== "planned") {
      throw new Error("Expected a deterministic plan");
    }
    expect(result.response.usedDeterministicFallback).toBe(true);

    const parsed = signalCommandSchema.safeParse(
      commandFor("fist", result.response.plan),
    );
    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data.plan).toEqual(result.response.plan);
    }
  });
});
