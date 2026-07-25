export type CameraQuality = "high" | "balanced" | "low";

export type CameraPhase =
  | "idle"
  | "requesting"
  | "initializing"
  | "live"
  | "paused"
  | "stopped"
  | "error";

export interface CameraMetrics {
  captureFps: number;
  processedFps: number;
  inferenceMs: number;
  droppedFrames: number;
}

export interface CameraSnapshot {
  phase: CameraPhase;
  message: string;
  metrics: CameraMetrics;
}

export interface VideoFrameResult {
  timestamp: number;
  captureTimestamp: number;
}

export interface VideoFrameProcessor<Result extends VideoFrameResult> {
  process(video: HTMLVideoElement, timestamp: number): Result | Promise<Result>;
  close(): void | Promise<void>;
}

export interface CameraSessionCallbacks<Result extends VideoFrameResult> {
  onSnapshot(snapshot: CameraSnapshot): void;
  onResult(result: Result): void;
  onError(error: CameraSessionError): void;
}

export class CameraSessionError extends Error {
  constructor(
    public readonly code:
      | "unsupported"
      | "permission-denied"
      | "not-found"
      | "camera-busy"
      | "disconnected"
      | "initialization-failed",
    message: string,
    options?: ErrorOptions,
  ) {
    super(message, options);
    this.name = "CameraSessionError";
  }
}

const QUALITY: Record<CameraQuality, MediaTrackConstraints> = {
  high: {
    facingMode: "user",
    width: { ideal: 640 },
    height: { ideal: 480 },
    frameRate: { ideal: 30, max: 30 },
  },
  balanced: {
    facingMode: "user",
    width: { ideal: 480 },
    height: { ideal: 360 },
    frameRate: { ideal: 24, max: 30 },
  },
  low: {
    facingMode: "user",
    width: { ideal: 320 },
    height: { ideal: 240 },
    frameRate: { ideal: 18, max: 24 },
  },
};

type VideoWithFrameCallback = HTMLVideoElement & {
  requestVideoFrameCallback?: (
    callback: (now: DOMHighResTimeStamp, metadata: { mediaTime: number }) => void,
  ) => number;
  cancelVideoFrameCallback?: (handle: number) => void;
};

export class CameraSession<Result extends VideoFrameResult> {
  private stream: MediaStream | null = null;
  private processor: VideoFrameProcessor<Result> | null = null;
  private frameHandle: number | null = null;
  private busy = false;
  private running = false;
  private hidden = false;
  private lastCaptureAt = 0;
  private lastProcessedAt = 0;
  private captureFps = 0;
  private processedFps = 0;
  private inferenceMs = 0;
  private droppedFrames = 0;
  private lastSnapshotAt = 0;

  constructor(
    private readonly video: VideoWithFrameCallback,
    private readonly createProcessor: () => Promise<VideoFrameProcessor<Result>>,
    private readonly callbacks: CameraSessionCallbacks<Result>,
    private readonly quality: CameraQuality = "balanced",
  ) {}

