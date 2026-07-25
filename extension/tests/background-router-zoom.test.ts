import { describe, expect, it, vi } from "vitest";

import {
  ActiveTabRouter,
  isSupportedPageUrl,
} from "../src/background/tab-router";
import { TabZoomController } from "../src/background/zoom";
import type {
  SignalMessage,
  TrackingFrameMessage,
} from "../src/shared/messages";

const frame = (sequence: number): TrackingFrameMessage => ({
  version: 1,
  type: "signal:tracking-frame",
  timestamp: sequence,
  sequence,
  gesture: "pointer",
  confidence: 1,
  pointerDelta: { dx: 1, dy: 0 },
});

describe("active-tab routing", () => {
  it("routes frames only to the active tab and resets on tab changes", async () => {
    const deliveries: Array<{ tabId: number; message: SignalMessage }> = [];
    const router = new ActiveTabRouter({
      getActiveTab: async () => ({
        id: 1,
        url: "https://www.wikipedia.org/",
      }),
      sendMessage: async (tabId, message) => {
        deliveries.push({ tabId, message });
      },
    });

    await router.restore();
    await router.routeTrackingFrame(frame(1));
    await router.activate({ id: 2, url: "https://github.com/" });
    await router.routeTrackingFrame(frame(2));

    expect(
      deliveries
        .filter((item) => item.message.type === "signal:tracking-frame")
        .map((item) => item.tabId),
    ).toEqual([1, 2]);
    expect(
      deliveries.some(
        (item) =>
          item.tabId === 2 &&
          item.message.type === "signal:reset" &&
          item.message.reason === "tab-change",
      ),
    ).toBe(true);
  });

  it("never replays an old or duplicate frame after a newer sequence", async () => {
    const sendMessage = vi.fn(async () => undefined);
    const router = new ActiveTabRouter({
      getActiveTab: async () => ({ id: 1, url: "https://example.com/" }),
      sendMessage,
    });
    await router.restore();
    expect((await router.routeTrackingFrame(frame(8))).status).toBe("sent");
    expect((await router.routeTrackingFrame(frame(8))).status).toBe("stale");
    expect((await router.routeTrackingFrame(frame(7))).status).toBe("stale");
  });

  it("accepts a reset sequence from a newly reconnected offscreen session", async () => {
    const sendMessage = vi.fn(async () => undefined);
    const router = new ActiveTabRouter({
      getActiveTab: async () => ({ id: 1, url: "https://example.com/" }),
      sendMessage,
    });
    await router.restore();
    expect(
      (
        await router.routeTrackingFrame({
          ...frame(20),
          sessionId: "offscreen-a",
        })
      ).status,
    ).toBe("sent");
    expect(
      (
        await router.routeTrackingFrame({
          ...frame(1),
          sessionId: "offscreen-b",
        })
      ).status,
    ).toBe("sent");
  });

  it("resets the active interaction generation after navigation", async () => {
    const messages: SignalMessage[] = [];
    const router = new ActiveTabRouter({
      getActiveTab: async () => ({ id: 1, url: "https://example.com/" }),
      sendMessage: async (_tabId, message) => {
        messages.push(message);
      },
    });
    await router.restore();
    const before = router.currentGeneration;
    await router.navigationCommitted(1, "https://example.com/next");
    expect(router.currentGeneration).toBe(before + 1);
    expect(messages.at(-1)).toMatchObject({
      type: "signal:reset",
      reason: "navigation",
      generation: before + 1,
    });
  });

  it("injects once when a permitted content script is missing", async () => {
    let ready = false;
    const injectContentScript = vi.fn(async () => {
      ready = true;
    });
    const sendMessage = vi.fn(async () => {
      if (!ready) throw new Error("No receiver");
    });
    const router = new ActiveTabRouter({
      getActiveTab: async () => ({ id: 1, url: "https://example.com/" }),
      sendMessage,
      injectContentScript,
    });
    expect((await router.restore()).status).toBe("sent");
    expect(injectContentScript).toHaveBeenCalledTimes(1);
  });

  it("reports protected pages and never tries to inject them", async () => {
    const onUnsupported = vi.fn();
    const injectContentScript = vi.fn();
    const router = new ActiveTabRouter({
      getActiveTab: async () => ({ id: 1, url: "chrome://settings/" }),
      sendMessage: vi.fn(),
      injectContentScript,
      onUnsupported,
    });
    expect((await router.restore()).status).toBe("unsupported");
    expect(onUnsupported).toHaveBeenCalledWith(
      "Signal cannot control this protected browser page.",
      expect.objectContaining({ id: 1 }),
    );
    expect(injectContentScript).not.toHaveBeenCalled();
  });

  it("classifies ordinary and protected destinations", () => {
    expect(isSupportedPageUrl("https://github.com/")).toBe(true);
    expect(isSupportedPageUrl("http://example.com/")).toBe(true);
    expect(isSupportedPageUrl("chrome://extensions/")).toBe(false);
    expect(
      isSupportedPageUrl("https://chromewebstore.google.com/detail/demo"),
    ).toBe(false);
  });
});

describe("tab zoom", () => {
  it("clamps zoom, rate limits updates, and deduplicates writes", async () => {
    const setZoom = vi.fn(async () => undefined);
    const zoom = new TabZoomController(
      { getZoom: async () => 1, setZoom },
      { rateLimitMs: 100 },
    );
    expect((await zoom.set(1, 20, 100)).factor).toBe(5);
    expect((await zoom.set(1, 5, 120)).factor).toBe(5);
    expect(setZoom).toHaveBeenCalledTimes(1);
    expect((await zoom.set(1, 0, 250)).factor).toBe(0.25);
    expect(setZoom).toHaveBeenCalledTimes(2);
  });

  it("maps horizontal movement to actual per-tab zoom updates", async () => {
    const setZoom = vi.fn(async () => undefined);
    const zoom = new TabZoomController(
      { getZoom: async () => 1, setZoom },
      { rateLimitMs: 0, deltaScale: 0.01 },
    );
    const right = await zoom.applyDelta(4, 10, 100);
    const left = await zoom.applyDelta(4, -20, 200);
    expect(right.factor).toBe(1.1);
    expect(left.factor).toBe(0.9);
    expect(setZoom).toHaveBeenNthCalledWith(1, 4, 1.1);
    expect(setZoom).toHaveBeenNthCalledWith(2, 4, 0.9);
  });

  it("returns a visible unsupported state when Chrome rejects zoom", async () => {
    const zoom = new TabZoomController({
      getZoom: async () => 1,
      setZoom: async () => {
        throw new Error("protected");
      },
    });
    expect(await zoom.set(2, 1.2)).toMatchObject({
      supported: false,
      error: "Signal cannot change zoom on this page.",
    });
  });
});
