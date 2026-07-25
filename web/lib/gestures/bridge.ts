import { gestureIds, type GestureId } from "../../config/gestureCommands";

export const SIGNAL_GESTURE_EVENT = "signal:gesture";

export type SignalGesturePhase =
  | "detected"
  | "holding"
  | "recognized"
  | "fired"
  | "released";

export type SignalGestureEventDetail = {
  gesture: GestureId;
  confidence: number;
  phase: SignalGesturePhase;
  progress?: number;
  timestamp?: number;
};

export function isSignalGestureEventDetail(
  value: unknown,
): value is SignalGestureEventDetail {
  if (!value || typeof value !== "object") return false;
  const candidate = value as Partial<SignalGestureEventDetail>;
  return (
    gestureIds.includes(candidate.gesture as GestureId) &&
    typeof candidate.confidence === "number" &&
    candidate.confidence >= 0 &&
    candidate.confidence <= 1 &&
    ["detected", "holding", "recognized", "fired", "released"].includes(
      candidate.phase ?? "",
    ) &&
    (candidate.progress === undefined ||
      (typeof candidate.progress === "number" &&
        candidate.progress >= 0 &&
        candidate.progress <= 1))
  );
}

export function dispatchSignalGesture(detail: SignalGestureEventDetail) {
  if (!isSignalGestureEventDetail(detail)) {
    throw new TypeError("Invalid normalized Signal gesture event.");
  }
  window.dispatchEvent(
    new CustomEvent<SignalGestureEventDetail>(SIGNAL_GESTURE_EVENT, {
      detail: { ...detail, timestamp: detail.timestamp ?? Date.now() },
    }),
  );
}

declare global {
  interface WindowEventMap {
    "signal:gesture": CustomEvent<SignalGestureEventDetail>;
  }

  interface Window {
    signalGestureBridge?: {
      emit: typeof dispatchSignalGesture;
    };
  }
}
