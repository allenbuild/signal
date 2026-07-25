import { describe, expect, it } from "vitest";
import {
  ACTIVE_COMMAND_CATALOG,
  ACTIVE_COMMAND_CATALOG_VERSION,
  ACTIVE_COMMAND_GESTURES,
  ANTHROPIC_X_URL,
  BOLT_PROMPT,
  CURSOR_AGENTS_URL,
  getActiveCommandDefinition,
  GMAIL_COMPOSE_URL,
  GMAIL_RECIPIENT,
  NEW_GOOGLE_DOC_URL,
  RICKROLL_URL,
} from "../src/shared/defaults";

describe("active command defaults", () => {
  it("defines one versioned catalog with exactly eight unique gestures", () => {
    expect(ACTIVE_COMMAND_CATALOG.schemaVersion).toBe(
      ACTIVE_COMMAND_CATALOG_VERSION,
    );
    expect(ACTIVE_COMMAND_CATALOG.commands).toHaveLength(8);
    expect(ACTIVE_COMMAND_CATALOG.commands.map(({ gesture }) => gesture)).toEqual(
      ACTIVE_COMMAND_GESTURES,
    );
    expect(new Set(ACTIVE_COMMAND_GESTURES).size).toBe(8);
  });

  it("does not expose or resolve the removed Five command", () => {
    expect(ACTIVE_COMMAND_GESTURES).not.toContain("five");
    expect(
      ACTIVE_COMMAND_CATALOG.commands.some(
        ({ gesture }) => (gesture as string) === "five",
      ),
    ).toBe(false);
    expect(getActiveCommandDefinition("five")).toBeNull();
  });

  it.each([
    ["one", "Rickroll", RICKROLL_URL],
    ["two", "New Gmail", GMAIL_COMPOSE_URL],
    ["three", "Cursor Agents", CURSOR_AGENTS_URL],
    ["four", "New Google Doc", NEW_GOOGLE_DOC_URL],
    ["c_shape", "Anthropic on X", ANTHROPIC_X_URL],
  ] as const)(
    "maps %s to %s with its exact new-tab URL",
    (gesture, name, url) => {
      const command = getActiveCommandDefinition(gesture);
      expect(command?.name).toBe(name);
      expect(command?.action).toEqual({
        type: "create_tab",
        parameters: { url, active: true },
      });
    },
  );

  it("keeps the Gmail recipient populated in the compose URL", () => {
    const composeUrl = new URL(GMAIL_COMPOSE_URL);
    expect(composeUrl.searchParams.get("view")).toBe("cm");
    expect(composeUrl.searchParams.get("fs")).toBe("1");
    expect(composeUrl.searchParams.get("to")).toBe(GMAIL_RECIPIENT);
  });

  it("preserves the exact Bolt prompt and website targeting contract", () => {
    const command = getActiveCommandDefinition("thumbs_up");
    expect(command?.name).toBe("Build with Bolt");
    expect(command?.action).toMatchObject({
      type: "website_action",
      parameters: {
        automation: "bolt_prompt",
        matchUrlPattern: "https://bolt.new/*",
        fallbackUrl: "https://bolt.new/",
        timeoutMs: 15_000,
        prompt: BOLT_PROMPT,
      },
    });
    expect(BOLT_PROMPT).toBe(
      "i want to build a website for my hand signal app",
    );
  });

  it("targets only Spotify Web for the next-track action", () => {
    const command = getActiveCommandDefinition("thumbs_down");
    expect(command?.name).toBe("Next Spotify Track");
    expect(command?.action).toMatchObject({
      type: "website_action",
      parameters: {
        automation: "spotify_next_track",
        matchUrlPattern: "https://open.spotify.com/*",
        fallbackUrl: "https://open.spotify.com/",
        timeoutMs: 10_000,
      },
    });
  });

  it("keeps Fist as the sole configurable placeholder", () => {
    const configurable = ACTIVE_COMMAND_CATALOG.commands.filter(
      ({ configurable }) => configurable,
    );
    expect(configurable).toHaveLength(1);
    expect(configurable[0]).toMatchObject({
      gesture: "fist",
      name: "Custom Command",
      action: { type: "show_overlay" },
    });
  });
});
