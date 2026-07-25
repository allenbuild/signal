export type HandLandmark = {
  x: number;
  y: number;
  z?: number;
  visibility?: number;
};

export type Point2D = Pick<HandLandmark, "x" | "y">;

export const HAND_CONNECTIONS: ReadonlyArray<readonly [number, number]> = [
  [0, 1],
  [1, 2],
  [2, 3],
  [3, 4],
  [0, 5],
  [5, 6],
  [6, 7],
  [7, 8],
  [5, 9],
  [9, 10],
  [10, 11],
  [11, 12],
  [9, 13],
  [13, 14],
  [14, 15],
  [15, 16],
  [13, 17],
  [17, 18],
  [18, 19],
  [19, 20],
  [0, 17],
] as const;

export const HAND = {
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
  pinkyMcp: 17,
  pinkyPip: 18,
  pinkyDip: 19,
  pinkyTip: 20,
} as const;

export function distance(a: Point2D, b: Point2D) {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

export function clamp(value: number, minimum: number, maximum: number) {
  return Math.min(maximum, Math.max(minimum, value));
}

export function mirrorLandmarks(
  landmarks: readonly HandLandmark[],
): HandLandmark[] {
  return landmarks.map((landmark) => ({
    ...landmark,
    x: 1 - landmark.x,
  }));
}

export function palmSize(landmarks: readonly HandLandmark[]) {
  if (landmarks.length < 21) return 0;
  const vertical = distance(
    landmarks[HAND.wrist],
    landmarks[HAND.middleMcp],
  );
  const horizontal = distance(
    landmarks[HAND.indexMcp],
    landmarks[HAND.pinkyMcp],
  );
  return Math.max(0.0001, (vertical + horizontal) / 2);
}

export function wholeHandCenter(
  landmarks: readonly HandLandmark[],
): Point2D {
  const indices = [
    HAND.wrist,
    HAND.thumbMcp,
    HAND.indexMcp,
    HAND.middleMcp,
    HAND.ringMcp,
    HAND.pinkyMcp,
  ];
  const points = indices.map((index) => landmarks[index]);
  return {
    x: points.reduce((sum, point) => sum + point.x, 0) / points.length,
    y: points.reduce((sum, point) => sum + point.y, 0) / points.length,
  };
}

export function pinchCenter(
  landmarks: readonly HandLandmark[],
): Point2D {
  const thumb = landmarks[HAND.thumbTip];
  const index = landmarks[HAND.indexTip];
  return {
    x: (thumb.x + index.x) / 2,
    y: (thumb.y + index.y) / 2,
  };
}

export function normalizedPinchDistance(
  landmarks: readonly HandLandmark[],
) {
  return (
    distance(
      landmarks[HAND.thumbTip],
      landmarks[HAND.indexTip],
    ) / palmSize(landmarks)
  );
}

export function angleDegrees(a: Point2D, vertex: Point2D, c: Point2D) {
  const ab = { x: a.x - vertex.x, y: a.y - vertex.y };
  const cb = { x: c.x - vertex.x, y: c.y - vertex.y };
  const denominator = Math.hypot(ab.x, ab.y) * Math.hypot(cb.x, cb.y);
  if (denominator <= Number.EPSILON) return 0;
  const cosine = clamp((ab.x * cb.x + ab.y * cb.y) / denominator, -1, 1);
  return (Math.acos(cosine) * 180) / Math.PI;
}
