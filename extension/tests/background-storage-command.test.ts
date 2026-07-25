import { describe, expect, it, vi } from "vitest";

import { CommandExecutor } from "../src/background/command-executor";
import {
  EXTENSION_STORAGE_KEY,
  ExtensionStorage,
  LEGACY_FIST_COMMAND_KEY,
  migrateStorageSnapshot,
  type StorageAreaLike,
} from "../src/background/storage";
import type {
  BrowserCommandAction,
  SignalCommand,
} from "../src/shared/types";

function commandWith(
  action: BrowserCommandAction = {
    type: "show_notification",
    parameters: { title: "Signal", body: "Ready" },
  },
): SignalCommand {
  const now = "2026-07-24T20:00:00.000Z";
  return {
    schemaVersion: 1,
    id: "signal.test.command",
    gesture: "fist",
    name: "Test command",
    description: "A reviewed browser command.",
    source: "natural_language",
    plan: {
      schemaVersion: 1,
      id: "signal.test.plan",
      name: "Test plan",
      description: "A browser-only plan.",
      steps: [
        {
          id: "step-1",
          action,
          timeoutMs: 5_000,
          onFailure: "stop",
          confirmation: { mode: "none", reason: "Local browser action." },
        },
      ],
      timeoutMs: 8_000,
      onFailure: "stop",
      confirmation: { mode: "none", reason: "Reviewed in the builder." },
      createdSource: "natural_language",
      secretReferences: [],
    },
    createdAt: now,
    updatedAt: now,
    enabled: true,
  };
}

class MemoryArea implements StorageAreaLike {
  values: Record<string, unknown> = {};

  async get(keys?: string | string[] | Record<string, unknown> | null) {
    if (keys == null) return { ...this.values };
    const list =
      typeof keys === "string"
        ? [keys]
        : Array.isArray(keys)
          ? keys
          : Object.keys(keys);
    return Object.fromEntries(
      list
        .filter((key) => key in this.values)
        .map((key) => [key, this.values[key]]),
    );
  }

  async set(items: Record<string, unknown>) {
    Object.assign(this.values, items);
  }
}

describe("extension storage migration", () => {
  it("migrates the browser-local Fist envelope without recordings or frames", () => {
    const command = commandWith();
    const migrated = migrateStorageSnapshot({
      [LEGACY_FIST_COMMAND_KEY]: JSON.stringify({
        storageVersion: 1,
        command,
      }),
      recordings: [{ video: "must not persist" }],
      liveFrames: [{ pixels: "must not persist" }],
    });
    expect(migrated.commands).toEqual([command]);
    expect(JSON.stringify(migrated)).not.toContain("must not persist");
    expect(migrated.storageVersion).toBe(2);
  });

  it("round-trips settings locally and optionally syncs only settings", async () => {
    const local = new MemoryArea();
    const sync = new MemoryArea();
    const repository = new ExtensionStorage({ local, sync });
    const state = await repository.load();
    state.settings.hideSiteCursor = true;
    await repository.save(state);

    expect(local.values[EXTENSION_STORAGE_KEY]).toMatchObject({
      storageVersion: 2,
      settings: { hideSiteCursor: true },
    });
    expect(Object.keys(sync.values)).toEqual([
      "signal.extension.settings.v1",
    ]);
  });

  it("migrates a safe existing web profile into extension commands", () => {
    const command = commandWith();
    const migrated = migrateStorageSnapshot(
      {
        profile: {
          schemaVersion: 1,
          id: "signal.web.profile",
          name: "Web profile",
          description: "Existing browser fallback profile.",
          mappings: [
            {
              gesture: "one",
              enabled: true,
              plan: command.plan,
            },
          ],
        },
      },
      "2026-07-24T21:00:00.000Z",
    );
    expect(migrated.profiles).toHaveLength(1);
    expect(migrated.profiles[0]).toMatchObject({
      id: "signal.web.profile",
      commands: [
        {
          gesture: "one",
          source: "natural_language",
          plan: command.plan,
        },
      ],
    });
  });

  it("rejects malformed profile imports", async () => {
    const repository = new ExtensionStorage({ local: new MemoryArea() });
    await expect(
      repository.importProfile({
        schemaVersion: 1,
        id: "bad",
        name: "Bad",
        description: "",
        commands: [],
        rawRecording: "data",
      }),
    ).rejects.toThrow(/unknown field/);
  });
});

describe("safe command execution", () => {
  it("runs tab, notification, and content actions through explicit capabilities", async () => {
    const createTab = vi.fn(async () => ({ id: 2 }));
    const createNotification = vi.fn(async () => undefined);
    const sendContentAction = vi.fn(async () => ({
      ok: true,
      message: "Clicked the reviewed element.",
    }));
    const executor = new CommandExecutor({
      getActiveTab: async () => ({ id: 1, windowId: 1, index: 0 }),
      createTab,
      updateTab: async (id) => ({ id }),
      removeTab: async () => undefined,
      listTabs: async () => [{ id: 1 }],
      sendContentAction,
      zoom: {
        set: async () => ({
          version: 1,
          type: "signal:zoom-status",
          supported: true,
          factor: 1,
          percentage: 100,
        }),
      },
      createNotification,
      randomId: () => "request-1",
    });

    const command = commandWith({
      type: "click_selector",
      parameters: { selector: "#safe-button" },
    });
    const receipt = await executor.execute(command, {
      confirmationsApproved: true,
    });
    expect(receipt.completedSteps).toBe(1);
    expect(sendContentAction).toHaveBeenCalledWith(
      1,
      command.plan.steps[0]!.action,
      "request-1",
    );
    expect(createTab).not.toHaveBeenCalled();
    expect(createNotification).not.toHaveBeenCalled();
  });

  it("requires configured protected integrations and never accepts raw endpoints", async () => {
    const executor = new CommandExecutor({
      getActiveTab: async () => ({ id: 1 }),
      createTab: async () => ({ id: 2 }),
      updateTab: async (id) => ({ id }),
      removeTab: async () => undefined,
      listTabs: async () => [],
      sendContentAction: async () => ({ ok: true, message: "ok" }),
      zoom: {
        set: async () => ({
          version: 1,
          type: "signal:zoom-status",
          supported: true,
          factor: 1,
          percentage: 100,
        }),
      },
      createNotification: async () => undefined,
    });
    await expect(
      executor.execute(
        commandWith({
          type: "protected_webhook",
          parameters: { configurationId: "demo-hook", payload: "hello" },
        }),
        { confirmationsApproved: true },
      ),
    ).rejects.toThrow(/not configured/);
  });
});
