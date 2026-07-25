import { afterEach, describe, expect, it, vi } from "vitest";

import { ClickController } from "../src/content/click";
import { DemoCapture } from "../src/content/demo-capture";
import {
  InteractionController,
  type InteractionTuning,
  VirtualCursor,
} from "../src/content/interaction";
import {
  createSignalOverlay,
  type CursorPosition,
  type SignalOverlay,
} from "../src/content/overlay";
import {
  pageCapability,
  PROTECTED_PAGE_MESSAGE,
} from "../src/content/page-capabilities";
import { ScrollController } from "../src/content/scroll";

function fakeOverlay(): SignalOverlay & {
  calls: {
    positions: CursorPosition[];
    clicks: CursorPosition[];
    scroll: number[];
    zoom: number[];
    status: string[];
    visible: boolean[];
  };
} {
  const host = document.createElement("div");
  document.body.append(host);
  let position = { x: 0, y: 0 };
  const calls = {
    positions: [] as CursorPosition[],
    clicks: [] as CursorPosition[],
    scroll: [] as number[],
    zoom: [] as number[],
    status: [] as string[],
    visible: [] as boolean[],
  };
  return {
    host,
    calls,
    get position() {
      return { ...position };
    },
    setCursor(next) {
      position = { ...next };
      calls.positions.push({ ...next });
    },
    setCursorVisible(visible) {
      calls.visible.push(visible);
    },
    showClick(next = position) {
      calls.clicks.push({ ...next });
    },
    showScroll(delta) {
      calls.scroll.push(delta);
    },
    showZoom(percent) {
      calls.zoom.push(percent);
    },
    showStatus(message) {
      calls.status.push(message);
    },
    clearIndicators: vi.fn(),
    setNativeCursorHidden: vi.fn(),
    reset({ hideCursor = true } = {}) {
      if (hideCursor) this.setCursorVisible(false);
      this.clearIndicators();
    },
    destroy() {
      host.remove();
    },
  };
}

const tuning: InteractionTuning = {
  cursor: {
    sensitivity: 1,
    acceleration: 1,
    smoothing: 1,
    deadZone: 0,
    maxDelta: 80,
    mirrorHorizontal: true,
    hideNativeCursor: false,
  },
  transactionThreshold: 12,
  dominanceRatio: 1.1,
  zoomPixelsPerStep: 30,
  zoomStep: 0.1,
  minZoom: 0.25,
  maxZoom: 5,
  zoomRateLimitMs: 80,
  minimumConfidence: 0.5,
};

function mockHitTarget(target: HTMLElement): void {
  Object.defineProperty(document, "elementsFromPoint", {
    configurable: true,
    value: vi.fn(() => [target, document.body, document.documentElement]),
  });
}

afterEach(() => {
  document.body.replaceChildren();
  document.head
    .querySelectorAll("#signal-extension-native-cursor")
    .forEach((element) => element.remove());
  vi.restoreAllMocks();
});

describe("content overlay and page capabilities", () => {
  it("creates exactly one isolated, non-interactive overlay", () => {
    const first = createSignalOverlay(document);
    const second = createSignalOverlay(document);

    expect(second).toBe(first);
    expect(
      document.querySelectorAll("#signal-extension-overlay"),
    ).toHaveLength(1);
    expect(first.host.style.pointerEvents).toBe("none");
    expect(first.host.style.zIndex).toBe("2147483647");
    expect(first.host.shadowRoot).toBeNull();

    first.destroy();
  });

  it("classifies ordinary and protected pages deterministically", () => {
    expect(pageCapability("https://en.wikipedia.org/wiki/Hand")).toEqual({
      supported: true,
    });
    expect(pageCapability("http://example.com")).toEqual({ supported: true });
    expect(pageCapability("chrome://settings")).toEqual({
      supported: false,
      reason: PROTECTED_PAGE_MESSAGE,
    });
    expect(pageCapability("https://chromewebstore.google.com/detail/x")).toEqual(
      {
        supported: false,
        reason: PROTECTED_PAGE_MESSAGE,
      },
    );
  });
});

