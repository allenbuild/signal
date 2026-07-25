import type {
  HandLandmarker,
  HandLandmarkerResult,
  NormalizedLandmark,
} from "@mediapipe/tasks-vision";

export const MEDIAPIPE_VERSION = "0.10.35";
export const HAND_LANDMARKER_MODEL_PATH =
  "mediapipe/hand_landmarker.task";
export const HAND_LANDMARKER_WASM_PATH =
  `mediapipe/${MEDIAPIPE_VERSION}/wasm`;

export const SIGNAL_GESTURES = [
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

export type SignalGestureId = (typeof SIGNAL_GESTURES)[number];

export type HandLandmark = {
  x: number;
  y: number;
  z: number;
  visibility?: number;
};

export type TrackingGesture =
  | SignalGestureId
  | "pointer"
  | "pinch"
  | "unknown";

export type PinchTransactionState =
  | "idle"
  | "pending"
  | "scrolling"
  | "zooming";

export type TrackingAnalysis = {
  landmarks: HandLandmark[];
  gesture: TrackingGesture;
  commandGesture?: SignalGestureId;
  confidence: number;
  pointerDelta?: { dx: number; dy: number; normalized: true };
  pinch: {
    closed: boolean;
    transactionState: PinchTransactionState;
    deltaX?: number;
    deltaY?: number;
  };
};

export type TrackingNormalizerOptions = {
  pinchCloseRatio?: number;
  pinchOpenRatio?: number;
  pinchIntentHoldMs?: number;
  pinchIntentDistance?: number;
  dominantAxisRatio?: number;
  pointerDeadZone?: number;
  pointerSmoothing?: number;
  pointerMaximumDelta?: number;
};

type Point = Pick<HandLandmark, "x" | "y">;

const HAND = {
  wrist: 0,
  thumbMcp: 2,
  thumbIp: 3,
  thumbTip: 4,
  indexMcp: 5,
  indexPip: 6,
  indexDip: 7,
  indexTip: 8,
  middleMcp: 9,
  middlePip: 10,
  middleDip: 11,
  middleTip: 12,
  ringMcp: 13,
  ringPip: 14,
  ringDip: 15,
  ringTip: 16,
  pinkyMcp: 17,
  pinkyPip: 18,
  pinkyDip: 19,
  pinkyTip: 20,
} as const;

const PINCH_DELTA_REFERENCE_PIXELS = 160;

type Finger = {
  mcp: number;
  pip: number;
  dip: number;
  tip: number;
};

const FINGERS: Record<"index" | "middle" | "ring" | "pinky", Finger> = {
  index: {
    mcp: HAND.indexMcp,
    pip: HAND.indexPip,
    dip: HAND.indexDip,
    tip: HAND.indexTip,
  },
  middle: {
    mcp: HAND.middleMcp,
    pip: HAND.middlePip,
    dip: HAND.middleDip,
    tip: HAND.middleTip,
  },
  ring: {
    mcp: HAND.ringMcp,
    pip: HAND.ringPip,
    dip: HAND.ringDip,
    tip: HAND.ringTip,
  },
  pinky: {
    mcp: HAND.pinkyMcp,
    pip: HAND.pinkyPip,
    dip: HAND.pinkyDip,
    tip: HAND.pinkyTip,
  },
};

function distance(a: Point, b: Point): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(maximum, Math.max(minimum, value));
}

function landmarkAt(
  landmarks: readonly HandLandmark[],
  index: number,
): HandLandmark {
  const landmark = landmarks[index];
  if (!landmark) {
    throw new RangeError(`Missing hand landmark at index ${index}.`);
  }
  return landmark;
}

function palmSize(landmarks: readonly HandLandmark[]): number {
  if (landmarks.length < 21) return 0;
  const vertical = distance(
    landmarkAt(landmarks, HAND.wrist),
    landmarkAt(landmarks, HAND.middleMcp),
  );
  const horizontal = distance(
    landmarkAt(landmarks, HAND.indexMcp),
    landmarkAt(landmarks, HAND.pinkyMcp),
  );
  return Math.max(0.0001, (vertical + horizontal) / 2);
}

