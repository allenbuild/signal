export const HAND_LANDMARK_COUNT = 21;

export type Handedness = "Left" | "Right";

export type FingerName = "thumb" | "index" | "middle" | "ring" | "little";

export type SignalPose =
  | "one"
  | "two"
  | "three"
  | "four"
  | "five"
  | "thumbs_up"
  | "thumbs_down"
  | "c"
  | "fist";

export type InteractionMode = "control" | "commands";

export interface Point2D {
  x: number;
  y: number;
}

export interface Point3D extends Point2D {
  z: number;
  confidence?: number;
}

export interface TrackedHand {
  id: string;
  handedness: Handedness;
  landmarks: Point3D[];
  worldLandmarks?: Point3D[];
  palmWidth: number;
  confidence: number;
  timestamp: number;
}

export interface FingerEvidence {
  extended: boolean;
  confidence: number;
  straightness: number;
  reach: number;
}

export type FingerState = Record<FingerName, FingerEvidence>;

export interface PoseClassification {
  pose: SignalPose | null;
  confidence: number;
  fingers: FingerState;
}

export type CursorPhase =
  | "neutral"
  | "tracking"
  | "pinchPending"
  | "clicking"
  | "scrolling"
  | "zooming"
  | "trackingLost";

export interface CursorPosition extends Point2D {
  phase: CursorPhase;
}

export interface ViewportBounds {
  width: number;
  height: number;
  padding?: number;
}

export interface TrackingSnapshot {
  processedFps: number;
  meanInferenceMs: number;
  droppedFrames: number;
  processedFrames: number;
  trackingConfidence: number;
  lastFrameAgeMs: number | null;
}

export interface RawMediaPipeCategory {
  categoryName?: string;
  displayName?: string;
  score?: number;
}

export interface RawMediaPipeHandResult {
  landmarks: Point3D[][];
  worldLandmarks?: Point3D[][];
  handedness?: RawMediaPipeCategory[][];
  handednesses?: RawMediaPipeCategory[][];
}

