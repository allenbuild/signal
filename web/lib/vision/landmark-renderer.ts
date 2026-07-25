import {
  HAND_CONNECTIONS,
  type HandLandmark,
} from "./hand-geometry";

export function drawHandLandmarks(
  canvas: HTMLCanvasElement,
  width: number,
  height: number,
  landmarks: readonly HandLandmark[],
) {
  if (width <= 0 || height <= 0) return false;
  if (canvas.width !== width || canvas.height !== height) {
    canvas.width = width;
    canvas.height = height;
  }
  const context = canvas.getContext("2d");
  if (!context) return false;
  context.clearRect(0, 0, canvas.width, canvas.height);
  context.lineCap = "round";
  context.lineJoin = "round";
  context.strokeStyle = "rgba(220, 233, 191, 0.78)";
  context.lineWidth = Math.max(2, canvas.width / 260);
  for (const [start, end] of HAND_CONNECTIONS) {
    const a = landmarks[start];
    const b = landmarks[end];
    if (!a || !b) continue;
    context.beginPath();
    context.moveTo(a.x * canvas.width, a.y * canvas.height);
    context.lineTo(b.x * canvas.width, b.y * canvas.height);
    context.stroke();
  }
  context.fillStyle = "#f6f0df";
  for (const landmark of landmarks) {
    context.beginPath();
    context.arc(
      landmark.x * canvas.width,
      landmark.y * canvas.height,
      Math.max(2.2, canvas.width / 190),
      0,
      Math.PI * 2,
    );
    context.fill();
  }
  return true;
}

export function clearHandLandmarks(canvas: HTMLCanvasElement | null) {
  if (!canvas) return;
  canvas.getContext("2d")?.clearRect(0, 0, canvas.width, canvas.height);
}
