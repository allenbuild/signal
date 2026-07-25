import { describe, expect, it } from "vitest";

import { CommandGestureEngine } from "../src/shared/gesture";
import {
  isSignalMessage,
  isTrackingFrameMessage,
  resetMessage,
} from "../src/shared/messages";
import { GESTURE_IDS } from "../src/shared/types";

const commands = {
  mode: "commands" as const,
  editing: false,
  supportedTab: true,
};

describe("versioned messages", () => {
  it("accepts structurally valid tracking frames and rejects stale contracts", () => {
    const frame = {
      version: 1 as const,
      type: "signal:tracking-frame" as const,
      timestamp: 100,
      sequence: 4,
      gesture: "pointer" as const,
      confidence: 0.92,
      landmarks: [{ x: 0.2, y: 0.4, z: -0.01 }],
      pointerDelta: { dx: 2, dy: -1 },
      pinch: { closed: false, transactionState: "idle" as const },
      fps: 30,
    };
    expect(isTrackingFrameMessage(frame)).toBe(true);
    expect(isSignalMessage(frame)).toBe(true);
    expect(isTrackingFrameMessage({ ...frame, version: 2 })).toBe(false);
    expect(isTrackingFrameMessage({ ...frame, confidence: 2 })).toBe(false);
  });

  it("creates generation-scoped reset messages", () => {
    expect(resetMessage("tab-change", 7)).toEqual({
      version: 1,
      type: "signal:reset",
      reason: "tab-change",
      generation: 7,
    });
  });
});

describe("nine-gesture one-shot engine", () => {
  it("supports exactly the nine documented command gestures", () => {
    expect(GESTURE_IDS).toEqual([
      "one",
      "two",
      "three",
      "four",
      "five",
      "thumbs_up",
      "thumbs_down",
      "c_shape",
      "fist",
    ]);
  });

  it("fires once after a stable hold and requires a pose change to rearm", () => {
    const engine = new CommandGestureEngine({
      holdMs: 500,
      cooldownMs: 200,
      minimumConfidence: 0.7,
    });
    expect(
      engine.update(
        { gesture: "fist", confidence: 0.9, timestamp: 0 },
        commands,
      )?.phase,
    ).toBe("detected");
    expect(
      engine.update(
        { gesture: "fist", confidence: 0.9, timestamp: 500 },
        commands,
      )?.firedNow,
    ).toBe(true);
    expect(
      engine.update(
        { gesture: "fist", confidence: 0.9, timestamp: 1_000 },
        commands,
      )?.firedNow,
    ).toBe(false);

    expect(
      engine.update(
        { gesture: null, confidence: 0, timestamp: 1_010 },
        commands,
      )?.phase,
    ).toBe("released");
    engine.update(
      { gesture: "fist", confidence: 0.9, timestamp: 1_020 },
      commands,
    );
    expect(
      engine.update(
        { gesture: "fist", confidence: 0.9, timestamp: 1_520 },
        commands,
      )?.firedNow,
    ).toBe(true);
  });

  it("suppresses commands while editing, paused, controlling, or unsupported", () => {
    const engine = new CommandGestureEngine();
    for (const context of [
      { ...commands, editing: true },
      { ...commands, supportedTab: false },
      { ...commands, mode: "control" as const },
      { ...commands, mode: "paused" as const },
    ]) {
      const result = engine.update(
        { gesture: "one", confidence: 1, timestamp: 1_000 },
        context,
      );
      expect(result?.phase).toBe("suppressed");
      expect(result?.firedNow).toBe(false);
    }
  });

  it("exposes deterministic hold progress and rejects weak detections", () => {
    const engine = new CommandGestureEngine({
      holdMs: 1_000,
      minimumConfidence: 0.8,
    });
    expect(
      engine.update(
        { gesture: "two", confidence: 0.7, timestamp: 0 },
        commands,
      ),
    ).toBeNull();
    engine.update(
      { gesture: "two", confidence: 0.9, timestamp: 100 },
      commands,
    );
    expect(
      engine.update(
        { gesture: "two", confidence: 0.9, timestamp: 600 },
        commands,
      )?.progress,
    ).toBe(0.5);
  });
});
