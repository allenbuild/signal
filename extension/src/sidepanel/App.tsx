import { ChangeEvent, useEffect, useMemo, useRef, useState } from "react";

const gestures = [
  ["five", "5", "Rickroll"],
  ["two", "2", "New Gmail"],
  ["three", "3", "Cursor Agents"],
  ["four", "4", "New Google Doc"],
  ["thumbs_up", "↑", "Build with Bolt"],
  ["thumbs_down", "↓", "Next Spotify Track"],
  ["c_shape", "C", "Anthropic on X"],
] as const;

type RuntimeState = {
  running: boolean;
  paused: boolean;
  mode: "control" | "commands";
  camera: "off" | "starting" | "running" | "paused" | "error" | "permission";
  fps: number;
  gesture: string | null;
  confidence: number;
  activeTabSupported: boolean;
  status: string;
  commandProgress?: number;
};

type FistCommand = {
  schemaVersion: 1;
  id: string;
  gesture: "fist";
  name: string;
  description: string;
  source: "natural_language" | "recording" | "hybrid";
  enabled: boolean;
  plan: unknown;
  createdAt: string;
  updatedAt: string;
};

const initialState: RuntimeState = {
  running: false,
  paused: false,
  mode: "control",
  camera: "off",
  fps: 0,
  gesture: null,
  confidence: 0,
  activeTabSupported: true,
  status: "Start Signal to enable private, on-device tracking.",
};

function send<T = { ok: boolean; error?: string }>(message: unknown): Promise<T> {
  return chrome.runtime.sendMessage(message) as Promise<T>;
}

