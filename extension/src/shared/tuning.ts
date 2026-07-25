import type { GestureTuning, SignalSettings } from "./types";

export const DEFAULT_SETTINGS: Readonly<SignalSettings> = Object.freeze({
  mode: "control",
  hideSiteCursor: false,
  resetCursorOnTabChange: true,
  naturalScroll: true,
  useSyncSettings: true,
});

export const DEFAULT_TUNING: Readonly<GestureTuning> = Object.freeze({
  holdMs: 550,
  cooldownMs: 800,
  minimumConfidence: 0.72,
  pointerSensitivity: 1.35,
  pointerSmoothing: 0.34,
  pointerDeadZone: 0.002,
  pointerAcceleration: 1.1,
  pointerMaxFrameMovement: 64,
  scrollRateLimitMs: 16,
  zoomRateLimitMs: 90,
});

const finite = (value: unknown, fallback: number, min: number, max: number) =>
  typeof value === "number" && Number.isFinite(value)
    ? Math.min(max, Math.max(min, value))
    : fallback;

export function sanitizeTuning(
  value: Partial<GestureTuning> | null | undefined,
): GestureTuning {
  return {
    holdMs: finite(value?.holdMs, DEFAULT_TUNING.holdMs, 250, 3_000),
    cooldownMs: finite(
      value?.cooldownMs,
      DEFAULT_TUNING.cooldownMs,
      0,
      10_000,
    ),
    minimumConfidence: finite(
      value?.minimumConfidence,
      DEFAULT_TUNING.minimumConfidence,
      0.5,
      1,
    ),
    pointerSensitivity: finite(
      value?.pointerSensitivity,
      DEFAULT_TUNING.pointerSensitivity,
      0.2,
      4,
    ),
    pointerSmoothing: finite(
      value?.pointerSmoothing,
      DEFAULT_TUNING.pointerSmoothing,
      0.05,
      1,
    ),
    pointerDeadZone: finite(
      value?.pointerDeadZone,
      DEFAULT_TUNING.pointerDeadZone,
      0,
      0.1,
    ),
    pointerAcceleration: finite(
      value?.pointerAcceleration,
      DEFAULT_TUNING.pointerAcceleration,
      0,
      4,
    ),
    pointerMaxFrameMovement: finite(
      value?.pointerMaxFrameMovement,
      DEFAULT_TUNING.pointerMaxFrameMovement,
      4,
      200,
    ),
    scrollRateLimitMs: finite(
      value?.scrollRateLimitMs,
      DEFAULT_TUNING.scrollRateLimitMs,
      8,
      250,
    ),
    zoomRateLimitMs: finite(
      value?.zoomRateLimitMs,
      DEFAULT_TUNING.zoomRateLimitMs,
      40,
      1_000,
    ),
  };
}

export function sanitizeSettings(
  value: Partial<SignalSettings> | null | undefined,
): SignalSettings {
  const mode =
    value?.mode === "control" ||
    value?.mode === "commands" ||
    value?.mode === "paused"
      ? value.mode
      : DEFAULT_SETTINGS.mode;
  return {
    mode,
    hideSiteCursor:
      typeof value?.hideSiteCursor === "boolean"
        ? value.hideSiteCursor
        : DEFAULT_SETTINGS.hideSiteCursor,
    resetCursorOnTabChange:
      typeof value?.resetCursorOnTabChange === "boolean"
        ? value.resetCursorOnTabChange
        : DEFAULT_SETTINGS.resetCursorOnTabChange,
    naturalScroll:
      typeof value?.naturalScroll === "boolean"
        ? value.naturalScroll
        : DEFAULT_SETTINGS.naturalScroll,
    useSyncSettings:
      typeof value?.useSyncSettings === "boolean"
        ? value.useSyncSettings
        : DEFAULT_SETTINGS.useSyncSettings,
  };
}
