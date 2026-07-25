const button = document.getElementById("allow") as HTMLButtonElement | null;
const statusElement = document.getElementById("status");
const preview = document.getElementById("preview") as HTMLVideoElement | null;

function setStatus(message: string, error = false) {
  if (!statusElement) return;
  statusElement.textContent = message;
  statusElement.classList.toggle("error", error);
}

button?.addEventListener("click", async () => {
  button.disabled = true;
  setStatus("Waiting for Chrome camera permission…");
  let stream: MediaStream | null = null;
  try {
    stream = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: {
        width: { ideal: 640 },
        height: { ideal: 480 },
        frameRate: { ideal: 30, max: 30 },
        facingMode: "user",
      },
    });
    if (preview) {
      preview.srcObject = stream;
      await preview.play();
    }
    // The visible setup page owns the preview stream. Release it before
    // asking the service worker to start the offscreen camera runtime so the
    // two contexts never contend for the same device.
    for (const track of stream.getTracks()) track.stop();
    if (preview) preview.srcObject = null;
    stream = null;
    await chrome.runtime.sendMessage({
      version: 1,
      type: "signal:setup/permission-granted",
    });
    setStatus("Camera enabled. Return to the Signal side panel and choose Start Signal.");
  } catch (error) {
    setStatus(
      error instanceof Error
        ? `Camera was not enabled: ${error.message}`
        : "Camera was not enabled. Check Chrome site settings and try again.",
      true,
    );
    button.disabled = false;
  } finally {
    for (const track of stream?.getTracks() ?? []) track.stop();
    if (preview) preview.srcObject = null;
  }
});
