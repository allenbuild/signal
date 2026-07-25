import type {
  FingerName,
  FingerState,
  PoseClassification,
  SignalPose,
  TrackedHand,
} from "./types.js";
import type { FingerTuning } from "./tuning.js";
import {
  FINGER_CHAINS,
  LANDMARK,
  clamp,
  distance3D,
  jointAngleDegrees,
} from "./geometry.js";
import {
  extendedFingerNames,
  fingerExtensionState,
  foldedFingertipProximity,
} from "./fingers.js";

const NUMBER_PATTERNS: ReadonlyArray<{
  pose: SignalPose;
  extended: readonly FingerName[];
}> = [
  { pose: "five", extended: ["thumb", "index", "middle", "ring", "little"] },
  { pose: "four", extended: ["index", "middle", "ring", "little"] },
  { pose: "three", extended: ["index", "middle", "ring"] },
  { pose: "two", extended: ["index", "middle"] },
  { pose: "one", extended: ["index"] },
];

function exactPattern(
  state: FingerState,
  expected: readonly FingerName[],
): boolean {
  const actual = extendedFingerNames(state);
  return (
    actual.length === expected.length &&
    expected.every((finger) => actual.includes(finger))
  );
}

function patternConfidence(
  state: FingerState,
  expected: readonly FingerName[],
): number {
  const all = Object.keys(state) as FingerName[];
  const evidence = all.map((finger) =>
    expected.includes(finger)
      ? state[finger].confidence
      : clamp(1 - state[finger].confidence, 0, 1),
  );
  return evidence.reduce((sum, value) => sum + value, 0) / evidence.length;
}

function thumbDirectionPose(
  hand: TrackedHand,
  state: FingerState,
): PoseClassification | null {
  const nonThumbs = ["index", "middle", "ring", "little"] as const;
  if (!state.thumb.extended || nonThumbs.some((finger) => state[finger].extended)) {
    return null;
  }
  const mcp = hand.landmarks[LANDMARK.thumbMcp];
  const tip = hand.landmarks[LANDMARK.thumbTip];
  const dx = tip.x - mcp.x;
  const dy = tip.y - mcp.y;
  const verticality = Math.abs(dy) / Math.max(Math.abs(dx), 0.0001);
  if (verticality < 1.35) {
    return null;
  }
  return {
    pose: dy < 0 ? "thumbs_up" : "thumbs_down",
    confidence: clamp(
      Math.min(state.thumb.confidence, verticality / 2.4, hand.confidence),
      0,
      1,
    ),
    fingers: state,
  };
}

function cPoseConfidence(
  hand: TrackedHand,
  state: FingerState,
  tuning: FingerTuning,
): number {
  const tipGap =
    distance3D(
      hand.landmarks[LANDMARK.thumbTip],
      hand.landmarks[LANDMARK.indexTip],
    ) / hand.palmWidth;
  if (
    tipGap < tuning.cMinTipGapPalmWidths ||
    tipGap > tuning.cMaxTipGapPalmWidths
  ) {
    return 0;
  }

  const nonThumbs = ["index", "middle", "ring", "little"] as const;
  const curved = nonThumbs.filter((finger) => {
    const [mcpIndex, pipIndex, dipIndex, tipIndex] = FINGER_CHAINS[finger];
    const proximal = jointAngleDegrees(
      hand.landmarks[mcpIndex],
      hand.landmarks[pipIndex],
      hand.landmarks[dipIndex],
    );
    const distal = jointAngleDegrees(
      hand.landmarks[pipIndex],
      hand.landmarks[dipIndex],
      hand.landmarks[tipIndex],
    );
    const reach = state[finger].reach;
    return (
      Math.min(proximal, distal) >= 70 &&
      !state[finger].extended &&
      reach > -0.05
    );
  }).length;
  if (curved < tuning.cMinCurvedFingers) {
    return 0;
  }

  const gapCenter =
    (tuning.cMinTipGapPalmWidths + tuning.cMaxTipGapPalmWidths) / 2;
  const halfRange =
    (tuning.cMaxTipGapPalmWidths - tuning.cMinTipGapPalmWidths) / 2;
  const gapScore = 1 - Math.abs(tipGap - gapCenter) / halfRange;
  return clamp(
    Math.min(hand.confidence, curved / nonThumbs.length, 0.55 + gapScore * 0.45),
    0,
    1,
  );
}

export function classifySignalPose(
  hand: TrackedHand,
  tuning: FingerTuning,
): PoseClassification {
  const fingers = fingerExtensionState(hand, tuning);

  const thumbPose = thumbDirectionPose(hand, fingers);
  if (thumbPose) {
    return thumbPose;
  }

  for (const pattern of NUMBER_PATTERNS) {
    if (exactPattern(fingers, pattern.extended)) {
      return {
        pose: pattern.pose,
        confidence: clamp(
          Math.min(patternConfidence(fingers, pattern.extended), hand.confidence),
          0,
          1,
        ),
        fingers,
      };
    }
  }

  const cConfidence = cPoseConfidence(hand, fingers, tuning);
  if (cConfidence > 0) {
    return { pose: "c", confidence: cConfidence, fingers };
  }

  const allFolded = ["index", "middle", "ring", "little"].every(
    (finger) => !fingers[finger as FingerName].extended,
  );
  if (
    allFolded &&
    !fingers.thumb.extended &&
    foldedFingertipProximity(hand) < 1.15
  ) {
    return {
      pose: "fist",
      confidence: clamp(
        Math.min(
          hand.confidence,
          1.15 - foldedFingertipProximity(hand) + 0.42,
        ),
        0,
        1,
      ),
      fingers,
    };
  }

  return { pose: null, confidence: 0, fingers };
}

