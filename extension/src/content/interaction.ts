import { ClickController, type ClickResult } from "./click";
import {
  createSignalOverlay,
  type CursorPosition,
  type SignalOverlay,
} from "./overlay";
import { ScrollController } from "./scroll";
import type {
  InteractionResetMessage,
  ZoomRequestMessage,
} from "../shared/messages";
import type {
  PinchTransactionState,
  SignalMode,
} from "../shared/types";

export type { PinchTransactionState, SignalMode };

export interface PointerDelta {
  dx: number;
  dy: number;
  normalized?: boolean;
}

export interface PinchFrame {
  closed: boolean;
  transactionState?: PinchTransactionState;
  deltaX?: number;
  deltaY?: number;
}

export interface TrackingFrame {
  timestamp: number;
  gesture:
    | "pointer"
    | "pinch"
    | "unknown"
    | "one"
    | "two"
    | "three"
    | "four"
    | "five"
    | "thumbs-up"
    | "thumbs-down"
    | "c"
    | "fist"
    | string;
  confidence: number;
  pointerDelta?: PointerDelta;
  palmWidth?: number;
  pinch?: PinchFrame;
}

export interface CursorTuning {
  sensitivity: number;
  acceleration: number;
  smoothing: number;
  deadZone: number;
  maxDelta: number;
  mirrorHorizontal: boolean;
  hideNativeCursor: boolean;
}

export interface InteractionTuning {
  cursor: CursorTuning;
  transactionThreshold: number;
  dominanceRatio: number;
  zoomPixelsPerStep: number;
  zoomStep: number;
  minZoom: number;
  maxZoom: number;
  zoomRateLimitMs: number;
  minimumConfidence: number;
}

export type ContentRuntimeMessage =
  | ZoomRequestMessage
  | InteractionResetMessage;

export type MessageSender = (
  message: ContentRuntimeMessage,
) => void | Promise<unknown>;

const DEFAULT_TUNING: InteractionTuning = {
  cursor: {
    sensitivity: 1.05,
    acceleration: 1.25,
    smoothing: 0.38,
    deadZone: 0.012,
    maxDelta: 72,
    mirrorHorizontal: true,
    hideNativeCursor: false,
  },
  transactionThreshold: 13,
  dominanceRatio: 1.15,
  zoomPixelsPerStep: 36,
  zoomStep: 0.1,
  minZoom: 0.25,
  maxZoom: 5,
  zoomRateLimitMs: 80,
  minimumConfidence: 0.25,
};

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function accelerated(value: number, exponent: number): number {
  return Math.sign(value) * Math.pow(Math.abs(value), exponent);
}

export class VirtualCursor {
  private anchored = false;
  private smoothedX = 0;
  private smoothedY = 0;
  private cursorPosition: CursorPosition;
  private tuning: CursorTuning;

  constructor(
    private readonly overlay: SignalOverlay,
    tuning: CursorTuning = DEFAULT_TUNING.cursor,
    private readonly viewport: () => { width: number; height: number } = () => ({
      width: window.innerWidth,
      height: window.innerHeight,
    }),
  ) {
    this.tuning = { ...tuning };
    const size = viewport();
    this.cursorPosition = { x: size.width / 2, y: size.height / 2 };
  }

  get position(): CursorPosition {
    return { ...this.cursorPosition };
  }

  updateTuning(
    tuning: Partial<
      Pick<CursorTuning, "sensitivity" | "smoothing" | "hideNativeCursor">
    >,
  ): void {
    this.tuning = {
      ...this.tuning,
      ...(Number.isFinite(tuning.sensitivity)
        ? { sensitivity: clamp(tuning.sensitivity as number, 0.2, 4) }
        : {}),
      ...(Number.isFinite(tuning.smoothing)
        ? { smoothing: clamp(tuning.smoothing as number, 0.05, 1) }
        : {}),
      ...(typeof tuning.hideNativeCursor === "boolean"
        ? { hideNativeCursor: tuning.hideNativeCursor }
        : {}),
    };
  }

  process(delta: PointerDelta, palmWidth = 1): CursorPosition {
    if (!this.anchored) {
      this.anchored = true;
      this.smoothedX = 0;
      this.smoothedY = 0;
      this.overlay.setCursor(this.cursorPosition, true);
      return this.position;
    }

    const { width, height } = this.viewport();
    const scale = Math.max(1, Math.min(width, height));
    const denominator = delta.normalized
      ? 1
      : Math.max(Math.abs(palmWidth), 0.03);
    let dx = delta.dx / denominator;
    let dy = delta.dy / denominator;
    if (this.tuning.mirrorHorizontal) dx *= -1;

    dx = Math.abs(dx) <= this.tuning.deadZone ? 0 : dx;
    dy = Math.abs(dy) <= this.tuning.deadZone ? 0 : dy;
    const requestedX =
      accelerated(dx, this.tuning.acceleration) *
      scale *
      this.tuning.sensitivity;
    const requestedY =
      accelerated(dy, this.tuning.acceleration) *
      scale *
      this.tuning.sensitivity;

    const smoothing = clamp(this.tuning.smoothing, 0.01, 1);
    this.smoothedX += (requestedX - this.smoothedX) * smoothing;
    this.smoothedY += (requestedY - this.smoothedY) * smoothing;
    const movementX = clamp(
      this.smoothedX,
      -this.tuning.maxDelta,
      this.tuning.maxDelta,
    );
    const movementY = clamp(
      this.smoothedY,
      -this.tuning.maxDelta,
      this.tuning.maxDelta,
    );
    const edgeX = Math.min(12, width / 2);
    const edgeY = Math.min(12, height / 2);

    this.cursorPosition = {
      x: clamp(
        this.cursorPosition.x + movementX,
        edgeX,
        Math.max(edgeX, width - edgeX),
      ),
      y: clamp(
        this.cursorPosition.y + movementY,
        edgeY,
        Math.max(edgeY, height - edgeY),
      ),
    };
    this.overlay.setCursor(this.cursorPosition, true);
    return this.position;
  }

