export const BOLT_PROMPT =
  "i want to build a website for my hand signal app";

export type WebsiteActionName = "bolt-prompt" | "spotify-next-track";

export type WebsiteActionResult =
  | {
      ok: true;
      action: WebsiteActionName;
      message: string;
      details: Record<string, string>;
    }
  | {
      ok: false;
      action: WebsiteActionName;
      code:
        | "prompt-not-found"
        | "prompt-insertion-failed"
        | "next-control-not-found"
        | "automation-failed";
      message: string;
    };

export interface WebsiteActionOptions {
  timeoutMs?: number;
  pollIntervalMs?: number;
}

type PromptKind =
  | "textarea"
  | "contenteditable"
  | "role-textbox"
  | "text-input";

type PromptCandidate = {
  element: HTMLElement;
  kind: PromptKind;
};

type ButtonCandidate = {
  button: HTMLButtonElement;
  match: "test-id" | "accessible-name";
};

const BOLT_CANDIDATES: ReadonlyArray<{
  selector: string;
  kind: PromptKind;
}> = [
  { selector: "textarea", kind: "textarea" },
  { selector: '[contenteditable="true"]', kind: "contenteditable" },
  { selector: '[role="textbox"]', kind: "role-textbox" },
  { selector: 'input[type="text"]', kind: "text-input" },
];

const BOLT_SUBMIT_LABELS = /\b(?:submit|send|build|generate)\b/i;
const SPOTIFY_NEXT_LABELS = new Set(["next", "skip forward", "next track"]);

function isElementVisible(element: HTMLElement): boolean {
  if (!element.isConnected) return false;
  const view = element.ownerDocument.defaultView;
  if (!view) return false;

  let current: HTMLElement | null = element;
  while (current) {
    const style = view.getComputedStyle(current);
    if (
      current.hidden ||
      current.getAttribute("aria-hidden") === "true" ||
      current.hasAttribute("inert") ||
      style.display === "none" ||
      style.visibility === "hidden" ||
      style.visibility === "collapse" ||
      Number(style.opacity) === 0
    ) {
      return false;
    }
    current = current.parentElement;
  }

  const rect = element.getBoundingClientRect();
  if (rect.width <= 0 || rect.height <= 0) return false;
  const viewportWidth =
    view.innerWidth || element.ownerDocument.documentElement.clientWidth;
  const viewportHeight =
    view.innerHeight || element.ownerDocument.documentElement.clientHeight;
  return (
    rect.bottom > 0 &&
    rect.right > 0 &&
    rect.top < viewportHeight &&
    rect.left < viewportWidth
  );
}

function isElementEnabled(element: HTMLElement): boolean {
  if (
    element.getAttribute("aria-disabled") === "true" ||
    element.getAttribute("aria-readonly") === "true"
  ) {
    return false;
  }
  try {
    if (element.matches(":disabled")) return false;
  } catch {
    // A non-form custom element may not support the pseudo-class.
  }
  if (
    element instanceof HTMLInputElement ||
    element instanceof HTMLTextAreaElement
  ) {
    return !element.disabled && !element.readOnly;
  }
  return true;
}

function isEditable(element: HTMLElement): boolean {
  if (
    element instanceof HTMLTextAreaElement ||
    (element instanceof HTMLInputElement &&
      element.type.toLowerCase() === "text")
  ) {
    return true;
  }
  return (
    element.isContentEditable ||
    element.getAttribute("contenteditable")?.toLowerCase() === "true"
  );
}

function findBoltPrompt(documentRef: Document): PromptCandidate | null {
  for (const candidate of BOLT_CANDIDATES) {
    const elements = documentRef.querySelectorAll<HTMLElement>(
      candidate.selector,
    );
    for (const element of elements) {
      if (
        isElementVisible(element) &&
        isElementEnabled(element) &&
        isEditable(element)
      ) {
        return { element, kind: candidate.kind };
      }
    }
  }
  return null;
}