function wholeHandCenter(landmarks: readonly HandLandmark[]): Point {
  const indices = [
    HAND.wrist,
    HAND.thumbMcp,
    HAND.indexMcp,
    HAND.middleMcp,
    HAND.ringMcp,
    HAND.pinkyMcp,
  ];
  const points = indices.map((index) => landmarkAt(landmarks, index));
  return {
    x: points.reduce((sum, point) => sum + point.x, 0) / points.length,
    y: points.reduce((sum, point) => sum + point.y, 0) / points.length,
  };
}

function angleDegrees(a: Point, vertex: Point, c: Point): number {
  const ab = { x: a.x - vertex.x, y: a.y - vertex.y };
  const cb = { x: c.x - vertex.x, y: c.y - vertex.y };
  const denominator = Math.hypot(ab.x, ab.y) * Math.hypot(cb.x, cb.y);
  if (denominator <= Number.EPSILON) return 0;
  const cosine = clamp((ab.x * cb.x + ab.y * cb.y) / denominator, -1, 1);
  return (Math.acos(cosine) * 180) / Math.PI;
}

function isFingerExtended(
  landmarks: readonly HandLandmark[],
  finger: Finger,
): boolean {
  const size = palmSize(landmarks);
  const pipAngle = angleDegrees(
    landmarkAt(landmarks, finger.mcp),
    landmarkAt(landmarks, finger.pip),
    landmarkAt(landmarks, finger.tip),
  );
  const dipAngle = angleDegrees(
    landmarkAt(landmarks, finger.pip),
    landmarkAt(landmarks, finger.dip),
    landmarkAt(landmarks, finger.tip),
  );
  const reach =
    distance(
      landmarkAt(landmarks, finger.tip),
      landmarkAt(landmarks, HAND.wrist),
    ) -
    distance(
      landmarkAt(landmarks, finger.pip),
      landmarkAt(landmarks, HAND.wrist),
    );
  return pipAngle >= 145 && dipAngle >= 135 && reach >= size * 0.16;
}

function isThumbExtended(landmarks: readonly HandLandmark[]): boolean {
  const size = palmSize(landmarks);
  const reach =
    distance(
      landmarkAt(landmarks, HAND.thumbTip),
      landmarkAt(landmarks, HAND.indexMcp),
    ) -
    distance(
      landmarkAt(landmarks, HAND.thumbIp),
      landmarkAt(landmarks, HAND.indexMcp),
    );
  const angle = angleDegrees(
    landmarkAt(landmarks, HAND.thumbMcp),
    landmarkAt(landmarks, HAND.thumbIp),
    landmarkAt(landmarks, HAND.thumbTip),
  );
  return reach >= size * 0.12 && angle >= 135;
}

function exactFingerPattern(
  extended: Record<keyof typeof FINGERS, boolean>,
  expected: readonly (keyof typeof FINGERS)[],
): boolean {
  const expectedSet = new Set(expected);
  return (Object.keys(FINGERS) as Array<keyof typeof FINGERS>).every(
    (finger) => extended[finger] === expectedSet.has(finger),
  );
}

export type PoseRecognition = {
  gesture: SignalGestureId | null;
  confidence: number;
  pointerPose: boolean;
};

/**
 * The browser fallback's deterministic nine-pose recognizer, migrated without
 * learned or remote classification.
 */