describe("relative virtual cursor", () => {
  it("anchors without jumping, normalizes by palm width, mirrors, and clamps", () => {
    const overlay = fakeOverlay();
    const cursor = new VirtualCursor(
      overlay,
      tuning.cursor,
      () => ({ width: 200, height: 100 }),
    );

    expect(cursor.process({ dx: 0.2, dy: 0.1 }, 0.2)).toEqual({
      x: 100,
      y: 50,
    });
    expect(cursor.process({ dx: 0.02, dy: 0.01 }, 0.2)).toEqual({
      x: 90,
      y: 55,
    });
    expect(cursor.process({ dx: -100, dy: 100 }, 0.2)).toEqual({
      x: 170,
      y: 88,
    });

    cursor.loseAnchor();
    expect(cursor.process({ dx: 1, dy: 1 }, 0.2)).toEqual({
      x: 170,
      y: 88,
    });
  });

  it("applies live sensitivity tuning without resetting the cursor", () => {
    const overlay = fakeOverlay();
    const cursor = new VirtualCursor(
      overlay,
      tuning.cursor,
      () => ({ width: 200, height: 100 }),
    );
    cursor.process({ dx: 0, dy: 0 }, 1);
    cursor.process({ dx: -0.1, dy: 0 }, 1);
    const before = cursor.position.x;
    cursor.updateTuning({ sensitivity: 2 });
    cursor.process({ dx: -0.1, dy: 0 }, 1);
    expect(cursor.position.x - before).toBeGreaterThan(10);
  });

  it("maps the tracked fingertip directly into the page viewport", () => {
    const overlay = fakeOverlay();
    const cursor = new VirtualCursor(
      overlay,
      { ...tuning.cursor, smoothing: 1 },
      () => ({ width: 200, height: 100 }),
    );

    expect(cursor.processAbsolute({ x: 0.5, y: 0.5 })).toEqual({
      x: 100,
      y: 50,
    });
    expect(cursor.processAbsolute({ x: 0.88, y: 0.92 })).toEqual({
      x: 200,
      y: 100,
    });
  });
});