  loseAnchor(hide = false): void {
    this.anchored = false;
    this.smoothedX = 0;
    this.smoothedY = 0;
    if (hide) this.overlay.setCursorVisible(false);
  }

  reset(center = true): void {
    this.loseAnchor(true);
    if (center) {
      const { width, height } = this.viewport();
      this.cursorPosition = { x: width / 2, y: height / 2 };
    }
  }
}

export class InteractionController {
  readonly cursor: VirtualCursor;
  private readonly click: ClickController;
  private readonly scroll: ScrollController;
  private mode: SignalMode = "control";
  private pendingMode: SignalMode | null = null;
  private transaction: PinchTransactionState = "idle";
  private accumulatedX = 0;
  private accumulatedY = 0;
  private zoomFactor = 1;
  private zoomPendingX = 0;
  private lastZoomAt = Number.NEGATIVE_INFINITY;
  private lastFrameTimestamp = Number.NEGATIVE_INFINITY;
  private resetGeneration = 0;
  private hideNativeCursor: boolean;

  constructor(
    private readonly documentRef: Document = document,
    private readonly overlay = createSignalOverlay(documentRef),
    private readonly sendMessage: MessageSender = (message) =>
      (
        globalThis as typeof globalThis & {
          chrome?: {
            runtime?: {
              sendMessage?: (message: unknown) => unknown;
            };
          };
        }
      ).chrome?.runtime?.sendMessage?.(message),
    private readonly tuning: InteractionTuning = DEFAULT_TUNING,
    viewport?: () => { width: number; height: number },
  ) {
    this.hideNativeCursor = tuning.cursor.hideNativeCursor;
    this.cursor = new VirtualCursor(
      overlay,
      tuning.cursor,
      viewport,
    );
    this.click = new ClickController(documentRef);
    this.scroll = new ScrollController(documentRef);
  }

  get currentMode(): SignalMode {
    return this.mode;
  }

  get transactionState(): PinchTransactionState {
    return this.transaction;
  }

  updatePointerTuning(tuning: {
    sensitivity: number;
    smoothing: number;
    hideSiteCursor: boolean;
  }): void {
    this.cursor.updateTuning({
      sensitivity: tuning.sensitivity,
      smoothing: tuning.smoothing,
      hideNativeCursor: tuning.hideSiteCursor,
    });
    this.hideNativeCursor = tuning.hideSiteCursor;
    this.overlay.setNativeCursorHidden(
      this.mode === "control" && tuning.hideSiteCursor,
    );
  }

  setMode(nextMode: SignalMode): boolean {
    if (nextMode === "paused") {
      this.mode = nextMode;
      this.pendingMode = null;
      this.reset("paused", false);
      this.overlay.showStatus("Signal paused");
      return true;
    }

    if (this.transaction !== "idle") {
      this.pendingMode = nextMode;
      return false;
    }

    this.mode = nextMode;
    this.cursor.loseAnchor(nextMode !== "control");
    this.overlay.setNativeCursorHidden(
      nextMode === "control" && this.hideNativeCursor,
    );
    this.overlay.showStatus(
      nextMode === "control" ? "Signal Control" : "Signal Commands",
      "active",
    );
    return true;
  }

  setZoomFactor(factor: number): void {
    if (Number.isFinite(factor)) {
      this.zoomFactor = clamp(
        factor,
        this.tuning.minZoom,
        this.tuning.maxZoom,
      );
    }
  }

  handleTrackingFrame(frame: TrackingFrame): void {
    if (
      !Number.isFinite(frame.timestamp) ||
      frame.timestamp <= this.lastFrameTimestamp
    ) {
      return;
    }
    this.lastFrameTimestamp = frame.timestamp;

    if (
      frame.gesture === "unknown" ||
      frame.confidence < this.tuning.minimumConfidence
    ) {
      this.reset("tracking-loss");
      this.overlay.showStatus("Hand not detected", "warning");
      return;
    }

    if (this.mode !== "control") return;

    const pinchClosed = frame.pinch?.closed === true;
    if (pinchClosed) {
      this.handleClosedPinch(frame);
      return;
    }

    if (this.transaction !== "idle") {
      this.releasePinch();
    }

    if (frame.gesture === "pointer" && frame.pointerDelta) {
      this.cursor.process(frame.pointerDelta, frame.palmWidth);
      this.overlay.setNativeCursorHidden(
        this.hideNativeCursor,
      );
      this.overlay.showStatus("Signal Control", "active");
    } else {
      this.cursor.loseAnchor();
    }
  }

