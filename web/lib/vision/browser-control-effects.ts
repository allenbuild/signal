import type { ControlEffect } from "./control-engine";

const interactiveSelector = [
  "[data-signal-interactive]",
  "button:not([disabled])",
  "a[href]",
  "input:not([disabled])",
  "textarea:not([disabled])",
  "select:not([disabled])",
  "[role='button']",
].join(",");

export function clickSignalElementAt(
  x: number,
  y: number,
  documentRef: Document = document,
) {
  const target = documentRef
    .elementsFromPoint(x, y)
    .map((element) =>
      element instanceof HTMLElement
        ? element.closest<HTMLElement>(interactiveSelector)
        : null,
    )
    .find(
      (element): element is HTMLElement =>
        Boolean(element && !element.closest("[aria-hidden='true']")),
    );
  if (!target) return null;
  target.click();
  return (
    target.getAttribute("aria-label") ??
    target.textContent?.trim().slice(0, 80) ??
    target.tagName.toLowerCase()
  );
}

function isScrollable(element: HTMLElement) {
  const styles = getComputedStyle(element);
  return (
    /(auto|scroll)/.test(styles.overflowY) &&
    element.scrollHeight > element.clientHeight
  );
}

export function scrollSignalAt(
  x: number,
  y: number,
  deltaY: number,
  documentRef: Document = document,
) {
  const target = documentRef
    .elementsFromPoint(x, y)
    .flatMap((element) => {
      const candidates: HTMLElement[] = [];
      let current =
        element instanceof HTMLElement ? element : element.parentElement;
      while (current) {
        candidates.push(current);
        current = current.parentElement;
      }
      return candidates;
    })
    .find(isScrollable);

  if (target) {
    target.scrollBy({ top: deltaY, behavior: "auto" });
    return target;
  }

  const scrollingElement = documentRef.scrollingElement;
  if (scrollingElement instanceof HTMLElement) {
    scrollingElement.scrollBy({ top: deltaY, behavior: "auto" });
    return scrollingElement;
  }
  window.scrollBy({ top: deltaY, behavior: "auto" });
  return null;
}

export function applyControlEffects(
  effects: readonly ControlEffect[],
  handlers: {
    onClickPulse(x: number, y: number): void;
    onZoom(delta: number, x: number, y: number): void;
    onStatus(message: string): void;
    document?: Document;
  },
) {
  const documentRef = handlers.document ?? document;
  for (const effect of effects) {
    if (effect.type === "click") {
      const target = clickSignalElementAt(effect.x, effect.y, documentRef);
      handlers.onClickPulse(effect.x, effect.y);
      handlers.onStatus(
        target ? `Clicked ${target}.` : "No Signal control was beneath the cursor.",
      );
    } else if (effect.type === "scroll") {
      scrollSignalAt(effect.x, effect.y, effect.deltaY, documentRef);
      handlers.onStatus("Scrolling Signal content.");
    } else {
      handlers.onZoom(effect.delta, effect.x, effect.y);
      handlers.onStatus("Zooming Signal content.");
    }
  }
}