describe("page interaction transactions", () => {
  it("fires one click on a full pinch release without duplicate activation", () => {
    const button = document.createElement("button");
    const activated = vi.fn();
    button.addEventListener("click", activated);
    document.body.append(button);
    mockHitTarget(button);

    const overlay = fakeOverlay();
    const controller = new InteractionController(
      document,
      overlay,
      vi.fn(),
      tuning,
      () => ({ width: 200, height: 100 }),
    );

    controller.handleTrackingFrame({
      timestamp: 1,
      gesture: "pinch",
      confidence: 1,
      pinch: { closed: true, transactionState: "pending" },
    });
    controller.handleTrackingFrame({
      timestamp: 2,
      gesture: "pointer",
      confidence: 1,
      pinch: { closed: false, transactionState: "idle" },
    });
    controller.handleTrackingFrame({
      timestamp: 3,
      gesture: "pointer",
      confidence: 1,
      pinch: { closed: false, transactionState: "idle" },
    });

    expect(activated).toHaveBeenCalledTimes(1);
    expect(overlay.calls.clicks).toHaveLength(1);
  });

  it("locks a vertical pinch to scroll and never converts it to a click", () => {
    const scroller = document.createElement("div");
    scroller.style.overflowY = "auto";
    Object.defineProperties(scroller, {
      scrollHeight: { configurable: true, value: 500 },
      clientHeight: { configurable: true, value: 100 },
    });
    const scrollBy = vi.fn();
    scroller.scrollBy = scrollBy;
    document.body.append(scroller);
    mockHitTarget(scroller);

    const overlay = fakeOverlay();
    const controller = new InteractionController(
      document,
      overlay,
      vi.fn(),
      tuning,
      () => ({ width: 200, height: 100 }),
    );
    controller.handleTrackingFrame({
      timestamp: 100,
      gesture: "pinch",
      confidence: 1,
      pinch: {
        closed: true,
        transactionState: "pending",
        deltaX: 1,
        deltaY: 20,
      },
    });

    expect(controller.transactionState).toBe("scrolling");
    expect(scrollBy).toHaveBeenCalledTimes(1);

    controller.handleTrackingFrame({
      timestamp: 120,
      gesture: "pointer",
      confidence: 1,
      pinch: { closed: false, transactionState: "idle" },
    });
    expect(overlay.calls.clicks).toHaveLength(0);
    expect(controller.transactionState).toBe("idle");
  });

  it("locks a horizontal pinch to tab zoom and rate-limits requests", () => {
    const send = vi.fn();
    const overlay = fakeOverlay();
    const controller = new InteractionController(
      document,
      overlay,
      send,
      tuning,
      () => ({ width: 200, height: 100 }),
    );

    controller.handleTrackingFrame({
      timestamp: 100,
      gesture: "pinch",
      confidence: 1,
      pinch: {
        closed: true,
        transactionState: "pending",
        deltaX: 35,
        deltaY: 1,
      },
    });
    controller.handleTrackingFrame({
      timestamp: 120,
      gesture: "pinch",
      confidence: 1,
      pinch: {
        closed: true,
        transactionState: "zooming",
        deltaX: 35,
        deltaY: 0,
      },
    });

    expect(controller.transactionState).toBe("zooming");
    expect(send).toHaveBeenCalledTimes(1);
    expect(send).toHaveBeenCalledWith({
      version: 1,
      type: "signal:zoom-request",
      delta: 0.1,
      timestamp: 100,
    });
    expect(overlay.calls.clicks).toHaveLength(0);
  });

  it("defers a mode switch until a pinch transaction is released", () => {
    const button = document.createElement("button");
    document.body.append(button);
    mockHitTarget(button);

    const controller = new InteractionController(
      document,
      fakeOverlay(),
      vi.fn(),
      tuning,
      () => ({ width: 200, height: 100 }),
    );
    controller.handleTrackingFrame({
      timestamp: 1,
      gesture: "pinch",
      confidence: 1,
      pinch: { closed: true, transactionState: "pending" },
    });

    expect(controller.setMode("commands")).toBe(false);
    expect(controller.currentMode).toBe("control");

    controller.handleTrackingFrame({
      timestamp: 2,
      gesture: "pointer",
      confidence: 1,
      pinch: { closed: false, transactionState: "idle" },
    });
    expect(controller.currentMode).toBe("commands");
  });

  it("clears locked interaction and prevents stale frames after tracking loss", () => {
    const send = vi.fn();
    const overlay = fakeOverlay();
    const controller = new InteractionController(
      document,
      overlay,
      send,
      tuning,
      () => ({ width: 200, height: 100 }),
    );
    controller.handleTrackingFrame({
      timestamp: 10,
      gesture: "pinch",
      confidence: 1,
      pinch: {
        closed: true,
        transactionState: "zooming",
        deltaX: 35,
      },
    });
    controller.handleTrackingFrame({
      timestamp: 20,
      gesture: "unknown",
      confidence: 0,
    });

    expect(controller.transactionState).toBe("idle");
    expect(overlay.calls.visible.at(-1)).toBe(false);
    expect(send).toHaveBeenLastCalledWith({
      version: 1,
      type: "signal:interaction-reset",
      generation: 1,
    });

    controller.handleTrackingFrame({
      timestamp: 15,
      gesture: "pinch",
      confidence: 1,
      pinch: { closed: true, transactionState: "pending" },
    });
    expect(controller.transactionState).toBe("idle");
  });
});

describe("low-level click and scroll controllers", () => {
  it("focuses a control and uses one standard activation", () => {
    const button = document.createElement("button");
    document.body.append(button);
    mockHitTarget(button);
    const focus = vi.spyOn(button, "focus");
    const activation = vi.fn();
    button.addEventListener("click", activation);

    const result = new ClickController(document).clickAt(20, 30);

    expect(result).toMatchObject({ clicked: true, target: button });
    expect(focus).toHaveBeenCalledOnce();
    expect(activation).toHaveBeenCalledOnce();
  });

  it("does not activate generic page containers", () => {
    const container = document.createElement("div");
    const activation = vi.fn();
    container.addEventListener("click", activation);
    document.body.append(container);
    mockHitTarget(container);
    expect(new ClickController(document).clickAt(20, 30)).toMatchObject({
      clicked: false,
      reason: "no-target",
    });
    expect(activation).not.toHaveBeenCalled();
  });

  it("stops scrolling immediately after reset", () => {
    const scroller = document.createElement("div");
    scroller.style.overflowY = "scroll";
    Object.defineProperties(scroller, {
      scrollHeight: { configurable: true, value: 500 },
      clientHeight: { configurable: true, value: 100 },
    });
    const scrollBy = vi.fn();
    scroller.scrollBy = scrollBy;
    document.body.append(scroller);
    mockHitTarget(scroller);

    const controller = new ScrollController(document, {
      naturalInversion: false,
      smoothing: 1,
      pixelsPerUnit: 1,
      maxStep: 100,
      minIntervalMs: 0,
    });
    controller.lockAt(1, 1);
    expect(controller.applyDelta(30, 1)).toBe(30);
    controller.reset();
    expect(controller.applyDelta(30, 2)).toBe(0);
    expect(scrollBy).toHaveBeenCalledTimes(1);
  });
});

