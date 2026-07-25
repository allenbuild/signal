import type { GestureId } from "../../config/gestureCommands";
import {
  angleDegrees,
  distance,
  HAND,
  palmSize,
  type HandLandmark,
} from "./hand-geometry";

type Finger = {
  mcp: number;
  pip: number;
  dip: number;
  tip: number;
};

const fingers: Record<"index" | "middle" | "ring" | "pinky", Finger> = {
  index: {
    mcp: HAND.indexMcp,
    pip: HAND.indexPip,
    dip: HAND.indexDip,
    tip: HAND.indexTip,
  },
  middle: {
    mcp: HAND.middleMcp,
    pip: HAND.middlePip,
    dip: HAND.middleDip,
    tip: HAND.middleTip,
  },
  ring: {
    mcp: HAND.ringMcp,
    pip: HAND.ringPip,
    dip: HAND.ringDip,
    tip: HAND.ringTip,
  },
  pinky: {
    mcp: HAND.pinkyMcp,
    pip: HAND.pinkyPip,
    dip: HAND.pinkyDip,
    tip: HAND.pinkyTip,
  },
};

function isFingerExtended(
  landmarks: readonly HandLandmark[],
  finger: Finger,
) {
  const size = palmSize(landmarks);
  const pipAngle = angleDegrees(
    landmarks[finger.mcp],
    landmarks[finger.pip],
    landmarks[finger.tip],
  );
  const dipAngle = angleDegrees(
    landmarks[finger.pip],
    landmarks[finger.dip],
    landmarks[finger.tip],
  );
  const reach =
    distance(landmarks[finger.tip], landmarks[HAND.wrist]) -
    distance(landmarks[finger.pip], landmarks[HAND.wrist]);
  return pipAngle >= 145 && dipAngle >= 135 && reach >= size * 0.16;
}

function isThumbExtended(landmarks: readonly HandLandmark[]) {
  const size = palmSize(landmarks);
  const reach =
    distance(landmarks[HAND.thumbTip], landmarks[HAND.indexMcp]) -
    distance(landmarks[HAND.thumbIp], landmarks[HAND.indexMcp]);
  const angle = angleDegrees(
    landmarks[HAND.thumbMcp],
    landmarks[HAND.thumbIp],
    landmarks[HAND.thumbTip],
  );
  return reach >= size * 0.12 && angle >= 135;
}

function exactFingerPattern(
  extended: Record<keyof typeof fingers, boolean>,
  expected: readonly (keyof typeof fingers)[],
) {
  const expectedSet = new Set(expected);
  return (Object.keys(fingers) as Array<keyof typeof fingers>).every(
    (finger) => extended[finger] === expectedSet.has(finger),
  );
}

export type PoseRecognition = {
  gesture: GestureId | null;
  confidence: number;
  pointerPose: boolean;
  extendedFingers: Readonly<Record<keyof typeof fingers, boolean>>;
};

/**
 * Deterministic geometry only. MediaPipe supplies landmarks; no learned
 * gesture classifier or remote inference participates in this decision.
 */
export function recognizeHandPose(
  landmarks: readonly HandLandmark[],
): PoseRecognition {
  if (landmarks.length < 21 || palmSize(landmarks) < 0.01) {
    return {
      gesture: null,
      confidence: 0,
      pointerPose: false,
      extendedFingers: {
        index: false,
        middle: false,
        ring: false,
        pinky: false,
      },
    };
  }

  const extended = {
    index: isFingerExtended(landmarks, fingers.index),
    middle: isFingerExtended(landmarks, fingers.middle),
    ring: isFingerExtended(landmarks, fingers.ring),
    pinky: isFingerExtended(landmarks, fingers.pinky),
  };
  const thumbExtended = isThumbExtended(landmarks);
  const onlyIndex = exactFingerPattern(extended, ["index"]);
  const noneExtended = exactFingerPattern(extended, []);
  const size = palmSize(landmarks);
  const thumbTip = landmarks[HAND.thumbTip];
  const wrist = landmarks[HAND.wrist];
  const thumbVertical = (wrist.y - thumbTip.y) / size;
  const thumbHorizontal = Math.abs(wrist.x - thumbTip.x) / size;

  let gesture: GestureId | null = null;
  let matchedFeatures = 0;
  const totalFeatures = 5;

  if (
    noneExtended &&
    thumbExtended &&
    thumbVertical > 0.42 &&
    thumbVertical > thumbHorizontal * 1.12
  ) {
    gesture = "thumbs_up";
    matchedFeatures = 5;
  } else if (
    noneExtended &&
    thumbExtended &&
    thumbVertical < -0.34 &&
    -thumbVertical > thumbHorizontal * 1.05
  ) {
    gesture = "thumbs_down";
    matchedFeatures = 5;
  } else if (
    exactFingerPattern(extended, ["index", "middle", "ring", "pinky"]) &&
    thumbExtended
  ) {
    gesture = "five";
    matchedFeatures = 5;
  } else if (
    exactFingerPattern(extended, ["index", "middle", "ring", "pinky"])
  ) {
    gesture = "four";
    matchedFeatures = 4;
  } else if (exactFingerPattern(extended, ["index", "middle", "ring"])) {
    gesture = "three";
    matchedFeatures = 4;
  } else if (exactFingerPattern(extended, ["index", "middle"])) {
    gesture = "two";
    matchedFeatures = 4;
  } else if (onlyIndex) {
    gesture = "one";
    matchedFeatures = 4;
  } else if (noneExtended) {
    const thumbIndexGap =
      distance(landmarks[HAND.thumbTip], landmarks[HAND.indexTip]) / size;
    const thumbMiddleGap =
      distance(landmarks[HAND.thumbTip], landmarks[HAND.middleTip]) / size;
    const isOpenC =
      !thumbExtended &&
      thumbIndexGap >= 0.42 &&
      thumbIndexGap <= 1.25 &&
      thumbMiddleGap >= 0.42;
    gesture = isOpenC ? "c_shape" : "fist";
    matchedFeatures = isOpenC ? 4 : 5;
  }

  const confidence =
    gesture === null ? 0 : Math.min(0.99, 0.55 + (matchedFeatures / totalFeatures) * 0.4);
  return {
    gesture,
    confidence,
    pointerPose: onlyIndex,
    extendedFingers: extended,
  };
}
