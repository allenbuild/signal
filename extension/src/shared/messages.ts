import {
  GESTURE_IDS,
  type BrowserCommandAction,
  type GestureId,
  type NormalizedLandmark,
  type PinchFrame,
  type PointerDelta,
  type SignalCommand,
  type SignalMode,
  type TrackingGesture,
} from "./types";

export const SIGNAL_MESSAGE_VERSION = 1 as const;
export const OFFSCREEN_PORT_NAME = "signal:offscreen";
export const PROTECTED_PAGE_MESSAGE =
  "Signal cannot control this protected browser page.";

export type TrackingFrameMessage = {
  version: 1;
  type: "signal:tracking-frame";
  timestamp: number;
  sequence: number;
  sessionId?: string;
  gesture: TrackingGesture;
  commandGesture?: GestureId;
  confidence: number;
  landmarks?: NormalizedLandmark[];
  pointerDelta?: PointerDelta;
  pinch?: PinchFrame;
  fps?: number;
};

export type OffscreenControlMessage =
  | { version: 1; type: "signal:offscreen/start" }
  | { version: 1; type: "signal:offscreen/pause" }
  | { version: 1; type: "signal:offscreen/stop" }
  | { version: 1; type: "signal:offscreen/ping" };

export type OffscreenStateMessage = {
  version: 1;
  type: "signal:offscreen/state";
  state:
    | "idle"
    | "starting"
    | "requesting-permission"
    | "running"
    | "paused"
    | "stopped"
    | "error";
  fps: number;
  cameraActive: boolean;
  error?: string;
};

export type OffscreenPermissionRequiredMessage = {
  version: 1;
  type: "signal:offscreen/permission-required";
  reason: "camera";
};

export type SignalModeMessage = {
  version: 1;
  type: "signal:mode";
  mode: SignalMode;
};

export type SignalTuningMessage = {
  version: 1;
  type: "signal:tuning";
  tuning: {
    sensitivity: number;
    smoothing: number;
    hideSiteCursor: boolean;
  };
};

export type SignalResetMessage = {
  version: 1;
  type: "signal:reset";
  reason:
    | "tab-change"
    | "navigation"
    | "tracking-loss"
    | "pause"
    | "stop"
    | "service-worker-restart";
  generation: number;
};

export type ZoomStatusMessage = {
  version: 1;
  type: "signal:zoom-status";
  factor?: number;
  percentage?: number;
  supported: boolean;
  error?: string;
};

export type UnsupportedPageMessage = {
  version: 1;
  type: "signal:unsupported";
  message: typeof PROTECTED_PAGE_MESSAGE;
};

export type ContentReadyMessage = {
  version: 1;
  type: "signal:content-ready";
  url: string;
  supported: boolean;
  reason?: string;
  topFrame: boolean;
};

export type InteractionResetMessage = {
  version: 1;
  type: "signal:interaction-reset";
  generation: number;
};

export type ZoomRequestMessage = {
  version: 1;
  type: "signal:zoom-request";
  delta: number;
  timestamp: number;
};

export type CommandMessage = {
  version: 1;
  type: "signal:command";
  command: SignalCommand;
};

export type ContentActionMessage = {
  version: 1;
  type: "signal:content-action";
  requestId: string;
  action: BrowserCommandAction;
};

export type ContentActionResultMessage = {
  version: 1;
  type: "signal:content-action-result";
  requestId: string;
  ok: boolean;
  message: string;
};

export type GestureProgressMessage = {
  version: 1;
  type: "signal:gesture-progress";
  gesture: GestureId;
  phase: "detected" | "holding" | "fired" | "released" | "suppressed";
  progress: number;
  confidence: number;
  timestamp: number;
};

export type SignalMessage =
  | TrackingFrameMessage
  | OffscreenControlMessage
  | OffscreenStateMessage
  | OffscreenPermissionRequiredMessage
  | SignalModeMessage
  | SignalTuningMessage
  | SignalResetMessage
  | ZoomStatusMessage
  | UnsupportedPageMessage
  | ContentReadyMessage
  | InteractionResetMessage
  | ZoomRequestMessage
  | CommandMessage
  | ContentActionMessage
  | ContentActionResultMessage
  | GestureProgressMessage;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const finite = (value: unknown): value is number =>
  typeof value === "number" && Number.isFinite(value);

