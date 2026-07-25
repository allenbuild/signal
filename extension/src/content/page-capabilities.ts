export const PROTECTED_PAGE_MESSAGE =
  "Signal cannot control this protected browser page.";

export type PageCapability =
  | { supported: true }
  | { supported: false; reason: string };

const PROTECTED_PROTOCOLS = new Set([
  "about:",
  "chrome:",
  "chrome-extension:",
  "devtools:",
  "edge:",
  "file:",
  "view-source:",
]);

const PROTECTED_HTTPS_HOSTS = new Set([
  "chrome.google.com",
  "chromewebstore.google.com",
]);

export function pageCapability(url: string): PageCapability {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return { supported: false, reason: PROTECTED_PAGE_MESSAGE };
  }

  if (PROTECTED_PROTOCOLS.has(parsed.protocol)) {
    return { supported: false, reason: PROTECTED_PAGE_MESSAGE };
  }

  if (
    parsed.protocol !== "http:" &&
    parsed.protocol !== "https:"
  ) {
    return { supported: false, reason: PROTECTED_PAGE_MESSAGE };
  }

  if (PROTECTED_HTTPS_HOSTS.has(parsed.hostname.toLowerCase())) {
    return { supported: false, reason: PROTECTED_PAGE_MESSAGE };
  }

  return { supported: true };
}

export function isElementDisabled(element: HTMLElement): boolean {
  if (
    element instanceof HTMLButtonElement ||
    element instanceof HTMLInputElement ||
    element instanceof HTMLSelectElement ||
    element instanceof HTMLTextAreaElement
  ) {
    return element.disabled;
  }

  return (
    element.getAttribute("aria-disabled") === "true" ||
    element.hasAttribute("inert")
  );
}

export function isFocusable(element: HTMLElement): boolean {
  if (isElementDisabled(element)) return false;

  if (
    element instanceof HTMLAnchorElement &&
    element.hasAttribute("href")
  ) {
    return true;
  }

  if (
    element instanceof HTMLButtonElement ||
    element instanceof HTMLInputElement ||
    element instanceof HTMLSelectElement ||
    element instanceof HTMLTextAreaElement
  ) {
    return true;
  }

  return (
    element.isContentEditable ||
    element.tabIndex >= 0 ||
    element.getAttribute("role") === "button" ||
    element.getAttribute("role") === "link"
  );
}

function shadowElementsFromPoint(
  root: Document | ShadowRoot,
  x: number,
  y: number,
): Element[] {
  const elements =
    "elementsFromPoint" in root
      ? root.elementsFromPoint(x, y)
      : [];
  const result: Element[] = [];

  for (const element of elements) {
    const shadowRoot = element.shadowRoot;
    if (shadowRoot?.mode === "open") {
      result.push(...shadowElementsFromPoint(shadowRoot, x, y));
    }
    result.push(element);
  }

  return result;
}

export function deepElementsFromPoint(
  documentRef: Document,
  x: number,
  y: number,
): HTMLElement[] {
  const htmlConstructor = documentRef.defaultView?.HTMLElement;
  if (!htmlConstructor) return [];

  const seen = new Set<Element>();
  return shadowElementsFromPoint(documentRef, x, y).filter(
    (element): element is HTMLElement => {
      if (!(element instanceof htmlConstructor) || seen.has(element)) {
        return false;
      }
      seen.add(element);
      return true;
    },
  );
}

function composedParent(element: HTMLElement): HTMLElement | null {
  if (element.parentElement) return element.parentElement;
  const root = element.getRootNode();
  return root instanceof ShadowRoot ? root.host as HTMLElement : null;
}

export function nearestScrollableElement(
  documentRef: Document,
  x: number,
  y: number,
): HTMLElement | Element {
  const start = deepElementsFromPoint(documentRef, x, y)[0] ?? null;
  let current = start;

  while (current) {
    const style = documentRef.defaultView?.getComputedStyle(current);
    const overflowY = style?.overflowY ?? "";
    if (
      /(auto|scroll|overlay)/.test(overflowY) &&
      current.scrollHeight > current.clientHeight
    ) {
      return current;
    }
    current = composedParent(current);
  }

  return (
    documentRef.scrollingElement ??
    documentRef.documentElement
  );
}
