import { describe, expect, it, vi } from "vitest";

import {
  assertSafeBrowserUrl,
  executeBrowserPlan,
} from "../lib/commands/browser-actions";
import type { ActionPlan } from "../lib/contracts";
import { CommandGestureEngine } from "../lib/vision/command-gesture-engine";
import { ControlEngine } from "../lib/vision/control-engine";
import {
  HAND,
  mirrorLandmarks,
  type HandLandmark,
} from "../lib/vision/hand-geometry";
import { drawHandLandmarks } from "../lib/vision/landmark-renderer";
import { recognizeHandPose } from "../lib/vision/pose-recognizer";

type FingerName = "index" | "middle" | "ring" | "pinky";

const fingerIndices: Record<
  FingerName,
  { mcp: number; pip: number; dip: number; tip: number; x: number }
> = {
  index: { mcp: 5, pip: 6, dip: 7, tip: 8, x: 0.38 },
  middle: { mcp: 9, pip: 10, dip: 11, tip: 12, x: 0.48 },
  ring: { mcp: 13, pip: 14, dip: 15, tip: 16, x: 0.58 },
  pinky: { mcp: 17, pip: 18, dip: 19, tip: 20, x: 0.67 },
};

function makeHand(
  extendedNames: readonly FingerName[] = [],
  thumb: "folded" | "extended" | "up" | "down" | "c" = "folded",
) {
  const points: HandLandmark[] = Array.from({ length: 21 }, () => ({
    x: 0.5,
    y: 0.7,
    z: 0,
  }));
  points[HAND.wrist] = { x: 0.5, y: 0.9 };
  for (const [name, indices] of Object.entries(fingerIndices) as Array<
    [FingerName, (typeof fingerIndices)[FingerName]]
  >) {
    const extended = extendedNames.includes(name);
    points[indices.mcp] = { x: indices.x, y: name === "pinky" ? 0.69 : 0.64 };
    points[indices.pip] = {
      x: indices.x,
      y: extended ? 0.49 : 0.57,
    };
    points[indices.dip] = {
      x: extended ? indices.x : indices.x + 0.035,
      y: extended ? 0.34 : 0.63,
    };
    points[indices.tip] = {
      x: extended ? indices.x : indices.x + 0.055,
      y: extended ? 0.19 : 0.7,
    };
  }

  points[HAND.thumbCmc] = { x: 0.42, y: 0.78 };
  points[HAND.thumbMcp] = { x: 0.36, y: 0.72 };
  points[HAND.thumbIp] = { x: 0.32, y: 0.67 };
  points[HAND.thumbTip] = { x: 0.43, y: 0.69 };
  if (thumb === "extended") {
    points[HAND.thumbIp] = { x: 0.25, y: 0.65 };
    points[HAND.thumbTip] = { x: 0.14, y: 0.62 };
  } else if (thumb === "up") {
    points[HAND.thumbMcp] = { x: 0.46, y: 0.72 };
    points[HAND.thumbIp] = { x: 0.46, y: 0.56 };
    points[HAND.thumbTip] = { x: 0.47, y: 0.35 };
  } else if (thumb === "down") {
    points[HAND.thumbMcp] = { x: 0.46, y: 0.76 };
    points[HAND.thumbIp] = { x: 0.46, y: 0.88 };
    points[HAND.thumbTip] = { x: 0.47, y: 1.06 };
  } else if (thumb === "c") {
    points[HAND.thumbIp] = { x: 0.29, y: 0.61 };
    points[HAND.thumbTip] = { x: 0.29, y: 0.59 };
  }
  return points;
}

function withPinch(
  landmarks: readonly HandLandmark[],
  gap: number,
) {
  const copy = landmarks.map((point) => ({ ...point }));
  copy[HAND.thumbTip] = { x: 0.48, y: 0.42 };
  copy[HAND.indexTip] = { x: 0.48 + gap, y: 0.42 };
  return copy;
}

function shift(
  landmarks: readonly HandLandmark[],
  x: number,
  y: number,
) {
  return landmarks.map((point) => ({
    ...point,
    x: point.x + x,
    y: point.y + y,
  }));
}

