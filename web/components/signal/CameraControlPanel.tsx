"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { HandLandmarker } from "@mediapipe/tasks-vision";

import {
  mirrorLandmarks,
  type HandLandmark,
} from "../../lib/vision/hand-geometry";
import {
  clearHandLandmarks,
  drawHandLandmarks,
} from "../../lib/vision/landmark-renderer";
import { createLocalHandLandmarker } from "../../lib/vision/mediapipe";
import {
  recognizeHandPose,
  type PoseRecognition,
} from "../../lib/vision/pose-recognizer";

export type SignalMode = "control" | "commands";

export type TrackingFrame = {
  landmarks: readonly HandLandmark[];
  pose: PoseRecognition;
  trackingConfidence: number;
  timestamp: number;
};

type TrackingStats = {
  captureFps: number;
  processedFps: number;
  inferenceMs: number;
  pose: string;
  confidence: number;
};

const initialStats: TrackingStats = {
  captureFps: 0,
  processedFps: 0,
  inferenceMs: 0,
  pose: "None",
  confidence: 0,
};

function cameraErrorMessage(error: unknown) {
  if (!(error instanceof DOMException)) {
    return error instanceof Error && error.message
      ? `Signal could not initialize local hand tracking: ${error.message}`
      : "Signal could not initialize local hand tracking.";
  }
  switch (error.name) {
    case "NotAllowedError":
    case "SecurityError":
      return "Camera access was denied. Allow camera access in the browser and try again.";
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

function displayPose(pose: PoseRecognition) {
  if (!pose.gesture) return pose.pointerPose ? "Pointer" : "Tracking";
  return pose.gesture
    .replace("c_shape", "C")
    .replaceAll("_", " ")
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

export function CameraControlPanel({
  mode,
  disabled,
  onModeChange,
  onTrackingFrame,
  onRunningChange,
  onStatus,
}: {
  mode: SignalMode;
  disabled: boolean;
  onModeChange(mode: SignalMode): void;
  onTrackingFrame(frame: TrackingFrame | null): void;
  onRunningChange(running: boolean): void;
  onStatus(message: string): void;
}) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const landmarkerRef = useRef<HandLandmarker | null>(null);
  const animationRef = useRef<number | null>(null);
  const lastVideoTimeRef = useRef(-1);
  const inferenceBusyRef = useRef(false);
  const visibleRef = useRef(true);
  const mountedRef = useRef(true);
  const onTrackingFrameRef = useRef(onTrackingFrame);
  const onStatusRef = useRef(onStatus);
  const disabledRef = useRef(disabled);
  const [state, setState] = useState<
    "idle" | "requesting" | "loading" | "running" | "error"
  >("idle");
  const [message, setMessage] = useState(
    "Camera stays on this device. Start Signal when you are ready.",
  );
  const [stats, setStats] = useState(initialStats);

  useEffect(() => {
    onTrackingFrameRef.current = onTrackingFrame;
    onStatusRef.current = onStatus;
    disabledRef.current = disabled;
  }, [disabled, onStatus, onTrackingFrame]);

  const stopSignal = useCallback(
    (nextMessage = "Signal stopped. Camera access is off.") => {
      if (animationRef.current !== null) {
        window.cancelAnimationFrame(animationRef.current);
        animationRef.current = null;
      }
      streamRef.current?.getTracks().forEach((track) => track.stop());
      streamRef.current = null;
      if (videoRef.current) videoRef.current.srcObject = null;
      landmarkerRef.current?.close();
      landmarkerRef.current = null;
      lastVideoTimeRef.current = -1;
      inferenceBusyRef.current = false;
      clearHandLandmarks(canvasRef.current);
      onTrackingFrameRef.current(null);
      if (mountedRef.current) {
        setState("idle");
        setStats(initialStats);
        setMessage(nextMessage);
        onRunningChange(false);
        onStatusRef.current(nextMessage);
      }
    },
    [onRunningChange],
  );

  useEffect(() => {
    mountedRef.current = true;
    const handleVisibility = () => {
      visibleRef.current = !document.hidden;
      if (document.hidden) {
        onTrackingFrameRef.current(null);
        setMessage("Tracking paused while this tab is hidden.");
      } else if (streamRef.current) {
        setMessage("Camera and local landmark tracking are active.");
      }
    };
    document.addEventListener("visibilitychange", handleVisibility);
    return () => {
      mountedRef.current = false;
      document.removeEventListener("visibilitychange", handleVisibility);
      if (animationRef.current !== null) {
        window.cancelAnimationFrame(animationRef.current);
      }
      streamRef.current?.getTracks().forEach((track) => track.stop());
      landmarkerRef.current?.close();
      onTrackingFrameRef.current(null);
    };
  }, []);

  useEffect(() => {
    if (disabled) {
      clearHandLandmarks(canvasRef.current);
      onTrackingFrameRef.current(null);
    }
  }, [disabled]);

  const renderLoop = useCallback(() => {
    let captureFrames = 0;
    let processedFrames = 0;
    let windowStartedAt = performance.now();
    let lastInferenceMs = 0;

    const draw = (landmarks: readonly HandLandmark[]) => {
      const canvas = canvasRef.current;
      const video = videoRef.current;
      if (!canvas || !video || !video.videoWidth || !video.videoHeight) return;
      drawHandLandmarks(
        canvas,
        video.videoWidth,
        video.videoHeight,
        landmarks,
      );
    };

    const clearCanvas = () => {
      clearHandLandmarks(canvasRef.current);
    };

    const tick = (timestamp: number) => {
      const video = videoRef.current;
      const landmarker = landmarkerRef.current;
      if (!video || !landmarker || !streamRef.current) return;

      if (
        visibleRef.current &&
        !disabledRef.current &&
        video.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA &&
        video.currentTime !== lastVideoTimeRef.current
      ) {
        captureFrames += 1;
        if (!inferenceBusyRef.current) {
          inferenceBusyRef.current = true;
          lastVideoTimeRef.current = video.currentTime;
          const startedAt = performance.now();
          try {
            const result = landmarker.detectForVideo(video, timestamp);
            lastInferenceMs = performance.now() - startedAt;
            processedFrames += 1;
            const raw = result.landmarks[0] as HandLandmark[] | undefined;
            let poseLabel = "No hand";
            let confidence = 0;
            if (raw?.length === 21) {
              const mirrored = mirrorLandmarks(raw);
              const pose = recognizeHandPose(mirrored);
              const trackingConfidence =
                result.handedness[0]?.[0]?.score ?? pose.confidence;
              poseLabel = displayPose(pose);
              confidence = trackingConfidence;
              draw(mirrored);
              onTrackingFrameRef.current({
                landmarks: mirrored,
                pose,
                trackingConfidence,
                timestamp,
              });
            } else {
              clearCanvas();
              onTrackingFrameRef.current(null);
            }
            if (timestamp - windowStartedAt >= 1_000) {
              const elapsedSeconds = (timestamp - windowStartedAt) / 1_000;
              setStats({
                captureFps: captureFrames / elapsedSeconds,
                processedFps: processedFrames / elapsedSeconds,
                inferenceMs: lastInferenceMs,
                pose: poseLabel,
                confidence,
              });
              captureFrames = 0;
              processedFrames = 0;
              windowStartedAt = timestamp;
            }
          } catch {
            clearCanvas();
            onTrackingFrameRef.current(null);
          } finally {
            inferenceBusyRef.current = false;
          }
        }
      }

      animationRef.current = window.requestAnimationFrame(tick);
    };

    animationRef.current = window.requestAnimationFrame(tick);
  }, []);

  async function startSignal() {
    if (state === "requesting" || state === "loading" || state === "running") {
      return;
    }
    if (!navigator.mediaDevices?.getUserMedia) {
      setState("error");
      setMessage("Camera capture is unavailable in this browser.");
      return;
    }

    setState("requesting");
    setMessage("Waiting for browser camera permission…");
    onStatus("Waiting for browser camera permission.");

    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode: "user",
          width: { ideal: 640 },
          height: { ideal: 480 },
          frameRate: { ideal: 30, max: 30 },
        },
        audio: false,
      });
      streamRef.current = stream;
      const video = videoRef.current;
      if (!video) throw new Error("Camera preview is unavailable.");
      video.srcObject = stream;
      await video.play();
      setState("loading");
      setMessage("Camera ready. Loading local MediaPipe hand tracking…");

      landmarkerRef.current = await createLocalHandLandmarker(
        window.location.origin,
      );

      setState("running");
      setMessage("Camera and local landmark tracking are active.");
      onRunningChange(true);
      onStatus("Signal is running in Control Mode.");
      renderLoop();
    } catch (error) {
      stopSignal(cameraErrorMessage(error));
      if (mountedRef.current) {
        setState("error");
        setMessage(cameraErrorMessage(error));
      }
    }
  }

  const running = state === "running";

  return (
    <section
      className={`signal-tracking-dock ${running ? "is-running" : ""}`}
      aria-label="Signal camera and tracking controls"
    >
      <div className="signal-camera-feed">
        <video
          ref={videoRef}
          muted
          playsInline
          aria-label="Mirrored live camera preview"
        />
        <canvas
          ref={canvasRef}
          aria-label="MediaPipe hand landmark overlay"
        />
        {!running && (
          <div className="signal-camera-placeholder" aria-hidden="true">
            <span>Local camera</span>
            <i>Frames are never uploaded</i>
          </div>
        )}
        <span className="signal-camera-state">
          <i aria-hidden="true" />
          {running ? "Live · local" : state}
        </span>
      </div>

      <div className="signal-tracking-controls">
        <div className="signal-mode-selector" aria-label="Signal mode">
          <button
            type="button"
            data-signal-interactive
            aria-pressed={mode === "control"}
            onClick={() => onModeChange("control")}
          >
            Control
          </button>
          <button
            type="button"
            data-signal-interactive
            aria-pressed={mode === "commands"}
            onClick={() => onModeChange("commands")}
          >
            Commands
          </button>
        </div>

        <div className="signal-tracking-primary-actions">
          {running ? (
            <button
              type="button"
              className="signal-button signal-button-danger"
              data-signal-interactive
              onClick={() => stopSignal()}
            >
              Stop Signal
            </button>
          ) : (
            <button
              type="button"
              className="signal-button signal-button-primary"
              data-signal-interactive
              disabled={state === "requesting" || state === "loading"}
              onClick={() => void startSignal()}
            >
              {state === "requesting" || state === "loading"
                ? "Starting…"
                : "Start Signal"}
            </button>
          )}
        </div>
      </div>

      <dl className="signal-tracking-hud" aria-label="Tracking telemetry">
        <div>
          <dt>Capture</dt>
          <dd>{stats.captureFps.toFixed(0)} fps</dd>
        </div>
        <div>
          <dt>Processed</dt>
          <dd>{stats.processedFps.toFixed(0)} fps</dd>
        </div>
        <div>
          <dt>Latency</dt>
          <dd>{stats.inferenceMs.toFixed(0)} ms</dd>
        </div>
        <div>
          <dt>Pose</dt>
          <dd>{stats.pose}</dd>
        </div>
        <div>
          <dt>Confidence</dt>
          <dd>{Math.round(stats.confidence * 100)}%</dd>
        </div>
      </dl>

      <p className={state === "error" ? "error" : ""} role="status">
        {message}
      </p>
    </section>
  );
}
