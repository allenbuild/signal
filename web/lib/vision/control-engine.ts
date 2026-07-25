import {
  clamp,
  HAND,
  normalizedPinchDistance,
  pinchCenter,
  wholeHandCenter,
  type HandLandmark,
  type Point2D,
} from "./hand-geometry";

export type PinchTransactionState =
  | "idle"
  | "pinchPending"
  | "scrolling"
  | "zooming"
  | "awaitingRelease";

export type ControlEffect =
  | { type: "click"; x: number; y: number }
  | { type: "scroll"; x: number; y: number; deltaY: number }
  | { type: "zoom"; x: number; y: number; delta: number };

export type ControlSnapshot = {
  cursor: { x: number; y: number; visible: boolean };
  transaction: PinchTransactionState;
  pinchClosed: boolean;
  effects: ControlEffect[];
};

export type ControlFrame = {
  landmarks: readonly HandLandmark[];
  pointerPose: boolean;
  timestamp: number;
};

export type ControlEngineOptions = {
  width: number;
  height: number;
  sensitivity?: number;
  smoothing?: number;
  deadZonePx?: number;
  pinchCloseRatio?: number;
  pinchOpenRatio?: number;
  intentHoldMs?: number;
  clickMaxMs?: number;
  clickMovementPx?: number;
  intentMovementPx?: number;
  dominantAxisRatio?: number;
};

const CURSOR_RADIUS_PX = 15;

export class ControlEngine {
  private width: number;
  private height: number;
  private readonly sensitivity: number;
  private readonly smoothing: number;
  private readonly deadZonePx: number;
  private readonly pinchCloseRatio: number;
  private readonly pinchOpenRatio: number;
  private readonly intentHoldMs: number;
  private readonly clickMaxMs: number;
  private readonly clickMovementPx: number;
  private readonly intentMovementPx: number;
  private readonly dominantAxisRatio: number;
  private cursor: { x: number; y: number; visible: boolean };
  private transaction: PinchTransactionState = "idle";
  private pinchClosed = false;
  private pointerAnchor: Point2D | null = null;
  private smoothedDelta = { x: 0, y: 0 };
  private pinchStartedAt = 0;
  private pinchStartCenter: Point2D | null = null;
  private pinchStartWhole: Point2D | null = null;
  private previousWhole: Point2D | null = null;

  constructor(options: ControlEngineOptions) {
    this.width = options.width;
    this.height = options.height;
    this.sensitivity = options.sensitivity ?? 1.35;
    this.smoothing = options.smoothing ?? 0.34;
    this.deadZonePx = options.deadZonePx ?? 1.8;
    this.pinchCloseRatio = options.pinchCloseRatio ?? 0.32;
    this.pinchOpenRatio = options.pinchOpenRatio ?? 0.46;
    this.intentHoldMs = options.intentHoldMs ?? 110;
    this.clickMaxMs = options.clickMaxMs ?? 420;
    this.clickMovementPx = options.clickMovementPx ?? 14;
    this.intentMovementPx = options.intentMovementPx ?? 18;
    this.dominantAxisRatio = options.dominantAxisRatio ?? 1.22;
    this.cursor = {
      x: options.width / 2,
      y: options.height / 2,
      visible: false,
    };
  }

  resize(width: number, height: number) {
    this.width = width;
    this.height = height;
    this.cursor.x = clamp(
      this.cursor.x,
      CURSOR_RADIUS_PX,
      Math.max(CURSOR_RADIUS_PX, width - CURSOR_RADIUS_PX),
    );
    this.cursor.y = clamp(
      this.cursor.y,
      CURSOR_RADIUS_PX,
      Math.max(CURSOR_RADIUS_PX, height - CURSOR_RADIUS_PX),
    );
  }

  reset(): ControlSnapshot {
    this.transaction = "idle";
    this.pinchClosed = false;
    this.pointerAnchor = null;
    this.smoothedDelta = { x: 0, y: 0 };
    this.pinchStartCenter = null;
    this.pinchStartWhole = null;
    this.previousWhole = null;
    this.cursor.visible = false;
    return this.snapshot([]);
  }