describe("content-script routing and safe command actions", () => {
  it("resets safely on navigation without creating a second overlay", async () => {
    (
      globalThis as typeof globalThis & {
        __SIGNAL_DISABLE_AUTO_START__?: boolean;
      }
    ).__SIGNAL_DISABLE_AUTO_START__ = true;
    const { startSignalContentRuntime } = await import(
      "../src/content/content-script"
    );
    const sendMessage = vi.mocked(chrome.runtime.sendMessage);
    sendMessage.mockClear();

    const first = startSignalContentRuntime(document);
    const second = startSignalContentRuntime(document);
    expect(second).toBe(first);
    expect(
      document.querySelectorAll("#signal-extension-overlay"),
    ).toHaveLength(1);

    window.dispatchEvent(new Event("pageshow"));
    expect(sendMessage).toHaveBeenCalledWith(
      expect.objectContaining({
        version: 1,
        type: "signal:interaction-reset",
      }),
    );

    first.dispose();
    delete (
      globalThis as typeof globalThis & {
        __SIGNAL_DISABLE_AUTO_START__?: boolean;
      }
    ).__SIGNAL_DISABLE_AUTO_START__;
  });

  it("types reviewed text but refuses sensitive fields", async () => {
    (
      globalThis as typeof globalThis & {
        __SIGNAL_DISABLE_AUTO_START__?: boolean;
      }
    ).__SIGNAL_DISABLE_AUTO_START__ = true;
    const { executeContentAction } = await import(
      "../src/content/content-script"
    );
    const overlay = fakeOverlay();
    const field = document.createElement("input");
    field.id = "safe";
    const password = document.createElement("input");
    password.id = "password";
    password.type = "password";
    document.body.append(field, password);

    const typed = await executeContentAction(document, overlay, {
      version: 1,
      type: "signal:content-action",
      requestId: "safe-action",
      action: {
        type: "type_text",
        parameters: {
          selector: "#safe",
          text: "predefined text",
          containsSensitiveData: false,
        },
      },
    });
    const blocked = await executeContentAction(document, overlay, {
      version: 1,
      type: "signal:content-action",
      requestId: "blocked-action",
      action: {
        type: "type_text",
        parameters: {
          selector: "#password",
          text: "never type this",
          containsSensitiveData: false,
        },
      },
    });

    expect(typed.ok).toBe(true);
    expect(field.value).toBe("predefined text");
    expect(blocked).toMatchObject({
      ok: false,
      message: "Signal will not type into a sensitive field.",
    });
    expect(password.value).toBe("");
    delete (
      globalThis as typeof globalThis & {
        __SIGNAL_DISABLE_AUTO_START__?: boolean;
      }
    ).__SIGNAL_DISABLE_AUTO_START__;
  });

  it("handles demo start/stop messages and restores hand control", async () => {
    (
      globalThis as typeof globalThis & {
        __SIGNAL_DISABLE_AUTO_START__?: boolean;
      }
    ).__SIGNAL_DISABLE_AUTO_START__ = true;
    const { startSignalContentRuntime } = await import(
      "../src/content/content-script"
    );
    const runtime = startSignalContentRuntime(document);
    const addListener = vi.mocked(chrome.runtime.onMessage.addListener);
    const listener = addListener.mock.calls.at(-1)?.[0];
    expect(listener).toBeTypeOf("function");

    const started = vi.fn();
    listener?.(
      {
        version: 1,
        type: "signal:demo/start",
        sessionId: "message-demo",
        maxActions: 10,
      },
      {},
      started,
    );
    expect(started).toHaveBeenCalledWith(
      expect.objectContaining({
        type: "signal:demo/state",
        state: "recording",
      }),
    );
    expect(runtime.controller.currentMode).toBe("paused");

    const button = document.createElement("button");
    button.id = "demo-button";
    document.body.append(button);
    button.click();

    const stopped = vi.fn();
    listener?.(
      {
        version: 1,
        type: "signal:demo/stop",
        sessionId: "message-demo",
      },
      {},
      stopped,
    );
    expect(stopped).toHaveBeenCalledWith(
      expect.objectContaining({
        version: 1,
        type: "signal:demo/result",
        sessionId: "message-demo",
        actions: [],
      }),
    );
    expect(runtime.controller.currentMode).toBe("control");

    runtime.dispose();
    delete (
      globalThis as typeof globalThis & {
        __SIGNAL_DISABLE_AUTO_START__?: boolean;
      }
    ).__SIGNAL_DISABLE_AUTO_START__;
  });
});

