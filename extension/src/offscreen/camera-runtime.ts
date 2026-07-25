export type CameraRuntimeState =
  | "idle"
  | "requesting"
  | "running"
  | "paused"
  | "error";

export type CameraRuntimeSnapshot = {
  state: CameraRuntimeState;
  width: number;
  height: number;
  frameRate: number;
  error?: string;
};

export type CameraRuntimeOptions = {
  video: HTMLVideoElement;
  mediaDevices?: Pick<MediaDevices, "getUserMedia">;
  onStateChange?(snapshot: CameraRuntimeSnapshot): void;
  onEnded?(): void;
};

export const SIGNAL_CAMERA_CONSTRAINTS: MediaStreamConstraints = {
  audio: false,
  video: {
    facingMode: "user",
    width: { ideal: 640 },
    height: { ideal: 480 },
    frameRate: { ideal: 30, max: 30 },
  },
};

const CAMERA_REQUEST_TIMEOUT_MS = 8_000;

export function cameraErrorMessage(error: unknown): string {
  if (!(error instanceof DOMException)) {
    return error instanceof Error && error.message
      ? `Signal could not initialize the camera: ${error.message}`
      : "Signal could not initialize the camera.";
  }

  switch (error.name) {
    case "NotAllowedError":
    case "SecurityError":
      return "Camera permission is required to start Signal.";
    case "NotFoundError":
    case "DevicesNotFoundError":
      return "No camera was found on this computer.";
    case "NotReadableError":
    case "TrackStartError":
      return "The camera is already in use or could not be started.";
    default:
      return `Camera initialization failed (${error.name}).`;
  }
}

/**
 * Owns Signal's one live camera stream.
 *
 * The runtime intentionally exposes only a MediaStream to the local offscreen
 * document. It has no persistence or networking APIs, so camera frames cannot
 * be retained or uploaded by this layer.
 */
export class CameraRuntime {
  private readonly video: HTMLVideoElement;
  private readonly mediaDevices: Pick<MediaDevices, "getUserMedia">;
  private readonly onStateChange?: CameraRuntimeOptions["onStateChange"];
  private readonly onEnded?: CameraRuntimeOptions["onEnded"];
  private stream: MediaStream | null = null;
  private startPromise: Promise<MediaStream> | null = null;
  private state: CameraRuntimeState = "idle";
  private lifecycleGeneration = 0;

  constructor(options: CameraRuntimeOptions) {
    this.video = options.video;
    this.mediaDevices =
      options.mediaDevices ??
      (() => {
        if (!navigator.mediaDevices?.getUserMedia) {
          throw new Error("Camera capture is unavailable in this browser.");
        }
        return navigator.mediaDevices;
      })();
    this.onStateChange = options.onStateChange;
    this.onEnded = options.onEnded;
  }

  get currentStream(): MediaStream | null {
    return this.stream;
  }

  get snapshot(): CameraRuntimeSnapshot {
    const settings = this.stream?.getVideoTracks()[0]?.getSettings();
    return {
      state: this.state,
      width: settings?.width ?? this.video.videoWidth ?? 0,
      height: settings?.height ?? this.video.videoHeight ?? 0,
      frameRate: settings?.frameRate ?? 0,
    };
  }

  async start(): Promise<MediaStream> {
    if (this.stream?.active) return this.stream;
    if (this.startPromise) return this.startPromise;

    this.setState("requesting");
    const generation = ++this.lifecycleGeneration;
    this.startPromise = this.openCamera(generation);
    try {
      return await this.startPromise;
    } finally {
      this.startPromise = null;
    }
  }

  pause(): void {
    this.lifecycleGeneration += 1;
    this.releaseStream();
    this.setState("paused");
  }

  stop(): void {
    this.lifecycleGeneration += 1;
    this.releaseStream();
    this.setState("idle");
  }

  fail(error: string): void {
    this.lifecycleGeneration += 1;
    this.releaseStream();
    this.setState("error", error);
  }

  private async openCamera(generation: number): Promise<MediaStream> {
    let requestTimedOut = false;
    let timeout: ReturnType<typeof setTimeout> | undefined;
    try {
      const request = this.mediaDevices
        .getUserMedia(SIGNAL_CAMERA_CONSTRAINTS)
        .then((stream) => {
          if (requestTimedOut) {
            stream.getTracks().forEach((track) => track.stop());
          }
          return stream;
        });
      const stream = await Promise.race([
        request,
        new Promise<never>((_, reject) => {
          timeout = setTimeout(() => {
            requestTimedOut = true;
            reject(
              new DOMException(
                "Camera permission did not complete in time.",
                "NotAllowedError",
              ),
            );
          }, CAMERA_REQUEST_TIMEOUT_MS);
        }),
      ]);
      if (timeout) clearTimeout(timeout);
      if (requestTimedOut) {
        stream.getTracks().forEach((track) => track.stop());
        throw new DOMException(
          "Camera permission did not complete in time.",
          "NotAllowedError",
        );
      }
      if (generation !== this.lifecycleGeneration) {
        stream.getTracks().forEach((track) => track.stop());
        throw new DOMException(
          "Camera request was superseded.",
          "AbortError",
        );
      }
      this.releaseStream();
      this.stream = stream;
      for (const track of stream.getTracks()) {
        track.addEventListener(
          "ended",
          () => {
            if (this.stream !== stream) return;
            this.releaseStream();
            this.setState("idle");
            this.onEnded?.();
          },
          { once: true },
        );
      }
      this.video.srcObject = stream;
      await this.video.play();
      this.setState("running");
      return stream;
    } catch (error) {
      if (timeout) clearTimeout(timeout);
      if (generation === this.lifecycleGeneration) {
        this.releaseStream();
        this.setState("error", cameraErrorMessage(error));
      }
      throw error;
    }
  }

  private releaseStream(): void {
    const stream = this.stream;
    this.stream = null;
    this.video.pause();
    this.video.srcObject = null;
    stream?.getTracks().forEach((track) => track.stop());
  }

  private setState(state: CameraRuntimeState, error?: string): void {
    this.state = state;
    this.onStateChange?.({ ...this.snapshot, error });
  }
}
