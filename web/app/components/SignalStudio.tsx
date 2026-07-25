"use client";

import { useMemo, useState } from "react";

const choices = [
  ["thumbs_up", "↑", "Thumbs up"],
  ["c_shape", "C", "C shape"],
  ["five", "05", "Five"],
] as const;

type PlanStep = {
  id: string;
  action: { type: string; parameters: Record<string, unknown> };
};

type Planned = {
  status: "planned";
  plan: {
    id: string;
    name: string;
    description: string;
    steps: PlanStep[];
    [key: string]: unknown;
  };
  warnings: string[];
};

const actionLabels: Record<string, string> = {
  open_url: "Open focus playlist",
  speak_text: "Say “Focus mode”",
  discord_webhook: "Send “Demo complete”",
  open_application: "Open TextEdit",
  keyboard_shortcut: "Press Command–N",
  type_text: "Type the taught phrase",
};

export function SignalStudio() {
  const [gesture, setGesture] = useState<(typeof choices)[number][0]>("thumbs_up");
  const [prompt, setPrompt] = useState(
    "When I give a thumbs up, open my focus playlist, say Focus mode, and send Demo complete to Discord.",
  );
  const [plan, setPlan] = useState<Planned | null>(null);
  const [status, setStatus] = useState<"idle" | "loading" | "error">("idle");
  const [shareCode, setShareCode] = useState("");
  const selected = useMemo(() => choices.find((choice) => choice[0] === gesture)!, [gesture]);

  async function interpret() {
    setStatus("loading");
    setShareCode("");
    try {
      const response = await fetch("/api/v1/plan", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          schemaVersion: 1,
          requestId: `web-${Date.now()}`,
          request: prompt,
          targetGesture: gesture,
          actionCatalog: [
            "open_url",
            "speak_text",
            "discord_webhook",
            "open_application",
            "keyboard_shortcut",
            "type_text",
          ],
        }),
      });
      const data = await response.json() as Planned;
      if (!response.ok || data.status !== "planned") throw new Error("not planned");
      setPlan(data);
      setStatus("idle");
    } catch {
      setPlan(null);
      setStatus("error");
    }
  }

  async function publish() {
    if (!plan) return;
    setStatus("loading");
    try {
      const response = await fetch("/api/v1/profiles", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          profile: {
            schemaVersion: 1,
            id: `signal.web.${gesture}`,
            name: `${selected[2]} workflow`,
            description: plan.plan.description,
            preferredMode: "hybrid",
            hybridOneBehavior: "pointer",
            mappings: [{
              gesture,
              enabled: true,
              holdDurationMs: gesture === "c_shape" ? 650 : 600,
              cooldownMs: 900,
              activation: "one_shot",
              allowedBundleIdentifiers: [],
              preferredMode: "commands",
              plan: plan.plan,
            }],
            share: { visibility: "unlisted" },
          },
        }),
      });
      const data = await response.json() as { shareCode?: string };
      if (!response.ok) throw new Error("not shared");
      if (!data.shareCode) throw new Error("missing share code");
      setShareCode(data.shareCode);
      setStatus("idle");
    } catch {
      setStatus("error");
    }
  }

  return (
    <div className="studio">
      <div className="studio-sidebar">
        <div className="studio-label">1 / CHOOSE GESTURE</div>
        {choices.map(([id, symbol, label]) => (
          <button
            className={gesture === id ? "gesture-choice active" : "gesture-choice"}
            key={id}
            onClick={() => {
              setGesture(id);
              setPlan(null);
              setShareCode("");
            }}
            type="button"
          >
            <span>{symbol}</span><b>{label}</b><i />
          </button>
        ))}
        <p>Three demo choices shown. Signal supports all nine gestures.</p>
      </div>
      <div className="studio-workspace">
        <div className="studio-label">2 / DESCRIBE WORKFLOW</div>
        <label htmlFor="signal-prompt">What should {selected[2].toLowerCase()} do?</label>
        <textarea
          id="signal-prompt"
          value={prompt}
          onChange={(event) => setPrompt(event.target.value)}
          maxLength={4000}
        />
        <div className="prompt-footer">
          <span><i className="green-dot" /> Seeded demo works without an AI key</span>
          <button className="button button-primary" type="button" onClick={interpret} disabled={status === "loading"}>
            {status === "loading" ? "Working…" : "Build plan"} <span>→</span>
          </button>
        </div>
      </div>
      <div className="studio-plan">
        <div className="studio-label">3 / REVIEW PLAN</div>
        {plan ? (
          <>
            <div className="plan-title"><span>{selected[1]}</span><div><b>{plan.plan.name}</b><small>{plan.plan.steps.length} steps · approval required</small></div></div>
            <ol className="plan-steps">
              {plan.plan.steps.map((step, index) => (
                <li key={step.id}><span>{String(index + 1).padStart(2, "0")}</span><p><b>{actionLabels[step.action.type] ?? step.action.type.replaceAll("_", " ")}</b><small>Validated action</small></p><i>✓</i></li>
              ))}
            </ol>
            <button className="publish-button" type="button" onClick={publish} disabled={status === "loading"}>
              Publish unlisted profile <span>↗</span>
            </button>
            {shareCode && <a className="share-result" href={`/p/${shareCode}`}>Shared as <b>{shareCode}</b> →</a>}
          </>
        ) : (
          <div className="plan-empty">
            <span>{selected[1]}</span>
            <p>{status === "error" ? "The planner is unavailable. Try the seeded focus phrase." : "Your validated steps will appear here."}</p>
          </div>
        )}
      </div>
    </div>
  );
}