function accessibleName(button: HTMLButtonElement): string {
  const ariaLabel = button.getAttribute("aria-label")?.trim();
  if (ariaLabel) return ariaLabel;

  const labelledBy = button.getAttribute("aria-labelledby");
  if (labelledBy) {
    const label = labelledBy
      .split(/\s+/)
      .map((id) => button.ownerDocument.getElementById(id)?.textContent ?? "")
      .join(" ")
      .trim();
    if (label) return label;
  }

  return (
    button.getAttribute("title")?.trim() ||
    button.textContent?.trim() ||
    ""
  );
}

function normalizeLabel(label: string): string {
  return label.toLowerCase().replace(/\s+/g, " ").trim();
}

function isSafeButton(button: HTMLButtonElement): boolean {
  return isElementVisible(button) && isElementEnabled(button);
}

function findAssociatedBoltSubmit(
  prompt: HTMLElement,
): HTMLButtonElement | null {
  let scope = prompt.parentElement;
  let levels = 0;
  while (scope && scope !== prompt.ownerDocument.body && levels < 6) {
    const candidates = Array.from(scope.querySelectorAll("button")).filter(
      (button): button is HTMLButtonElement =>
        button instanceof HTMLButtonElement &&
        isSafeButton(button) &&
        BOLT_SUBMIT_LABELS.test(accessibleName(button)),
    );
    if (candidates.length === 1) return candidates[0] ?? null;
    if (candidates.length > 1) return null;
    scope = scope.parentElement;
    levels += 1;
  }
  return null;
}

function fieldValue(element: HTMLElement): string {
  if (
    element instanceof HTMLInputElement ||
    element instanceof HTMLTextAreaElement
  ) {
    return element.value;
  }
  return element.textContent ?? "";
}

function setBoltPrompt(element: HTMLElement): void {
  const view = element.ownerDocument.defaultView;
  if (!view) throw new Error("The Bolt page is no longer available.");

  if (element instanceof view.HTMLTextAreaElement) {
    const setter = Object.getOwnPropertyDescriptor(
      view.HTMLTextAreaElement.prototype,
      "value",
    )?.set;
    if (!setter) throw new Error("The Bolt prompt field is not writable.");
    setter.call(element, BOLT_PROMPT);
  } else if (element instanceof view.HTMLInputElement) {
    const setter = Object.getOwnPropertyDescriptor(
      view.HTMLInputElement.prototype,
      "value",
    )?.set;
    if (!setter) throw new Error("The Bolt prompt field is not writable.");
    setter.call(element, BOLT_PROMPT);
  } else if (isEditable(element)) {
    element.replaceChildren(view.document.createTextNode(BOLT_PROMPT));
  } else {
    throw new Error("The Bolt prompt field is not editable.");
  }

  element.dispatchEvent(
    new view.InputEvent("input", {
      bubbles: true,
      cancelable: false,
      composed: true,
      data: BOLT_PROMPT,
      inputType: "insertText",
    }),
  );
  element.dispatchEvent(
    new view.Event("change", { bubbles: true, composed: true }),
  );
  if (fieldValue(element) !== BOLT_PROMPT) {
    throw new Error("Bolt did not accept the prompt text.");
  }
}

function dispatchEnter(element: HTMLElement): boolean {
  const view = element.ownerDocument.defaultView;
  if (!view) return false;
  const eventInit: KeyboardEventInit = {
    key: "Enter",
    code: "Enter",
    bubbles: true,
    cancelable: true,
    composed: true,
  };
  const keyDown = new view.KeyboardEvent("keydown", eventInit);
  const keyPress = new view.KeyboardEvent("keypress", eventInit);
  const keyUp = new view.KeyboardEvent("keyup", eventInit);
  const accepted = element.dispatchEvent(keyDown);
  element.dispatchEvent(keyPress);
  element.dispatchEvent(keyUp);
  return !accepted || keyDown.defaultPrevented;
}

async function waitFor<T>(
  find: () => T | null,
  timeoutMs: number,
  pollIntervalMs: number,
): Promise<T | null> {
  const deadline = Date.now() + Math.max(0, timeoutMs);
  do {
    const result = find();
    if (result) return result;
    const remaining = deadline - Date.now();
    if (remaining <= 0) return null;
    await new Promise((resolve) =>
      setTimeout(resolve, Math.min(Math.max(1, pollIntervalMs), remaining)),
    );
  } while (Date.now() <= deadline);
  return null;
}

