"use client";

import { ChangeEvent, useEffect, useRef, useState } from "react";

import {
  fistGesture,
  gestureCommands,
  presetGestures,
  type GestureId,
} from "../../config/gestureCommands";
import {
  executeBrowserPlan,
  isBrowserSafeAction,
  type BrowserActionTab,
} from "../../lib/commands/browser-actions";
import {
  FIST_COMMAND_STORAGE_KEY,
  loadSavedFistCommand,
  saveFistCommand,
  signalCommandSchema,
  type SignalCommand,
} from "../../lib/commands/schema";
import { dispatchSignalGesture } from "../../lib/gestures/bridge";
import { useSignalGestureBridge } from "../../lib/gestures/useSignalGestureBridge";
import {
  applyControlEffects,
} from "../../lib/vision/browser-control-effects";
import {
  ControlEngine,
  type PinchTransactionState,
} from "../../lib/vision/control-engine";
import { CommandGestureEngine } from "../../lib/vision/command-gesture-engine";
import {
  CameraControlPanel,
  type SignalMode,
  type TrackingFrame,
} from "./CameraControlPanel";
import { CustomCommandModal } from "./CustomCommandModal";
import { GestureCard } from "./GestureCard";

type OverlayMessage = {
  title: string;
  body: string;
};

function browserSafeCommand(command: SignalCommand) {
  return command.plan.steps.every((step) => isBrowserSafeAction(step.action));
}

