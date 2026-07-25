export interface TrackingTuning {
  landmarkSmoothing: number;
  confidenceThreshold: number;
  freshnessMs: number;
  trackingLossGraceMs: number;
  handAssociationDistance: number;
  minimumPalmWidth: number;
}

export interface FingerTuning {
  extendedJointAngleDegrees: number;
  extendedReachPalmWidths: number;
  thumbJointAngleDegrees: number;
  thumbReachPalmWidths: number;
  cMinTipGapPalmWidths: number;
  cMaxTipGapPalmWidths: number;
  cMinCurvedFingers: number;
}

export interface PointerTuning {
  deadZonePalmWidths: number;
  sensitivityPixels: number;
  smoothing: number;
  maximumDeltaPixels: number;
  accelerationExponent: number;
  mirrorHorizontal: boolean;
}

export interface PinchTuning {
  closeThreshold: number;
  openThreshold: number;
  clickMaximumDurationMs: number;
  clickMaximumMovementPalmWidths: number;
  modeLockMovementPalmWidths: number;
  axisDominanceRatio: number;
  movementDeadZonePalmWidths: number;
  scrollSmoothing: number;
  scrollPixelsPerPalmWidth: number;
  maximumScrollPixelsPerFrame: number;
  naturalScroll: boolean;
  zoomSmoothing: number;
  zoomPerPalmWidth: number;
  maximumZoomDeltaPerFrame: number;
  invertZoom: boolean;
  minimumZoom: number;
  maximumZoom: number;
}

export interface CommandTuning {
  stableHoldMs: number;
  cooldownMs: number;
  confidenceThreshold: number;
}

export interface MetricsTuning {
  sampleWindowMs: number;
}

export interface SignalTrackingTuning {
  tracking: TrackingTuning;
  fingers: FingerTuning;
  pointer: PointerTuning;
  pinch: PinchTuning;
  commands: CommandTuning;
  metrics: MetricsTuning;
}

export const DEFAULT_SIGNAL_TRACKING_TUNING: Readonly<SignalTrackingTuning> = {
  tracking: {
    landmarkSmoothing: 0.42,
    confidenceThreshold: 0.55,
    freshnessMs: 180,
    trackingLossGraceMs: 180,
    handAssociationDistance: 1.25,
    minimumPalmWidth: 0.015,
  },
  fingers: {
    extendedJointAngleDegrees: 145,
    extendedReachPalmWidths: 0.18,
    thumbJointAngleDegrees: 138,
    thumbReachPalmWidths: 0.12,
    cMinTipGapPalmWidths: 0.35,
    cMaxTipGapPalmWidths: 1.45,
    cMinCurvedFingers: 2,
  },
  pointer: {
    deadZonePalmWidths: 0.012,
    sensitivityPixels: 145,
    smoothing: 0.48,
    maximumDeltaPixels: 42,
    accelerationExponent: 1.18,
    mirrorHorizontal: true,
  },
  pinch: {
    closeThreshold: 0.3,
    openThreshold: 0.42,
    clickMaximumDurationMs: 350,
    clickMaximumMovementPalmWidths: 0.12,
    modeLockMovementPalmWidths: 0.16,
    axisDominanceRatio: 1.35,
    movementDeadZonePalmWidths: 0.015,
    scrollSmoothing: 0.45,
    scrollPixelsPerPalmWidth: 520,
    maximumScrollPixelsPerFrame: 68,
    naturalScroll: false,
    zoomSmoothing: 0.42,
    zoomPerPalmWidth: 0.8,
    maximumZoomDeltaPerFrame: 0.08,
    invertZoom: false,
    minimumZoom: 0.75,
    maximumZoom: 1.75,
  },
  commands: {
    stableHoldMs: 550,
    cooldownMs: 800,
    confidenceThreshold: 0.62,
  },
  metrics: {
    sampleWindowMs: 1_000,
  },
};

export function mergeSignalTrackingTuning(
  overrides: Partial<{
    [K in keyof SignalTrackingTuning]: Partial<SignalTrackingTuning[K]>;
  }> = {},
): SignalTrackingTuning {
  const defaults = DEFAULT_SIGNAL_TRACKING_TUNING;
  const merged: SignalTrackingTuning = {
    tracking: { ...defaults.tracking, ...overrides.tracking },
    fingers: { ...defaults.fingers, ...overrides.fingers },
    pointer: { ...defaults.pointer, ...overrides.pointer },
    pinch: { ...defaults.pinch, ...overrides.pinch },
    commands: { ...defaults.commands, ...overrides.commands },
    metrics: { ...defaults.metrics, ...overrides.metrics },
  };

  if (merged.pinch.openThreshold <= merged.pinch.closeThreshold) {
    throw new Error("pinch.openThreshold must be greater than pinch.closeThreshold");
  }
  if (
    merged.pinch.minimumZoom <= 0 ||
    merged.pinch.maximumZoom <= merged.pinch.minimumZoom
  ) {
    throw new Error("pinch zoom range is invalid");
  }
  return merged;
}