export async function runBoltPromptAutomation(
  documentRef: Document,
  options: WebsiteActionOptions = {},
): Promise<WebsiteActionResult> {
  const prompt = await waitFor(
    () => findBoltPrompt(documentRef),
    options.timeoutMs ?? 15_000,
    options.pollIntervalMs ?? 100,
  );
  if (!prompt) {
    return {
      ok: false,
      action: "bolt-prompt",
      code: "prompt-not-found",
      message: "Bolt opened, but Signal could not find its prompt field.",
    };
  }

  try {
    prompt.element.focus({ preventScroll: true });
    setBoltPrompt(prompt.element);
    const enterHandled = dispatchEnter(prompt.element);
    await Promise.resolve();

    let submission = "enter";
    if (
      !enterHandled &&
      prompt.element.isConnected &&
      fieldValue(prompt.element) === BOLT_PROMPT
    ) {
      const submit = findAssociatedBoltSubmit(prompt.element);
      if (submit) {
        submit.click();
        submission = "enter-and-submit-button";
      }
    }

    return {
      ok: true,
      action: "bolt-prompt",
      message: "Bolt prompt inserted and submission attempted.",
      details: {
        field: prompt.kind,
        submission,
      },
    };
  } catch (error) {
    return {
      ok: false,
      action: "bolt-prompt",
      code: "prompt-insertion-failed",
      message:
        error instanceof Error
          ? error.message
          : "Signal could not insert the Bolt prompt.",
    };
  }
}

function findSpotifyNext(documentRef: Document): ButtonCandidate | null {
  const preferred = Array.from(
    documentRef.querySelectorAll<HTMLButtonElement>(
      'button[data-testid="control-button-skip-forward"]',
    ),
  ).find(isSafeButton);
  if (preferred) return { button: preferred, match: "test-id" };

  const fallback = Array.from(
    documentRef.querySelectorAll<HTMLButtonElement>("button"),
  ).find(
    (button) =>
      isSafeButton(button) &&
      SPOTIFY_NEXT_LABELS.has(normalizeLabel(accessibleName(button))),
  );
  return fallback
    ? { button: fallback, match: "accessible-name" }
    : null;
}

function findSpotifyPlayPause(
  documentRef: Document,
): HTMLButtonElement | null {
  const preferred = Array.from(
    documentRef.querySelectorAll<HTMLButtonElement>(
      'button[data-testid="control-button-playpause"]',
    ),
  ).find(isSafeButton);
  if (preferred) return preferred;

  return (
    Array.from(
      documentRef.querySelectorAll<HTMLButtonElement>("button"),
    ).find((button) => {
      if (!isSafeButton(button)) return false;
      const label = normalizeLabel(accessibleName(button));
      return label === "play" || label === "pause";
    }) ?? null
  );
}

export async function runSpotifyNextTrackAutomation(
  documentRef: Document,
  options: WebsiteActionOptions = {},
): Promise<WebsiteActionResult> {
  const next = await waitFor(
    () => findSpotifyNext(documentRef),
    options.timeoutMs ?? 10_000,
    options.pollIntervalMs ?? 100,
  );
  if (!next) {
    return {
      ok: false,
      action: "spotify-next-track",
      code: "next-control-not-found",
      message: "Spotify is open, but Signal could not find the next-track control.",
    };
  }

  try {
    next.button.click();
    const playPause = findSpotifyPlayPause(documentRef);
    const playPauseLabel = playPause
      ? normalizeLabel(accessibleName(playPause))
      : "";
    let playback = "unchanged";
    if (playPause && playPauseLabel === "play") {
      playPause.click();
      playback = "play-clicked";
    } else if (playPauseLabel === "pause") {
      playback = "already-playing";
    }

    return {
      ok: true,
      action: "spotify-next-track",
      message: "Advanced to the next Spotify track.",
      details: {
        nextControl: next.match,
        playback,
      },
    };
  } catch (error) {
    return {
      ok: false,
      action: "spotify-next-track",
      code: "automation-failed",
      message:
        error instanceof Error
          ? error.message
          : "Signal could not control Spotify.",
    };
  }
}