  private handleClosedPinch(frame: TrackingFrame): void {
    if (this.transaction === "idle") {
      this.transaction = "pending";
      this.accumulatedX = 0;
      this.accumulatedY = 0;
      this.overlay.clearIndicators();
    }

    this.accumulatedX += frame.pinch?.deltaX ?? 0;
    this.accumulatedY += frame.pinch?.deltaY ?? 0;

    const requestedState = frame.pinch?.transactionState;
    if (this.transaction === "pending") {
      if (requestedState === "scrolling") {
        this.lockScroll();
      } else if (requestedState === "zooming") {
        this.lockZoom();
      } else {
        const absX = Math.abs(this.accumulatedX);
        const absY = Math.abs(this.accumulatedY);
        if (
          absY >= this.tuning.transactionThreshold &&
          absY >= absX * this.tuning.dominanceRatio
        ) {
          this.lockScroll();
        } else if (
          absX >= this.tuning.transactionThreshold &&
          absX >= absY * this.tuning.dominanceRatio
        ) {
          this.lockZoom();
        }
      }
    }

    if (this.transaction === "scrolling") {
      const applied = this.scroll.applyDelta(
        frame.pinch?.deltaY ?? 0,
        frame.timestamp,
      );
      this.overlay.showScroll(applied || this.accumulatedY);
    } else if (this.transaction === "zooming") {
      this.applyZoomDelta(frame.pinch?.deltaX ?? 0, frame.timestamp);
    }
  }

  private lockScroll(): void {
    this.transaction = "scrolling";
    const position = this.cursor.position;
    this.scroll.lockAt(position.x, position.y);
  }

  private lockZoom(): void {
    this.transaction = "zooming";
    this.zoomPendingX = 0;
  }

  private applyZoomDelta(deltaX: number, timestamp: number): void {
    this.zoomPendingX += deltaX;
    if (
      timestamp - this.lastZoomAt < this.tuning.zoomRateLimitMs ||
      Math.abs(this.zoomPendingX) < 0.001
    ) {
      this.overlay.showZoom(this.zoomFactor * 100);
      return;
    }

    const steps = Math.trunc(
      this.zoomPendingX / this.tuning.zoomPixelsPerStep,
    );
    if (steps === 0) {
      this.overlay.showZoom(this.zoomFactor * 100);
      return;
    }
    const nextFactor = clamp(
      Math.round((this.zoomFactor + steps * this.tuning.zoomStep) * 100) / 100,
      this.tuning.minZoom,
      this.tuning.maxZoom,
    );
    if (nextFactor !== this.zoomFactor) {
      const delta =
        Math.round((nextFactor - this.zoomFactor) * 100) / 100;
      this.zoomFactor = nextFactor;
      this.zoomPendingX -= steps * this.tuning.zoomPixelsPerStep;
      this.lastZoomAt = timestamp;
      void this.sendMessage({
        version: 1,
        type: "signal:zoom-request",
        delta,
        timestamp,
      });
    }
    this.overlay.showZoom(this.zoomFactor * 100);
  }

  private releasePinch(): ClickResult | null {
    let result: ClickResult | null = null;
    if (this.transaction === "pending") {
      const position = this.cursor.position;
      result = this.click.clickAt(position.x, position.y);
      if (result.clicked) {
        this.overlay.showClick(position);
        this.overlay.showStatus("Clicked", "active");
      } else {
        this.overlay.showStatus(
          result.reason === "disabled"
            ? "That control is disabled"
            : "No page control beneath the Signal cursor",
          "warning",
        );
      }
    }

    this.scroll.reset();
    this.transaction = "idle";
    this.accumulatedX = 0;
    this.accumulatedY = 0;
    this.zoomPendingX = 0;
    this.overlay.clearIndicators();

    if (this.pendingMode) {
      const next = this.pendingMode;
      this.pendingMode = null;
      this.setMode(next);
    }
    return result;
  }

  reset(
    reason: string,
    notify = true,
    generation?: number,
  ): void {
    this.scroll.reset();
    this.transaction = "idle";
    this.accumulatedX = 0;
    this.accumulatedY = 0;
    this.pendingMode = null;
    this.zoomPendingX = 0;
    this.cursor.reset(reason !== "pose-loss");
    this.overlay.reset({ hideCursor: true });
    if (notify) {
      this.resetGeneration =
        generation ?? this.resetGeneration + 1;
      void this.sendMessage({
        version: 1,
        type: "signal:interaction-reset",
        generation: this.resetGeneration,
      });
    }
  }

  destroy(): void {
    this.reset("content-destroyed");
    this.overlay.destroy();
  }
}
