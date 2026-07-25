import type {
  FingerName,
  Handedness,
  Point2D,
  Point3D,
  TrackedHand,
} from "./types.js";

export const LANDMARK = {
  wrist: 0,
  thumbCmc: 1,
  thumbMcp: 2,
  thumbIp: 3,
  thumbTip: 4,
  indexMcp: 5,
  indexPip: 6,
  indexDip: 7,
  indexTip: 8,
  middleMcp: 9,
  middlePip: 10,
  middleDip: 11,
  middleTip: 12,
  ringMcp: 13,
  ringPip: 14,
  ringDip: 15,
  ringTip: 16,
  littleMcp: 17,
  littlePip: 18,
  littleDip: 19,
  littleTip: 20,
} as const;

export const FINGER_CHAINS: Readonly<Record<FingerName, readonly number[]>> = {
  thumb: [
    LANDMARK.thumbCmc,
    LANDMARK.thumbMcp,
    LANDMARK.thumbIp,
    LANDMARK.thumbTip,
  ],
  index: [
    LANDMARK.indexMcp,
    LANDMARK.indexPip,
    LANDMARK.indexDip,
    LANDMARK.indexTip,
  ],
  middle: [
    LANDMARK.middleMcp,
    LANDMARK.middlePip,
    LANDMARK.middleDip,
    LANDMARK.middleTip,
  ],
  ring: [
    LANDMARK.ringMcp,
    LANDMARK.ringPip,
    LANDMARK.ringDip,
    LANDMARK.ringTip,
  ],
  little: [
    LANDMARK.littleMcp,
    LANDMARK.littlePip,
    LANDMARK.littleDip,
    LANDMARK.littleTip,
  ],
};

const PALM_INDICES = [
  LANDMARK.wrist,
  LANDMARK.indexMcp,
  LANDMARK.middleMcp,
  LANDMARK.ringMcp,
  LANDMARK.littleMcp,
] as const;

export function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(maximum, Math.max(minimum, value));
}

export function distance2D(a: Point2D, b: Point2D): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

export function distance3D(a: Point3D, b: Point3D): number {
  return Math.hypot(a.x - b.x, a.y - b.y, a.z - b.z);
}

export function midpoint(a: Point3D, b: Point3D): Point3D {
  return {
    x: (a.x + b.x) / 2,
    y: (a.y + b.y) / 2,
    z: (a.z + b.z) / 2,
    confidence: Math.min(a.confidence ?? 1, b.confidence ?? 1),
  };
}

export function palmCenter(landmarks: readonly Point3D[]): Point3D {
  assertLandmarks(landmarks);
  const points = PALM_INDICES.map((index) => landmarks[index]);
  return {
    x: points.reduce((sum, point) => sum + point.x, 0) / points.length,
    y: points.reduce((sum, point) => sum + point.y, 0) / points.length,
    z: points.reduce((sum, point) => sum + point.z, 0) / points.length,
    confidence: Math.min(...points.map((point) => point.confidence ?? 1)),
  };
}

export function measurePalmWidth(landmarks: readonly Point3D[]): number {
  assertLandmarks(landmarks);
  return distance3D(landmarks[LANDMARK.indexMcp], landmarks[LANDMARK.littleMcp]);
}

export function palmNormalizedDistance(
  a: Point3D,
  b: Point3D,
  palmWidth: number,
): number {
  if (!Number.isFinite(palmWidth) || palmWidth <= 0) {
    return Number.POSITIVE_INFINITY;
  }
  return distance3D(a, b) / palmWidth;
}

export function jointAngleDegrees(a: Point3D, vertex: Point3D, c: Point3D): number {
  const ab = { x: a.x - vertex.x, y: a.y - vertex.y, z: a.z - vertex.z };
  const cb = { x: c.x - vertex.x, y: c.y - vertex.y, z: c.z - vertex.z };
  const abLength = Math.hypot(ab.x, ab.y, ab.z);
  const cbLength = Math.hypot(cb.x, cb.y, cb.z);
  if (abLength === 0 || cbLength === 0) {
    return 0;
  }
  const cosine = clamp(
    (ab.x * cb.x + ab.y * cb.y + ab.z * cb.z) / (abLength * cbLength),
    -1,
    1,
  );
  return (Math.acos(cosine) * 180) / Math.PI;
}

export function averageLandmarkConfidence(landmarks: readonly Point3D[]): number {
  assertLandmarks(landmarks);
  return (
    landmarks.reduce((sum, point) => sum + clamp(point.confidence ?? 1, 0, 1), 0) /
    landmarks.length
  );
}

export function smoothLandmarks(
  previous: readonly Point3D[] | undefined,
  current: readonly Point3D[],
  alpha: number,
): Point3D[] {
  assertLandmarks(current);
  if (!previous || previous.length !== current.length) {
    return current.map((point) => ({ ...point }));
  }
  const weight = clamp(alpha, 0, 1);
  return current.map((point, index) => ({
    x: previous[index].x + (point.x - previous[index].x) * weight,
    y: previous[index].y + (point.y - previous[index].y) * weight,
    z: previous[index].z + (point.z - previous[index].z) * weight,
    confidence:
      (previous[index].confidence ?? 1) +
      ((point.confidence ?? 1) - (previous[index].confidence ?? 1)) * weight,
  }));
}

export function createTrackedHand(input: {
  id: string;
  handedness: Handedness;
  landmarks: readonly Point3D[];
  worldLandmarks?: readonly Point3D[];
  timestamp: number;
  minimumPalmWidth?: number;
  confidence?: number;
}): TrackedHand | null {
  assertLandmarks(input.landmarks);
  if (!Number.isFinite(input.timestamp)) {
    return null;
  }
  const palmWidth = measurePalmWidth(input.landmarks);
  if (palmWidth < (input.minimumPalmWidth ?? 0.015)) {
    return null;
  }
  const confidence =
    input.confidence ?? averageLandmarkConfidence(input.landmarks);
  return {
    id: input.id,
    handedness: input.handedness,
    landmarks: input.landmarks.map((point) => ({ ...point })),
    worldLandmarks: input.worldLandmarks?.map((point) => ({ ...point })),
    palmWidth,
    confidence: clamp(confidence, 0, 1),
    timestamp: input.timestamp,
  };
}

export function isHandFresh(
  hand: TrackedHand,
  now: number,
  freshnessMs: number,
): boolean {
  const age = now - hand.timestamp;
  return age >= 0 && age <= freshnessMs;
}

export function assertLandmarks(landmarks: readonly Point3D[]): void {
  if (landmarks.length !== 21) {
    throw new Error(`Expected 21 hand landmarks, received ${landmarks.length}`);
  }
  for (const point of landmarks) {
    if (![point.x, point.y, point.z].every(Number.isFinite)) {
      throw new Error("Hand landmarks must contain finite coordinates");
    }
  }
}