  update(frame: ControlFrame | null): ControlSnapshot {
    if (!frame || frame.landmarks.length < 21) return this.reset();

    const effects: ControlEffect[] = [];
    const landmarks = frame.landmarks;
    const whole = wholeHandCenter(landmarks);
    const center = pinchCenter(landmarks);
    const pinchRatio = normalizedPinchDistance(landmarks);

    if (this.pinchClosed) {
      if (pinchRatio >= this.pinchOpenRatio) this.pinchClosed = false;
    } else if (pinchRatio <= this.pinchCloseRatio) {
      this.pinchClosed = true;
    }

    if (this.transaction === "awaitingRelease") {
      if (!this.pinchClosed) this.transaction = "idle";
      this.pointerAnchor = null;
      this.cursor.visible = true;
      return this.snapshot(effects);
    }

    if (this.transaction === "idle" && this.pinchClosed) {
      this.transaction = "pinchPending";
      this.pinchStartedAt = frame.timestamp;
      this.pinchStartCenter = center;
      this.pinchStartWhole = whole;
      this.previousWhole = whole;
      this.pointerAnchor = null;
      this.smoothedDelta = { x: 0, y: 0 };
    }

    if (this.transaction === "pinchPending") {
      const start = this.pinchStartWhole ?? whole;
      const dx = (whole.x - start.x) * this.width;
      const dy = (whole.y - start.y) * this.height;
      const movement = Math.hypot(dx, dy);
      const heldMs = frame.timestamp - this.pinchStartedAt;

      if (!this.pinchClosed) {
        if (
          heldMs <= this.clickMaxMs &&
          movement <= this.clickMovementPx &&
          this.pinchStartCenter
        ) {
          effects.push({
            type: "click",
            x: this.cursor.x,
            y: this.cursor.y,
          });
        }
        this.transaction = "awaitingRelease";
      } else if (
        heldMs >= this.intentHoldMs &&
        movement >= this.intentMovementPx
      ) {
        if (Math.abs(dy) >= Math.abs(dx) * this.dominantAxisRatio) {
          this.transaction = "scrolling";
        } else if (Math.abs(dx) >= Math.abs(dy) * this.dominantAxisRatio) {
          this.transaction = "zooming";
        }
        this.previousWhole = whole;
      }
    } else if (this.transaction === "scrolling") {
      if (!this.pinchClosed) {
        this.transaction = "awaitingRelease";
      } else {
        const previous = this.previousWhole ?? whole;
        const deltaY = (whole.y - previous.y) * this.height * 2.2;
        if (Math.abs(deltaY) >= 0.5) {
          effects.push({
            type: "scroll",
            x: this.cursor.x,
            y: this.cursor.y,
            deltaY,
          });
        }
        this.previousWhole = whole;
      }
    } else if (this.transaction === "zooming") {
      if (!this.pinchClosed) {
        this.transaction = "awaitingRelease";
      } else {
        const previous = this.previousWhole ?? whole;
        const deltaX = (whole.x - previous.x) * this.width;
        if (Math.abs(deltaX) >= 0.5) {
          effects.push({
            type: "zoom",
            x: this.cursor.x,
            y: this.cursor.y,
            delta: deltaX / 280,
          });
        }
        this.previousWhole = whole;
      }
    }

    const pointerFrozen =
      this.transaction !== "idle" || this.pinchClosed;
    if (!pointerFrozen && frame.pointerPose) {
      const index = landmarks[HAND.indexTip];
      if (!this.pointerAnchor) {
        this.pointerAnchor = { x: index.x, y: index.y };
        this.smoothedDelta = { x: 0, y: 0 };
      } else {
        const rawX =
          (index.x - this.pointerAnchor.x) * this.width * this.sensitivity;
        const rawY =
          (index.y - this.pointerAnchor.y) * this.height * this.sensitivity;
        this.pointerAnchor = { x: index.x, y: index.y };
        const speed = Math.hypot(rawX, rawY);
        const acceleration = 1 + Math.min(1.1, speed / 34);
        const adjustedX =
          Math.abs(rawX) < this.deadZonePx ? 0 : rawX * acceleration;
        const adjustedY =
          Math.abs(rawY) < this.deadZonePx ? 0 : rawY * acceleration;
        this.smoothedDelta.x =
          this.smoothedDelta.x * (1 - this.smoothing) +
          adjustedX * this.smoothing;
        this.smoothedDelta.y =
          this.smoothedDelta.y * (1 - this.smoothing) +
          adjustedY * this.smoothing;
        this.cursor.x = clamp(
          this.cursor.x + this.smoothedDelta.x,
          CURSOR_RADIUS_PX,
          Math.max(CURSOR_RADIUS_PX, this.width - CURSOR_RADIUS_PX),
        );
        this.cursor.y = clamp(
          this.cursor.y + this.smoothedDelta.y,
          CURSOR_RADIUS_PX,
          Math.max(CURSOR_RADIUS_PX, this.height - CURSOR_RADIUS_PX),
        );
      }
      this.cursor.visible = true;
    } else if (!frame.pointerPose && this.transaction === "idle") {
      this.pointerAnchor = null;
      this.smoothedDelta = { x: 0, y: 0 };
      this.cursor.visible = true;
    } else {
      this.cursor.visible = true;
    }

    return this.snapshot(effects);
  }

  private snapshot(effects: ControlEffect[]): ControlSnapshot {
    return {
      cursor: { ...this.cursor },
      transaction: this.transaction,
      pinchClosed: this.pinchClosed,
      effects,
    };
  }
}