  async start(): Promise<void> {
    if (this.running) return;
    if (
      typeof navigator === "undefined"
      || !navigator.mediaDevices?.getUserMedia
      || typeof window === "undefined"
    ) {
      throw this.fail("unsupported", "This browser cannot access a webcam.");
    }
    this.emit("requesting", "Waiting for camera permission…");
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: QUALITY[this.quality],
        audio: false,
      });
    } catch (error) {
      throw this.mapMediaError(error);
    }
    const [track] = this.stream.getVideoTracks();
    if (!track) {
      this.stopTracks();
      throw this.fail("not-found", "No usable camera track was returned.");
    }
    track.addEventListener("ended", this.onTrackEnded, { once: true });
    this.video.srcObject = this.stream;
    this.video.muted = true;
    this.video.playsInline = true;
    try {
      await this.video.play();
      this.emit("initializing", "Loading local hand tracking…");
      this.processor = await this.createProcessor();
    } catch (error) {
      await this.closeProcessor();
      this.stopTracks();
      throw this.fail(
        "initialization-failed",
        "Camera opened, but local hand tracking could not start.",
        error,
      );
    }
    this.running = true;
    this.hidden = document.visibilityState === "hidden";
    document.addEventListener("visibilitychange", this.onVisibilityChange);
    this.emit(this.hidden ? "paused" : "live", this.hidden ? "Paused while this tab is hidden." : "Camera and local tracking are live.");
    this.schedule();
  }

  pause(): void {
    if (!this.running) return;
    this.hidden = true;
    this.cancelFrame();
    this.emit("paused", "Tracking paused.");
  }

  resume(): void {
    if (!this.running || document.visibilityState === "hidden") return;
    this.hidden = false;
    this.emit("live", "Camera and local tracking are live.");
    this.schedule();
  }

  async stop(): Promise<void> {
    this.running = false;
    this.hidden = false;
    this.busy = false;
    this.cancelFrame();
    document.removeEventListener("visibilitychange", this.onVisibilityChange);
    this.stopTracks();
    this.video.srcObject = null;
    await this.closeProcessor();
    this.resetMetrics();
    this.emit("stopped", "Camera is off.");
  }

  private readonly onVisibilityChange = (): void => {
    if (document.visibilityState === "hidden") {
      this.hidden = true;
      this.cancelFrame();
      this.emit("paused", "Tracking paused while this tab is hidden.");
    } else {
      this.hidden = false;
      this.emit("live", "Camera and local tracking are live.");
      this.schedule();
    }
  };

  private readonly onTrackEnded = (): void => {
    if (!this.running) return;
    this.running = false;
    this.cancelFrame();
    this.fail("disconnected", "The camera disconnected or became unavailable.");
  };

  private schedule(): void {
    if (!this.running || this.hidden || this.frameHandle !== null) return;
    if (this.video.requestVideoFrameCallback) {
      this.frameHandle = this.video.requestVideoFrameCallback((now) => {
        this.frameHandle = null;
        void this.processNewest(now);
      });
    } else {
      this.frameHandle = window.requestAnimationFrame((now) => {
        this.frameHandle = null;
        void this.processNewest(now);
      });
    }
  }

  private async processNewest(captureTimestamp: number): Promise<void> {
    if (!this.running || this.hidden || !this.processor) return;
    this.updateCaptureFps(captureTimestamp);
    if (this.busy || this.video.readyState < HTMLMediaElement.HAVE_CURRENT_DATA) {
      this.droppedFrames += 1;
      this.emitMetricsIfDue(captureTimestamp);
      this.schedule();
      return;
    }
    this.busy = true;
    const started = performance.now();
    try {
      const result = await this.processor.process(this.video, captureTimestamp);
      if (!this.running || this.hidden) return;
      this.inferenceMs = performance.now() - started;
      this.updateProcessedFps(result.timestamp);
      this.callbacks.onResult(result);
    } catch (error) {
      this.fail(
        "initialization-failed",
        "Local hand tracking stopped unexpectedly.",
        error,
      );
      await this.stop();
      return;
    } finally {
      this.busy = false;
    }
    this.emitMetricsIfDue(captureTimestamp);
    this.schedule();
  }

  private updateCaptureFps(now: number): void {
    if (this.lastCaptureAt > 0) {
      const instant = 1000 / Math.max(1, now - this.lastCaptureAt);
      this.captureFps = this.captureFps === 0 ? instant : this.captureFps * 0.82 + instant * 0.18;
    }
    this.lastCaptureAt = now;
  }

  private updateProcessedFps(now: number): void {
    if (this.lastProcessedAt > 0) {
      const instant = 1000 / Math.max(1, now - this.lastProcessedAt);
      this.processedFps = this.processedFps === 0 ? instant : this.processedFps * 0.82 + instant * 0.18;
    }
    this.lastProcessedAt = now;
  }

  private emitMetricsIfDue(now: number): void {
    if (now - this.lastSnapshotAt < 200) return;
    this.lastSnapshotAt = now;
    this.emit("live", "Camera and local tracking are live.");
  }

  private emit(phase: CameraPhase, message: string): void {
    this.callbacks.onSnapshot({
      phase,
      message,
      metrics: {
        captureFps: this.captureFps,
        processedFps: this.processedFps,
        inferenceMs: this.inferenceMs,
        droppedFrames: this.droppedFrames,
      },
    });
  }

  private cancelFrame(): void {
    if (this.frameHandle === null) return;
    if (this.video.cancelVideoFrameCallback) {
      this.video.cancelVideoFrameCallback(this.frameHandle);
    } else if (typeof window !== "undefined") {
      window.cancelAnimationFrame(this.frameHandle);
    }
    this.frameHandle = null;
  }

  private stopTracks(): void {
    this.stream?.getTracks().forEach((track) => track.stop());
    this.stream = null;
  }

  private async closeProcessor(): Promise<void> {
    const current = this.processor;
    this.processor = null;
    await current?.close();
  }

  private resetMetrics(): void {
    this.lastCaptureAt = 0;
    this.lastProcessedAt = 0;
    this.captureFps = 0;
    this.processedFps = 0;
    this.inferenceMs = 0;
    this.droppedFrames = 0;
    this.lastSnapshotAt = 0;
  }

  private mapMediaError(error: unknown): CameraSessionError {
    const name = error instanceof DOMException ? error.name : "";
    if (name === "NotAllowedError" || name === "SecurityError") {
      return this.fail(
        "permission-denied",
        "Camera permission was denied. Allow camera access for this site, then try again.",
        error,
      );
    }
    if (name === "NotFoundError" || name === "OverconstrainedError") {
      return this.fail("not-found", "No compatible camera is available.", error);
    }
    if (name === "NotReadableError" || name === "AbortError") {
      return this.fail(
        "camera-busy",
        "The camera may already be in use by another application.",
        error,
      );
    }
    return this.fail("initialization-failed", "Signal could not start the camera.", error);
  }

  private fail(code: CameraSessionError["code"], message: string, cause?: unknown): CameraSessionError {
    const error = new CameraSessionError(code, message, cause === undefined ? undefined : { cause });
    this.callbacks.onError(error);
    this.emit("error", message);
    return error;
  }
}
