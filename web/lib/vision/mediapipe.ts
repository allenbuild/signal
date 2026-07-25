import type { HandLandmarker } from "@mediapipe/tasks-vision";

export const MEDIAPIPE_VERSION = "0.10.35";
export const HAND_LANDMARKER_MODEL_PATH =
  "/mediapipe/hand_landmarker.task";

export async function createLocalHandLandmarker(
  origin: string,
): Promise<HandLandmarker> {
  const { FilesetResolver, HandLandmarker: HandLandmarkerTask } =
    await import("@mediapipe/tasks-vision");
  const assetRoot = new URL(
    `/mediapipe/${MEDIAPIPE_VERSION}/wasm`,
    origin,
  ).toString();
  const modelAssetPath = new URL(HAND_LANDMARKER_MODEL_PATH, origin).toString();
  const fileset = await FilesetResolver.forVisionTasks(assetRoot);
  const commonOptions = {
    baseOptions: { modelAssetPath, delegate: "GPU" as const },
    runningMode: "VIDEO" as const,
    numHands: 1,
    minHandDetectionConfidence: 0.55,
    minHandPresenceConfidence: 0.55,
    minTrackingConfidence: 0.5,
  };
  try {
    return await HandLandmarkerTask.createFromOptions(fileset, commonOptions);
  } catch {
    return HandLandmarkerTask.createFromOptions(fileset, {
      ...commonOptions,
      baseOptions: { modelAssetPath, delegate: "CPU" },
    });
  }
}
