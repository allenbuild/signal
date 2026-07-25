export interface DisplayTrackLike {
  stop(): void;
  addEventListener?(
    type: "ended",
    listener: () => void,
    options?: { once?: boolean },
  ): void;
}

export interface DisplayStreamLike {
  getTracks(): DisplayTrackLike[];
}

export interface RecorderDataEventLike {
  data: Blob;
}

export interface RecorderErrorEventLike {
  error?: Error;
}

export interface MediaRecorderLike {
  readonly state: string;
  readonly mimeType?: string;
  ondataavailable: ((event: RecorderDataEventLike) => void) | null;
  onstop: (() => void) | null;
  onerror: ((event: RecorderErrorEventLike) => void) | null;
  start(timeslice?: number): void;
  stop(): void;
}

export interface RecordingDependencies {
  getDisplayMedia(constraints: {
    video: boolean;
    audio: boolean;
  }): Promise<DisplayStreamLike>;
  createRecorder(stream: DisplayStreamLike): MediaRecorderLike;
  createObjectURL(blob: Blob): string;
  revokeObjectURL(url: string): void;
  setTimeout(callback: () => void, delayMs: number): unknown;
  clearTimeout(handle: unknown): void;
  createBlob?(parts: BlobPart[], options: BlobPropertyBag): Blob;
}

export interface RecordingPreview {
  blob: Blob;
  url: string;
  mimeType: string;
}

export type TeachRecordingState =
  | "idle"
  | "requesting"
  | "recording"
  | "stopping"
  | "preview"
  | "error"
  | "disposed";

/**
 * Owns one explicit getDisplayMedia/MediaRecorder lifecycle. Raw bytes only
 * live in memory and are never passed to the command repository.
 */
export class TeachRecordingSession {
  private stream: DisplayStreamLike | null = null;
  private recorder: MediaRecorderLike | null = null;
  private chunks: Blob[] = [];
  private timer: unknown = null;
  private preview: RecordingPreview | null = null;
  private stopPromise: Promise<RecordingPreview> | null = null;
  private resolveStop: ((preview: RecordingPreview) => void) | null = null;
  private rejectStop: ((error: Error) => void) | null = null;
  private currentState: TeachRecordingState = "idle";

  constructor(
    private readonly dependencies: RecordingDependencies,
    private readonly maximumDurationMs = 60_000,
  ) {
    if (
      !Number.isFinite(maximumDurationMs) ||
      maximumDurationMs <= 0 ||
      maximumDurationMs > 60_000
    ) {
      throw new Error("Recording duration must be between 1 and 60 seconds.");
    }
  }

  get state(): TeachRecordingState {
    return this.currentState;
  }

  get currentPreview(): RecordingPreview | null {
    return this.preview;
  }

  async start(): Promise<void> {
    if (this.currentState === "disposed") {
      throw new Error("Recording session is disposed.");
    }
    if (
      this.currentState === "requesting" ||
      this.currentState === "recording" ||
      this.currentState === "stopping"
    ) {
      throw new Error("A recording is already active.");
    }
    this.revokePreview();
    this.chunks = [];
    this.currentState = "requesting";
    let stream: DisplayStreamLike | null = null;
    try {
      stream = await this.dependencies.getDisplayMedia({
        video: true,
        audio: false,
      });
      this.stream = stream;
      const recorder = this.dependencies.createRecorder(stream);
      this.recorder = recorder;
      recorder.ondataavailable = (event) => {
        if (event.data.size > 0) this.chunks.push(event.data);
      };
      recorder.onerror = (event) => {
        this.fail(event.error ?? new Error("Screen recording failed."));
      };
      recorder.onstop = () => this.finishRecording();
      for (const track of stream.getTracks()) {
        track.addEventListener?.("ended", () => {
          if (this.currentState === "recording") void this.stop();
        }, { once: true });
      }
      recorder.start(250);
      this.currentState = "recording";
      this.timer = this.dependencies.setTimeout(
        () => void this.stop(),
        this.maximumDurationMs,
      );
    } catch (error) {
      stream?.getTracks().forEach((track) => track.stop());
      this.stream = null;
      this.recorder = null;
      this.currentState = "error";
      throw error;
    }
  }

  stop(): Promise<RecordingPreview> {
    if (this.stopPromise) return this.stopPromise;
    if (this.currentState === "preview" && this.preview) {
      return Promise.resolve(this.preview);
    }
    if (this.currentState !== "recording" || !this.recorder) {
      return Promise.reject(new Error("No screen recording is active."));
    }
    this.currentState = "stopping";
    this.clearMaximumTimer();
    this.stopPromise = new Promise<RecordingPreview>((resolve, reject) => {
      this.resolveStop = resolve;
      this.rejectStop = reject;
    });
    const recorder = this.recorder;
    this.stopTracks();
    try {
      recorder.stop();
    } catch (error) {
      this.fail(
        error instanceof Error ? error : new Error("Screen recording failed to stop."),
      );
    }
    return this.stopPromise;
  }

  retake(): void {
    if (
      this.currentState === "recording" ||
      this.currentState === "stopping" ||
      this.currentState === "requesting"
    ) {
      throw new Error("Stop the active recording before retaking it.");
    }
    this.revokePreview();
    this.chunks = [];
    this.currentState = "idle";
  }

  dispose(): void {
    if (this.currentState === "disposed") return;
    this.clearMaximumTimer();
    this.stopTracks();
    const recorder = this.recorder;
    this.recorder = null;
    this.currentState = "disposed";
    if (recorder && recorder.state !== "inactive") {
      recorder.onstop = null;
      recorder.ondataavailable = null;
      recorder.onerror = null;
      try {
        recorder.stop();
      } catch {
        // Cleanup must remain best-effort even after a recorder implementation fails.
      }
    }
    this.chunks = [];
    this.revokePreview();
    this.rejectStop?.(new Error("Recording session was disposed."));
    this.stopPromise = null;
    this.resolveStop = null;
    this.rejectStop = null;
  }

  private finishRecording(): void {
    this.clearMaximumTimer();
    this.stopTracks();
    if (this.currentState === "disposed") return;
    const mimeType = this.recorder?.mimeType || "video/webm";
    const createBlob =
      this.dependencies.createBlob ??
      ((parts: BlobPart[], options: BlobPropertyBag) => new Blob(parts, options));
    const blob = createBlob(this.chunks, { type: mimeType });
    const preview: RecordingPreview = {
      blob,
      url: this.dependencies.createObjectURL(blob),
      mimeType,
    };
    this.preview = preview;
    this.currentState = "preview";
    this.recorder = null;
    this.chunks = [];
    this.resolveStop?.(preview);
    this.stopPromise = null;
    this.resolveStop = null;
    this.rejectStop = null;
  }

  private fail(error: Error): void {
    this.clearMaximumTimer();
    this.stopTracks();
    this.recorder = null;
    this.chunks = [];
    this.currentState = "error";
    this.rejectStop?.(error);
    this.stopPromise = null;
    this.resolveStop = null;
    this.rejectStop = null;
  }

  private stopTracks(): void {
    const stream = this.stream;
    this.stream = null;
    stream?.getTracks().forEach((track) => {
      try {
        track.stop();
      } catch {
        // A disconnected share surface may already have stopped its track.
      }
    });
  }

  private clearMaximumTimer(): void {
    if (this.timer === null) return;
    this.dependencies.clearTimeout(this.timer);
    this.timer = null;
  }

  private revokePreview(): void {
    if (!this.preview) return;
    this.dependencies.revokeObjectURL(this.preview.url);
    this.preview = null;
  }
}
