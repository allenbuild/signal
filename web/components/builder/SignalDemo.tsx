"use client";

import { useRef, useState } from "react";

const DEMO_GESTURES = [
  { id: "one", label: "One", mark: "1" },
  { id: "two", label: "Two", mark: "2" },
  { id: "three", label: "Three", mark: "3" },
  { id: "four", label: "Four", mark: "4" },
  { id: "five", label: "Five", mark: "5" },
  { id: "fist", label: "Fist", mark: "✊" },
  { id: "thumbs_up", label: "Thumbs up", mark: "↑" },
  { id: "thumbs_down", label: "Thumbs down", mark: "↓" },
  { id: "c_shape", label: "C shape", mark: "C" },
] as const;

type DemoGesture = (typeof DEMO_GESTURES)[number]["id"];

type DemoStep = {
  title: string;
  detail: string;
  capability: "Browser-safe" | "Native Mac required" | "Cloud action";
  receipt: string;
};

type DemoReceipt = DemoStep & {
  state: "simulated" | "fallback";
};

const focusDemo: DemoStep[] = [
  {
    title: "Open focus playlist",
    detail: "https://open.spotify.com/",
    capability: "Browser-safe",
    receipt: "Browser navigation previewed",
  },
  {
    title: "Say “Focus mode”",
    detail: "Local speech action",
    capability: "Native Mac required",
    receipt: "Speech caption simulated",
  },
  {
    title: "Send “Demo complete”",
    detail: "Configured Discord secret reference",
    capability: "Cloud action",
    receipt: "Local fallback receipt — no message sent",
  },
];

const teachDemo: DemoStep[] = [
  {
    title: "Open TextEdit",
    detail: "com.apple.TextEdit",
    capability: "Native Mac required",
    receipt: "App launch simulated",
  },
  {
    title: "Create a new document",
    detail: "Command-N",
    capability: "Native Mac required",
    receipt: "Keyboard shortcut simulated",
  },
  {
    title: "Type reviewed demo text",
    detail: "“Signal replayed this workflow with a hand gesture.”",
    capability: "Native Mac required",
    receipt: "Text entry simulated",
  },
];

function stepsForGesture(gesture: DemoGesture): DemoStep[] {
  if (gesture === "thumbs_up") return focusDemo;
  if (gesture === "c_shape") return teachDemo;
  const label =
    DEMO_GESTURES.find((candidate) => candidate.id === gesture)?.label ??
    gesture;
  return [
    {
      title: `Recognize ${label}`,
      detail: "Mocked gesture input",
      capability: "Browser-safe",
      receipt: `${label} recognition simulated`,
    },
    {
      title: "Show a completion overlay",
      detail: `${label} command is ready`,
      capability: "Native Mac required",
      receipt: "Mac overlay simulated",
    },
  ];
}

function wait(durationMs: number) {
  return new Promise<void>((resolve) => {
    window.setTimeout(resolve, durationMs);
  });
}

