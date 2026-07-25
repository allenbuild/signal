import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
  BOLT_PROMPT,
  runBoltPromptAutomation,
  runSpotifyNextTrackAutomation,
} from "../src/content/website-actions";

function rect({
  left = 10,
  top = 10,
  width = 120,
  height = 40,
}: Partial<DOMRect> = {}): DOMRect {
  return {
    x: left,
    y: top,
    left,
    top,
    width,
    height,
    right: left + width,
    bottom: top + height,
    toJSON: () => ({}),
  };
}

beforeEach(() => {
  vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockReturnValue(
    rect(),
  );
});

afterEach(() => {
  document.body.replaceChildren();
  vi.restoreAllMocks();
});

describe("Bolt prompt automation", () => {
  it("uses the first visible enabled candidate by the required priority", async () => {
    const hiddenTextarea = document.createElement("textarea");
    hiddenTextarea.style.display = "none";
    const editor = document.createElement("div");
    editor.contentEditable = "true";
    editor.setAttribute("contenteditable", "true");
    const lowerPriority = document.createElement("input");
    lowerPriority.type = "text";
    document.body.append(hiddenTextarea, editor, lowerPriority);

    const events: string[] = [];
    editor.addEventListener("input", () => events.push("input"));
    editor.addEventListener("change", () => events.push("change"));
    editor.addEventListener("keydown", (event) => {
      events.push((event as KeyboardEvent).key);
      event.preventDefault();
    });

    const result = await runBoltPromptAutomation(document, { timeoutMs: 0 });

    expect(result).toMatchObject({
      ok: true,
      action: "bolt-prompt",
      details: { field: "contenteditable", submission: "enter" },
    });
    expect(editor.textContent).toBe(BOLT_PROMPT);
    expect(lowerPriority.value).toBe("");
    expect(events).toEqual(["input", "change", "Enter"]);
  });

  it("uses the native value path and one unambiguous submit fallback", async () => {
    const composer = document.createElement("form");
    const textarea = document.createElement("textarea");
    const submit = document.createElement("button");
    submit.type = "button";
    submit.setAttribute("aria-label", "Generate site");
    composer.append(textarea, submit);
    document.body.append(composer);
    const clicked = vi.fn();
    submit.addEventListener("click", clicked);
    const inputEvent = vi.fn();
    textarea.addEventListener("input", inputEvent);

    const result = await runBoltPromptAutomation(document, { timeoutMs: 0 });

    expect(textarea.value).toBe(BOLT_PROMPT);
    expect(inputEvent).toHaveBeenCalledTimes(1);
    expect(clicked).toHaveBeenCalledTimes(1);
    expect(result).toMatchObject({
      ok: true,
      details: { submission: "enter-and-submit-button" },
    });
  });

  it("never clicks an ambiguous submit fallback", async () => {
    const composer = document.createElement("div");
    const textarea = document.createElement("textarea");
    const send = document.createElement("button");
    const build = document.createElement("button");
    send.setAttribute("aria-label", "Send");
    build.setAttribute("aria-label", "Build");
    composer.append(textarea, send, build);
    document.body.append(composer);
    const sendClick = vi.fn();
    const buildClick = vi.fn();
    send.addEventListener("click", sendClick);
    build.addEventListener("click", buildClick);

    const result = await runBoltPromptAutomation(document, { timeoutMs: 0 });

    expect(result).toMatchObject({
      ok: true,
      details: { submission: "enter" },
    });
    expect(sendClick).not.toHaveBeenCalled();
    expect(buildClick).not.toHaveBeenCalled();
  });

  it("returns the exact safe failure when no prompt is available", async () => {
    const result = await runBoltPromptAutomation(document, { timeoutMs: 0 });

    expect(result).toEqual({
      ok: false,
      action: "bolt-prompt",
      code: "prompt-not-found",
      message: "Bolt opened, but Signal could not find its prompt field.",
    });
  });
});

describe("Spotify next-track automation", () => {
  it("prefers the exact next control and starts playback only for Play", async () => {
    const fallback = document.createElement("button");
    fallback.setAttribute("aria-label", "Next track");
    const next = document.createElement("button");
    next.dataset.testid = "control-button-skip-forward";
    const playPause = document.createElement("button");
    playPause.dataset.testid = "control-button-playpause";
    playPause.setAttribute("aria-label", "Play");
    document.body.append(fallback, next, playPause);
    const fallbackClick = vi.fn();
    const nextClick = vi.fn();
    const playClick = vi.fn();
    fallback.addEventListener("click", fallbackClick);
    next.addEventListener("click", nextClick);
    playPause.addEventListener("click", playClick);

    const result = await runSpotifyNextTrackAutomation(document, {
      timeoutMs: 0,
    });

    expect(nextClick).toHaveBeenCalledTimes(1);
    expect(fallbackClick).not.toHaveBeenCalled();
    expect(playClick).toHaveBeenCalledTimes(1);
    expect(result).toMatchObject({
      ok: true,
      details: { nextControl: "test-id", playback: "play-clicked" },
    });
  });

  it("uses only a clear accessible-name fallback and leaves Pause alone", async () => {
    const offscreen = document.createElement("button");
    offscreen.dataset.testid = "control-button-skip-forward";
    Object.defineProperty(offscreen, "getBoundingClientRect", {
      configurable: true,
      value: () => rect({ left: 2_000 }),
    });
    const next = document.createElement("button");
    next.setAttribute("aria-label", "Skip forward");
    const pause = document.createElement("button");
    pause.setAttribute("aria-label", "Pause");
    document.body.append(offscreen, next, pause);
    const offscreenClick = vi.fn();
    const nextClick = vi.fn();
    const pauseClick = vi.fn();
    offscreen.addEventListener("click", offscreenClick);
    next.addEventListener("click", nextClick);
    pause.addEventListener("click", pauseClick);

    const result = await runSpotifyNextTrackAutomation(document, {
      timeoutMs: 0,
    });

    expect(result).toMatchObject({
      ok: true,
      details: {
        nextControl: "accessible-name",
        playback: "already-playing",
      },
    });
    expect(nextClick).toHaveBeenCalledTimes(1);
    expect(offscreenClick).not.toHaveBeenCalled();
    expect(pauseClick).not.toHaveBeenCalled();
  });

  it("does not click a vaguely labelled media control", async () => {
    const ambiguous = document.createElement("button");
    ambiguous.setAttribute("aria-label", "Continue listening");
    document.body.append(ambiguous);
    const clicked = vi.fn();
    ambiguous.addEventListener("click", clicked);

    const result = await runSpotifyNextTrackAutomation(document, {
      timeoutMs: 0,
    });

    expect(clicked).not.toHaveBeenCalled();
    expect(result).toEqual({
      ok: false,
      action: "spotify-next-track",
      code: "next-control-not-found",
      message:
        "Spotify is open, but Signal could not find the next-track control.",
    });
  });
});