export function recognizeHandPose(
  landmarks: readonly HandLandmark[],
): PoseRecognition {
  if (landmarks.length < 21 || palmSize(landmarks) < 0.01) {
    return { gesture: null, confidence: 0, pointerPose: false };
  }

  const extended = {
    index: isFingerExtended(landmarks, FINGERS.index),
    middle: isFingerExtended(landmarks, FINGERS.middle),
    ring: isFingerExtended(landmarks, FINGERS.ring),
    pinky: isFingerExtended(landmarks, FINGERS.pinky),
  };
  const thumbExtended = isThumbExtended(landmarks);
  const noneExtended = exactFingerPattern(extended, []);
  const onlyIndex = exactFingerPattern(extended, ["index"]);
  const size = palmSize(landmarks);
  const thumbTip = landmarkAt(landmarks, HAND.thumbTip);
  const wrist = landmarkAt(landmarks, HAND.wrist);
  const thumbVertical = (wrist.y - thumbTip.y) / size;
  const thumbHorizontal = Math.abs(wrist.x - thumbTip.x) / size;

  let gesture: SignalGestureId | null = null;
  let matchedFeatures = 0;
  if (
    noneExtended &&
    thumbExtended &&
    thumbVertical > 0.42 &&
    thumbVertical > thumbHorizontal * 1.12
  ) {
    gesture = "thumbs_up";
    matchedFeatures = 5;
  } else if (
    noneExtended &&
    thumbExtended &&
    thumbVertical < -0.34 &&
    -thumbVertical > thumbHorizontal * 1.05
  ) {
    gesture = "thumbs_down";
    matchedFeatures = 5;
  } else if (
    exactFingerPattern(extended, ["index", "middle", "ring", "pinky"]) &&
    thumbExtended
  ) {
    gesture = "five";
    matchedFeatures = 5;
  } else if (
    exactFingerPattern(extended, ["index", "middle", "ring", "pinky"])
  ) {
    gesture = "four";
    matchedFeatures = 4;
  } else if (exactFingerPattern(extended, ["index", "middle", "ring"])) {
    gesture = "three";
    matchedFeatures = 4;
  } else if (exactFingerPattern(extended, ["index", "middle"])) {
    gesture = "two";
    matchedFeatures = 4;
  } else if (onlyIndex) {
    gesture = "one";
    matchedFeatures = 4;
  } else if (noneExtended) {
    const thumbIndexGap =
      distance(
        landmarkAt(landmarks, HAND.thumbTip),
        landmarkAt(landmarks, HAND.indexTip),
      ) / size;
    const thumbMiddleGap =
      distance(
        landmarkAt(landmarks, HAND.thumbTip),
        landmarkAt(landmarks, HAND.middleTip),
      ) / size;
    const isOpenC =
      !thumbExtended &&
      thumbIndexGap >= 0.42 &&
      thumbIndexGap <= 1.25 &&
      thumbMiddleGap >= 0.42;
    gesture = isOpenC ? "c_shape" : "fist";
    matchedFeatures = isOpenC ? 4 : 5;
  }

  return {
    gesture,
    confidence:
      gesture === null
        ? 0
        : Math.min(0.99, 0.55 + (matchedFeatures / 5) * 0.4),
    pointerPose: onlyIndex,
  };
}

/**
 * Turns mirrored landmarks into transport-safe gesture and relative motion
 * data. Pointer anchors and pinch transactions live here so they can be reset
 * atomically when tracking is lost, paused, or stopped.
 */
export class TrackingNormalizer {
  private readonly pinchCloseRatio: number;
  private readonly pinchOpenRatio: number;
  private readonly pinchIntentHoldMs: number;
  private readonly pinchIntentDistance: number;
  private readonly dominantAxisRatio: number;
  private readonly pointerDeadZone: number;
  private readonly pointerSmoothing: number;
  private readonly pointerMaximumDelta: number;
  private pointerAnchor: Point | null = null;
  private smoothedPointerDelta = { dx: 0, dy: 0 };
  private pinchClosed = false;
  private pinchState: PinchTransactionState = "idle";
  private pinchStartedAt = 0;
  private pinchStartCenter: Point | null = null;
  private previousPinchCenter: Point | null = null;

  constructor(options: TrackingNormalizerOptions = {}) {
    this.pinchCloseRatio = options.pinchCloseRatio ?? 0.32;
    this.pinchOpenRatio = options.pinchOpenRatio ?? 0.46;
    this.pinchIntentHoldMs = options.pinchIntentHoldMs ?? 110;
    this.pinchIntentDistance = options.pinchIntentDistance ?? 0.13;
    this.dominantAxisRatio = options.dominantAxisRatio ?? 1.22;
    this.pointerDeadZone = options.pointerDeadZone ?? 0.015;
    this.pointerSmoothing = options.pointerSmoothing ?? 0.34;
    this.pointerMaximumDelta = options.pointerMaximumDelta ?? 0.42;
  }

