import type { PresetGestureCommand } from "../../config/gestureCommands";

export function GestureCard({
  command,
  assignedName,
  active,
  progress,
  fired,
  updated,
  onClick,
  buttonRef,
}: {
  command: PresetGestureCommand;
  assignedName?: string;
  active: boolean;
  progress: number;
  fired: boolean;
  updated?: boolean;
  onClick(): void;
  buttonRef?: React.Ref<HTMLButtonElement>;
}) {
  const availability =
    command.availability === "ready"
      ? "Ready"
      : command.availability === "native_required"
        ? "Native companion"
        : "Unavailable";

  return (
    <button
      ref={buttonRef}
      type="button"
      className={[
        "signal-gesture-card",
        command.custom ? "signal-fist-card" : "",
        active ? "is-active" : "",
        fired ? "is-fired" : "",
        updated ? "is-updated" : "",
      ].filter(Boolean).join(" ")}
      data-gesture={command.gesture}
      aria-label={`${command.label}: ${assignedName ?? command.commandName}`}
      aria-pressed={active}
      onClick={onClick}
    >
      <span className="signal-gesture-topline">
        <span>{command.actionType}</span>
        <span>{fired ? "Command fired" : availability}</span>
      </span>
      <span className="signal-gesture-mark" aria-hidden="true">
        {command.mark}
      </span>
      <span className="signal-gesture-copy">
        <strong>{command.label}</strong>
        <span>{assignedName ?? command.commandName}</span>
      </span>
      <span
        className="signal-gesture-progress"
        aria-hidden="true"
        style={{ transform: `scaleX(${active ? Math.max(0.04, progress) : 0})` }}
      />
    </button>
  );
}