export function App() {
  const [runtime, setRuntime] = useState(initialState);
  const [fistCommand, setFistCommand] = useState<FistCommand | null>(null);
  const [editorOpen, setEditorOpen] = useState(false);
  const [instruction, setInstruction] = useState(
    "When I make a fist, open https://calendar.google.com and say focus time.",
  );
  const [commandName, setCommandName] = useState("My fist command");
  const [draftPlan, setDraftPlan] = useState<unknown>(null);
  const [builderStatus, setBuilderStatus] = useState(
    "Describe a browser workflow or teach one by demonstration.",
  );
  const [busy, setBusy] = useState(false);
  const [recording, setRecording] = useState(false);
  const [demoCaptured, setDemoCaptured] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [sensitivity, setSensitivity] = useState(1.35);
  const [smoothing, setSmoothing] = useState(0.34);
  const importRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    void send<{
      ok: boolean;
      state?: RuntimeState;
      fistCommand?: FistCommand | null;
      tuning?: { sensitivity?: number; smoothing?: number };
    }>({ version: 1, type: "signal:sidepanel/status" }).then((response) => {
      if (response.state) setRuntime((current) => ({ ...current, ...response.state }));
      if (response.fistCommand) {
        setFistCommand(response.fistCommand);
        setCommandName(response.fistCommand.name);
      }
      if (response.tuning?.sensitivity) setSensitivity(response.tuning.sensitivity);
      if (response.tuning?.smoothing) setSmoothing(response.tuning.smoothing);
    });

    const listener = (message: unknown) => {
      if (!message || typeof message !== "object") return;
      const event = message as {
        version?: number;
        type?: string;
        state?: Partial<RuntimeState>;
        fps?: number;
        gesture?: string | null;
        confidence?: number;
        progress?: number;
        status?: string;
      };
      if (event.version !== 1) return;
      if (event.type === "signal:runtime-state" && event.state) {
        setRuntime((current) => ({ ...current, ...event.state }));
      } else if (event.type === "signal:tracking-state") {
        setRuntime((current) => ({
          ...current,
          fps: event.fps ?? current.fps,
          gesture: event.gesture ?? null,
          confidence: event.confidence ?? 0,
          commandProgress: event.progress,
          status: event.status ?? current.status,
        }));
      }
    };
    chrome.runtime.onMessage.addListener(listener);
    return () => chrome.runtime.onMessage.removeListener(listener);
  }, []);

  useEffect(() => {
    void send({
      version: 1,
      type: "signal:sidepanel/editor",
      open: editorOpen,
    });
    return () => {
      void send({
        version: 1,
        type: "signal:sidepanel/editor",
        open: false,
      });
    };
  }, [editorOpen]);

  const cameraLabel = useMemo(() => {
    if (runtime.camera === "running") return `${Math.round(runtime.fps)} FPS`;
    if (runtime.camera === "permission") return "Permission needed";
    return runtime.camera;
  }, [runtime.camera, runtime.fps]);

  async function start() {
    setRuntime((current) => ({
      ...current,
      camera: "starting",
      status: "Starting private hand tracking…",
    }));
    const response = await send<{ ok: boolean; error?: string; permission?: boolean }>({
      version: 1,
      type: "signal:sidepanel/start",
    });
    if (!response.ok) {
      setRuntime((current) => ({
        ...current,
        camera: response.permission ? "permission" : "error",
        status: response.error ?? "Signal could not start the camera.",
      }));
    }
  }

  async function stop() {
    await send({ version: 1, type: "signal:sidepanel/stop" });
    setRuntime((current) => ({ ...current, ...initialState }));
  }

  async function togglePause() {
    await send({
      version: 1,
      type: runtime.paused ? "signal:sidepanel/resume" : "signal:sidepanel/pause",
    });
  }

  async function openPermissionSetup() {
    await send({ version: 1, type: "signal:sidepanel/open-permission" });
  }

  async function generatePlan() {
    if (!instruction.trim()) return;
    setBusy(true);
    setBuilderStatus("Building and validating a browser-safe plan…");
    try {
      const response = await send<{
        ok: boolean;
        plan?: unknown;
        name?: string;
        error?: string;
        fallback?: boolean;
      }>({
        version: 1,
        type: "signal:sidepanel/plan",
        instruction: instruction.trim(),
        demonstration: demoCaptured ? "captured" : undefined,
      });
      if (!response.ok || !response.plan) {
        throw new Error(response.error ?? "The planner did not return a valid plan.");
      }
      setDraftPlan(response.plan);
      if (response.name) setCommandName(response.name);
      setBuilderStatus(
        response.fallback
          ? "Built with Signal’s deterministic fallback and validated locally."
          : "Built with Claude and validated locally.",
      );
    } catch (error) {
      setBuilderStatus(error instanceof Error ? error.message : "Plan generation failed.");
    } finally {
      setBusy(false);
    }
  }

  async function saveCommand() {
    if (!draftPlan || !commandName.trim()) return;
    const now = new Date().toISOString();
    const command: FistCommand = {
      schemaVersion: 1,
      id: fistCommand?.id ?? `fist-${crypto.randomUUID()}`,
      gesture: "fist",
      name: commandName.trim(),
      description: instruction.trim().slice(0, 500),
      source: demoCaptured
        ? instruction.trim()
          ? "hybrid"
          : "recording"
        : "natural_language",
      plan: draftPlan,
      enabled: true,
      createdAt: fistCommand?.createdAt ?? now,
      updatedAt: now,
    };
    const response = await send<{ ok: boolean; error?: string }>({
      version: 1,
      type: "signal:sidepanel/save-command",
      command,
    });
    if (!response.ok) {
      setBuilderStatus(response.error ?? "Signal rejected that command.");
      return;
    }
    setFistCommand(command);
    setEditorOpen(false);
    setBuilderStatus("Fist command saved locally in Chrome.");
  }

  async function toggleRecording() {
    const next = !recording;
    const response = await send<{
      ok: boolean;
      error?: string;
      plan?: unknown;
      name?: string;
      truncated?: boolean;
    }>({
      version: 1,
      type: next ? "signal:sidepanel/demo-start" : "signal:sidepanel/demo-stop",
    });
    if (!response.ok) {
      setBuilderStatus(response.error ?? "Demonstration capture is unavailable here.");
      return;
    }
    setRecording(next);
    if (next) {
      setDemoCaptured(false);
      setDraftPlan(null);
    } else if (response.plan) {
      setDemoCaptured(true);
      setDraftPlan(response.plan);
      if (response.name) setCommandName(response.name);
    }
    setBuilderStatus(
      next
        ? "Teaching is active. Use the page normally; passwords and sensitive fields are never captured."
        : response.truncated
          ? "Demonstration captured at the safe action limit. Review the plan; no video or values were saved."
          : "Demonstration captured as reviewed browser actions. No video or field values were saved.",
    );
  }

  async function exportProfile() {
    const response = await send<{ ok: boolean; profile?: unknown }>({
      version: 1,
      type: "signal:sidepanel/export",
    });
    if (!response.ok || !response.profile) return;
    const url = URL.createObjectURL(
      new Blob([JSON.stringify(response.profile, null, 2)], {
        type: "application/json",
      }),
    );
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = "signal-profile.json";
    anchor.click();
    URL.revokeObjectURL(url);
  }

  async function importProfile(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    try {
      const profile: unknown = JSON.parse(await file.text());
      const response = await send<{ ok: boolean; error?: string }>({
        version: 1,
        type: "signal:sidepanel/import",
        profile,
      });
      setBuilderStatus(
        response.ok ? "Profile imported and validated." : response.error ?? "Import failed.",
      );
    } catch {
      setBuilderStatus("That file is not valid Signal profile JSON.");
    }
  }

  async function saveTuning(next: { sensitivity?: number; smoothing?: number }) {
    const tuning = {
      sensitivity: next.sensitivity ?? sensitivity,
      smoothing: next.smoothing ?? smoothing,
    };
    setSensitivity(tuning.sensitivity);
    setSmoothing(tuning.smoothing);
    await send({ version: 1, type: "signal:sidepanel/tuning", tuning });
  }

  return (
    <main className="panel-shell">
      <header className="topbar">
        <div>
          <p className="eyebrow"><i /> Signal Extension</p>
          <h1>signal</h1>
          <p>Point, click, and run gestures together.</p>
        </div>
        <span className={`camera-pill camera-${runtime.camera}`}>{cameraLabel}</span>
      </header>

      {!runtime.activeTabSupported && (
        <div className="notice error" role="status">
          Page controls are unavailable here. Command gestures can still open tabs.
        </div>
      )}

      <section className="runtime-card" aria-label="Signal runtime">
        <div className="runtime-actions">
          {!runtime.running ? (
            <button className="primary" onClick={() => void start()}>Start Signal</button>
          ) : (
            <>
              <button onClick={() => void togglePause()}>
                {runtime.paused ? "Resume" : "Pause"}
              </button>
              <button className="danger" onClick={() => void stop()}>Stop</button>
            </>
          )}
        </div>
        {runtime.camera === "permission" && (
          <button className="permission-link" onClick={() => void openPermissionSetup()}>
            Grant camera permission
          </button>
        )}
        {runtime.running && runtime.camera === "running" && runtime.fps <= 0 && (
          <button className="permission-link" onClick={() => void openPermissionSetup()}>
            Repair zero-FPS camera
          </button>
        )}
        <div className="telemetry">
          <span><small>Gesture</small>{runtime.gesture ?? "No hand"}</span>
          <span><small>Confidence</small>{Math.round(runtime.confidence * 100)}%</span>
          <span><small>Active</small>Control + commands</span>
        </div>
        <p className="status" aria-live="polite">{runtime.status}</p>
      </section>

      <section className="commands">
        <div className="section-heading">
          <div>
            <p className="eyebrow">Command poses</p>
            <h2>Hold to run</h2>
          </div>
          {runtime.commandProgress !== undefined && (
            <span>{Math.round(runtime.commandProgress * 100)}%</span>
          )}
        </div>
        <div className="gesture-grid">
          {gestures.map(([id, mark, label]) => (
            <article className={runtime.gesture === id ? "active" : ""} key={id}>
              <strong>{mark}</strong>
              <div><b>{id.replace("_", " ")}</b><span>{label}</span></div>
            </article>
          ))}
          <button
            className={`gesture-card ${runtime.gesture === "fist" ? "active" : ""}`}
            onClick={() => setEditorOpen((open) => !open)}
          >
            <strong>●</strong>
            <div>
              <b>Fist</b>
              <span>{fistCommand?.name ?? "Custom Command"}</span>
            </div>
          </button>
        </div>
      </section>

      {editorOpen && (
        <section className="builder" aria-label="Fist command builder">
          <div className="section-heading">
            <div><p className="eyebrow">Programmable gesture</p><h2>Edit Fist</h2></div>
            <button className="icon-button" onClick={() => setEditorOpen(false)} aria-label="Close">×</button>
          </div>
          <label>
            What should Fist do?
            <textarea
              rows={4}
              value={instruction}
              onChange={(event) => setInstruction(event.target.value)}
            />
          </label>
          <div className="builder-row">
            <button onClick={() => void toggleRecording()}>
              {recording ? "Stop teaching" : "Teach by Demo"}
            </button>
            <button className="primary" disabled={busy} onClick={() => void generatePlan()}>
              {busy ? "Building…" : "Generate plan"}
            </button>
          </div>
          {draftPlan !== null && (
            <>
              <label>
                Command name
                <input value={commandName} onChange={(event) => setCommandName(event.target.value)} />
              </label>
              <details open>
                <summary>Review validated plan</summary>
                <pre>{JSON.stringify(draftPlan, null, 2)}</pre>
              </details>
              <button className="primary wide" onClick={() => void saveCommand()}>
                Save Fist command
              </button>
            </>
          )}
          <p className="builder-status" aria-live="polite">{builderStatus}</p>
        </section>
      )}

      <section className="utilities">
        <button onClick={() => void exportProfile()}>Export profile</button>
        <button onClick={() => importRef.current?.click()}>Import profile</button>
        <input
          hidden
          ref={importRef}
          type="file"
          accept="application/json"
          onChange={(event) => void importProfile(event)}
        />
        <button onClick={() => setSettingsOpen((open) => !open)}>Tuning</button>
      </section>

      {settingsOpen && (
        <section className="tuning">
          <label>
            Sensitivity <output>{sensitivity.toFixed(2)}</output>
            <input
              type="range"
              min="0.5"
              max="3"
              step="0.05"
              value={sensitivity}
              onChange={(event) => void saveTuning({ sensitivity: Number(event.target.value) })}
            />
          </label>
          <label>
            Smoothing <output>{smoothing.toFixed(2)}</output>
            <input
              type="range"
              min="0.05"
              max="0.9"
              step="0.01"
              value={smoothing}
              onChange={(event) => void saveTuning({ smoothing: Number(event.target.value) })}
            />
          </label>
        </section>
      )}

      <footer>
        Frames stay on this computer. Signal stores settings and reviewed commands—not camera video.
      </footer>
    </main>
  );
}
