import { nearestScrollableElement } from "./page-capabilities";

export interface ScrollTuning {
  naturalInversion: boolean;
  smoothing: number;
  pixelsPerUnit: number;
  maxStep: number;
  minIntervalMs: number;
}

const DEFAULT_SCROLL_TUNING: ScrollTuning = {
  naturalInversion: false,
  smoothing: 0.42,
  pixelsPerUnit: 1,
  maxStep: 96,
  minIntervalMs: 12,
};

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

export class ScrollController {
  private target: HTMLElement | Element | null = null;
  private smoothedDelta = 0;
  private pendingDelta = 0;
  private lastAppliedAt = Number.NEGATIVE_INFINITY;

  constructor(
    private readonly documentRef: Document = document,
    private readonly tuning: ScrollTuning = DEFAULT_SCROLL_TUNING,
  ) {}

  lockAt(x: number, y: number): void {
    this.target = nearestScrollableElement(this.documentRef, x, y);
    this.smoothedDelta = 0;
    this.pendingDelta = 0;
    this.lastAppliedAt = Number.NEGATIVE_INFINITY;
  }

  applyDelta(deltaY: number, timestamp: number): number {
    if (!this.target) return 0;

    const direction = this.tuning.naturalInversion ? -1 : 1;
    this.pendingDelta += deltaY * this.tuning.pixelsPerUnit * direction;
    if (timestamp - this.lastAppliedAt < this.tuning.minIntervalMs) return 0;

    const smoothing = clamp(this.tuning.smoothing, 0.01, 1);
    this.smoothedDelta +=
      (this.pendingDelta - this.smoothedDelta) * smoothing;
    this.pendingDelta = 0;
    const step = clamp(
      this.smoothedDelta,
      -this.tuning.maxStep,
      this.tuning.maxStep,
    );
    this.lastAppliedAt = timestamp;

    const scrollTarget = this.target as HTMLElement & {
      scrollBy?: (options: ScrollToOptions) => void;
    };
    if (typeof scrollTarget.scrollBy === "function") {
      scrollTarget.scrollBy({ top: step, left: 0, behavior: "auto" });
    } else if ("scrollTop" in scrollTarget) {
      scrollTarget.scrollTop += step;
    }
    return step;
  }

  reset(): void {
    this.target = null;
    this.smoothedDelta = 0;
    this.pendingDelta = 0;
    this.lastAppliedAt = Number.NEGATIVE_INFINITY;
  }
}