const validGesture = (value: unknown): value is TrackingGesture =>
  value === "pointer" ||
  value === "pinch" ||
  value === "unknown" ||
  GESTURE_IDS.includes(value as GestureId);

export function isTrackingFrameMessage(
  value: unknown,
): value is TrackingFrameMessage {
  if (!isRecord(value)) return false;
  if (
    value.version !== SIGNAL_MESSAGE_VERSION ||
    value.type !== "signal:tracking-frame" ||
    !finite(value.timestamp) ||
    !Number.isSafeInteger(value.sequence) ||
    (value.sequence as number) < 0 ||
    !validGesture(value.gesture) ||
    !finite(value.confidence) ||
    (value.confidence as number) < 0 ||
    (value.confidence as number) > 1
  ) {
    return false;
  }
  if (
    value.sessionId !== undefined &&
    (typeof value.sessionId !== "string" || value.sessionId.length > 128)
  ) {
    return false;
  }
  if (
    value.commandGesture !== undefined &&
    !GESTURE_IDS.includes(value.commandGesture as GestureId)
  ) {
    return false;
  }
  if (
    value.pointerDelta !== undefined &&
    (!isRecord(value.pointerDelta) ||
      !finite(value.pointerDelta.dx) ||
      !finite(value.pointerDelta.dy) ||
      (value.pointerDelta.normalized !== undefined &&
        typeof value.pointerDelta.normalized !== "boolean"))
  ) {
    return false;
  }
  if (value.pinch !== undefined) {
    if (!isRecord(value.pinch) || typeof value.pinch.closed !== "boolean") {
      return false;
    }
    if (
      !["idle", "pending", "scrolling", "zooming"].includes(
        String(value.pinch.transactionState),
      )
    ) {
      return false;
    }
    if (
      (value.pinch.deltaX !== undefined && !finite(value.pinch.deltaX)) ||
      (value.pinch.deltaY !== undefined && !finite(value.pinch.deltaY))
    ) {
      return false;
    }
  }
  return value.fps === undefined || (finite(value.fps) && value.fps >= 0);
}

export function isSignalMessage(value: unknown): value is SignalMessage {
  if (!isRecord(value) || value.version !== SIGNAL_MESSAGE_VERSION) return false;
  switch (value.type) {
    case "signal:tracking-frame":
      return isTrackingFrameMessage(value);
    case "signal:offscreen/start":
    case "signal:offscreen/pause":
    case "signal:offscreen/stop":
    case "signal:offscreen/ping":
      return true;
    case "signal:offscreen/state":
      return (
        [
          "idle",
          "starting",
          "requesting-permission",
          "running",
          "paused",
          "stopped",
          "error",
        ].includes(String(value.state)) &&
        finite(value.fps) &&
        typeof value.cameraActive === "boolean"
      );
    case "signal:offscreen/permission-required":
      return value.reason === "camera";
    case "signal:mode":
      return ["control", "commands", "paused"].includes(String(value.mode));
    case "signal:reset":
      return (
        [
          "tab-change",
          "navigation",
          "tracking-loss",
          "pause",
          "stop",
          "service-worker-restart",
        ].includes(String(value.reason)) &&
        Number.isSafeInteger(value.generation)
      );
    case "signal:zoom-request":
      return finite(value.delta) && finite(value.timestamp);
    case "signal:content-ready":
      return (
        typeof value.url === "string" &&
        typeof value.supported === "boolean" &&
        typeof value.topFrame === "boolean" &&
        (value.reason === undefined || typeof value.reason === "string")
      );
    case "signal:interaction-reset":
      return Number.isSafeInteger(value.generation);
    case "signal:unsupported":
      return value.message === PROTECTED_PAGE_MESSAGE;
    case "signal:zoom-status":
      return typeof value.supported === "boolean";
    case "signal:content-action-result":
      return (
        typeof value.requestId === "string" &&
        typeof value.ok === "boolean" &&
        typeof value.message === "string"
      );
    case "signal:gesture-progress":
      return (
        GESTURE_IDS.includes(value.gesture as GestureId) &&
        finite(value.progress) &&
        finite(value.confidence) &&
        finite(value.timestamp)
      );
    case "signal:command":
    case "signal:content-action":
      return true;
    default:
      return false;
  }
}

export function resetMessage(
  reason: SignalResetMessage["reason"],
  generation: number,
): SignalResetMessage {
  return { version: 1, type: "signal:reset", reason, generation };
}
