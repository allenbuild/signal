export const SCHEMA_VERSION = 1 as const;

export const GESTURES = [
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

export const MODES = ["touch", "commands", "hybrid"] as const;

export const ACTION_TYPES = [
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

export type Gesture = (typeof GESTURES)[number];
export type SignalMode = (typeof MODES)[number];
export type ActionType = (typeof ACTION_TYPES)[number];

export interface Confirmation {
  mode: "none" | "first_run" | "every_run";
  reason: string;
}

export interface PlanStep {
  id: string;
  action: { type: ActionType; parameters: Record<string, unknown> };
  timeoutMs: number;
  onFailure: "stop" | "continue" | "ask";
  confirmation: Confirmation;
}

export interface ActionPlan {
  schemaVersion: 1;
  id: string;
  name: string;
  description: string;
  steps: PlanStep[];
  timeoutMs: number;
  onFailure: "stop" | "continue" | "ask";
  confirmation: Confirmation;
  createdSource: "visual" | "natural_language" | "demo_recording" | "import";
  secretReferences: Array<{
    id: string;
    provider: "discord" | "slack" | "http_bearer" | "http_basic" | "http_api_key";
    purpose: string;
    storage: "keychain_or_server_environment";
  }>;
}

export interface GestureMapping {
  gesture: Gesture;
  enabled: boolean;
  holdDurationMs: number;
  cooldownMs: number;
  activation: "one_shot" | "repeat";
  repeatIntervalMs?: number;
  allowedBundleIdentifiers: string[];
  preferredMode?: "commands" | "hybrid";
  plan: ActionPlan;
}

export interface SignalProfile {
  schemaVersion: 1;
  id: string;
  name: string;
  description: string;
  preferredMode: SignalMode;
  hybridOneBehavior: "pointer" | "command";
  mappings: GestureMapping[];
  share: {
    visibility: "private" | "unlisted";
    shareCode?: string;
  };
}

export interface ApiErrorBody {
  schemaVersion: 1;
  error: {
    code: string;
    message: string;
    fields?: string[];
  };
}
