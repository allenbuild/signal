export type DemoAction =
  | {
      type: "click";
      selector: string;
      tag: string;
      role?: string;
      timestamp: number;
    }
  | {
      type: "focus";
      selector: string;
      tag: string;
      inputKind?: string;
      timestamp: number;
    }
  | {
      type: "input";
      selector: string;
      tag: string;
      inputKind: string;
      valueCaptured: false;
      timestamp: number;
    }
  | {
      type: "scroll";
      selector: string;
      scrollTop: number;
      scrollLeft: number;
      timestamp: number;
    };

export interface DemoCaptureResult {
  sessionId: string;
  origin: string;
  actions: DemoAction[];
  truncated: boolean;
}

const DEFAULT_MAX_ACTIONS = 64;
const ABSOLUTE_MAX_ACTIONS = 100;
const MAX_CAPTURE_DURATION_MS = 120_000;
const SENSITIVE_AUTOCOMPLETE = new Set([
  "current-password",
  "new-password",
  "one-time-code",
  "cc-number",
  "cc-csc",
  "cc-exp",
  "cc-exp-month",
  "cc-exp-year",
]);
const SENSITIVE_HINT =
  /(pass(word)?|secret|token|auth|otp|one.?time|credit|card|cvc|cvv|ssn|social.?security)/i;

function boundedMax(value: number | undefined): number {
  if (!Number.isFinite(value)) return DEFAULT_MAX_ACTIONS;
  return Math.max(
    1,
    Math.min(ABSOLUTE_MAX_ACTIONS, Math.floor(value as number)),
  );
}

function escapeCss(value: string): string {
  if (globalThis.CSS?.escape) return globalThis.CSS.escape(value);
  return value.replace(/[^a-zA-Z0-9_-]/g, (character) => {
    return `\\${character.codePointAt(0)?.toString(16)} `;
  });
}

function safeId(element: HTMLElement): string | null {
  const id = element.id.trim();
  if (
    !id ||
    id.length > 64 ||
    SENSITIVE_HINT.test(id)
  ) {
    return null;
  }
  return `#${escapeCss(id)}`;
}

export function stableSelector(element: HTMLElement): string {
  const direct = safeId(element);
  if (direct) return direct;

  const parts: string[] = [];
  let current: HTMLElement | null = element;
  while (current && parts.length < 7) {
    const tag = current.localName;
    if (!tag) break;
    const siblings = current.parentElement
      ? Array.from(current.parentElement.children).filter(
          (sibling) => sibling.localName === tag,
        )
      : [];
    const suffix =
      siblings.length > 1
        ? `:nth-of-type(${siblings.indexOf(current) + 1})`
        : "";
    parts.unshift(`${tag}${suffix}`);
    const parent: HTMLElement | null = current.parentElement;
    if (!parent || tag === "html") break;
    const parentId = safeId(parent);
    if (parentId) {
      parts.unshift(parentId);
      break;
    }
    current = parent;
  }
  return parts.join(" > ");
}

export function isSensitiveDemoField(element: HTMLElement): boolean {
  const label =
    element instanceof HTMLLabelElement
      ? element
      : element.closest("label");
  if (
    label?.control instanceof HTMLElement &&
    label.control !== element &&
    isSensitiveDemoField(label.control)
  ) {
    return true;
  }

  const input =
    element instanceof HTMLInputElement ? element : null;
  if (input?.type.toLowerCase() === "password") return true;

  const autocomplete = (
    input?.autocomplete ??
    element.getAttribute("autocomplete") ??
    ""
  )
    .trim()
    .toLowerCase()
    .split(/\s+/)
    .at(-1);
  if (autocomplete && SENSITIVE_AUTOCOMPLETE.has(autocomplete)) return true;

  return [
    element.id,
    element.getAttribute("name") ?? "",
    element.getAttribute("aria-label") ?? "",
  ].some((value) => SENSITIVE_HINT.test(value));
}

function htmlTarget(event: Event): HTMLElement | null {
  const target = event.composedPath()[0] ?? event.target;
  return target instanceof HTMLElement ? target : null;
}

function clickableTarget(target: HTMLElement): HTMLElement {
  return (
    target.closest<HTMLElement>(
      "button,a[href],input,select,textarea,[role='button'],[role='link'],[tabindex]",
    ) ?? target
  );
}

function editableKind(target: HTMLElement): string | null {
  if (target instanceof HTMLInputElement) {
    return target.type.toLowerCase() || "text";
  }
  if (target instanceof HTMLTextAreaElement) return "textarea";
  if (target.isContentEditable) return "contenteditable";
  return null;
}

export class DemoCapture {
  private recording = false;
  private sessionId = "";
  private actions: DemoAction[] = [];
  private maxActions = DEFAULT_MAX_ACTIONS;
  private truncated = false;
  private captureTimer: ReturnType<typeof setTimeout> | null = null;

