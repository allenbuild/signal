import "@testing-library/jest-dom/vitest";

import { cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const { createLocalHandLandmarker } = vi.hoisted(() => ({
  createLocalHandLandmarker: vi.fn(),
}));

vi.mock("../lib/vision/mediapipe", () => ({
  createLocalHandLandmarker,
}));

import { CameraControlPanel } from "../components/signal/CameraControlPanel";

describe("camera permission and lifecycle", () => {
  const stop = vi.fn();
  const stream = {
    getTracks: () => [{ stop }],
  } as unknown as MediaStream;
  const getUserMedia = vi.fn();

  beforeEach(() => {
    stop.mockReset();
    getUserMedia.mockReset();
    createLocalHandLandmarker.mockReset();
    vi.spyOn(HTMLMediaElement.prototype, "play").mockResolvedValue();
    vi.stubGlobal("requestAnimationFrame", vi.fn(() => 1));
    vi.stubGlobal("cancelAnimationFrame", vi.fn());
    Object.defineProperty(navigator, "mediaDevices", {
      configurable: true,
      value: { getUserMedia },
    });
    createLocalHandLandmarker.mockResolvedValue({
      detectForVideo: vi.fn(() => ({
        landmarks: [],
        handedness: [],
      })),
      close: vi.fn(),
    });
  });

  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it("does not request camera access until Start Signal is clicked", async () => {
    getUserMedia.mockResolvedValue(stream);
    const user = userEvent.setup();
    render(
      <CameraControlPanel
        mode="control"
        disabled={false}
        onModeChange={vi.fn()}
        onTrackingFrame={vi.fn()}
        onRunningChange={vi.fn()}
        onStatus={vi.fn()}
      />,
    );
    expect(getUserMedia).not.toHaveBeenCalled();

    await user.click(screen.getByRole("button", { name: "Start Signal" }));

    await waitFor(() =>
      expect(getUserMedia).toHaveBeenCalledWith({
        video: {
          facingMode: "user",
          width: { ideal: 640 },
          height: { ideal: 480 },
          frameRate: { ideal: 30, max: 30 },
        },
        audio: false,
      }),
    );
    await waitFor(() =>
      expect(createLocalHandLandmarker).toHaveBeenCalledWith(
        window.location.origin,
      ),
    );
    expect(
      await screen.findByRole("button", { name: "Stop Signal" }),
    ).toBeInTheDocument();
  });

  it("stops every camera track when Signal stops", async () => {
    getUserMedia.mockResolvedValue(stream);
    const user = userEvent.setup();
    render(
      <CameraControlPanel
        mode="control"
        disabled={false}
        onModeChange={vi.fn()}
        onTrackingFrame={vi.fn()}
        onRunningChange={vi.fn()}
        onStatus={vi.fn()}
      />,
    );
    await user.click(screen.getByRole("button", { name: "Start Signal" }));
    await user.click(
      await screen.findByRole("button", { name: "Stop Signal" }),
    );
    expect(stop).toHaveBeenCalledOnce();
    expect(
      screen.getByText("Signal stopped. Camera access is off."),
    ).toBeInTheDocument();
  });

  it("shows a recoverable message when permission is denied", async () => {
    getUserMedia.mockRejectedValue(
      new DOMException("Permission denied", "NotAllowedError"),
    );
    const user = userEvent.setup();
    render(
      <CameraControlPanel
        mode="control"
        disabled={false}
        onModeChange={vi.fn()}
        onTrackingFrame={vi.fn()}
        onRunningChange={vi.fn()}
        onStatus={vi.fn()}
      />,
    );
    await user.click(screen.getByRole("button", { name: "Start Signal" }));
    expect(
      await screen.findByText(/Camera access was denied/i),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Start Signal" }),
    ).toBeEnabled();
  });
});
