export interface RegisteredInteraction {
  id: string;
  label: string;
  gestureAllowed: boolean;
  requiresTrustedActivation?: boolean;
  activate(): void | Promise<void>;
}

export type ActivationResult =
  | { status: "activated"; id: string; label: string }
  | { status: "blocked"; reason: "trusted-activation-required" | "gesture-disabled"; label: string }
  | { status: "miss"; reason: "no-target" | "unsupported-target" };

function isDisabled(element: Element): boolean {
  return element.matches(":disabled, [aria-disabled='true'], [inert], [hidden]");
}

export class InteractionRegistry {
  private readonly entries = new WeakMap<Element, RegisteredInteraction>();

  register(element: Element, interaction: RegisteredInteraction): () => void {
    this.entries.set(element, interaction);
    return () => this.entries.delete(element);
  }

  resolveAt(x: number, y: number): Element | null {
    if (typeof document === "undefined") return null;
    return document.elementFromPoint(x, y);
  }

  async activateAt(x: number, y: number): Promise<ActivationResult> {
    const target = this.resolveAt(x, y);
    if (!target) return { status: "miss", reason: "no-target" };
    return this.activate(target);
  }

  async activate(target: Element): Promise<ActivationResult> {
    let current: Element | null = target;
    while (current) {
      const registered = this.entries.get(current);
      if (registered) {
        if (!registered.gestureAllowed || isDisabled(current)) {
          return { status: "blocked", reason: "gesture-disabled", label: registered.label };
        }
        if (registered.requiresTrustedActivation) {
          return {
            status: "blocked",
            reason: "trusted-activation-required",
            label: registered.label,
          };
        }
        await registered.activate();
        return { status: "activated", id: registered.id, label: registered.label };
      }
      current = current.parentElement;
    }

    const ordinary = target.closest<HTMLElement>(
      "button, input[type='button'], input[type='checkbox'], input[type='radio'], summary, [role='button'], a[href]",
    );
    if (!ordinary || isDisabled(ordinary)) {
      return { status: "miss", reason: "unsupported-target" };
    }
    if (ordinary instanceof HTMLAnchorElement) {
      const url = new URL(ordinary.href, window.location.href);
      if (url.origin !== window.location.origin) {
        return {
          status: "blocked",
          reason: "trusted-activation-required",
          label: ordinary.textContent?.trim() || "External link",
        };
      }
    }
    ordinary.focus({ preventScroll: true });
    ordinary.click();
    return {
      status: "activated",
      id: ordinary.id || ordinary.getAttribute("name") || ordinary.tagName.toLowerCase(),
      label: ordinary.getAttribute("aria-label") || ordinary.textContent?.trim() || "Control",
    };
  }
}

export function nearestScrollableElement(target: Element | null): HTMLElement {
  let current = target instanceof HTMLElement ? target : null;
  while (current) {
    const style = window.getComputedStyle(current);
    const allowsScroll = /(auto|scroll)/.test(style.overflowY);
    if (allowsScroll && current.scrollHeight > current.clientHeight) return current;
    current = current.parentElement;
  }
  return (document.scrollingElement as HTMLElement | null) ?? document.documentElement;
}

export interface SignalZoomState {
  scale: number;
  originX: number;
  originY: number;
}

export class SignalZoomController {
  private state: SignalZoomState = { scale: 1, originX: 0.5, originY: 0.5 };

  constructor(
    private readonly minimum = 0.75,
    private readonly maximum = 1.75,
  ) {}

  update(delta: number, cursorX: number, cursorY: number, viewport: { width: number; height: number }): SignalZoomState {
    const next = Math.min(this.maximum, Math.max(this.minimum, this.state.scale + delta));
    this.state = {
      scale: next,
      originX: Math.min(1, Math.max(0, cursorX / Math.max(1, viewport.width))),
      originY: Math.min(1, Math.max(0, cursorY / Math.max(1, viewport.height))),
    };
    return this.snapshot();
  }

  reset(): SignalZoomState {
    this.state = { scale: 1, originX: 0.5, originY: 0.5 };
    return this.snapshot();
  }

  snapshot(): SignalZoomState {
    return { ...this.state };
  }
}