function simplePlan(
  action: ActionPlan["steps"][number]["action"],
): ActionPlan {
  return {
    schemaVersion: 1,
    id: "browser-plan",
    name: "Browser plan",
    description: "Test browser plan",
    steps: [
      {
        id: "step-1",
        action,
        timeoutMs: 2_000,
        onFailure: "stop",
        confirmation: { mode: "none", reason: "" },
      },
    ],
    timeoutMs: 5_000,
    onFailure: "stop",
    confirmation: { mode: "none", reason: "" },
    createdSource: "import",
    secretReferences: [],
  };
}

describe("browser hand geometry and pose recognition", () => {
  it.each([
    [["index"], "folded", "one"],
    [["index", "middle"], "folded", "two"],
    [["index", "middle", "ring"], "folded", "three"],
    [["index", "middle", "ring", "pinky"], "folded", "four"],
    [["index", "middle", "ring", "pinky"], "extended", "five"],
    [[], "up", "thumbs_up"],
    [[], "down", "thumbs_down"],
    [[], "c", "c_shape"],
    [[], "folded", "fist"],
  ] as Array<[FingerName[], Parameters<typeof makeHand>[1], string]>)(
    "recognizes %s with %s thumb as %s",
    (fingers, thumb, expected) => {
      expect(recognizeHandPose(makeHand(fingers, thumb)).gesture).toBe(expected);
    },
  );

  it("marks the index-only pose for relative pointer control", () => {
    const result = recognizeHandPose(makeHand(["index"]));
    expect(result.pointerPose).toBe(true);
    expect(result.confidence).toBeGreaterThan(0.8);
  });

  it("mirrors landmark x coordinates exactly once", () => {
    const mirrored = mirrorLandmarks([{ x: 0.2, y: 0.4 }]);
    expect(mirrored).toEqual([{ x: 0.8, y: 0.4 }]);
  });

  it("renders every landmark and connection on the camera canvas", () => {
    const context = {
      clearRect: vi.fn(),
      beginPath: vi.fn(),
      moveTo: vi.fn(),
      lineTo: vi.fn(),
      stroke: vi.fn(),
      arc: vi.fn(),
      fill: vi.fn(),
      lineCap: "",
      lineJoin: "",
      strokeStyle: "",
      lineWidth: 0,
      fillStyle: "",
    } as unknown as CanvasRenderingContext2D;
    const canvas = {
      width: 0,
      height: 0,
      getContext: vi.fn(() => context),
    } as unknown as HTMLCanvasElement;

    expect(drawHandLandmarks(canvas, 640, 480, makeHand(["index"]))).toBe(true);
    expect(context.arc).toHaveBeenCalledTimes(21);
    expect(context.stroke).toHaveBeenCalledTimes(21);
    expect(canvas.width).toBe(640);
    expect(canvas.height).toBe(480);
  });
});

