"use client";

import { useEffect, useRef, useState } from "react";

import type { GestureId } from "../../config/gestureCommands";
import {
  dispatchSignalGesture,
  isSignalGestureEventDetail,
  SIGNAL_GESTURE_EVENT,
} from "./bridge";

type BridgeState = {
  activeGesture: GestureId | null;
  confidence: number;
  progress: number;
  lastFiredGesture: GestureId | null;
};

const initialState: BridgeState = {
  activeGesture: null,
  confidence: 0,
  progress: 0,
  lastFiredGesture: null,
};

export function useSignalGestureBridge({
  disabled,
  cooldownMs = 900,
  onFire,
}: {
  disabled: boolean;
  cooldownMs?: number;
  onFire?(gesture: GestureId): void;
}) {
  const [state, setState] = useState(initialState);
  const lastFireAt = useRef<Record<string, number>>({});
  const onFireRef = useRef(onFire);

  useEffect(() => {
    onFireRef.current = onFire;
  }, [onFire]);

  useEffect(() => {
    window.signalGestureBridge = {
      emit(detail) {
        dispatchSignalGesture(detail);
      },
    };

    function handle(event: Event) {
      if (disabled || !(event instanceof CustomEvent)) return;
      const detail: unknown = event.detail;
      if (!isSignalGestureEventDetail(detail)) return;
      const gesture = detail.gesture;

      if (detail.phase === "released") {
        setState((current) => ({
          ...current,
          activeGesture:
            current.activeGesture === gesture ? null : current.activeGesture,
          progress: 0,
        }));
        return;
      }

      const progress =
        detail.progress ??
        (detail.phase === "holding"
          ? Math.min(1, detail.confidence)
          : detail.phase === "recognized" || detail.phase === "fired"
            ? 1
            : 0);
      const now = detail.timestamp ?? Date.now();
      const shouldFire =
        detail.phase === "fired" || detail.phase === "recognized";
      const previousFire = lastFireAt.current[gesture] ?? 0;
      const acceptedFire = shouldFire && now - previousFire >= cooldownMs;
      if (acceptedFire) {
        lastFireAt.current[gesture] = now;
        onFireRef.current?.(gesture);
      }

      setState((current) => ({
        activeGesture: gesture,
        confidence: detail.confidence,
        progress,
        lastFiredGesture: acceptedFire
          ? gesture
          : current.lastFiredGesture,
      }));
    }

    window.addEventListener(SIGNAL_GESTURE_EVENT, handle);
    return () => {
      window.removeEventListener(SIGNAL_GESTURE_EVENT, handle);
      delete window.signalGestureBridge;
    };
  }, [cooldownMs, disabled]);

  return state;
}