  reset(): void {
    this.pointerAnchor = null;
    this.smoothedPointerDelta = { dx: 0, dy: 0 };
    this.pinchClosed = false;
    this.pinchState = "idle";
    this.pinchStartedAt = 0;
    this.pinchStartCenter = null;
    this.previousPinchCenter = null;
  }

  analyze(
    rawLandmarks: readonly NormalizedLandmark[] | readonly HandLandmark[],
    timestamp: number,
    handednessConfidence = 0,
  ): TrackingAnalysis | null {
    if (rawLandmarks.length !== 21) {
      this.reset();
      return null;
    }

    const landmarks = rawLandmarks.map((landmark) => ({
      x: 1 - landmark.x,
      y: landmark.y,
      z: landmark.z ?? 0,
      ...("visibility" in landmark
        ? { visibility: landmark.visibility }
        : {}),
    }));
    const pose = recognizeHandPose(landmarks);
    const size = palmSize(landmarks);
    const whole = wholeHandCenter(landmarks);
    const pinchRatio =
      distance(
        landmarkAt(landmarks, HAND.thumbTip),
        landmarkAt(landmarks, HAND.indexTip),
      ) / size;

    if (this.pinchClosed) {
      if (pinchRatio >= this.pinchOpenRatio) this.pinchClosed = false;
    } else if (pinchRatio <= this.pinchCloseRatio) {
      this.pinchClosed = true;
    }

    let deltaX: number | undefined;
    let deltaY: number | undefined;
    if (this.pinchState === "idle" && this.pinchClosed) {
      this.pinchState = "pending";
      this.pinchStartedAt = timestamp;
      this.pinchStartCenter = whole;
      this.previousPinchCenter = whole;
      this.pointerAnchor = null;
      this.smoothedPointerDelta = { dx: 0, dy: 0 };
    } else if (this.pinchState !== "idle" && !this.pinchClosed) {
      this.pinchState = "idle";
      this.pinchStartCenter = null;
      this.previousPinchCenter = null;
    } else if (this.pinchState === "pending" && this.pinchClosed) {
      const start = this.pinchStartCenter ?? whole;
      const dx = (whole.x - start.x) / size;
      const dy = (whole.y - start.y) / size;
      const heldMs = timestamp - this.pinchStartedAt;
      if (
        heldMs >= this.pinchIntentHoldMs &&
        Math.hypot(dx, dy) >= this.pinchIntentDistance
      ) {
        if (Math.abs(dy) >= Math.abs(dx) * this.dominantAxisRatio) {
          this.pinchState = "scrolling";
        } else if (Math.abs(dx) >= Math.abs(dy) * this.dominantAxisRatio) {
          this.pinchState = "zooming";
        }
        this.previousPinchCenter = whole;
      }
    } else if (
      (this.pinchState === "scrolling" ||
        this.pinchState === "zooming") &&
      this.pinchClosed
    ) {
      const previous = this.previousPinchCenter ?? whole;
      deltaX =
        ((whole.x - previous.x) / size) *
        PINCH_DELTA_REFERENCE_PIXELS;
      deltaY =
        ((whole.y - previous.y) / size) *
        PINCH_DELTA_REFERENCE_PIXELS;
      this.previousPinchCenter = whole;
    }

    let pointerDelta: TrackingAnalysis["pointerDelta"];
    if (pose.pointerPose && this.pinchState === "idle") {
      const pointer = landmarkAt(landmarks, HAND.indexTip);
      if (this.pointerAnchor) {
        const rawDx = (pointer.x - this.pointerAnchor.x) / size;
        const rawDy = (pointer.y - this.pointerAnchor.y) / size;
        const nextDx =
          Math.abs(rawDx) < this.pointerDeadZone ? 0 : rawDx;
        const nextDy =
          Math.abs(rawDy) < this.pointerDeadZone ? 0 : rawDy;
        this.smoothedPointerDelta.dx =
          this.smoothedPointerDelta.dx * (1 - this.pointerSmoothing) +
          nextDx * this.pointerSmoothing;
        this.smoothedPointerDelta.dy =
          this.smoothedPointerDelta.dy * (1 - this.pointerSmoothing) +
          nextDy * this.pointerSmoothing;
        pointerDelta = {
          // Landmarks are mirrored for presentation and deterministic pose
          // parity with the web fallback. Transport raw horizontal motion;
          // the per-page virtual cursor applies the user's mirror setting.
          dx: clamp(
            -this.smoothedPointerDelta.dx,
            -this.pointerMaximumDelta,
            this.pointerMaximumDelta,
          ),
          dy: clamp(
            this.smoothedPointerDelta.dy,
            -this.pointerMaximumDelta,
            this.pointerMaximumDelta,
          ),
          normalized: true,
        };
      }
      this.pointerAnchor = { x: pointer.x, y: pointer.y };
    } else {
      this.pointerAnchor = null;
      this.smoothedPointerDelta = { dx: 0, dy: 0 };
    }

    return {
      landmarks,
      gesture:
        this.pinchClosed
          ? "pinch"
          : pose.pointerPose
            ? "pointer"
            : (pose.gesture ?? "unknown"),
      ...(pose.gesture ? { commandGesture: pose.gesture } : {}),
      confidence: Math.max(pose.confidence, handednessConfidence),
      ...(pointerDelta ? { pointerDelta } : {}),
      pinch: {
        closed: this.pinchClosed,
        transactionState: this.pinchState,
        ...(deltaX === undefined ? {} : { deltaX }),
        ...(deltaY === undefined ? {} : { deltaY }),
      },
    };
  }
}

