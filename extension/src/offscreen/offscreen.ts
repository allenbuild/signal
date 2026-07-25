import {
  CameraRuntime,
  type CameraRuntimeSnapshot,
} from "./camera-runtime";
import {
  MediaPipeRuntime,
  TrackingNormalizer,
  type TrackingAnalysis,
} from "./mediapipe-runtime";

const MESSAGE_VERSION = 1 as const;
const PORT_NAME = "signal:offscreen";
const OFFSCREEN_SOURCE = "signal-offscreen";

type OffscreenControlMessage =
  | { version?: number; type: "signal:offscreen/start" }
  | { version?: number; type: "signal:offscreen/pause" }
  | { version?: number; type: "signal:offscreen/stop" }
  | { version?: number; type: "signal:offscreen/reset" }
  | { version?: number; type: "signal:offscreen/ping" };

type TrackingStats = {
  captureFps: number;
  processedFps: number;
  inferenceMs: number;
  width: number;
  height: number;
};

type OffscreenOutboundMessage =
  | {
      version: typeof MESSAGE_VERSION;
      source: typeof OFFSCREEN_SOURCE;
      type: "signal:offscreen/ready";
      sessionId: string;
    }
  | {
      version: typeof MESSAGE_VERSION;
      source: typeof OFFSCREEN_SOURCE;
      type: "signal:offscreen/state";
      sessionId: string;
      state:
        | "idle"
        | "starting"
        | "requesting-permission"
        | "running"
        | "paused"
        | "stopped"
        | "error";
      fps: number;
      cameraActive: boolean;
      error?: string;
      camera: CameraRuntimeSnapshot;
    }
  | {
      version: typeof MESSAGE_VERSION;
      source: typeof OFFSCREEN_SOURCE;
      type: "signal:offscreen/permission-required";
      sessionId: string;
      reason: "camera";
    }
  | {
      version: typeof MESSAGE_VERSION;
      source: typeof OFFSCREEN_SOURCE;
      type: "signal:tracking-frame";
      sessionId: string;
      sequence: number;
      timestamp: number;
      stats: TrackingStats;
      landmarks: TrackingAnalysis["landmarks"];
      gesture: TrackingAnalysis["gesture"];
      confidence: number;
      fps: number;
      pointerDelta?: TrackingAnalysis["pointerDelta"];
      pinch: TrackingAnalysis["pinch"];
    };

type VideoWithFrameCallback = HTMLVideoElement & {
  requestVideoFrameCallback?(
    callback: (now: number, metadata: VideoFrameCallbackMetadata) => void,
  ): number;
  cancelVideoFrameCallback?(handle: number): void;
};

function requireCameraElement(): HTMLVideoElement {
  const element =
    document.querySelector<HTMLVideoElement>("#signal-camera");
  if (!element) {
    throw new Error("Signal offscreen camera element is missing.");
  }
  return element;
}

const video = requireCameraElement();

const sessionId = crypto.randomUUID();
const mediapipe = new MediaPipeRuntime();
const normalizer = new TrackingNormalizer();
let port: chrome.runtime.Port | null = null;
let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
let reconnectAttempt = 0;
let running = false;
let starting = false;
let stopping = false;
let lifecycleGeneration = 0;
let desiredRuntimeState: "running" | "paused" | "idle" = "idle";
let sequence = 0;
let videoFrameHandle: number | null = null;
let timeoutHandle: ReturnType<typeof setTimeout> | null = null;
let lastVideoTime = -1;
let lastTrackingVisible = false;
let captureFrames = 0;
let processedFrames = 0;
let statsStartedAt = performance.now();
let currentStats: TrackingStats = {
  captureFps: 0,
  processedFps: 0,
  inferenceMs: 0,
  width: 0,
  height: 0,
};
let controlQueue: Promise<void> = Promise.resolve();

function isControlMessage(value: unknown): value is OffscreenControlMessage {
  if (!value || typeof value !== "object") return false;
  const message = value as { version?: unknown; type?: unknown };
  if (
    message.version !== undefined &&
    message.version !== MESSAGE_VERSION
  ) {
    return false;
  }
  return (
    message.type === "signal:offscreen/start" ||
    message.type === "signal:offscreen/pause" ||
    message.type === "signal:offscreen/stop" ||
    message.type === "signal:offscreen/reset" ||
    message.type === "signal:offscreen/ping"
  );
}

function post(message: OffscreenOutboundMessage): void {
  try {
    port?.postMessage(message);
  } catch {
    port = null;
    scheduleReconnect();
  }
}

function postReady(): void {
  post({
    version: MESSAGE_VERSION,
    source: OFFSCREEN_SOURCE,
    type: "signal:offscreen/ready",
    sessionId,
  });
}

