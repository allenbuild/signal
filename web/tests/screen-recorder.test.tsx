import "@testing-library/jest-dom/vitest";

import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { ScreenRecorder } from "../components/signal/ScreenRecorder";

class FakeTrack extends EventTarget {
  stop = vi.fn();
}

class FakeMediaRecorder extends EventTarget {
  static instances: FakeMediaRecorder[] = [];

  static isTypeSupported(type: string) {
    return type === "video/webm;codecs=vp9";
  }

  state: RecordingState = "inactive";
  mimeType: string;

  constructor(
    public readonly stream: MediaStream,
    options?: MediaRecorderOptions,
  ) {
    super();
    this.mimeType = options?.mimeType ?? "video/webm";
    FakeMediaRecorder.instances.push(this);
  }

  start() {
    this.state = "recording";
  }

  stop() {
    if (this.state === "inactive") return;
    this.state = "inactive";
    this.dispatchEvent(new Event("stop"));
  }
}

const originalMediaDevices = Object.getOwnPropertyDescriptor(
  navigator,
  "mediaDevices",
);
const originalCreateObjectURL = Object.getOwnPropertyDescriptor(
  URL,
  "createObjectURL",
);
const originalRevokeObjectURL = Object.getOwnPropertyDescriptor(
  URL,
  "revokeObjectURL",
);

function installRecorderEnvironment(
  getDisplayMedia: ReturnType<typeof vi.fn>,
) {
  Object.defineProperty(navigator, "mediaDevices", {
    configurable: true,
    value: { getDisplayMedia },
  });
  vi.stubGlobal("MediaRecorder", FakeMediaRecorder);
  Object.defineProperty(URL, "createObjectURL", {
    configurable: true,
    value: vi.fn(() => "blob:signal-preview"),
  });
  Object.defineProperty(URL, "revokeObjectURL", {
    configurable: true,
    value: vi.fn(),
  });
}

function restoreUrlMethod(
  name: "createObjectURL" | "revokeObjectURL",
  descriptor: PropertyDescriptor | undefined,
) {
  if (descriptor) {
    Object.defineProperty(URL, name, descriptor);
  } else {
    Reflect.deleteProperty(URL, name);
  }
}

beforeEach(() => {
  FakeMediaRecorder.instances = [];
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  if (originalMediaDevices) {
    Object.defineProperty(navigator, "mediaDevices", originalMediaDevices);
  } else {
    Reflect.deleteProperty(navigator, "mediaDevices");
  }
  restoreUrlMethod("createObjectURL", originalCreateObjectURL);
  restoreUrlMethod("revokeObjectURL", originalRevokeObjectURL);
  vi.restoreAllMocks();
});

describe("ScreenRecorder browser lifecycle", () => {
  it("turns getDisplayMedia denial into a recoverable, explicit message", async () => {
    installRecorderEnvironment(
      vi.fn().mockRejectedValue(
        new DOMException("Permission denied", "NotAllowedError"),
      ),
    );
    render(<ScreenRecorder onUse={vi.fn()} />);

    fireEvent.click(screen.getByRole("button", { name: "Start recording" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Screen sharing was cancelled or denied. You can retry or describe the command instead.",
    );
    expect(
      screen.getByRole("button", { name: "Start recording" }),
    ).toBeEnabled();
  });

  it("stops every display track when the user stops recording", async () => {
    const track = new FakeTrack();
    const stream = {
      getTracks: () => [track],
      getVideoTracks: () => [track],
    } as unknown as MediaStream;
    installRecorderEnvironment(vi.fn().mockResolvedValue(stream));
    render(<ScreenRecorder onUse={vi.fn()} />);

    fireEvent.click(screen.getByRole("button", { name: "Start recording" }));
    fireEvent.click(
      await screen.findByRole("button", { name: "Stop recording" }),
    );

    expect(track.stop).toHaveBeenCalled();
    expect(
      await screen.findByLabelText("Screen recording preview"),
    ).toHaveAttribute("src", "blob:signal-preview");
    expect(FakeMediaRecorder.instances[0]?.state).toBe("inactive");
  });

  it("stops tracks and the recorder when unmounted during capture", async () => {
    const track = new FakeTrack();
    const stream = {
      getTracks: () => [track],
      getVideoTracks: () => [track],
    } as unknown as MediaStream;
    installRecorderEnvironment(vi.fn().mockResolvedValue(stream));
    const { unmount } = render(<ScreenRecorder onUse={vi.fn()} />);

    fireEvent.click(screen.getByRole("button", { name: "Start recording" }));
    await screen.findByRole("button", { name: "Stop recording" });
    const recorder = FakeMediaRecorder.instances[0];
    expect(recorder?.state).toBe("recording");

    unmount();

    expect(track.stop).toHaveBeenCalled();
    expect(recorder?.state).toBe("inactive");
  });

  it("revokes preview blob URLs on retake and unmount", async () => {
    const track = new FakeTrack();
    const stream = {
      getTracks: () => [track],
      getVideoTracks: () => [track],
    } as unknown as MediaStream;
    installRecorderEnvironment(vi.fn().mockResolvedValue(stream));
    const { unmount } = render(<ScreenRecorder onUse={vi.fn()} />);

    fireEvent.click(screen.getByRole("button", { name: "Start recording" }));
    fireEvent.click(
      await screen.findByRole("button", { name: "Stop recording" }),
    );
    await screen.findByLabelText("Screen recording preview");
    expect(URL.createObjectURL).toHaveBeenCalledTimes(1);

    fireEvent.click(screen.getByRole("button", { name: "Retake" }));
    await waitFor(() => {
      expect(URL.revokeObjectURL).toHaveBeenCalledWith("blob:signal-preview");
    });

    const secondTrack = new FakeTrack();
    const secondStream = {
      getTracks: () => [secondTrack],
      getVideoTracks: () => [secondTrack],
    } as unknown as MediaStream;
    const getDisplayMedia = navigator.mediaDevices
      .getDisplayMedia as ReturnType<typeof vi.fn>;
    getDisplayMedia.mockResolvedValueOnce(secondStream);
    fireEvent.click(screen.getByRole("button", { name: "Start recording" }));
    fireEvent.click(
      await screen.findByRole("button", { name: "Stop recording" }),
    );
    await screen.findByLabelText("Screen recording preview");
    vi.mocked(URL.revokeObjectURL).mockClear();

    unmount();
    expect(URL.revokeObjectURL).toHaveBeenCalledWith("blob:signal-preview");
  });
});