export function SignalPage() {
  const [customCommand, setCustomCommand] = useState<SignalCommand | null>(null);
  const [editorOpen, setEditorOpen] = useState(false);
  const [previewGesture, setPreviewGesture] = useState<GestureId | null>(null);
  const [mode, setMode] = useState<SignalMode>("control");
  const [running, setRunning] = useState(false);
  const [status, setStatus] = useState(
    "Click Start Signal to enable private, on-device hand tracking.",
  );
  const [updated, setUpdated] = useState(false);
  const [commandBusy, setCommandBusy] = useState(false);
  const [cursor, setCursor] = useState({
    x: 0,
    y: 0,
    visible: false,
  });
  const [transaction, setTransaction] =
    useState<PinchTransactionState>("idle");
  const [zoom, setZoom] = useState(1);
  const [zoomOrigin, setZoomOrigin] = useState({ x: 0, y: 0 });
  const [clickPulse, setClickPulse] = useState<{
    x: number;
    y: number;
    id: number;
  } | null>(null);
  const [overlay, setOverlay] = useState<OverlayMessage | null>(null);
  const [guideOpen, setGuideOpen] = useState(false);
  const fistButtonRef = useRef<HTMLButtonElement>(null);
  const importInputRef = useRef<HTMLInputElement>(null);
  const actionTabRef = useRef<BrowserActionTab | null>(null);
  const controlEngineRef = useRef<ControlEngine | null>(null);
  const commandEngineRef = useRef(new CommandGestureEngine(550, 800));
  const commandAbortRef = useRef<AbortController | null>(null);
  const overlayTimerRef = useRef<number | null>(null);
  const focusTimerRef = useRef<number | null>(null);
  const pulseTimerRef = useRef<number | null>(null);

  const bridge = useSignalGestureBridge({
    disabled: editorOpen || !running || mode !== "commands",
    cooldownMs: 800,
    onFire: (gesture) => void executeGestureCommand(gesture),
  });

  useEffect(() => {
    controlEngineRef.current = new ControlEngine({
      width: window.innerWidth,
      height: window.innerHeight,
    });
    const handleResize = () =>
      controlEngineRef.current?.resize(window.innerWidth, window.innerHeight);
    window.addEventListener("resize", handleResize);

    const initialization = window.setTimeout(() => {
      const saved = loadSavedFistCommand(window.localStorage);
      if (saved && browserSafeCommand(saved)) {
        setCustomCommand(saved);
      } else if (saved) {
        setStatus(
          "A legacy native command was found but not loaded. Create a browser-safe Fist command.",
        );
      }
    }, 0);

    return () => {
      window.removeEventListener("resize", handleResize);
      window.clearTimeout(initialization);
      commandAbortRef.current?.abort();
      if (overlayTimerRef.current) window.clearTimeout(overlayTimerRef.current);
      if (focusTimerRef.current) window.clearTimeout(focusTimerRef.current);
      if (pulseTimerRef.current) window.clearTimeout(pulseTimerRef.current);
    };
  }, []);

  const bridgeStatus = !running
    ? status
    : mode === "control"
      ? transaction === "idle"
        ? status
        : `Control transaction: ${transaction}. Cursor is locked until release.`
      : bridge.activeGesture
        ? bridge.lastFiredGesture === bridge.activeGesture
          ? `${
              gestureCommands.find(
                (command) => command.gesture === bridge.activeGesture,
              )?.label
            } ran inside this fallback page only. Use the Chrome extension for other tabs.`
          : `${
              gestureCommands.find(
                (command) => command.gesture === bridge.activeGesture,
              )?.label
            } held at ${Math.round(bridge.confidence * 100)}% confidence.`
        : status;

  function showOverlay(title: string, body: string, durationMs = 4_000) {
    if (overlayTimerRef.current) window.clearTimeout(overlayTimerRef.current);
    setOverlay({ title, body });
    overlayTimerRef.current = window.setTimeout(
      () => setOverlay(null),
      durationMs,
    );
  }

  function pulseAt(x: number, y: number) {
    const pulse = { x, y, id: Date.now() };
    setClickPulse(pulse);
    if (pulseTimerRef.current) window.clearTimeout(pulseTimerRef.current);
    pulseTimerRef.current = window.setTimeout(() => {
      setClickPulse((current) => (current?.id === pulse.id ? null : current));
    }, 420);
  }

  function resetInteraction(message?: string) {
    const control = controlEngineRef.current?.reset();
    setCursor(
      control?.cursor ?? {
        x: window.innerWidth / 2,
        y: window.innerHeight / 2,
        visible: false,
      },
    );
    setTransaction("idle");
    const released = commandEngineRef.current.reset();
    if (released) dispatchSignalGesture(released);
    if (message) setStatus(message);
  }

  function handleTrackingFrame(frame: TrackingFrame | null) {
    const controlEngine = controlEngineRef.current;
    if (!controlEngine) return;
    if (!frame || editorOpen || !running) {
      resetInteraction();
      return;
    }

    if (mode === "control") {
      const released = commandEngineRef.current.reset(frame.timestamp);
      if (released) dispatchSignalGesture(released);
      const next = controlEngine.update({
        landmarks: frame.landmarks,
        pointerPose: frame.pose.pointerPose,
        timestamp: frame.timestamp,
      });
      setCursor(next.cursor);
      setTransaction(next.transaction);
      applyControlEffects(next.effects, {
        onClickPulse: pulseAt,
        onZoom(delta, x, y) {
          setZoomOrigin({ x, y });
          setZoom((current) =>
            Math.min(1.75, Math.max(0.75, current + delta)),
          );
        },
        onStatus: setStatus,
      });
      return;
    }

    const reset = controlEngine.reset();
    setCursor(reset.cursor);
    setTransaction("idle");
    const update = commandEngineRef.current.update(
      frame.pose.gesture,
      Math.min(frame.pose.confidence, frame.trackingConfidence),
      frame.timestamp,
    );
    if (update) dispatchSignalGesture(update);
  }

  function handleModeChange(nextMode: SignalMode) {
    setMode(nextMode);
    resetInteraction(
      !running
        ? `${
            nextMode === "control" ? "Control" : "Commands"
          } selected. Click Start Signal to enable private, on-device hand tracking.`
        : nextMode === "control"
          ? "Control Mode: point to move, pinch to click, scroll, or zoom."
          : "Command Mode: hold a command pose until its card fills.",
    );
  }

  function handleRunningChange(nextRunning: boolean) {
    setRunning(nextRunning);
    if (!nextRunning) resetInteraction("Signal stopped. Camera access is off.");
  }

  function closeEditor() {
    setEditorOpen(false);
    window.setTimeout(() => fistButtonRef.current?.focus(), 0);
  }

  function openEditor() {
    setPreviewGesture(null);
    setEditorOpen(true);
    resetInteraction("Command execution pauses while the editor is open.");
  }

  function handleSave(command: SignalCommand) {
    if (!browserSafeCommand(command)) {
      setStatus(
        "That plan contains a native-only action. Regenerate a browser-safe command.",
      );
      return;
    }
    saveFistCommand(window.localStorage, command);
    setCustomCommand(command);
    setUpdated(true);
    setStatus(`${command.name} assigned to Fist and saved in this browser.`);
    setEditorOpen(false);
    window.setTimeout(() => {
      setUpdated(false);
      fistButtonRef.current?.focus();
    }, 1_200);
  }

  async function executeGestureCommand(gesture: GestureId) {
    if (!running || mode !== "commands" || editorOpen || commandBusy) return;

    if (gesture === "fist") {
      if (!customCommand) {
        openEditor();
        return;
      }
      setCommandBusy(true);
      commandAbortRef.current?.abort();
      const controller = new AbortController();
      commandAbortRef.current = controller;
      setStatus(`Running ${customCommand.name} inside the browser…`);
      try {
        const receipt = await executeBrowserPlan(customCommand.plan, {
          actionTab: actionTabRef.current,
          speechSynthesis: window.speechSynthesis,
          notification:
            typeof Notification === "undefined" ? undefined : Notification,
          document,
          signal: controller.signal,
          onStatus: setStatus,
          onOverlay: showOverlay,
        });
        setStatus(
          `${customCommand.name} completed ${receipt.completedSteps} browser step${
            receipt.completedSteps === 1 ? "" : "s"
          }.`,
        );
      } catch (error) {
        setStatus(
          error instanceof Error
            ? `Command stopped: ${error.message}`
            : "The browser command stopped.",
        );
      } finally {
        setCommandBusy(false);
      }
      return;
    }

    switch (gesture) {
      case "one":
        setGuideOpen(true);
        showOverlay(
          "Control guide",
          "Control Mode: point with your index finger. Pinch quickly to click; hold and move vertically to scroll or horizontally to zoom.",
          7_000,
        );
        setStatus("Opened the Signal control guide.");
        break;
      case "two":
        fistButtonRef.current?.scrollIntoView({
          behavior: "smooth",
          block: "center",
        });
        fistButtonRef.current?.focus({ preventScroll: true });
        setStatus("Focused the custom Fist command.");
        break;
      case "three":
        setZoom(1);
        setStatus("Signal zoom reset to 100%.");
        break;
      case "four":
        if (focusTimerRef.current) window.clearTimeout(focusTimerRef.current);
        focusTimerRef.current = window.setTimeout(() => {
          showOverlay("Focus timer", "Five minutes are complete.");
        }, 5 * 60_000);
        showOverlay("Focus timer", "Five-minute Signal timer started.");
        setStatus("Five-minute focus timer started in Signal.");
        break;
      case "five":
        showOverlay(
          "Signal fallback demo",
          `${mode === "commands" ? "Command" : "Control"} Mode is active in this tab at ${Math.round(
            zoom * 100,
          )}% zoom. Install the Chrome extension for cross-tab website control; no native companion is required.`,
          6_000,
        );
        setStatus("Displayed the active Signal summary.");
        break;
      case "thumbs_up":
        if ("speechSynthesis" in window) {
          window.speechSynthesis.speak(
            new SpeechSynthesisUtterance("Nice work. Signal is ready."),
          );
          setStatus("Spoke encouragement through the browser.");
        } else {
          setStatus("Speech synthesis is unavailable in this browser.");
        }
        break;
      case "thumbs_down": {
        window.speechSynthesis?.cancel();
        const media = Array.from(
          document.querySelectorAll<HTMLMediaElement>("audio, video"),
        ).filter((element) => !element.closest(".signal-camera-feed"));
        media.forEach((element) => element.pause());
        setStatus("Paused media playing inside Signal.");
        break;
      }
      case "c_shape":
        openEditor();
        break;
    }
  }

  function exportCommand() {
    if (!customCommand) return;
    const blob = new Blob(
      [JSON.stringify({ storageVersion: 1, command: customCommand }, null, 2)],
      { type: "application/json" },
    );
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `${customCommand.id}.json`;
    link.click();
    URL.revokeObjectURL(url);
    setStatus("Fist command exported. Exporting did not run it.");
  }

  async function importCommand(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    if (file.size > 256 * 1024) {
      setStatus("Import rejected: command files must be under 256 KiB.");
      return;
    }
    try {
      const value: unknown = JSON.parse(await file.text());
      const candidate =
        value && typeof value === "object" && "command" in value
          ? (value as { command: unknown }).command
          : value;
      const parsed = signalCommandSchema.safeParse(candidate);
      if (
        !parsed.success ||
        parsed.data.gesture !== "fist" ||
        !browserSafeCommand(parsed.data)
      ) {
        throw new Error("invalid");
      }
      saveFistCommand(window.localStorage, parsed.data);
      setCustomCommand(parsed.data);
      setUpdated(true);
      setStatus(`${parsed.data.name} imported and assigned to Fist.`);
      window.setTimeout(() => setUpdated(false), 1_200);
    } catch {
      setStatus(
        "Import rejected: use a strict browser-safe Signal version 1 Fist command.",
      );
    }
  }

  function resetCommand() {
    window.localStorage.removeItem(FIST_COMMAND_STORAGE_KEY);
    setCustomCommand(null);
    setPreviewGesture(null);
    setStatus("Fist reset to the editable browser default.");
  }

  function prepareActionTab() {
    const actionTab = window.open("about:blank", "signal-action-tab", "popup");
    if (!actionTab) {
      setStatus(
        "The browser blocked the action tab. Allow this popup and try again.",
      );
      return;
    }
    actionTab.opener = null;
    actionTab.document.title = "Signal action tab";
    actionTab.document.body.innerHTML =
      "<main style='font:16px system-ui;padding:3rem'><h1>Signal action tab</h1><p>Keep this tab open. Reviewed HTTPS navigation commands will reuse it.</p></main>";
    actionTabRef.current = actionTab;
    setStatus("Reusable action tab prepared for reviewed HTTPS navigation.");
  }

  async function enableNotifications() {
    if (typeof Notification === "undefined") {
      setStatus("Browser notifications are unavailable.");
      return;
    }
    const permission = await Notification.requestPermission();
    setStatus(
      permission === "granted"
        ? "Browser notifications enabled."
        : "Notifications were not enabled; Signal will use in-page overlays.",
    );
  }

  const preview = previewGesture
    ? gestureCommands.find((command) => command.gesture === previewGesture)
    : null;

  return (
    <main id="main-content" className="signal-command-page">
      <div className="signal-ambient-light" aria-hidden="true" />
      <header className="signal-command-statusbar">
        <span>
          <i aria-hidden="true" /> {running ? `${mode} mode live` : "Camera off"}
        </span>
        <nav aria-label="Signal runtime status">
          <span>Browser only · local vision</span>
          <span>{Math.round(zoom * 100)}% zoom</span>
        </nav>
      </header>

      <aside className="signal-extension-notice" role="note">
        <div>
          <strong>Browser fallback demo</strong>
          <span>
            This page only controls itself. Stop its camera before starting the
            extension.
          </span>
        </div>
        <a href="/setup">Use Signal across Chrome tabs</a>
      </aside>

      <CameraControlPanel
        mode={mode}
        disabled={editorOpen}
        onModeChange={handleModeChange}
        onTrackingFrame={handleTrackingFrame}
        onRunningChange={handleRunningChange}
        onStatus={setStatus}
      />

      <div
        className="signal-zoom-surface"
        style={{
          transform: `scale(${zoom})`,
          transformOrigin: `${zoomOrigin.x}px ${zoomOrigin.y}px`,
        }}
      >
        <section className="signal-command-stage" aria-labelledby="signal-title">
          <h1 id="signal-title">signal</h1>

          <div className="signal-preset-grid" aria-label="Preset gesture commands">
            {presetGestures.map((command) => (
              <GestureCard
                command={command}
                key={command.gesture}
                active={bridge.activeGesture === command.gesture}
                progress={
                  bridge.activeGesture === command.gesture ? bridge.progress : 0
                }
                fired={bridge.lastFiredGesture === command.gesture}
                onClick={() =>
                  setPreviewGesture((current) =>
                    current === command.gesture ? null : command.gesture,
                  )
                }
              />
            ))}
          </div>

          <div className="signal-fist-row">
            <GestureCard
              buttonRef={fistButtonRef}
              command={fistGesture}
              assignedName={customCommand?.name}
              active={bridge.activeGesture === "fist"}
              progress={bridge.activeGesture === "fist" ? bridge.progress : 0}
              fired={bridge.lastFiredGesture === "fist"}
              updated={updated}
              onClick={openEditor}
            />
          </div>

          <p className="signal-bridge-status" role="status" aria-live="polite">
            {bridgeStatus}
          </p>

          {preview && (
            <aside className="signal-command-preview" aria-live="polite">
              <div>
                <p className="signal-kicker">
                  Browser preset · {preview.actionType}
                </p>
                <h2>{preview.commandName}</h2>
                <p>{preview.description}</p>
              </div>
              <button
                type="button"
                data-signal-interactive
                aria-label="Close preset preview"
                onClick={() => setPreviewGesture(null)}
              >
                ×
              </button>
            </aside>
          )}

          <div className="signal-command-utilities">
            <input
              ref={importInputRef}
              type="file"
              accept="application/json,.json"
              onChange={(event) => void importCommand(event)}
              className="visually-hidden"
            />
            <button
              type="button"
              data-signal-interactive
              onClick={prepareActionTab}
            >
              Prepare action tab
            </button>
            <button
              type="button"
              data-signal-interactive
              onClick={() => void enableNotifications()}
            >
              Enable notifications
            </button>
            <button
              type="button"
              data-signal-interactive
              onClick={() => importInputRef.current?.click()}
            >
              Import Fist JSON
            </button>
            {customCommand && (
              <>
                <button
                  type="button"
                  data-signal-interactive
                  onClick={exportCommand}
                >
                  Export Fist JSON
                </button>
                <button
                  type="button"
                  data-signal-interactive
                  onClick={resetCommand}
                >
                  Reset Fist
                </button>
              </>
            )}
          </div>
        </section>
      </div>

      <div
        className={`signal-virtual-cursor ${
          cursor.visible && running && mode === "control" ? "is-visible" : ""
        } ${transaction !== "idle" ? "is-locked" : ""}`}
        style={{ transform: `translate3d(${cursor.x}px, ${cursor.y}px, 0)` }}
        aria-hidden="true"
      >
        <span />
      </div>

      {clickPulse && (
        <div
          className="signal-click-pulse"
          style={{ left: clickPulse.x, top: clickPulse.y }}
          aria-hidden="true"
        />
      )}

      {overlay && (
        <aside className="signal-runtime-overlay" aria-live="polite">
          <p className="signal-kicker">Signal</p>
          <strong>{overlay.title}</strong>
          <p>{overlay.body}</p>
          <button
            type="button"
            data-signal-interactive
            aria-label="Close Signal message"
            onClick={() => setOverlay(null)}
          >
            ×
          </button>
        </aside>
      )}

      {guideOpen && (
        <button
          type="button"
          className="signal-guide-dismiss"
          data-signal-interactive
          onClick={() => setGuideOpen(false)}
        >
          Hide control guide
        </button>
      )}

      {editorOpen && (
        <CustomCommandModal
          existingCommand={customCommand}
          onClose={closeEditor}
          onSave={handleSave}
        />
      )}
    </main>
  );
}