export function SignalDemo() {
  const [selectedGesture, setSelectedGesture] =
    useState<DemoGesture>("thumbs_up");
  const [running, setRunning] = useState(false);
  const [receipts, setReceipts] = useState<DemoReceipt[]>([]);
  const [status, setStatus] = useState(
    "Choose a mocked gesture, then run the in-page simulation.",
  );
  const runToken = useRef(0);

  const gesture =
    DEMO_GESTURES.find((candidate) => candidate.id === selectedGesture) ??
    DEMO_GESTURES[0];
  const steps = stepsForGesture(selectedGesture);

  async function runSimulation() {
    const token = runToken.current + 1;
    runToken.current = token;
    setRunning(true);
    setReceipts([]);
    setStatus(`Holding ${gesture.label} for a simulated 600 milliseconds…`);
    await wait(600);
    if (runToken.current !== token) return;
    setStatus(`${gesture.label} recognized in mock input. Simulating the plan…`);

    for (const step of steps) {
      await wait(450);
      if (runToken.current !== token) return;
      setReceipts((current) => [
        ...current,
        {
          ...step,
          state: step.capability === "Cloud action" ? "fallback" : "simulated",
        },
      ]);
    }

    if (runToken.current !== token) return;
    setRunning(false);
    setStatus(
      `Simulation complete. ${steps.length} simulated receipts. System actions performed: 0.`,
    );
  }

  function chooseGesture(nextGesture: DemoGesture) {
    runToken.current += 1;
    setRunning(false);
    setReceipts([]);
    setSelectedGesture(nextGesture);
    const label =
      DEMO_GESTURES.find((candidate) => candidate.id === nextGesture)?.label ??
      nextGesture;
    setStatus(`${label} selected. Ready to simulate inside this page.`);
  }

  return (
    <main className="demo-page">
      <header className="demo-hero">
        <div className="demo-hero-copy">
          <p className="eyebrow">Browser simulator · Mock input</p>
          <h1>Try a command, safely.</h1>
          <p className="lede">
            See how a gesture becomes a reviewed timeline and typed receipt.
            This browser demo never moves your Mac cursor, launches an app, or
            sends an integration message.
          </p>
        </div>
        <div className="demo-boundary-card" role="note">
          <span className="demo-boundary-icon" aria-hidden="true">
            ◎
          </span>
          <div>
            <strong>Page-local simulation</strong>
            <p>Camera off · Mac control unavailable · No external effects</p>
          </div>
        </div>
      </header>

      <section className="demo-stage" aria-labelledby="demo-stage-heading">
        <aside className="demo-gesture-panel">
          <div className="section-heading">
            <p className="eyebrow">Mock input</p>
            <h2 id="demo-stage-heading">Choose a gesture</h2>
            <p>All nine command gestures are represented as labeled controls.</p>
          </div>
          <div className="demo-gesture-grid">
            {DEMO_GESTURES.map((candidate) => (
              <button
                type="button"
                key={candidate.id}
                className={`demo-gesture-button${
                  candidate.id === selectedGesture ? " selected" : ""
                }`}
                aria-pressed={candidate.id === selectedGesture}
                onClick={() => chooseGesture(candidate.id)}
              >
                <span className="gesture-mark" aria-hidden="true">
                  {candidate.mark}
                </span>
                <span>{candidate.label}</span>
              </button>
            ))}
          </div>
        </aside>

        <div className="demo-simulator">
          <div className="simulator-toolbar">
            <div className="simulator-lights" aria-hidden="true">
              <span />
              <span />
              <span />
            </div>
            <span>Signal receipt preview</span>
            <span className="simulated-badge">SIMULATED</span>
          </div>

          <div className="simulator-canvas">
            <div className={`gesture-orbit${running ? " active" : ""}`}>
              <div className="gesture-orbit-ring" aria-hidden="true" />
              <span className="gesture-orbit-mark" aria-hidden="true">
                {gesture.mark}
              </span>
              <strong>{gesture.label}</strong>
              <small>{running ? "Mock recognition in progress" : "Ready"}</small>
            </div>

            <div
              className={`demo-status${running ? " running" : ""}`}
              role="status"
              aria-live="polite"
            >
              <span className="status-dot" aria-hidden="true" />
              <p>{status}</p>
            </div>

            <button
              className="button button-primary primary demo-run-button"
              type="button"
              disabled={running}
              onClick={() => void runSimulation()}
            >
              {running
                ? `Simulating ${gesture.label}…`
                : `Run ${gesture.label} simulation`}
            </button>
            <p className="demo-input-help">
              This button is the keyboard- and touch-accessible alternative to a
              timed hand hold.
            </p>
          </div>
        </div>

        <aside className="demo-plan-panel" aria-labelledby="demo-plan-heading">
          <div className="section-heading">
            <p className="eyebrow">Reviewed plan</p>
            <h2 id="demo-plan-heading">
              {selectedGesture === "thumbs_up"
                ? "Focus mode"
                : selectedGesture === "c_shape"
                  ? "Replay recorded note"
                  : `${gesture.label} sample`}
            </h2>
            <p>{steps.length} bounded version 1 steps.</p>
          </div>

          <ol className="demo-step-list">
            {steps.map((step, index) => {
              const receipt = receipts[index];
              return (
                <li
                  className={`demo-step${receipt ? " complete" : ""}`}
                  key={`${step.title}-${index}`}
                >
                  <span className="step-number" aria-hidden="true">
                    {String(index + 1).padStart(2, "0")}
                  </span>
                  <div>
                    <span className="capability-chip">{step.capability}</span>
                    <h3>{step.title}</h3>
                    <p>{step.detail}</p>
                    {receipt && (
                      <div
                        className={`demo-receipt ${receipt.state}`}
                        role="status"
                      >
                        <strong>
                          {receipt.state === "fallback"
                            ? "LOCAL FALLBACK"
                            : "SIMULATED"}
                        </strong>
                        <span>{receipt.receipt}</span>
                      </div>
                    )}
                  </div>
                </li>
              );
            })}
          </ol>

          <div className="demo-receipt-summary" aria-live="polite">
            <span>
              {receipts.length} / {steps.length} simulated receipts
            </span>
            <strong>External effects: 0</strong>
          </div>
        </aside>
      </section>

      <section className="demo-explainer" aria-labelledby="demo-boundary-heading">
        <div>
          <p className="eyebrow">The honest boundary</p>
          <h2 id="demo-boundary-heading">
            The browser explains. The Mac app acts.
          </h2>
        </div>
        <div className="demo-boundary-grid">
          <article>
            <span aria-hidden="true">01</span>
            <h3>Browser</h3>
            <p>
              Build profiles, preview plans, simulate receipts, and share
              redacted mappings.
            </p>
          </article>
          <article>
            <span aria-hidden="true">02</span>
            <h3>Signal for Mac</h3>
            <p>
              Recognize live gestures and perform approved system-wide actions
              with a visible safety gate.
            </p>
          </article>
          <article>
            <span aria-hidden="true">03</span>
            <h3>Your approval</h3>
            <p>
              Validate every imported plan, inspect every effect, and approve it
              before save or first run.
            </p>
          </article>
        </div>
        <div className="demo-cta">
          <div>
            <strong>Ready for real system-wide control?</strong>
            <p>Download the verified Mac release or build your own profile.</p>
          </div>
          <div className="demo-cta-actions">
            <a className="button button-secondary secondary" href="/builder">
              Open builder
            </a>
            <a className="button button-primary primary" href="/download">
              Download Signal
            </a>
          </div>
        </div>
      </section>
    </main>
  );
}

export default SignalDemo;
