import { describe, expect, it } from "vitest";

import {
  isSafeWebUrl,
  safeParseSignalCommand,
} from "../src/shared/schema";
import type {
  BrowserCommandAction,
  SignalCommand,
} from "../src/shared/types";

const now = "2026-07-24T20:00:00.000Z";

export function commandWith(
  action: BrowserCommandAction = {
    type: "show_notification",
    parameters: { title: "Signal", body: "Ready" },
  },
): SignalCommand {
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

describe("extension command schema", () => {
  it("accepts the browser command allowlist", () => {
    expect(safeParseSignalCommand(commandWith()).success).toBe(true);
    expect(
      safeParseSignalCommand(
        commandWith({
          type: "create_tab",
          parameters: { url: "https://example.com/", active: true },
        }),
      ).success,
    ).toBe(true);
  });

  it.each([
    {
      type: "shell_command",
      parameters: { command: "open -a Calculator" },
    },
    {
      type: "open_application",
      parameters: { bundleIdentifier: "com.apple.TextEdit" },
    },
    {
      type: "run_applescript_template",
      parameters: { script: "tell application Finder" },
    },
    {
      type: "set_clipboard",
      parameters: { text: "secret" },
    },
  ])("rejects dangerous action $type", (action) => {
    expect(
      safeParseSignalCommand(
        commandWith(action as unknown as BrowserCommandAction),
      ).success,
    ).toBe(false);
  });

  it("rejects javascript, embedded credentials, and private-network URLs", () => {
    for (const url of [
      "javascript:alert(1)",
      "https://user:pass@example.com/",
      "http://127.0.0.1:3000/",
      "https://192.168.1.4/",
      "http://localhost/",
    ]) {
      expect(
        safeParseSignalCommand(
          commandWith({
            type: "create_tab",
            parameters: { url },
          }),
        ).success,
        url,
      ).toBe(false);
    }
  });

  it("rejects password selectors, sensitive text, future versions, and extras", () => {
    expect(
      safeParseSignalCommand(
        commandWith({
          type: "type_text",
          parameters: {
            selector: "input[type=password]",
            text: "hello",
            containsSensitiveData: false,
          },
        }),
      ).success,
    ).toBe(false);
    expect(
      safeParseSignalCommand(
        commandWith({
          type: "type_text",
          parameters: {
            selector: "#note",
            text: "Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            containsSensitiveData: false,
          },
        }),
      ).success,
    ).toBe(false);
    expect(
      safeParseSignalCommand({ ...commandWith(), schemaVersion: 2 }).success,
    ).toBe(false);
    expect(
      safeParseSignalCommand({ ...commandWith(), rawToken: "nope" }).success,
    ).toBe(false);
  });
});

describe("safe web destinations", () => {
  it("allows public HTTPS hostnames but nothing executable or local", () => {
    expect(isSafeWebUrl("https://www.wikipedia.org/")).toBe(true);
    expect(isSafeWebUrl("http://example.com/docs")).toBe(false);
    expect(isSafeWebUrl("javascript:document.cookie")).toBe(false);
    expect(isSafeWebUrl("file:///tmp/demo")).toBe(false);
    expect(isSafeWebUrl("https://127.0.0.1/")).toBe(false);
    expect(isSafeWebUrl("https://[::ffff:127.0.0.1]/")).toBe(false);
    expect(isSafeWebUrl("https://router.lan/")).toBe(false);
  });
});
