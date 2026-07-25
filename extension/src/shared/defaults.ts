import type { BrowserCommandAction, GestureId } from "./types";

export const ACTIVE_COMMAND_CATALOG_VERSION = 1 as const;

export const ACTIVE_COMMAND_GESTURES = [
  "one",
  "two",
  "three",
  "four",
  "thumbs_up",
  "thumbs_down",
  "c_shape",
  "fist",
] as const satisfies readonly GestureId[];

export type ActiveCommandGesture = (typeof ACTIVE_COMMAND_GESTURES)[number];

export const RICKROLL_URL =
  "https://www.youtube.com/watch?v=dQw4w9WgXcQ";
export const GMAIL_RECIPIENT = "allenjxu07@gmail.com";
export const GMAIL_COMPOSE_URL =
  "https://mail.google.com/mail/?view=cm&fs=1&to=allenjxu07%40gmail.com";
export const CURSOR_AGENTS_URL = "https://cursor.com/agents";
export const NEW_GOOGLE_DOC_URL = "https://doc.new";
export const ANTHROPIC_X_URL = "https://x.com/AnthropicAI?lang=en";
export const BOLT_PROMPT =
  "i want to build a website for my hand signal app";

export type BoltWebsiteAction = {
  type: "website_action";
  parameters: {
    automation: "bolt_prompt";
    matchUrlPattern: "https://bolt.new/*";
    fallbackUrl: "https://bolt.new/";
    timeoutMs: 15_000;
    prompt: typeof BOLT_PROMPT;
    inputSelectors: readonly [
      "textarea",
      '[contenteditable="true"]',
      '[role="textbox"]',
      'input[type="text"]',
    ];
  };
};

export type SpotifyWebsiteAction = {
  type: "website_action";
  parameters: {
    automation: "spotify_next_track";
    matchUrlPattern: "https://open.spotify.com/*";
    fallbackUrl: "https://open.spotify.com/";
    timeoutMs: 10_000;
    nextTrackSelector: 'button[data-testid="control-button-skip-forward"]';
    playPauseSelector: 'button[data-testid="control-button-playpause"]';
  };
};

export type WebsiteAction = BoltWebsiteAction | SpotifyWebsiteAction;

export type ActiveCommandDefinition = {
  id: string;
  gesture: ActiveCommandGesture;
  name: string;
  description: string;
  configurable: boolean;
  action: BrowserCommandAction | WebsiteAction;
};

const createTab = (url: string): BrowserCommandAction => ({
  type: "create_tab",
  parameters: { url, active: true },
});

export const ACTIVE_COMMAND_CATALOG = {
  schemaVersion: ACTIVE_COMMAND_CATALOG_VERSION,
  commands: [
    {
      id: "signal.default.v1.one",
      gesture: "one",
      name: "Rickroll",
      description: "Open the Rickroll video in a new active tab.",
      configurable: false,
      action: createTab(RICKROLL_URL),
    },
    {
      id: "signal.default.v1.two",
      gesture: "two",
      name: "New Gmail",
      description:
        "Open a Gmail compose page with the recipient already populated.",
      configurable: false,
      action: createTab(GMAIL_COMPOSE_URL),
    },
    {
      id: "signal.default.v1.three",
      gesture: "three",
      name: "Cursor Agents",
      description: "Open Cursor Agents in a new active tab.",
      configurable: false,
      action: createTab(CURSOR_AGENTS_URL),
    },
    {
      id: "signal.default.v1.four",
      gesture: "four",
      name: "New Google Doc",
      description: "Create a new Google document in a new active tab.",
      configurable: false,
      action: createTab(NEW_GOOGLE_DOC_URL),
    },
    {
      id: "signal.default.v1.thumbs-up",
      gesture: "thumbs_up",
      name: "Build with Bolt",
      description: "Open Bolt and submit the configured Signal build prompt.",
      configurable: false,
      action: {
        type: "website_action",
        parameters: {
          automation: "bolt_prompt",
          matchUrlPattern: "https://bolt.new/*",
          fallbackUrl: "https://bolt.new/",
          timeoutMs: 15_000,
          prompt: BOLT_PROMPT,
          inputSelectors: [
            "textarea",
            '[contenteditable="true"]',
            '[role="textbox"]',
            'input[type="text"]',
          ],
        },
      },
    },
    {
      id: "signal.default.v1.thumbs-down",
      gesture: "thumbs_down",
      name: "Next Spotify Track",
      description: "Advance Spotify Web to the next track.",
      configurable: false,
      action: {
        type: "website_action",
        parameters: {
          automation: "spotify_next_track",
          matchUrlPattern: "https://open.spotify.com/*",
          fallbackUrl: "https://open.spotify.com/",
          timeoutMs: 10_000,
          nextTrackSelector:
            'button[data-testid="control-button-skip-forward"]',
          playPauseSelector:
            'button[data-testid="control-button-playpause"]',
        },
      },
    },
    {
      id: "signal.default.v1.c-shape",
      gesture: "c_shape",
      name: "Anthropic on X",
      description: "Open Anthropic on X in a new active tab.",
      configurable: false,
      action: createTab(ANTHROPIC_X_URL),
    },
    {
      id: "signal.default.v1.fist",
      gesture: "fist",
      name: "Custom Command",
      description: "Configure a custom safe command for the Fist gesture.",
      configurable: true,
      action: {
        type: "show_overlay",
        parameters: {
          title: "Custom Command",
          body: "Open the Signal side panel to configure your Fist command.",
          durationMs: 4_000,
        },
      },
    },
  ],
} as const satisfies {
  schemaVersion: typeof ACTIVE_COMMAND_CATALOG_VERSION;
  commands: readonly ActiveCommandDefinition[];
};

export function getActiveCommandDefinition(
  gesture: GestureId,
): ActiveCommandDefinition | null {
  return (
    ACTIVE_COMMAND_CATALOG.commands.find(
      (command) => command.gesture === gesture,
    ) ?? null
  );
}
