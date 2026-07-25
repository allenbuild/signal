import {
  deepElementsFromPoint,
  isElementDisabled,
  isFocusable,
} from "./page-capabilities";

export interface ClickResult {
  clicked: boolean;
  target: HTMLElement | null;
  reason?: "no-target" | "disabled";
}

function dispatchMouseTransition(
  target: HTMLElement,
  type: "mousedown" | "mouseup",
  x: number,
  y: number,
): void {
  const view = target.ownerDocument.defaultView;
  if (!view) return;

  const common = {
    bubbles: true,
    cancelable: true,
    composed: true,
    clientX: x,
    clientY: y,
    button: 0,
    buttons: type === "mousedown" ? 1 : 0,
  };

  if (typeof view.PointerEvent === "function") {
    target.dispatchEvent(
      new view.PointerEvent(
        type === "mousedown" ? "pointerdown" : "pointerup",
        {
          ...common,
          pointerId: 1,
          pointerType: "mouse",
          isPrimary: true,
        },
      ),
    );
  }

  target.dispatchEvent(new view.MouseEvent(type, common));
}

export class ClickController {
  constructor(private readonly documentRef: Document = document) {}

  clickAt(x: number, y: number): ClickResult {
    const target =
      deepElementsFromPoint(this.documentRef, x, y)
        .map((candidate) => {
          let current: HTMLElement | null = candidate;
          while (current) {
            if (isFocusable(current)) return current;
            const root = current.getRootNode();
            current =
              current.parentElement ??
              (root instanceof ShadowRoot ? (root.host as HTMLElement) : null);
          }
          return null;
        })
        .find((candidate): candidate is HTMLElement => candidate !== null) ??
      null;
    if (!target) {
      return { clicked: false, target: null, reason: "no-target" };
    }
    if (isElementDisabled(target)) {
      return { clicked: false, target, reason: "disabled" };
    }

    if (isFocusable(target)) {
      try {
        target.focus({ preventScroll: true });
      } catch {
        target.focus();
      }
    }

    dispatchMouseTransition(target, "mousedown", x, y);
    dispatchMouseTransition(target, "mouseup", x, y);

    // HTMLElement.click() supplies one composed, untrusted click event and the
    // browser's standard element activation behavior. Dispatching an
    // additional click event here would activate controls twice.
    target.click();
    return { clicked: true, target };
  }
}