describe("Teach-by-Demo semantic capture", () => {
  it("returns a bounded semantic list without recording entered values", () => {
    let timestamp = 0;
    const capture = new DemoCapture(document, () => ++timestamp, () => true);
    const button = document.createElement("button");
    button.id = "save-button";
    const field = document.createElement("input");
    field.id = "display-name";
    document.body.append(button, field);

    capture.start({ sessionId: "demo-1", maxActions: 3 });
    button.click();
    field.focus();
    field.value = "private demo value";
    field.dispatchEvent(new InputEvent("input", { bubbles: true }));
    button.click();
    const result = capture.stop();

    expect(result).toMatchObject({
      sessionId: "demo-1",
      truncated: true,
    });
    expect(result.actions).toHaveLength(3);
    expect(result.actions.map((action) => action.type)).toEqual([
      "click",
      "focus",
      "input",
    ]);
    expect(result.actions[2]).toMatchObject({
      type: "input",
      valueCaptured: false,
    });
    expect(JSON.stringify(result)).not.toContain("private demo value");
  });

  it("skips password, authentication, and payment fields entirely", () => {
    const capture = new DemoCapture(document, () => 1, () => true);
    const password = document.createElement("input");
    password.type = "password";
    password.id = "account-password";
    const card = document.createElement("input");
    card.autocomplete = "cc-number";
    const otp = document.createElement("input");
    otp.autocomplete = "one-time-code";
    document.body.append(password, card, otp);

    capture.start({ sessionId: "secure-demo" });
    for (const field of [password, card, otp]) {
      field.focus();
      field.value = "do-not-record-me";
      field.dispatchEvent(new InputEvent("input", { bubbles: true }));
      field.click();
    }
    const result = capture.stop();

    expect(result.actions).toEqual([]);
    expect(JSON.stringify(result)).not.toContain("do-not-record-me");
  });

  it("coalesces repeated scroll events for the same container", () => {
    let timestamp = 0;
    const capture = new DemoCapture(document, () => ++timestamp, () => true);
    const scroller = document.createElement("div");
    scroller.id = "results";
    document.body.append(scroller);

    capture.start({ sessionId: "scroll-demo" });
    scroller.scrollTop = 20;
    scroller.dispatchEvent(new Event("scroll"));
    scroller.scrollTop = 75;
    scroller.dispatchEvent(new Event("scroll"));
    const result = capture.stop();

    expect(result.actions).toEqual([
      {
        type: "scroll",
        selector: "#results",
        scrollTop: 75,
        scrollLeft: 0,
        timestamp: 2,
      },
    ]);
  });

  it("ignores synthetic page-script events", () => {
    const capture = new DemoCapture(document, () => 1);
    const button = document.createElement("button");
    button.id = "scripted";
    document.body.append(button);
    capture.start({ sessionId: "untrusted-demo" });
    button.click();
    expect(capture.stop().actions).toEqual([]);
  });
});
