import { describe, expect, it, vi } from "vitest";

import {
  CameraRuntime,
  cameraErrorMessage,
} from "../src/offscreen/camera-runtime";
import {
  TrackingNormalizer,
  type HandLandmark,
} from "../src/offscreen/mediapipe-runtime";

function makeStream() {
  const track = {
    addEventListener: vi.fn(),
    getSettings: vi.fn(() => ({
      width: 640,
      height: 480,
      frameRate: 30,
    })),
    stop: vi.fn(),
  };
  const stream = {
    active: true,
    getTracks: () => [track],
    getVideoTracks: () => [track],
  } as unknown as MediaStream;
  return { stream, track };
}

function makeVideo() {
  return {
    videoWidth: 640,
    videoHeight: 480,
    srcObject: null,
    play: vi.fn(async () => undefined),
    pause: vi.fn(),
  } as unknown as HTMLVideoElement;
}

function landmarks(): HandLandmark[] {
  return Array.from({ length: 21 }, (_, index) => ({
    x: 0.25 + (index % 4) * 0.03,
    y: 0.75 - Math.floor(index / 4) * 0.03,
    z: 0,
  }));
}

function setPointerShape(points: HandLandmark[]): void {
  points[0] = { x: 0.5, y: 0.85, z: 0 };
  points[5] = { x: 0.48, y: 0.62, z: 0 };
  points[6] = { x: 0.48, y: 0.48, z: 0 };
  points[7] = { x: 0.48, y: 0.34, z: 0 };
  points[8] = { x: 0.48, y: 0.18, z: 0 };
  for (const [mcp, pip, dip, tip, x] of [
    [9, 10, 11, 12, 0.53],
    [13, 14, 15, 16, 0.58],
    [17, 18, 19, 20, 0.63],
  ] as const) {
    points[mcp] = { x, y: 0.62, z: 0 };
    points[pip] = { x: x + 0.01, y: 0.58, z: 0 };
    points[dip] = { x: x + 0.04, y: 0.62, z: 0 };
    points[tip] = { x: x + 0.06, y: 0.68, z: 0 };
  }
  points[2] = { x: 0.42, y: 0.67, z: 0 };
  points[3] = { x: 0.4, y: 0.64, z: 0 };
  points[4] = { x: 0.39, y: 0.63, z: 0 };
}

function pinchedHand(): HandLandmark[] {
  const points = landmarks();
  points[0] = { x: 0.5, y: 0.8, z: 0 };
  points[5] = { x: 0.4, y: 0.62, z: 0 };
  points[9] = { x: 0.5, y: 0.6, z: 0 };
  points[17] = { x: 0.6, y: 0.62, z: 0 };
  points[2] = { x: 0.43, y: 0.58, z: 0 };
  points[4] = { x: 0.49, y: 0.4, z: 0 };
  points[8] = { x: 0.51, y: 0.4, z: 0 };
  return points;
}

function translate(
  points: readonly HandLandmark[],
  dx: number,
  dy: number,
): HandLandmark[] {
  return points.map((point) => ({
    ...point,
    x: point.x + dx,
    y: point.y + dy,
  }));
}

