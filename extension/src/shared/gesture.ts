import type { GestureProgressMessage } from "./messages";
import { GESTURE_IDS, type GestureId, type SignalMode } from "./types";
import { DEFAULT_TUNING } from "./tuning";

export type GestureDetection = {
  gesture: GestureId | null;
  confidence: number;
  timestamp: number;
};

export type GestureExecutionContext = {
  mode: SignalMode;
  editing: boolean;
  supportedTab: boolean;
};

export type CommandGestureUpdate = GestureProgressMessage & {
  firedNow: boolean;
};

export type CommandGestureEngineOptions = {
  holdMs?: number;
  cooldownMs?: number;
  minimumConfidence?: number;
};

export class CommandGestureEngine {
  private candidate: GestureId | null = null;
  private candidateStartedAt = 0;
  private firedForCandidate = false;
  private latchedGesture: GestureId | null = null;
  private readonly lastFireAt = new Map<GestureId, number>();
  private readonly holdMs: number;
  private readonly cooldownMs: number;
  private readonly minimumConfidence: number;

  constructor(options: CommandGestureEngineOptions = {}) {
    this.holdMs = Math.max(1, options.holdMs ?? DEFAULT_TUNING.holdMs);
    this.cooldownMs = Math.max(
      0,
      options.cooldownMs ?? DEFAULT_TUNING.cooldownMs,
    );
    this.minimumConfidence = Math.min(
      1,
      Math.max(
        0,
        options.minimumConfidence ?? DEFAULT_TUNING.minimumConfidence,
      ),
    );
  }

  reset(
    timestamp = Date.now(),
    preserveFiredGesture = false,
  ): CommandGestureUpdate | null {
    const released = this.candidate ?? this.latchedGesture;
    this.latchedGesture =
      preserveFiredGesture &&
      (this.firedForCandidate || this.latchedGesture !== null)
        ? (this.candidate ?? this.latchedGesture)
        : null;
    this.candidate = null;
    this.candidateStartedAt = 0;
    this.firedForCandidate = false;
    return released
      ? this.result(released, "released", 0, 0, timestamp, false)
      : null;
  }

  update(
    detection: GestureDetection,
    context: GestureExecutionContext,
  ): CommandGestureUpdate | null {
    const confidence = Math.min(1, Math.max(0, detection.confidence));
    const validGesture =
      detection.gesture &&
      GESTURE_IDS.includes(detection.gesture) &&
      confidence >= this.minimumConfidence
        ? detection.gesture
        : null;

    if (validGesture && validGesture === this.latchedGesture) {
      return this.result(
        validGesture,
        "holding",
        confidence,
        1,
        detection.timestamp,
        false,
      );
    }
    if (validGesture && validGesture !== this.latchedGesture) {
      this.latchedGesture = null;
    }

    if (
      !validGesture ||
      context.mode === "paused" ||
      context.editing ||
      !context.supportedTab
    ) {
      const previous = this.reset(detection.timestamp);
      if (!validGesture) return previous;
      return this.result(
        validGesture,
        "suppressed",
        confidence,
        0,
        detection.timestamp,
        false,
      );
    }

    if (validGesture !== this.candidate) {
      this.candidate = validGesture;
      this.candidateStartedAt = detection.timestamp;
      this.firedForCandidate = false;
      return this.result(
        validGesture,
        "detected",
        confidence,
        0,
        detection.timestamp,
        false,
      );
    }

    const elapsed = Math.max(0, detection.timestamp - this.candidateStartedAt);
    const progress = Math.min(1, elapsed / this.holdMs);
    const lastFire = this.lastFireAt.get(validGesture) ?? -Infinity;
    const cooldownComplete =
      detection.timestamp - lastFire >= this.cooldownMs;
    const canFire =
      !this.firedForCandidate && progress >= 1 && cooldownComplete;

    if (canFire) {
      this.firedForCandidate = true;
      this.lastFireAt.set(validGesture, detection.timestamp);
      return this.result(
        validGesture,
        "fired",
        confidence,
        1,
        detection.timestamp,
        true,
      );
    }

    return this.result(
      validGesture,
      "holding",
      confidence,
      progress,
      detection.timestamp,
      false,
    );
  }

  private result(
    gesture: GestureId,
    phase: GestureProgressMessage["phase"],
    confidence: number,
    progress: number,
    timestamp: number,
    firedNow: boolean,
  ): CommandGestureUpdate {
    return {
      version: 1,
      type: "signal:gesture-progress",
      gesture,
      phase,
      confidence,
      progress,
      timestamp,
      firedNow,
    };
  }
}
