import "@testing-library/jest-dom/vitest";

import { cleanup, render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { gestureCommands } from "../config/gestureCommands";
import { SignalPage } from "../components/signal/SignalPage";
import {
  FIST_COMMAND_STORAGE_KEY,
  type SignalCommand,
} from "../lib/commands/schema";
import type { ActionPlan } from "../lib/contracts";

class MemoryStorage implements Storage {
  private readonly values = new Map<string, string>();

  get length() {
    return this.values.size;
  }

  clear() {
    this.values.clear();
  }

  getItem(key: string) {
    return this.values.get(key) ?? null;
  }

  key(index: number) {
    return [...this.values.keys()][index] ?? null;
  }

  removeItem(key: string) {
    this.values.delete(key);
  }

  setItem(key: string, value: string) {
    this.values.set(key, String(value));
  }
}

const originalLocalStorage = Object.getOwnPropertyDescriptor(
  window,
  "localStorage",
);

const fallbackPlan: ActionPlan = {
  schemaVersion: 1,
  id: "signal.fist.fallback",
  name: "Fallback focus command",
  description: "A deterministic reviewed command.",
  steps: [
    {
      id: "open-spotify",
      action: {
        type: "open_application",
        parameters: {
          bundleIdentifier: "com.spotify.client",
          applicationName: "Spotify",
        },
      },
      timeoutMs: 8_000,
      onFailure: "stop",
      confirmation: {
        mode: "first_run",
        reason: "Review before opening Spotify.",
      },
    },
    {
      id: "wait",
      action: {
        type: "wait",
        parameters: { durationMs: 1_000 },
      },
      timeoutMs: 2_000,
      onFailure: "stop",
      confirmation: { mode: "none", reason: "" },
    },
  ],
  timeoutMs: 13_000,
  onFailure: "stop",
  confirmation: {
    mode: "first_run",
    reason: "Review before the first run.",
  },
  createdSource: "natural_language",
  secretReferences: [],
};

function savedFistCommand(): SignalCommand {
  return {
    schemaVersion: 1,
    id: "fist-saved-test",
    gesture: "fist",
    name: "Saved local command",
    description: "A locally saved command.",
    source: "natural_language",
    plan: fallbackPlan,
    createdAt: "2026-07-24T20:00:00.000Z",
    updatedAt: "2026-07-24T20:00:00.000Z",
    enabled: true,
  };
}

beforeEach(() => {
  Object.defineProperty(window, "localStorage", {
    configurable: true,
    value: new MemoryStorage(),
  });
  vi.stubGlobal("crypto", {
    randomUUID: vi.fn(() => "00000000-0000-4000-8000-000000000009"),
  });
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  document.body.style.overflow = "";
  if (originalLocalStorage) {
    Object.defineProperty(window, "localStorage", originalLocalStorage);
  }
});

describe("Signal one-page gesture surface", () => {
  it("renders all nine configured gesture commands exactly once", () => {
    render(<SignalPage />);

    for (const command of gestureCommands) {
      expect(
        screen.getByRole("button", {
          name: `${command.label}: ${command.commandName}`,
        }),
      ).toHaveAttribute("data-gesture", command.gesture);
    }
    expect(
      document.querySelectorAll("button[data-gesture]"),
    ).toHaveLength(9);
  });

  it("opens locked previews for presets but reserves the editor modal for Fist", async () => {
    const user = userEvent.setup();
    render(<SignalPage />);

    await user.click(
      screen.getByRole("button", { name: "One: Open Spotify" }),
    );
    expect(
      screen.getByRole("heading", { name: "Open Spotify" }),
    ).toBeInTheDocument();
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();

    await user.click(
      screen.getByRole("button", { name: "Two: Open Gmail" }),
    );
    expect(
      screen.getByRole("heading", { name: "Open Gmail" }),
    ).toBeInTheDocument();
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();

    await user.click(
      screen.getByRole("button", { name: "Fist: Custom command" }),
    );
    expect(
      screen.getByRole("dialog", { name: "Tell Signal what to do." }),
    ).toBeInTheDocument();
    expect(
      screen.getByLabelText("What should happen when you make a fist?"),
    ).toBeInTheDocument();
  });

  it("loads a strict local fist assignment into the editable review state", async () => {
    const command = savedFistCommand();
    window.localStorage.setItem(
      FIST_COMMAND_STORAGE_KEY,
      JSON.stringify({ storageVersion: 1, command }),
    );
    const user = userEvent.setup();
    render(<SignalPage />);

    const fist = await screen.findByRole("button", {
      name: "Fist: Saved local command",
    });
    await user.click(fist);

    expect(
      screen.getByRole("dialog", { name: "Confirm every step." }),
    ).toBeInTheDocument();
    expect(screen.getByDisplayValue("Saved local command")).toBeInTheDocument();
    expect(screen.getByText("Saved version 1 plan")).toBeInTheDocument();
  });

  it("keeps a validated fallback plan through review and local save", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify({
          schemaVersion: 1,
          requestId: "web_fallback",
          status: "planned",
          plan: fallbackPlan,
          warnings: [
            "Built with Signal’s deterministic fallback; no AI provider was used.",
          ],
          usedDeterministicFallback: true,
        }),
        {
          status: 200,
          headers: { "content-type": "application/json" },
        },
      ),
    );
    vi.stubGlobal("fetch", fetchMock);
    const user = userEvent.setup();
    render(<SignalPage />);

    await user.click(
      screen.getByRole("button", { name: "Fist: Custom command" }),
    );
    await user.click(
      screen.getByRole("button", { name: "Generate structured command" }),
    );

    expect(
      await screen.findByText("Deterministic fallback"),
    ).toBeInTheDocument();
    expect(
      screen.getByText(
        "Built with Signal’s deterministic fallback. Claude was not used.",
      ),
    ).toBeInTheDocument();
    const reviewDialog = screen.getByRole("dialog", {
      name: "Confirm every step.",
    });
    expect(within(reviewDialog).getByText("Open Spotify")).toBeInTheDocument();
    expect(within(reviewDialog).getByText("Wait 1 seconds")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Save to Fist" }));

    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Fist: Fallback focus command" }),
    ).toBeInTheDocument();
    const envelope = JSON.parse(
      window.localStorage.getItem(FIST_COMMAND_STORAGE_KEY) ?? "{}",
    );
    expect(envelope).toMatchObject({
      storageVersion: 1,
      command: {
        gesture: "fist",
        name: "Fallback focus command",
        plan: fallbackPlan,
      },
    });
    expect(fetchMock).toHaveBeenCalledWith(
      "/api/v1/plan",
      expect.objectContaining({ method: "POST" }),
    );
  });
});