describe("CameraRuntime", () => {
  it("stops every camera track when paused", async () => {
    const { stream, track } = makeStream();
    const video = makeVideo();
    const runtime = new CameraRuntime({
      video,
      mediaDevices: { getUserMedia: vi.fn(async () => stream) },
    });

    await runtime.start();
    expect(runtime.snapshot.state).toBe("running");
    runtime.pause();

    expect(track.stop).toHaveBeenCalledOnce();
    expect(video.srcObject).toBeNull();
    expect(runtime.snapshot.state).toBe("paused");
  });

  it("does not open a second stream while already running", async () => {
    const { stream } = makeStream();
    const getUserMedia = vi.fn(async () => stream);
    const runtime = new CameraRuntime({
      video: makeVideo(),
      mediaDevices: { getUserMedia },
    });

    await runtime.start();
    await runtime.start();

    expect(getUserMedia).toHaveBeenCalledOnce();
  });

  it("stops a camera stream that resolves after Pause", async () => {
    const { stream, track } = makeStream();
    let resolveCamera: ((value: MediaStream) => void) | undefined;
    const getUserMedia = vi.fn(
      () =>
        new Promise<MediaStream>((resolve) => {
          resolveCamera = resolve;
        }),
    );
    const runtime = new CameraRuntime({
      video: makeVideo(),
      mediaDevices: { getUserMedia },
    });

    const start = runtime.start();
    runtime.pause();
    resolveCamera?.(stream);

    await expect(start).rejects.toMatchObject({ name: "AbortError" });
    expect(track.stop).toHaveBeenCalledOnce();
    expect(runtime.snapshot.state).toBe("paused");
  });

  it("fails a camera request that never resolves instead of hanging", async () => {
    vi.useFakeTimers();
    try {
      const runtime = new CameraRuntime({
        video: makeVideo(),
        mediaDevices: {
          getUserMedia: vi.fn(() => new Promise<MediaStream>(() => undefined)),
        },
      });

      const start = runtime.start();
      const rejection = expect(start).rejects.toMatchObject({
        name: "NotAllowedError",
      });
      await vi.advanceTimersByTimeAsync(8_000);
      await rejection;
    } finally {
      vi.useRealTimers();
    }
  });

  it("maps camera denial to the visible-setup fallback message", () => {
    expect(
      cameraErrorMessage(new DOMException("", "NotAllowedError")),
    ).toContain("Camera permission");
  });
});

describe("TrackingNormalizer", () => {
  it("establishes a pointer anchor without emitting a jump", () => {
    const input = landmarks();
    setPointerShape(input);
    const normalizer = new TrackingNormalizer({
      pointerDeadZone: 0,
      pointerSmoothing: 1,
    });

    const first = normalizer.analyze(input, 0);

    expect(first?.gesture).toBe("pointer");
    expect(first?.pointerDelta).toBeUndefined();
  });

  it("emits palm-normalized mirrored pointer movement after anchoring", () => {
    const input = landmarks();
    setPointerShape(input);
    const normalizer = new TrackingNormalizer({
      pointerDeadZone: 0,
      pointerSmoothing: 1,
    });
    normalizer.analyze(input, 0);
    input[8] = { ...input[8]!, x: input[8]!.x - 0.02 };

    const moved = normalizer.analyze(input, 16);

    expect(moved?.pointerDelta?.dx).toBeLessThan(0);
    expect(moved?.pointerDelta?.normalized).toBe(true);
    expect(moved?.pointerDelta?.dy).toBeCloseTo(0);
  });

  it("clears pointer and pinch state on tracking loss", () => {
    const input = landmarks();
    setPointerShape(input);
    const normalizer = new TrackingNormalizer();
    normalizer.analyze(input, 0);

    expect(normalizer.analyze([], 16)).toBeNull();
    const reacquired = normalizer.analyze(input, 32);

    expect(reacquired?.pointerDelta).toBeUndefined();
    expect(reacquired?.pinch.transactionState).toBe("idle");
  });

  it("locks a held dominant vertical pinch as scrolling until release", () => {
    const normalizer = new TrackingNormalizer();
    const initial = pinchedHand();

    expect(
      normalizer.analyze(initial, 0)?.pinch.transactionState,
    ).toBe("pending");
    expect(
      normalizer.analyze(translate(initial, 0, 0.06), 150)?.pinch
        .transactionState,
    ).toBe("scrolling");
    expect(
      normalizer.analyze(translate(initial, 0, 0.08), 166)?.pinch.deltaY,
    ).toBeGreaterThan(0);

    const released = translate(initial, 0, 0.08);
    released[4] = { x: 0.25, y: 0.4, z: 0 };
    released[8] = { x: 0.75, y: 0.4, z: 0 };
    const release = normalizer.analyze(released, 182);
    expect(release?.pinch.closed).toBe(false);
    expect(release?.pinch.transactionState).toBe("idle");
  });

  it("locks a held dominant horizontal pinch as zooming", () => {
    const normalizer = new TrackingNormalizer();
    const initial = pinchedHand();
    normalizer.analyze(initial, 0);

    const locked = normalizer.analyze(
      translate(initial, 0.06, 0),
      150,
    );

    expect(locked?.pinch.transactionState).toBe("zooming");
  });
});
