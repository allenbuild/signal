import type { GestureId } from "../../config/gestureCommands";
import type {
  SignalGestureEventDetail,
  SignalGesturePhase,
} from "../gestures/bridge";

export type CommandGestureUpdate = SignalGestureEventDetail & {
  firedNow: boolean;
};

export class CommandGestureEngine {
  private candidate: GestureId | null = null;
  private candidateStartedAt = 0;
  private firedForCandidate = false;
  private readonly lastFireAt = new Map<GestureId, number>();

  constructor(
    private readonly holdMs = 550,
    private readonly cooldownMs = 800,
  ) {}

  reset(timestamp = Date.now()): CommandGestureUpdate | null {
    const released = this.candidate;
    this.candidate = null;
    this.candidateStartedAt = 0;
    this.firedForCandidate = false;
    return released
      ? {
          gesture: released,
          confidence: 0,
          phase: "released",
          progress: 0,
          timestamp,
          firedNow: false,
        }
      : null;
  }

  update(
    gesture: GestureId | null,
    confidence: number,
    timestamp: number,
  ): CommandGestureUpdate | null {
    if (!gesture) return this.reset(timestamp);

    if (gesture !== this.candidate) {
      this.candidate = gesture;
      this.candidateStartedAt = timestamp;
      this.firedForCandidate = false;
      return this.result("detected", confidence, 0, timestamp, false);
    }

    const elapsed = Math.max(0, timestamp - this.candidateStartedAt);
    const progress = Math.min(1, elapsed / this.holdMs);
    const previousFire = this.lastFireAt.get(gesture) ?? -Infinity;
    const canFire =
      !this.firedForCandidate &&
      progress >= 1 &&
      timestamp - previousFire >= this.cooldownMs;

    if (canFire) {
      this.firedForCandidate = true;
      this.lastFireAt.set(gesture, timestamp);
      return this.result("fired", confidence, 1, timestamp, true);
    }

    return this.result("holding", confidence, progress, timestamp, false);
  }

  private result(
    phase: SignalGesturePhase,
    confidence: number,
    progress: number,
    timestamp: number,
    firedNow: boolean,
  ): CommandGestureUpdate {
    return {
      gesture: this.candidate!,
      confidence: Math.min(1, Math.max(0, confidence)),
      phase,
      progress,
      timestamp,
      firedNow,
    };
  }
}