export class MediaPipeRuntime {
  private landmarker: HandLandmarker | null = null;
  private lifecycleGeneration = 0;
  private startPromise: Promise<void> | null = null;

  async start(): Promise<void> {
    if (this.landmarker) return;
    if (this.startPromise) return this.startPromise;
    const generation = ++this.lifecycleGeneration;
    const startPromise = this.createLandmarker(generation);
    this.startPromise = startPromise;
    try {
      await startPromise;
    } finally {
      if (this.startPromise === startPromise) this.startPromise = null;
    }
  }

  private async createLandmarker(generation: number): Promise<void> {
    const { FilesetResolver, HandLandmarker: HandLandmarkerTask } =
      await import("@mediapipe/tasks-vision");
    const assetUrl = (path: string) => chrome.runtime.getURL(path);
    const fileset = await FilesetResolver.forVisionTasks(
      assetUrl(HAND_LANDMARKER_WASM_PATH),
    );
    const commonOptions = {
      baseOptions: {
        modelAssetPath: assetUrl(HAND_LANDMARKER_MODEL_PATH),
        delegate: "GPU" as const,
      },
      runningMode: "VIDEO" as const,
      numHands: 1,
      minHandDetectionConfidence: 0.55,
      minHandPresenceConfidence: 0.55,
      minTrackingConfidence: 0.5,
    };
    let landmarker: HandLandmarker;
    try {
      landmarker = await HandLandmarkerTask.createFromOptions(
        fileset,
        commonOptions,
      );
    } catch {
      landmarker = await HandLandmarkerTask.createFromOptions(fileset, {
        ...commonOptions,
        baseOptions: {
          modelAssetPath: assetUrl(HAND_LANDMARKER_MODEL_PATH),
          delegate: "CPU",
        },
      });
    }
    if (generation !== this.lifecycleGeneration) {
      landmarker.close();
      return;
    }
    this.landmarker = landmarker;
  }

  detect(
    video: HTMLVideoElement,
    timestamp: number,
  ): HandLandmarkerResult {
    if (!this.landmarker) {
      throw new Error("MediaPipe has not been initialized.");
    }
    return this.landmarker.detectForVideo(video, timestamp);
  }

  stop(): void {
    this.lifecycleGeneration += 1;
    this.startPromise = null;
    this.landmarker?.close();
    this.landmarker = null;
  }
}
