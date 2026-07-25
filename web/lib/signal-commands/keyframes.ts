export const MIN_TEACH_KEYFRAMES = 6;
export const MAX_TEACH_KEYFRAMES = 10;

export interface SampledKeyframe {
  timestampMs: number;
  mediaType: "image/jpeg" | "image/webp";
  dataUrl: string;
  width: number;
  height: number;
}

export interface KeyframeSampler {
  durationMs(recording: Blob): Promise<number>;
  sample(
    recording: Blob,
    timestampsMs: readonly number[],
  ): Promise<SampledKeyframe[]>;
}

export interface ApprovedKeyframe {
  timestampMs: number;
  mediaType: "image/jpeg" | "image/webp";
  data: string;
}

export function selectKeyframeTimestamps(
  durationMs: number,
  count = 8,
): number[] {
  if (!Number.isFinite(durationMs) || durationMs <= 0 || durationMs > 60_000) {
    throw new Error("Teach by Demo recordings must be between 0 and 60 seconds.");
  }
  if (!Number.isInteger(count) || count < MIN_TEACH_KEYFRAMES || count > MAX_TEACH_KEYFRAMES) {
    throw new Error("Signal extracts between 6 and 10 Teach by Demo keyframes.");
  }
  if (count === 1) return [0];
  const safeEnd = Math.max(0, durationMs - 1);
  return Array.from({ length: count }, (_, index) =>
    Math.round((safeEnd * index) / (count - 1)),
  );
}

export async function extractTeachKeyframes(
  recording: Blob,
  sampler: KeyframeSampler,
  count = 8,
): Promise<SampledKeyframe[]> {
  const durationMs = await sampler.durationMs(recording);
  const timestamps = selectKeyframeTimestamps(durationMs, count);
  const frames = await sampler.sample(recording, timestamps);
  if (frames.length !== count) {
    throw new Error("Keyframe extraction returned an incomplete frame set.");
  }
  for (let index = 0; index < frames.length; index += 1) {
    const frame = frames[index];
    if (
      frame.timestampMs !== timestamps[index] ||
      !frame.dataUrl.startsWith(`data:${frame.mediaType};base64,`) ||
      frame.width <= 0 ||
      frame.height <= 0
    ) {
      throw new Error("Keyframe extraction returned an invalid frame.");
    }
  }
  return frames;
}

export function approveTeachKeyframes(
  frames: readonly SampledKeyframe[],
  approved: boolean,
): ApprovedKeyframe[] {
  if (!approved) {
    throw new Error("Explicit approval is required before sending keyframes.");
  }
  if (
    frames.length < MIN_TEACH_KEYFRAMES ||
    frames.length > MAX_TEACH_KEYFRAMES
  ) {
    throw new Error("Signal sends between 6 and 10 approved keyframes.");
  }
  return frames.map((frame) => {
    const prefix = `data:${frame.mediaType};base64,`;
    if (!frame.dataUrl.startsWith(prefix)) {
      throw new Error("Approved keyframe data is not a supported compressed image.");
    }
    return {
      timestampMs: frame.timestampMs,
      mediaType: frame.mediaType,
      data: frame.dataUrl.slice(prefix.length),
    };
  });
}