  constructor(
    private readonly documentRef: Document = document,
    private readonly now: () => number = () => performance.now(),
    private readonly acceptEvent: (event: Event) => boolean = (event) =>
      event.isTrusted,
  ) {}

  get isRecording(): boolean {
    return this.recording;
  }

  start(options: { sessionId: string; maxActions?: number }): void {
    this.stopListening();
    this.sessionId = options.sessionId;
    this.maxActions = boundedMax(options.maxActions);
    this.actions = [];
    this.truncated = false;
    this.recording = true;
    this.documentRef.addEventListener("click", this.onClick, true);
    this.documentRef.addEventListener("focusin", this.onFocus, true);
    this.documentRef.addEventListener("input", this.onInput, true);
    this.documentRef.addEventListener("scroll", this.onScroll, true);
    this.captureTimer = setTimeout(
      () => this.stopListening(),
      MAX_CAPTURE_DURATION_MS,
    );
  }

  stop(): DemoCaptureResult {
    this.stopListening();
    return {
      sessionId: this.sessionId,
      origin: this.documentRef.location.origin,
      actions: this.actions.map((action) => ({ ...action })),
      truncated: this.truncated,
    };
  }

  dispose(): void {
    this.stopListening();
    this.sessionId = "";
    this.actions = [];
    this.truncated = false;
  }

  private readonly onClick = (event: Event): void => {
    if (!this.acceptEvent(event)) return;
    const rawTarget = htmlTarget(event);
    if (!rawTarget || isSensitiveDemoField(rawTarget)) return;
    const target = clickableTarget(rawTarget);
    if (isSensitiveDemoField(target)) return;
    this.push({
      type: "click",
      selector: stableSelector(target),
      tag: target.localName,
      ...(target.getAttribute("role")
        ? { role: target.getAttribute("role") as string }
        : {}),
      timestamp: this.now(),
    });
  };

  private readonly onFocus = (event: Event): void => {
    if (!this.acceptEvent(event)) return;
    const target = htmlTarget(event);
    if (!target || isSensitiveDemoField(target)) return;
    const inputKind = editableKind(target);
    if (!inputKind) return;
    this.push({
      type: "focus",
      selector: stableSelector(target),
      tag: target.localName,
      inputKind,
      timestamp: this.now(),
    });
  };

  private readonly onInput = (event: Event): void => {
    if (!this.acceptEvent(event)) return;
    const target = htmlTarget(event);
    if (!target || isSensitiveDemoField(target)) return;
    const inputKind = editableKind(target);
    if (!inputKind) return;
    this.push({
      type: "input",
      selector: stableSelector(target),
      tag: target.localName,
      inputKind,
      valueCaptured: false,
      timestamp: this.now(),
    });
  };

  private readonly onScroll = (event: Event): void => {
    if (!this.acceptEvent(event)) return;
    const target = event.target;
    const scrollingElement =
      target === this.documentRef
        ? this.documentRef.scrollingElement
        : target instanceof Element
          ? target
          : null;
    if (!scrollingElement) return;

    const selector =
      target === this.documentRef
        ? (() => {
            const viewportTarget =
              typeof this.documentRef.elementFromPoint === "function"
                ? this.documentRef.elementFromPoint(
                    (this.documentRef.defaultView?.innerWidth ?? 0) / 2,
                    (this.documentRef.defaultView?.innerHeight ?? 0) / 2,
                  )
                : null;
            return viewportTarget instanceof HTMLElement
              ? stableSelector(viewportTarget)
              : "body";
          })()
        : stableSelector(scrollingElement as HTMLElement);
    const next: DemoAction = {
      type: "scroll",
      selector,
      scrollTop: scrollingElement.scrollTop,
      scrollLeft: scrollingElement.scrollLeft,
      timestamp: this.now(),
    };
    const previous = this.actions.at(-1);
    if (previous?.type === "scroll" && previous.selector === selector) {
      this.actions[this.actions.length - 1] = next;
      return;
    }
    this.push(next);
  };

  private push(action: DemoAction): void {
    if (!this.recording) return;
    if (this.actions.length >= this.maxActions) {
      this.truncated = true;
      return;
    }
    this.actions.push(action);
  }

  private stopListening(): void {
    if (this.captureTimer !== null) {
      clearTimeout(this.captureTimer);
      this.captureTimer = null;
    }
    if (!this.recording) return;
    this.recording = false;
    this.documentRef.removeEventListener("click", this.onClick, true);
    this.documentRef.removeEventListener("focusin", this.onFocus, true);
    this.documentRef.removeEventListener("input", this.onInput, true);
    this.documentRef.removeEventListener("scroll", this.onScroll, true);
  }
}
