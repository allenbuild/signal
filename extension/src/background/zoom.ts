import type { ZoomStatusMessage } from "../shared/messages";

export const MIN_TAB_ZOOM = 0.25;
export const MAX_TAB_ZOOM = 5;

export type ZoomDependencies = {
  getZoom(tabId: number): Promise<number>;
  setZoom(tabId: number, factor: number): Promise<void>;
};

export type ZoomControllerOptions = {
  min?: number;
  max?: number;
  rateLimitMs?: number;
  deltaScale?: number;
};

const roundZoom = (value: number) => Math.round(value * 100) / 100;

export class TabZoomController {
  private readonly lastWriteAt = new Map<number, number>();
  private readonly lastFactor = new Map<number, number>();
  private readonly min: number;
  private readonly max: number;
  private readonly rateLimitMs: number;
  private readonly deltaScale: number;

  constructor(
    private readonly dependencies: ZoomDependencies,
    options: ZoomControllerOptions = {},
  ) {
    this.min = options.min ?? MIN_TAB_ZOOM;
    this.max = options.max ?? MAX_TAB_ZOOM;
    this.rateLimitMs = Math.max(0, options.rateLimitMs ?? 90);
    this.deltaScale = options.deltaScale ?? 0.0018;
  }

  clear(tabId?: number) {
    if (tabId === undefined) {
      this.lastWriteAt.clear();
      this.lastFactor.clear();
      return;
    }
    this.lastWriteAt.delete(tabId);
    this.lastFactor.delete(tabId);
  }

  async set(
    tabId: number,
    requestedFactor: number,
    timestamp = Date.now(),
  ): Promise<ZoomStatusMessage> {
    if (!Number.isFinite(requestedFactor)) {
      return this.failure("Invalid zoom request.");
    }
    const factor = roundZoom(
      Math.min(this.max, Math.max(this.min, requestedFactor)),
    );
    const previousWrite = this.lastWriteAt.get(tabId) ?? -Infinity;
    const previousFactor = this.lastFactor.get(tabId);
    if (
      previousFactor === factor ||
      timestamp - previousWrite < this.rateLimitMs
    ) {
      const current = previousFactor ?? factor;
      return this.success(current);
    }

    try {
      if (previousFactor === undefined) {
        const current = roundZoom(await this.dependencies.getZoom(tabId));
        this.lastFactor.set(tabId, current);
        if (current === factor) return this.success(current);
      }
      await this.dependencies.setZoom(tabId, factor);
      this.lastWriteAt.set(tabId, timestamp);
      this.lastFactor.set(tabId, factor);
      return this.success(factor);
    } catch {
      return this.failure("Signal cannot change zoom on this page.");
    }
  }

  async applyDelta(
    tabId: number,
    deltaX: number,
    timestamp = Date.now(),
  ): Promise<ZoomStatusMessage> {
    if (!Number.isFinite(deltaX)) return this.failure("Invalid zoom request.");
    const previousWrite = this.lastWriteAt.get(tabId) ?? -Infinity;
    if (timestamp - previousWrite < this.rateLimitMs) {
      const factor = this.lastFactor.get(tabId);
      return factor === undefined
        ? this.failure("Zoom update is rate limited.")
        : this.success(factor);
    }
    try {
      const current =
        this.lastFactor.get(tabId) ??
        roundZoom(await this.dependencies.getZoom(tabId));
      return this.set(tabId, current + deltaX * this.deltaScale, timestamp);
    } catch {
      return this.failure("Signal cannot change zoom on this page.");
    }
  }

  private success(factor: number): ZoomStatusMessage {
    return {
      version: 1,
      type: "signal:zoom-status",
      supported: true,
      factor,
      percentage: Math.round(factor * 100),
    };
  }

  private failure(error: string): ZoomStatusMessage {
    return {
      version: 1,
      type: "signal:zoom-status",
      supported: false,
      error,
    };
  }
}
