import "@testing-library/jest-dom/vitest";

import { createElement } from "react";
import { act, cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";

import {
  dispatchSignalGesture,
  isSignalGestureEventDetail,
  SIGNAL_GESTURE_EVENT,
  type SignalGestureEventDetail,
} from "../lib/gestures/bridge";
import { useSignalGestureBridge } from "../lib/gestures/useSignalGestureBridge";

function BridgeHarness({
  disabled = false,
  cooldownMs = 900,
}: {
  disabled?: boolean;
  cooldownMs?: number;
}) {
  const state = useSignalGestureBridge({ disabled, cooldownMs });
  return createElement("output", {
    "aria-label": "bridge state",
    "data-active": state.activeGesture ?? "",
    "data-confidence": String(state.confidence),
    "data-progress": String(state.progress),
    "data-fired": state.lastFiredGesture ?? "",
  });
}

afterEach(() => {
  cleanup();
});

describe("normalized gesture event contract", () => {
  it("accepts bounded normalized input and rejects malformed input", () => {
    expect(
      isSignalGestureEventDetail({
        gesture: "thumbs_up",
        confidence: 0.92,
        phase: "holding",
        progress: 0.6,
      }),
    ).toBe(true);
    expect(
      isSignalGestureEventDetail({
        gesture: "unknown",
        confidence: 0.92,
        phase: "holding",
      }),
    ).toBe(false);
    expect(
      isSignalGestureEventDetail({
        gesture: "fist",
        confidence: 1.01,
        phase: "recognized",
      }),
    ).toBe(false);
    expect(
      isSignalGestureEventDetail({
        gesture: "fist",
        confidence: 0.8,
        phase: "holding",
        progress: -0.1,
      }),
    ).toBe(false);
  });

  it("dispatches a normalized CustomEvent and supplies a timestamp", () => {
    let received: SignalGestureEventDetail | undefined;
    const listener = (event: Event) => {
      received = (event as CustomEvent<SignalGestureEventDetail>).detail;
    };
    window.addEventListener(SIGNAL_GESTURE_EVENT, listener);
    try {
      dispatchSignalGesture({
        gesture: "c_shape",
        confidence: 0.88,
        phase: "recognized",
      });
      expect(received).toMatchObject({
        gesture: "c_shape",
        confidence: 0.88,
        phase: "recognized",
      });
      expect(received?.timestamp).toEqual(expect.any(Number));
    } finally {
      window.removeEventListener(SIGNAL_GESTURE_EVENT, listener);
    }

    expect(() =>
      dispatchSignalGesture({
        gesture: "fist",
        confidence: 2,
        phase: "fired",
      }),
    ).toThrow("Invalid normalized Signal gesture event.");
  });
});

describe("useSignalGestureBridge", () => {
  it("normalizes hold progress and clears the active gesture on release", () => {
    render(createElement(BridgeHarness));
    const state = screen.getByLabelText("bridge state");

    act(() => {
      dispatchSignalGesture({
        gesture: "three",
        confidence: 0.72,
        phase: "holding",
        timestamp: 1_000,
      });
    });
    expect(state).toHaveAttribute("data-active", "three");
    expect(state).toHaveAttribute("data-progress", "0.72");
    expect(state).toHaveAttribute("data-confidence", "0.72");

    act(() => {
      dispatchSignalGesture({
        gesture: "three",
        confidence: 0.7,
        phase: "released",
        timestamp: 1_100,
      });
    });
    expect(state).toHaveAttribute("data-active", "");
    expect(state).toHaveAttribute("data-progress", "0");
  });

  it("applies per-gesture cooldown without suppressing normalized state", () => {
    render(createElement(BridgeHarness, { cooldownMs: 900 }));
    const state = screen.getByLabelText("bridge state");

    act(() => {
      dispatchSignalGesture({
        gesture: "fist",
        confidence: 0.95,
        phase: "recognized",
        timestamp: 1_000,
      });
      dispatchSignalGesture({
        gesture: "two",
        confidence: 0.9,
        phase: "fired",
        timestamp: 1_100,
      });
      dispatchSignalGesture({
        gesture: "fist",
        confidence: 0.93,
        phase: "fired",
        timestamp: 1_500,
      });
    });

    expect(state).toHaveAttribute("data-active", "fist");
    expect(state).toHaveAttribute("data-progress", "1");
    expect(state).toHaveAttribute("data-fired", "two");

    act(() => {
      dispatchSignalGesture({
        gesture: "fist",
        confidence: 0.94,
        phase: "fired",
        timestamp: 1_901,
      });
    });
    expect(state).toHaveAttribute("data-fired", "fist");
  });

  it("ignores gesture events while command editing is disabled", () => {
    const { rerender } = render(
      createElement(BridgeHarness, { disabled: false }),
    );
    const state = screen.getByLabelText("bridge state");

    act(() => {
      dispatchSignalGesture({
        gesture: "one",
        confidence: 0.8,
        phase: "holding",
        timestamp: 1_000,
      });
    });
    expect(state).toHaveAttribute("data-active", "one");

    rerender(createElement(BridgeHarness, { disabled: true }));
    act(() => {
      window.signalGestureBridge?.emit({
        gesture: "five",
        confidence: 1,
        phase: "fired",
        timestamp: 2_000,
      });
    });
    expect(state).toHaveAttribute("data-active", "one");
    expect(state).toHaveAttribute("data-fired", "");
  });
});
