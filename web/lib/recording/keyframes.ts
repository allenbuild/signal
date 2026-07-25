export type RecordingKeyframe = {
  dataUrl: string;
  timestampMs: number;
  width: number;
  height: number;
};

function once(target: EventTarget, eventName: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const cleanup = () => {
      target.removeEventListener(eventName, resolveEvent);
      target.removeEventListener("error", rejectEvent);
    };
    const resolveEvent = () => {
      cleanup();
      resolve();
    };
    const rejectEvent = () => {
      cleanup();
      reject(new Error(`Could not read recording ${eventName}.`));
    };
    target.addEventListener(eventName, resolveEvent, { once: true });
    target.addEventListener("error", rejectEvent, { once: true });
  });
}

export async function extractRecordingKeyframes(
  blob: Blob,
  options: { count?: number; longestSide?: number } = {},
): Promise<RecordingKeyframe[]> {
  const count = Math.min(10, Math.max(6, options.count ?? 8));
  const longestSide = Math.min(1024, Math.max(320, options.longestSide ?? 1024));
  const url = URL.createObjectURL(blob);
  const video = document.createElement("video");
  video.muted = true;
  video.preload = "metadata";
  video.src = url;

  try {
    await once(video, "loadedmetadata");
    const duration = Number.isFinite(video.duration) ? video.duration : 0;
    if (duration <= 0 || video.videoWidth <= 0 || video.videoHeight <= 0) {
      throw new Error("The recording did not contain readable video frames.");
    }
    const scale = Math.min(
      1,
      longestSide / Math.max(video.videoWidth, video.videoHeight),
    );
    const width = Math.max(1, Math.round(video.videoWidth * scale));
    const height = Math.max(1, Math.round(video.videoHeight * scale));
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext("2d");
    if (!context) throw new Error("Canvas capture is unavailable.");

    const frames: RecordingKeyframe[] = [];
    for (let index = 0; index < count; index += 1) {
      const seconds = Math.min(
        Math.max(0, duration - 0.05),
        ((index + 1) / (count + 1)) * duration,
      );
      video.currentTime = seconds;
      await once(video, "seeked");
      context.drawImage(video, 0, 0, width, height);
      const dataUrl = canvas.toDataURL("image/webp", 0.72);
      frames.push({
        dataUrl,
        timestampMs: Math.round(seconds * 1000),
        width,
        height,
      });
    }
    return frames;
  } finally {
    video.removeAttribute("src");
    video.load();
    URL.revokeObjectURL(url);
  }
}