function connect(): void {
  if (port) return;
  if (reconnectTimer !== null) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
  try {
    const nextPort = chrome.runtime.connect({ name: PORT_NAME });
    port = nextPort;
    reconnectAttempt = 0;
    nextPort.onMessage.addListener((message: unknown) => {
      if (isControlMessage(message)) void enqueueControlMessage(message);
    });
    nextPort.onDisconnect.addListener(() => {
      if (port === nextPort) port = null;
      scheduleReconnect();
    });
    postReady();
    postCameraState(camera.snapshot);
  } catch {
    port = null;
    scheduleReconnect();
  }
}

function scheduleReconnect(): void {
  if (reconnectTimer !== null) return;
  const delay = Math.min(5_000, 250 * 2 ** reconnectAttempt);
  reconnectAttempt = Math.min(5, reconnectAttempt + 1);
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connect();
  }, delay);
}

function postCameraState(snapshot: CameraRuntimeSnapshot): void {
  const state =
    snapshot.state === "requesting"
      ? "requesting-permission"
      : snapshot.state === "running" && !running
        ? "starting"
        : snapshot.state;
  post({
    version: MESSAGE_VERSION,
    source: OFFSCREEN_SOURCE,
    type: "signal:offscreen/state",
    sessionId,
    state,
    fps: currentStats.processedFps,
    cameraActive: snapshot.state === "running",
    ...(snapshot.error ? { error: snapshot.error } : {}),
    camera: snapshot,
  });
}

const camera = new CameraRuntime({
  video,
  onStateChange: postCameraState,
  onEnded: () => {
    void teardown("idle");
  },
});

function interruptedTeardownTarget(): "paused" | "idle" {
  return desiredRuntimeState === "paused" ? "paused" : "idle";
}

async function start(): Promise<void> {
  if (running || starting || stopping) return;
  starting = true;
  desiredRuntimeState = "running";
  const generation = ++lifecycleGeneration;
  postCameraState({
    ...camera.snapshot,
    state: "requesting",
  });
  try {
    await camera.start();
    if (
      generation !== lifecycleGeneration ||
      desiredRuntimeState !== "running"
    ) {
      await teardown(interruptedTeardownTarget());
      return;
    }
    await mediapipe.start();
    if (
      generation !== lifecycleGeneration ||
      desiredRuntimeState !== "running"
    ) {
      await teardown(interruptedTeardownTarget());
      return;
    }
    normalizer.reset();
    sequence = 0;
    lastVideoTime = -1;
    lastTrackingVisible = false;
    captureFrames = 0;
    processedFrames = 0;
    statsStartedAt = performance.now();
    running = true;
    postCameraState(camera.snapshot);
    scheduleNextFrame();
  } catch (error) {
    if (
      generation !== lifecycleGeneration ||
      desiredRuntimeState !== "running"
    ) {
      await teardown(interruptedTeardownTarget());
      return;
    }
    const message =
      error instanceof Error
        ? error.message
        : "Signal could not initialize local hand tracking.";
    await teardown("error", message);
    const name =
      error instanceof DOMException ? error.name : "CameraInitializationError";
    if (name === "NotAllowedError" || name === "SecurityError") {
      post({
        version: MESSAGE_VERSION,
        source: OFFSCREEN_SOURCE,
        type: "signal:offscreen/permission-required",
        sessionId,
        reason: "camera",
      });
    }
  } finally {
    starting = false;
  }
}

async function teardown(
  target: "idle" | "paused" | "error",
  error = "Signal could not initialize local hand tracking.",
): Promise<void> {
  if (stopping) return;
  stopping = true;
  running = false;
  cancelScheduledFrame();
  normalizer.reset();
  mediapipe.stop();
  if (target === "paused") camera.pause();
  else if (target === "error") camera.fail(error);
  else camera.stop();
  if (lastTrackingVisible) postTrackingLost();
  lastTrackingVisible = false;
  lastVideoTime = -1;
  stopping = false;
}

function resetTracking(): void {
  normalizer.reset();
  if (lastTrackingVisible) postTrackingLost();
  lastTrackingVisible = false;
}

function postTrackingLost(): void {
  post({
    version: MESSAGE_VERSION,
    source: OFFSCREEN_SOURCE,
    type: "signal:tracking-frame",
    sessionId,
    sequence: ++sequence,
    timestamp: Date.now(),
    stats: currentStats,
    gesture: "unknown",
    confidence: 0,
    fps: currentStats.processedFps,
    landmarks: [],
    pinch: {
      closed: false,
      transactionState: "idle",
    },
  });
}

