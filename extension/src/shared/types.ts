export const GESTURE_IDS = [
  "one",
  "two",
  "three",
  "four",
  "five",
  "thumbs_up",
  "thumbs_down",
  "c_shape",
  "fist",
] as const;

export type GestureId = (typeof GESTURE_IDS)[number];
export type TrackingGesture = GestureId | "pointer" | "pinch" | "unknown";
export type SignalMode = "control" | "commands" | "paused";

export type NormalizedLandmark = {
  x: number;
  y: number;
  z?: number;
  visibility?: number;
};

export type PointerDelta = {
  dx: number;
  dy: number;
  normalized?: boolean;
};

export type PinchTransactionState =
  | "idle"
  | "pending"
  | "scrolling"
  | "zooming";

export type PinchFrame = {
  closed: boolean;
  transactionState: PinchTransactionState;
  deltaX?: number;
  deltaY?: number;
};

export type CommandSource =
  | "preset"
  | "natural_language"
  | "recording"
  | "hybrid";

export type Confirmation = {
  mode: "none" | "first_run" | "every_run";
  reason: string;
};

export type FailurePolicy = "stop" | "continue" | "ask";

export type OpenUrlAction = {
  type: "open_url";
  parameters: {
    url: string;
    networkPolicy?: "public_web_only" | "public_https_only";
    disposition?: "current_tab" | "new_tab";
  };
};

export type CreateTabAction = {
  type: "create_tab";
  parameters: { url: string; active?: boolean };
};

export type NavigateCurrentTabAction = {
  type: "navigate_current_tab";
  parameters: { url: string };
};

export type CloseTabAction = {
  type: "close_tab";
  parameters: Record<string, never>;
};

export type SwitchTabAction = {
  type: "switch_tab";
  parameters: { direction: "next" | "previous" };
};

export type SelectorAction =
  | {
      type: "scroll_to_selector";
      parameters: {
        selector: string;
        origin?: string;
        behavior?: "auto" | "smooth";
        block?: "start" | "center" | "end" | "nearest";
      };
    }
  | {
      type: "click_selector";
      parameters: { selector: string; origin?: string };
    }
  | {
      type: "focus_field";
      parameters: { selector: string; origin?: string };
    };

export type TypeTextAction = {
  type: "type_text";
  parameters: {
    selector: string;
    origin?: string;
    text: string;
    containsSensitiveData: false;
  };
};

export type ProtectedWebhookAction = {
  type: "protected_webhook";
  parameters: {
    configurationId: string;
    payload: string;
  };
};

export type DiscordWebhookAction = {
  type: "discord_webhook";
  parameters: {
    secretRef: string;
    message: string;
    fallback?: "local_receipt";
  };
};

export type ClaudeWorkflowAction = {
  type: "claude_workflow";
  parameters: {
    configurationId: string;
    workflowId: string;
    input: string;
  };
};

export type SpeakTextAction = {
  type: "speak_text";
  parameters: { text: string; rate?: number; voice?: string };
};

export type ShowNotificationAction = {
  type: "show_notification";
  parameters: { title: string; body: string };
};

export type ShowOverlayAction = {
  type: "show_overlay";
  parameters: { title: string; body: string; durationMs: number };
};

export type MediaControlAction = {
  type: "media_control";
  parameters: {
    command: "play" | "pause" | "toggle_play_pause";
  };
};

export type WebsiteAutomationAction =
  | {
      type: "bolt_prompt";
      parameters: { prompt: string };
    }
  | {
      type: "spotify_next_track";
      parameters: Record<string, never>;
    };

export type SetTabZoomAction = {
  type: "set_tab_zoom";
  parameters: { factor: number };
};

export type WaitAction = {
  type: "wait";
  parameters: { durationMs: number };
};

export type BrowserCommandAction =
  | OpenUrlAction
  | CreateTabAction
  | NavigateCurrentTabAction
  | CloseTabAction
  | SwitchTabAction
  | SelectorAction
  | TypeTextAction
  | ProtectedWebhookAction
  | DiscordWebhookAction
  | ClaudeWorkflowAction
  | SpeakTextAction
  | ShowNotificationAction
  | ShowOverlayAction
  | MediaControlAction
  | WebsiteAutomationAction
  | SetTabZoomAction
  | WaitAction;

export type CommandStep = {
  id: string;
  action: BrowserCommandAction;
  timeoutMs: number;
  onFailure: FailurePolicy;
  confirmation: Confirmation;
};

export type CommandPlan = {
  schemaVersion: 1;
  id: string;
  name: string;
  description: string;
  steps: CommandStep[];
  timeoutMs: number;
  onFailure: FailurePolicy;
  confirmation: Confirmation;
  createdSource: "visual" | "natural_language" | "demo_recording" | "import";
  secretReferences: Array<{
    id: string;
    provider:
      | "discord"
      | "slack"
      | "http_bearer"
      | "http_basic"
      | "http_api_key"
      | "claude";
    purpose: string;
    storage:
      | "server_environment"
      | "extension_local"
      | "keychain_or_server_environment";
  }>;
};

export type SignalCommand = {
  schemaVersion: 1;
  id: string;
  gesture: GestureId;
  name: string;
  description: string;
  source: CommandSource;
  plan: CommandPlan;
  createdAt: string;
  updatedAt: string;
  enabled: boolean;
};

export type SignalSettings = {
  mode: SignalMode;
  hideSiteCursor: boolean;
  resetCursorOnTabChange: boolean;
  naturalScroll: boolean;
  useSyncSettings: boolean;
};

export type GestureTuning = {
  holdMs: number;
  cooldownMs: number;
  minimumConfidence: number;
  pointerSensitivity: number;
  pointerSmoothing: number;
  pointerDeadZone: number;
  pointerAcceleration: number;
  pointerMaxFrameMovement: number;
  scrollRateLimitMs: number;
  zoomRateLimitMs: number;
};

export type StoredProfile = {
  schemaVersion: 1;
  id: string;
  name: string;
  description: string;
  commands: SignalCommand[];
  settings?: Partial<SignalSettings>;
  tuning?: Partial<GestureTuning>;
};
