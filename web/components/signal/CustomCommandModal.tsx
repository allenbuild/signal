"use client";

import { useEffect, useMemo, useRef, useState } from "react";

import {
  actionPlanSchema,
  actionTypeValues,
  plannerResponseSchema,
  type ActionPlan,
} from "../../lib/contracts";
import {
  signalCommandSchema,
  type CommandSource,
  type SignalCommand,
} from "../../lib/commands/schema";
import { ScreenRecorder, type BrowserRecording } from "./ScreenRecorder";

const DEFAULT_INSTRUCTION =
  "When I make a fist, open Spotify, wait one second, and start my focus playlist.";

export function CustomCommandModal({
  existingCommand,
  onClose,
  onSave,
}: {
  existingCommand: SignalCommand | null;
  onClose(): void;
  onSave(command: SignalCommand): void;
}) {
  const [stage, setStage] = useState<"compose" | "review">(
    existingCommand ? "review" : "compose",
  );
  const [instruction, setInstruction] = useState(DEFAULT_INSTRUCTION);
  const [recording, setRecording] = useState<BrowserRecording | null>(null);
  const [plan, setPlan] = useState<ActionPlan | null>(
    existingCommand?.plan ?? null,
  );
  const [commandName, setCommandName] = useState(
    existingCommand?.name ?? "My fist command",
  );
  const [source, setSource] = useState<CommandSource>(
    existingCommand?.source ?? "natural_language",
  );
  const [generator, setGenerator] = useState<"claude" | "fallback" | null>(
    null,
  );
  const [status, setStatus] = useState(
    existingCommand
      ? "Review the saved fist command or regenerate it."
      : "Describe a workflow, record a short demonstration, or combine both.",
  );
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [testReceipt, setTestReceipt] = useState("");
  const dialogRef = useRef<HTMLDivElement>(null);
  const nameInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const firstInput = dialogRef.current?.querySelector<HTMLElement>(
      "textarea, input, button",
    );
    firstInput?.focus();

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape" && !busy) {
        event.preventDefault();
        onClose();
        return;
      }
      if (event.key !== "Tab") return;
      const focusable = Array.from(
        dialogRef.current?.querySelectorAll<HTMLElement>(
          'button:not([disabled]), input:not([disabled]), textarea:not([disabled]), video[controls], [href]',
        ) ?? [],
      ).filter((element) => element.offsetParent !== null);
      if (focusable.length === 0) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    }

    document.addEventListener("keydown", handleKeyDown);
    return () => {
      document.body.style.overflow = previousOverflow;
      document.removeEventListener("keydown", handleKeyDown);
    };
  }, [busy, onClose]);

  const effectiveSource = useMemo<CommandSource>(() => {
    if (recording && instruction.trim()) return "hybrid";
    if (recording) return "recording";
    return "natural_language";
  }, [instruction, recording]);

  async function generatePlan() {
    if (!instruction.trim() && !recording) {
      setError("Describe the command or use a recording before generating.");
      return;
    }
    setBusy(true);
    setError("");
    setTestReceipt("");
    setStatus("Building a constrained version 1 plan…");
    const requestId = `web_${Date.now().toString(36)}`;
    const requestText =
      instruction.trim() ||
      "Use the recording context to propose a safe fist command. Ask for clarification if the intent is uncertain.";
    const payload = {
      schemaVersion: 1,
      requestId,
      request: requestText,
      targetGesture: "fist",
      actionCatalog: actionTypeValues,
      ...(recording
        ? {
            recording: {
              durationMs: recording.durationMs,
              mimeType: recording.mimeType,
              sizeBytes: recording.blob.size,
              keyframes: recording.keyframes,
            },
          }
        : {}),
    };

    try {
      const response = await fetch(
        recording ? "/api/v1/plan/demo" : "/api/v1/plan",
        {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify(payload),
        },
      );
      const body: unknown = await response.json();
      if (!response.ok) {
        const message =
          body &&
          typeof body === "object" &&
          "error" in body &&
          body.error &&
          typeof body.error === "object" &&
          "message" in body.error &&
          typeof body.error.message === "string"
            ? body.error.message
            : "Signal could not create a safe command plan.";
        throw new Error(message);
      }
      const parsed = plannerResponseSchema.safeParse(body);
      if (!parsed.success) {
        throw new Error("The planner returned an invalid command plan.");
      }
      if (parsed.data.status === "needs_clarification") {
        setError(parsed.data.question);
        setStatus("One detail is needed before Signal can build the plan.");
        return;
      }
      setPlan(parsed.data.plan);
      setCommandName(parsed.data.plan.name);
      setSource(effectiveSource);
      setGenerator(
        parsed.data.usedDeterministicFallback ? "fallback" : "claude",
      );
      setStatus(
        parsed.data.usedDeterministicFallback
          ? "Built with Signal’s deterministic fallback. Claude was not used."
          : "Built with Claude and validated against Signal schema version 1.",
      );
      setStage("review");
      window.setTimeout(() => nameInputRef.current?.focus(), 0);
    } catch (caught) {
      setError(
        caught instanceof Error
          ? caught.message
          : "Signal could not create a command plan.",
      );
      setStatus(
        "Natural-language creation remains available. Recording is optional.",
      );
    } finally {
      setBusy(false);
    }
  }

  function updateSteps(nextSteps: ActionPlan["steps"]) {
    if (!plan || nextSteps.length === 0) return;
    const nextPlan = {
      ...plan,
      steps: nextSteps,
      timeoutMs: Math.min(
        300_000,
        Math.max(
          100,
          nextSteps.reduce((sum, step) => sum + step.timeoutMs, 0) + 3_000,
        ),
      ),
    };
    const parsed = actionPlanSchema.safeParse(nextPlan);
    if (parsed.success) {
      setPlan(parsed.data);
      setTestReceipt("");
    } else {
      setError("That edit would make the plan invalid.");
    }
  }

  function moveStep(index: number, direction: -1 | 1) {
    if (!plan) return;
    const target = index + direction;
    if (target < 0 || target >= plan.steps.length) return;
    const next = [...plan.steps];
    [next[index], next[target]] = [next[target], next[index]];
    updateSteps(next);
  }

  function saveCommand() {
    if (!plan) return;
    const now = new Date().toISOString();
    const parsed = signalCommandSchema.safeParse({
      schemaVersion: 1,
      id: existingCommand?.id ?? `fist-${crypto.randomUUID()}`,
      gesture: "fist",
      name: commandName.trim(),
      description:
        instruction.trim().slice(0, 500) ||
        "Command created with a browser demonstration.",
      source,
      plan: { ...plan, name: commandName.trim() },
      createdAt: existingCommand?.createdAt ?? now,
      updatedAt: now,
      enabled: true,
    });
    if (!parsed.success) {
      setError("Give the command a short name before saving.");
      return;
    }
    onSave(parsed.data);
  }

  return (
    <div className="signal-modal-backdrop">
      <div
        ref={dialogRef}
        className="signal-command-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="signal-command-title"
        aria-describedby="signal-command-description"
      >
        <header className="signal-modal-header">
          <div>
            <p className="signal-kicker">
              {stage === "compose" ? "Create fist command" : "Review command"}
            </p>
            <h2 id="signal-command-title">
              {stage === "compose"
                ? "Tell Signal what to do."
                : "Confirm every step."}
            </h2>
            <p id="signal-command-description">
              {stage === "compose"
                ? "Describe it, teach it by recording, or combine both."
                : "This plan is data to review. Saving does not execute it."}
            </p>
          </div>
          <button
            type="button"
            className="signal-modal-close"
            aria-label="Close custom command editor"
            onClick={onClose}
            disabled={busy}
          >
            ×
          </button>
        </header>

        <div className="signal-flow-steps" aria-label="Command creation steps">
          {["Describe", "Record", "Generate", "Review", "Assign"].map(
            (label, index) => (
              <span
                key={label}
                className={
                  stage === "review" || index < 2 ? "is-current" : ""
                }
              >
                <i>{index + 1}</i>{label}
              </span>
            ),
          )}
        </div>

        {stage === "compose" ? (
          <div className="signal-compose-grid">
            <section className="signal-natural-builder">
              <p className="signal-kicker">Natural language</p>
              <label htmlFor="signal-command-instruction">
                What should happen when you make a fist?
              </label>
              <textarea
                id="signal-command-instruction"
                value={instruction}
                onChange={(event) => setInstruction(event.target.value)}
                maxLength={4000}
                placeholder="When I make a fist, open Spotify, wait one second, and start my focus playlist."
              />
              <p>
                Signal generates allowlisted actions only—never shell commands
                or raw AppleScript.
              </p>
              {recording && (
                <div className="signal-recording-attached">
                  <strong>Recording context attached</strong>
                  <span>
                    {Math.round(recording.durationMs / 100) / 10}s ·{" "}
                    {recording.keyframes.length} compressed keyframes · raw video local
                  </span>
                </div>
              )}
            </section>
            <ScreenRecorder onUse={setRecording} />
          </div>
        ) : (
          <div className="signal-review">
            <div className="signal-review-toolbar">
              <label>
                Command name
                <input
                  ref={nameInputRef}
                  value={commandName}
                  onChange={(event) => setCommandName(event.target.value)}
                  maxLength={80}
                />
              </label>
              <span className={`signal-generator-badge ${generator ?? ""}`}>
                {generator === "claude"
                  ? "Generated by Claude"
                  : generator === "fallback"
                    ? "Deterministic fallback"
                    : "Saved version 1 plan"}
              </span>
            </div>

            <ol className="signal-review-steps">
              {plan?.steps.map((step, index) => (
                <li key={step.id}>
                  <span className="signal-review-number">
                    {String(index + 1).padStart(2, "0")}
                  </span>
                  <div>
                    <strong>{summarizeAction(step.action)}</strong>
                    <span>
                      {step.action.type.replaceAll("_", " ")} ·{" "}
                      {step.confirmation.mode.replaceAll("_", " ")} confirmation
                    </span>
                  </div>
                  <div className="signal-step-buttons">
                    <button
                      type="button"
                      aria-label={`Move step ${index + 1} up`}
                      onClick={() => moveStep(index, -1)}
                      disabled={index === 0}
                    >
                      ↑
                    </button>
                    <button
                      type="button"
                      aria-label={`Move step ${index + 1} down`}
                      onClick={() => moveStep(index, 1)}
                      disabled={!plan || index === plan.steps.length - 1}
                    >
                      ↓
                    </button>
                    <button
                      type="button"
                      aria-label={`Remove step ${index + 1}`}
                      onClick={() =>
                        plan &&
                        updateSteps(
                          plan.steps.filter((_, stepIndex) => stepIndex !== index),
                        )
                      }
                      disabled={!plan || plan.steps.length === 1}
                    >
                      ×
                    </button>
                  </div>
                </li>
              ))}
            </ol>
            <div className="signal-plan-note">
              <strong>Native boundary</strong>
              <span>
                The browser can preview this plan. Allen’s native app validates
                it again before any system-wide action.
              </span>
            </div>
          </div>
        )}

        <div className="signal-modal-status">
          <p role="status" aria-live="polite">{status}</p>
          {error && <p className="error" role="alert">{error}</p>}
          {testReceipt && <p className="receipt" role="status">{testReceipt}</p>}
        </div>

        <footer className="signal-modal-footer">
          {stage === "review" ? (
            <>
              <button
                type="button"
                className="signal-button signal-button-quiet"
                onClick={() => setStage("compose")}
              >
                Regenerate or retake
              </button>
              <button
                type="button"
                className="signal-button signal-button-secondary"
                onClick={() =>
                  setTestReceipt(
                    "Simulated preview complete. Native system actions performed: 0.",
                  )
                }
              >
                Test preview
              </button>
              <button
                type="button"
                className="signal-button signal-button-primary"
                onClick={saveCommand}
              >
                Save to Fist
              </button>
            </>
          ) : (
            <>
              <button
                type="button"
                className="signal-button signal-button-quiet"
                onClick={onClose}
                disabled={busy}
              >
                Cancel
              </button>
              <button
                type="button"
                className="signal-button signal-button-primary"
                onClick={() => void generatePlan()}
                disabled={busy}
              >
                {busy ? "Generating…" : "Generate structured command"}
              </button>
            </>
          )}
        </footer>
      </div>
    </div>
  );
}

function summarizeAction(action: ActionPlan["steps"][number]["action"]) {
  switch (action.type) {
    case "open_application":
      return `Open ${action.parameters.applicationName ?? action.parameters.bundleIdentifier}`;
    case "open_url":
      return `Open ${action.parameters.url}`;
    case "open_deep_link":
      return `Open reviewed ${action.parameters.scheme} link`;
    case "wait":
      return `Wait ${action.parameters.durationMs / 1000} seconds`;
    case "speak_text":
      return `Say “${action.parameters.text}”`;
    case "show_notification":
      return `Show notification “${action.parameters.title}”`;
    case "discord_webhook":
      return `Send “${action.parameters.message}” to Discord`;
    case "media_control":
      return `Media: ${action.parameters.command.replaceAll("_", " ")}`;
    case "set_volume":
      return `Set volume to ${action.parameters.percent}%`;
    case "type_text":
      return `Type reviewed text`;
    default:
      return action.type.replaceAll("_", " ");
  }
}
