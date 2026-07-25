import type {
  FingerEvidence,
  FingerName,
  FingerState,
  TrackedHand,
} from "./types.js";
import type { FingerTuning } from "./tuning.js";
import {
  FINGER_CHAINS,
  LANDMARK,
  clamp,
  distance3D,
  jointAngleDegrees,
  palmCenter,
} from "./geometry.js";

const NON_THUMB_FINGERS: readonly FingerName[] = [
  "index",
  "middle",
  "ring",
  "little",
];

function scoreAbove(value: number, threshold: number, range: number): number {
  return clamp((value - threshold + range) / (2 * range), 0, 1);
}

function extensionEvidence(
  hand: TrackedHand,
  finger: FingerName,
  tuning: FingerTuning,
): FingerEvidence {
  const [mcpIndex, pipIndex, dipIndex, tipIndex] = FINGER_CHAINS[finger];
  const mcp = hand.landmarks[mcpIndex];
  const pip = hand.landmarks[pipIndex];
  const dip = hand.landmarks[dipIndex];
  const tip = hand.landmarks[tipIndex];
  const proximalAngle = jointAngleDegrees(mcp, pip, dip);
  const distalAngle = jointAngleDegrees(pip, dip, tip);
  const straightness = Math.min(proximalAngle, distalAngle);
  const palm = palmCenter(hand.landmarks);
  const reach = (distance3D(tip, palm) - distance3D(pip, palm)) / hand.palmWidth;
  const angleThreshold =
    finger === "thumb"
      ? tuning.thumbJointAngleDegrees
      : tuning.extendedJointAngleDegrees;
  const reachThreshold =
    finger === "thumb"
      ? tuning.thumbReachPalmWidths
      : tuning.extendedReachPalmWidths;
  const angleScore = scoreAbove(straightness, angleThreshold, 18);
  const reachScore = scoreAbove(reach, reachThreshold, 0.12);
  const confidence = Math.min(angleScore, reachScore, hand.confidence);
  return {
    extended: straightness >= angleThreshold && reach >= reachThreshold,
    confidence,
    straightness,
    reach,
  };
}

export function fingerExtensionState(
  hand: TrackedHand,
  tuning: FingerTuning,
): FingerState {
  const state = {} as FingerState;
  for (const finger of ["thumb", ...NON_THUMB_FINGERS] as const) {
    state[finger] = extensionEvidence(hand, finger, tuning);
  }
  return state;
}

export function extendedFingerNames(state: FingerState): FingerName[] {
  return (Object.keys(state) as FingerName[]).filter(
    (finger) => state[finger].extended,
  );
}

export function foldedFingertipProximity(hand: TrackedHand): number {
  const palm = palmCenter(hand.landmarks);
  const tips = [
    LANDMARK.indexTip,
    LANDMARK.middleTip,
    LANDMARK.ringTip,
    LANDMARK.littleTip,
  ];
  return (
    tips.reduce(
      (sum, index) => sum + distance3D(hand.landmarks[index], palm) / hand.palmWidth,
      0,
    ) / tips.length
  );
}

