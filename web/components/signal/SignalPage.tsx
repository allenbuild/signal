"use client";

import Link from "next/link";
import { ChangeEvent, useEffect, useRef, useState } from "react";

import {
  fistGesture,
  gestureCommands,
  presetGestures,
  type GestureId,
} from "../../config/gestureCommands";
import {
  FIST_COMMAND_STORAGE_KEY,
  loadSavedFistCommand,
  saveFistCommand,
  signalCommandSchema,
  type SignalCommand,
} from "../../lib/commands/schema";
import { useSignalGestureBridge } from "../../lib/gestures/useSignalGestureBridge";
import { CustomCommandModal } from "./CustomCommandModal";
import { GestureCard } from "./GestureCard";

export function SignalPage() {
  const [customCommand, setCustomCommand] = useState<SignalCommand | null>(null);
  const [editorOpen, setEditorOpen] = useState(false);
  const [previewGesture, setPreviewGesture] = useState<GestureId | null>(null);
  const [status, setStatus] = useState(
    "Gesture bridge ready. Waiting for normalized input.",
  );
  const [updated, setUpdated] = useState(false);
  const fistButtonRef = useRef<HTMLButtonElement>(null);
  const importInputRef = useRef<HTMLInputElement>(null);
  const bridge = useSignalGestureBridge({ disabled: editorOpen });

  useEffect(() => {
    const initialization = window.setTimeout(() => {
      const saved = loadSavedFistCommand(window.localStorage);
      if (saved) setCustomCommand(saved);
    }, 0);
    return () => window.clearTimeout(initialization);
  }, []);

  const bridgeStatus = bridge.activeGesture
    ? bridge.lastFiredGesture === bridge.activeGesture
      ? `${
          gestureCommands.find(
            (command) => command.gesture === bridge.activeGesture,
          )?.label
        } command fired. Execution is delegated to the native companion.`
      : `${
          gestureCommands.find(
            (command) => command.gesture === bridge.activeGesture,
          )?.label
        } detected at ${Math.round(bridge.confidence * 100)}% confidence.`
    : status;

  function closeEditor() {
    setEditorOpen(false);
    window.setTimeout(() => fistButtonRef.current?.focus(), 0);
  }

  function handleSave(command: SignalCommand) {
    saveFistCommand(window.localStorage, command);
    setCustomCommand(command);
    setUpdated(true);
    setStatus(`${command.name} assigned to Fist and saved locally.`);
    setEditorOpen(false);
    window.setTimeout(() => {
      setUpdated(false);
      fistButtonRef.current?.focus();
    }, 1_200);
  }

  function exportCommand() {
    if (!customCommand) return;
    const blob = new Blob(
      [
        JSON.stringify(
          { storageVersion: 1, command: customCommand },
          null,
          2,
        ),
      ],
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
        value &&
        typeof value === "object" &&
        "command" in value
          ? (value as { command: unknown }).command
          : value;
      const parsed = signalCommandSchema.safeParse(candidate);
      if (!parsed.success || parsed.data.gesture !== "fist") {
        throw new Error("invalid");
      }
      saveFistCommand(window.localStorage, parsed.data);
      setCustomCommand(parsed.data);
      setUpdated(true);
      setStatus(`${parsed.data.name} imported and assigned to Fist.`);
      window.setTimeout(() => setUpdated(false), 1_200);
    } catch {
      setStatus(
        "Import rejected: use a strict Signal version 1 fist command.",
      );
    }
  }

  function resetCommand() {
    window.localStorage.removeItem(FIST_COMMAND_STORAGE_KEY);
    setCustomCommand(null);
    setPreviewGesture(null);
    setStatus("Fist reset to the editable default.");
  }

  const preview = previewGesture
    ? gestureCommands.find((command) => command.gesture === previewGesture)
    : null;

  return (
    <main id="main-content" className="signal-command-page">
      <div className="signal-ambient-light" aria-hidden="true" />
      <header className="signal-command-statusbar">
        <span>
          <i aria-hidden="true" /> Bridge ready
        </span>
        <nav aria-label="Signal product links">
          <span>Output preview only</span>
          <Link href="/builder">Profile builder</Link>
          <Link href="/download">Mac app</Link>
        </nav>
      </header>

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
            onClick={() => {
              setPreviewGesture(null);
              setEditorOpen(true);
            }}
          />
        </div>

        <p className="signal-bridge-status" role="status" aria-live="polite">
          {bridgeStatus}
        </p>

        {preview && (
          <aside className="signal-command-preview" aria-live="polite">
            <div>
              <p className="signal-kicker">Locked preset · {preview.actionType}</p>
              <h2>{preview.commandName}</h2>
              <p>{preview.description}</p>
            </div>
            <button
              type="button"
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
            onClick={() => importInputRef.current?.click()}
          >
            Import fist JSON
          </button>
          {customCommand && (
            <>
              <button type="button" onClick={exportCommand}>
                Export fist JSON
              </button>
              <button type="button" onClick={resetCommand}>
                Reset fist
              </button>
            </>
          )}
        </div>
      </section>

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