describe("control-mode transaction engine", () => {
  it("reanchors after pose loss without a cursor jump", () => {
    const engine = new ControlEngine({ width: 1_000, height: 800 });
    const first = makeHand(["index"]);
    const anchored = engine.update({
      landmarks: first,
      pointerPose: true,
      timestamp: 0,
    });
    const moved = engine.update({
      landmarks: shift(first, 0.04, 0),
      pointerPose: true,
      timestamp: 16,
    });
    expect(moved.cursor.x).toBeGreaterThan(anchored.cursor.x);

    engine.update(null);
    const reentered = engine.update({
      landmarks: shift(first, -0.3, 0),
      pointerPose: true,
      timestamp: 40,
    });
    expect(reentered.cursor.x).toBeCloseTo(moved.cursor.x, 5);
  });

  it("uses pinch hysteresis and emits one click only after quick release", () => {
    const engine = new ControlEngine({ width: 1_000, height: 800 });
    const base = makeHand([]);
    const closed = withPinch(base, 0.02);
    const intermediate = withPinch(base, 0.1);
    const open = withPinch(base, 0.2);

    expect(
      engine.update({ landmarks: closed, pointerPose: false, timestamp: 0 })
        .pinchClosed,
    ).toBe(true);
    expect(
      engine.update({
        landmarks: intermediate,
        pointerPose: false,
        timestamp: 80,
      }).pinchClosed,
    ).toBe(true);
    const released = engine.update({
      landmarks: open,
      pointerPose: false,
      timestamp: 180,
    });
    expect(released.effects).toHaveLength(1);
    expect(released.effects[0]?.type).toBe("click");
    const next = engine.update({
      landmarks: open,
      pointerPose: false,
      timestamp: 200,
    });
    expect(next.effects).toHaveLength(0);
  });

  it("locks vertical movement to scroll until release", () => {
    const engine = new ControlEngine({ width: 1_000, height: 800 });
    const closed = withPinch(makeHand([]), 0.02);
    engine.update({ landmarks: closed, pointerPose: false, timestamp: 0 });
    const locked = engine.update({
      landmarks: shift(closed, 0.005, 0.08),
      pointerPose: false,
      timestamp: 160,
    });
    expect(locked.transaction).toBe("scrolling");
    const moved = engine.update({
      landmarks: shift(closed, 0.12, 0.1),
      pointerPose: false,
      timestamp: 180,
    });
    expect(moved.transaction).toBe("scrolling");
    expect(moved.effects.some((effect) => effect.type === "scroll")).toBe(true);
    expect(moved.effects.some((effect) => effect.type === "zoom")).toBe(false);
  });

  it("locks horizontal movement to zoom until release", () => {
    const engine = new ControlEngine({ width: 1_000, height: 800 });
    const closed = withPinch(makeHand([]), 0.02);
    engine.update({ landmarks: closed, pointerPose: false, timestamp: 0 });
    const locked = engine.update({
      landmarks: shift(closed, 0.08, 0.005),
      pointerPose: false,
      timestamp: 160,
    });
    expect(locked.transaction).toBe("zooming");
    const moved = engine.update({
      landmarks: shift(closed, 0.1, 0.12),
      pointerPose: false,
      timestamp: 180,
    });
    expect(moved.transaction).toBe("zooming");
    expect(moved.effects.some((effect) => effect.type === "zoom")).toBe(true);
    expect(moved.effects.some((effect) => effect.type === "scroll")).toBe(false);
  });

  it("resets interaction immediately when tracking is lost", () => {
    const engine = new ControlEngine({ width: 1_000, height: 800 });
    const closed = withPinch(makeHand([]), 0.02);
    engine.update({ landmarks: closed, pointerPose: false, timestamp: 0 });
    expect(engine.update(null)).toMatchObject({
      transaction: "idle",
      pinchClosed: false,
      cursor: { visible: false },
      effects: [],
    });
  });
});

describe("command-mode stable hold", () => {
  it("fires once after 550 ms and requires pose loss before rearming", () => {
    const engine = new CommandGestureEngine(550, 800);
    expect(engine.update("fist", 0.95, 0)).toMatchObject({
      phase: "detected",
      firedNow: false,
    });
    expect(engine.update("fist", 0.95, 400)).toMatchObject({
      phase: "holding",
      firedNow: false,
    });
    expect(engine.update("fist", 0.95, 550)).toMatchObject({
      phase: "fired",
      firedNow: true,
    });
    expect(engine.update("fist", 0.95, 1_500)?.firedNow).toBe(false);
    expect(engine.update(null, 0, 1_600)?.phase).toBe("released");
    expect(engine.update("fist", 0.95, 1_700)?.phase).toBe("detected");
    expect(engine.update("fist", 0.95, 2_250)?.firedNow).toBe(true);
  });
});

describe("browser-only command execution", () => {
  it("rejects dangerous and local navigation schemes", () => {
    for (const value of [
      "javascript:alert(1)",
      "data:text/html,hello",
      "file:///tmp/secret",
      "http://localhost:3000",
      "https://127.0.0.1/private",
    ]) {
      expect(() => assertSafeBrowserUrl(value)).toThrow(/public HTTPS/i);
    }
  });

  it("navigates only a user-prepared reusable action tab", async () => {
    const tab = {
      closed: false,
      location: { href: "about:blank" },
      focus: vi.fn(),
    } as unknown as Window;
    const receipt = await executeBrowserPlan(
      simplePlan({
        type: "open_url",
        parameters: {
          url: "https://example.com/path",
          networkPolicy: "public_https_only",
        },
      }),
      { actionTab: tab },
    );
    expect(tab.location.href).toBe("https://example.com/path");
    expect(tab.focus).toHaveBeenCalledOnce();
    expect(receipt.completedSteps).toBe(1);
  });

  it("refuses native-only actions even when legacy schema data is valid", async () => {
    await expect(
      executeBrowserPlan(
        simplePlan({
          type: "open_application",
          parameters: {
            bundleIdentifier: "com.apple.Safari",
            applicationName: "Safari",
          },
        }),
      ),
    ).rejects.toThrow(/not available in browser-only Signal/i);
  });
});