async function handleControlMessage(
  message: OffscreenControlMessage,
): Promise<void> {
  switch (message.type) {
    case "signal:offscreen/start":
      await start();
      break;
    case "signal:offscreen/pause":
      desiredRuntimeState = "paused";
      lifecycleGeneration += 1;
      await teardown("paused");
      break;
    case "signal:offscreen/stop":
      desiredRuntimeState = "idle";
      lifecycleGeneration += 1;
      await teardown("idle");
      break;
    case "signal:offscreen/reset":
      resetTracking();
      break;
    case "signal:offscreen/ping":
      postReady();
      postCameraState(camera.snapshot);
      break;
  }
}

function enqueueControlMessage(message: OffscreenControlMessage) {
  const operation = controlQueue.then(
    () => handleControlMessage(message),
    () => handleControlMessage(message),
  );
  controlQueue = operation.catch(() => undefined);
  return operation;
}

function processFrame(timestamp: number): void {
  if (!running || camera.snapshot.state !== "running") return;
  if (
    video.readyState < HTMLMediaElement.HAVE_CURRENT_DATA ||
    video.currentTime === lastVideoTime
  ) {
    scheduleNextFrame();
    return;
  }

  captureFrames += 1;
  lastVideoTime = video.currentTime;
  const startedAt = performance.now();
  try {
    const result = mediapipe.detect(video, timestamp);
    const inferenceMs = performance.now() - startedAt;
    processedFrames += 1;
    updateStats(timestamp, inferenceMs);
    const hand = result.landmarks[0];
    const confidence = result.handedness[0]?.[0]?.score ?? 0;
    const analysis = hand
      ? normalizer.analyze(hand, timestamp, confidence)
      : null;
    if (analysis) {
      lastTrackingVisible = true;
      post({
        version: MESSAGE_VERSION,
        source: OFFSCREEN_SOURCE,
        type: "signal:tracking-frame",
        sessionId,
        sequence: ++sequence,
        timestamp: Date.now(),
        stats: currentStats,
        landmarks: analysis.landmarks,
        gesture: analysis.gesture,
        confidence: analysis.confidence,
        fps: currentStats.processedFps,
        ...(analysis.pointerDelta
          ? { pointerDelta: analysis.pointerDelta }
          : {}),
        pinch: analysis.pinch,
      });
    } else {
      if (lastTrackingVisible) postTrackingLost();
      lastTrackingVisible = false;
    }
  } catch {
    resetTracking();
  }
  scheduleNextFrame();
}

function updateStats(timestamp: number, inferenceMs: number): void {
  const elapsed = timestamp - statsStartedAt;
  if (elapsed >= 1_000) {
    const seconds = elapsed / 1_000;
    currentStats = {
      captureFps: captureFrames / seconds,
      processedFps: processedFrames / seconds,
      inferenceMs,
      width: video.videoWidth,
      height: video.videoHeight,
    };
    captureFrames = 0;
    processedFrames = 0;
    statsStartedAt = timestamp;
    postCameraState(camera.snapshot);
  } else {
    currentStats = {
      ...currentStats,
      inferenceMs,
      width: video.videoWidth,
      height: video.videoHeight,
    };
  }
}

function scheduleNextFrame(): void {
  if (!running || videoFrameHandle !== null || timeoutHandle !== null) return;
  const callback = (now: number) => {
    videoFrameHandle = null;
    timeoutHandle = null;
    processFrame(now);
  };
  const frameVideo = video as VideoWithFrameCallback;
  if (frameVideo.requestVideoFrameCallback) {
    videoFrameHandle = frameVideo.requestVideoFrameCallback(callback);
  } else {
    timeoutHandle = setTimeout(() => callback(performance.now()), 33);
  }
}

function cancelScheduledFrame(): void {
  const frameVideo = video as VideoWithFrameCallback;
  if (
    videoFrameHandle !== null &&
    frameVideo.cancelVideoFrameCallback
  ) {
    frameVideo.cancelVideoFrameCallback(videoFrameHandle);
  }
  if (timeoutHandle !== null) clearTimeout(timeoutHandle);
  videoFrameHandle = null;
  timeoutHandle = null;
}

chrome.runtime.onMessage.addListener(
  (
    message: unknown,
    _sender: chrome.runtime.MessageSender,
    sendResponse: (response?: unknown) => void,
  ) => {
    if (!isControlMessage(message)) return false;
    void enqueueControlMessage(message).then(
      () => sendResponse({ ok: true, version: MESSAGE_VERSION }),
      () => sendResponse({ ok: false, version: MESSAGE_VERSION }),
    );
    return true;
  },
);

window.addEventListener("pagehide", () => {
  desiredRuntimeState = "idle";
  lifecycleGeneration += 1;
  void teardown("idle");
  if (reconnectTimer !== null) clearTimeout(reconnectTimer);
  port?.disconnect();
  port = null;
});

connect();
