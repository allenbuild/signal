"use client";

import { useEffect, useRef, useState } from "react";

import {
  extractRecordingKeyframes,
  type RecordingKeyframe,
} from "../../lib/recording/keyframes";

const RECOMMENDED_DURATION_MS = 30_000;
const HARD_DURATION_MS = 60_000;
const MAX_RECORDING_BYTES = 40 * 1024 * 1024;

export type BrowserRecording = {
  blob: Blob;
  durationMs: number;
  keyframes: RecordingKeyframe[];
  mimeType: string;
};

export function ScreenRecorder({
  onUse,
}: {
  onUse(recording: BrowserRecording): void;
}) {
  const [state, setState] = useState<
    "idle" | "requesting" | "recording" | "preview" | "extracting" | "error"
  >("idle");
  const [elapsedMs, setElapsedMs] = useState(0);
  const [recordingBlob, setRecordingBlob] = useState<Blob | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [message, setMessage] = useState(
    "Choose a screen, window, or browser tab. The recording stays in browser memory.",
  );
  const streamRef = useRef<MediaStream | null>(null);
  const recorderRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const startedAtRef = useRef(0);
  const tickerRef = useRef<number | null>(null);
  const hardStopRef = useRef<number | null>(null);
  const elapsedRef = useRef(0);

  function clearTimers() {
    if (tickerRef.current !== null) window.clearInterval(tickerRef.current);
    if (hardStopRef.current !== null) window.clearTimeout(hardStopRef.current);
    tickerRef.current = null;
    hardStopRef.current = null;
  }

  function stopTracks() {
    streamRef.current?.getTracks().forEach((track) => track.stop());
    streamRef.current = null;
  }

  function revokePreview() {
    if (previewUrl) URL.revokeObjectURL(previewUrl);
  }

  function reset() {
    clearTimers();
    stopTracks();
    if (
      recorderRef.current &&
      recorderRef.current.state !== "inactive"
    ) {
      recorderRef.current.stop();
    }
    recorderRef.current = null;
    chunksRef.current = [];
    revokePreview();
    setPreviewUrl(null);
    setRecordingBlob(null);
    setElapsedMs(0);
    elapsedRef.current = 0;
    setState("idle");
    setMessage(
      "Choose a screen, window, or browser tab. The recording stays in browser memory.",
    );
  }

  useEffect(() => {
    return () => {
      clearTimers();
      stopTracks();
      if (
        recorderRef.current &&
        recorderRef.current.state !== "inactive"
      ) {
        recorderRef.current.stop();
      }
      if (previewUrl) URL.revokeObjectURL(previewUrl);
    };
  }, [previewUrl]);

  function stopRecording() {
    clearTimers();
    const recorder = recorderRef.current;
    if (recorder && recorder.state !== "inactive") recorder.stop();
    stopTracks();
  }

  async function startRecording() {
    revokePreview();
    setPreviewUrl(null);
    setRecordingBlob(null);
    if (
      !navigator.mediaDevices?.getDisplayMedia ||
      typeof MediaRecorder === "undefined"
    ) {
      setState("error");
      setMessage(
        "Screen recording is unavailable in this browser. Describe the command instead.",
      );
      return;
    }

    setState("requesting");
    setMessage("Waiting for the browser’s screen picker…");
    try {
      const stream = await navigator.mediaDevices.getDisplayMedia({
        video: { frameRate: { ideal: 8, max: 12 } },
        audio: false,
      });
      streamRef.current = stream;
      const mimeType = [
        "video/webm;codecs=vp9",
        "video/webm;codecs=vp8",
        "video/webm",
      ].find((type) => MediaRecorder.isTypeSupported(type));
      const recorder = new MediaRecorder(
        stream,
        mimeType ? { mimeType, videoBitsPerSecond: 2_500_000 } : undefined,
      );
      recorderRef.current = recorder;
      chunksRef.current = [];
      startedAtRef.current = Date.now();
      setElapsedMs(0);
      elapsedRef.current = 0;

      recorder.addEventListener("dataavailable", (event) => {
        if (event.data.size > 0) chunksRef.current.push(event.data);
      });
      recorder.addEventListener("stop", () => {
        clearTimers();
        stopTracks();
        const durationMs = Math.max(
          1,
          Date.now() - startedAtRef.current,
        );
        elapsedRef.current = durationMs;
        setElapsedMs(durationMs);
        const blob = new Blob(chunksRef.current, {
          type: recorder.mimeType || "video/webm",
        });
        chunksRef.current = [];
        recorderRef.current = null;
        if (blob.size > MAX_RECORDING_BYTES) {
          setState("error");
          setMessage(
            "That recording is larger than 40 MiB. Retake a shorter demonstration.",
          );
          return;
        }
        const url = URL.createObjectURL(blob);
        setRecordingBlob(blob);
        setPreviewUrl(url);
        setState("preview");
        setMessage(
          durationMs > RECOMMENDED_DURATION_MS
            ? "Recording captured. A shorter demonstration may produce a clearer plan."
            : "Recording captured. Review it before using it as planning context.",
        );
      });
      recorder.addEventListener("error", () => {
        clearTimers();
        stopTracks();
        setState("error");
        setMessage(
          "Recording stopped unexpectedly. You can retry or continue with a description.",
        );
      });
      stream.getVideoTracks()[0]?.addEventListener("ended", stopRecording, {
        once: true,
      });

      recorder.start(500);
      setState("recording");
      setMessage("Recording in progress. Stop when the key actions are visible.");
      tickerRef.current = window.setInterval(() => {
        const elapsed = Date.now() - startedAtRef.current;
        elapsedRef.current = elapsed;
        setElapsedMs(elapsed);
      }, 250);
      hardStopRef.current = window.setTimeout(
        stopRecording,
        HARD_DURATION_MS,
      );
    } catch (error) {
      clearTimers();
      stopTracks();
      setState("error");
      setMessage(
        error instanceof DOMException &&
            ["NotAllowedError", "AbortError"].includes(error.name)
          ? "Screen sharing was cancelled or denied. You can retry or describe the command instead."
          : "Signal could not start screen recording in this browser.",
      );
    }
  }

  async function acceptRecording() {
    if (!recordingBlob) return;
    setState("extracting");
    setMessage("Preparing a small set of local keyframes…");
    try {
      const keyframes = await extractRecordingKeyframes(recordingBlob);
      onUse({
        blob: recordingBlob,
        durationMs: elapsedRef.current,
        keyframes,
        mimeType: recordingBlob.type,
      });
      setState("preview");
      setMessage(
        `${keyframes.length} compressed keyframes are ready. The raw recording remains local.`,
      );
    } catch {
      setState("error");
      setMessage(
        "The browser could not extract keyframes. Retake or continue with the written description.",
      );
    }
  }

  return (
    <section className="signal-recorder" aria-labelledby="recorder-heading">
      <div className="signal-recorder-heading">
        <div>
          <p className="signal-kicker">Teach by Demo</p>
          <h3 id="recorder-heading">Show Signal the workflow</h3>
        </div>
        {state === "recording" && (
          <span className="signal-recording-live">
            <i aria-hidden="true" /> REC {formatTime(elapsedMs)}
          </span>
        )}
      </div>

      {previewUrl ? (
        <video
          className="signal-recording-preview"
          src={previewUrl}
          controls
          playsInline
          aria-label="Screen recording preview"
        />
      ) : (
        <div className="signal-recording-empty" aria-hidden="true">
          <span>▣</span>
          <i>Screen, window, or tab</i>
        </div>
      )}

      <p
        className={`signal-recorder-message ${state === "error" ? "error" : ""}`}
        role={state === "error" ? "alert" : "status"}
        aria-live="polite"
      >
        {message}
      </p>

      {state === "recording" && elapsedMs > RECOMMENDED_DURATION_MS && (
        <p className="signal-recording-warning">
          Over 30 seconds. Stop soon for a smaller, clearer demonstration.
        </p>
      )}

      <div className="signal-recorder-actions">
        {(state === "idle" || state === "error") && (
          <button
            type="button"
            className="signal-button signal-button-secondary"
            onClick={() => void startRecording()}
          >
            Start recording
          </button>
        )}
        {state === "requesting" && (
          <button type="button" className="signal-button" disabled>
            Waiting for permission…
          </button>
        )}
        {state === "recording" && (
          <button
            type="button"
            className="signal-button signal-button-danger"
            onClick={stopRecording}
          >
            Stop recording
          </button>
        )}
        {(state === "preview" || state === "extracting") && (
          <>
            <button
              type="button"
              className="signal-button signal-button-quiet"
              onClick={reset}
              disabled={state === "extracting"}
            >
              Retake
            </button>
            <button
              type="button"
              className="signal-button signal-button-secondary"
              onClick={() => void acceptRecording()}
              disabled={state === "extracting"}
            >
              {state === "extracting" ? "Preparing…" : "Use recording"}
            </button>
          </>
        )}
      </div>
    </section>
  );
}

function formatTime(milliseconds: number) {
  const seconds = Math.floor(milliseconds / 1000);
  return `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(
    seconds % 60,
  ).padStart(2, "0")}`;
}
