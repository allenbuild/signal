export interface CursorPosition {
  x: number;
  y: number;
}

export interface SignalOverlay {
  readonly host: HTMLElement;
  readonly position: CursorPosition;
  setCursor(position: CursorPosition, visible?: boolean): void;
  setCursorVisible(visible: boolean): void;
  showClick(position?: CursorPosition): void;
  showScroll(deltaY: number): void;
  showZoom(percent: number): void;
  showStatus(message: string, tone?: "neutral" | "active" | "warning"): void;
  clearIndicators(): void;
  setNativeCursorHidden(hidden: boolean): void;
  reset(options?: { hideCursor?: boolean; status?: string }): void;
  destroy(): void;
}

const OVERLAY_ID = "signal-extension-overlay";
const NATIVE_CURSOR_STYLE_ID = "signal-extension-native-cursor";
const overlayByDocument = new WeakMap<Document, SignalOverlay>();

function appendStyle(root: ShadowRoot): void {
  const style = root.ownerDocument.createElement("style");
  style.textContent = `
    :host, * { box-sizing: border-box; }
    #surface {
      position: fixed;
      inset: 0;
      pointer-events: none;
      overflow: hidden;
      color: #111827;
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont,
        "Segoe UI", sans-serif;
    }
    #cursor {
      position: fixed;
      left: 0;
      top: 0;
      width: 24px;
      height: 24px;
      margin: -12px 0 0 -12px;
      border: 3px solid #fff;
      border-radius: 999px;
      background: #111827;
      box-shadow: 0 2px 14px rgba(0, 0, 0, .36);
      opacity: 0;
      transform: translate3d(0, 0, 0);
      transition: opacity 100ms ease;
      will-change: transform;
    }
    #cursor[data-visible="true"] { opacity: .96; }
    #cursor::after {
      content: "";
      position: absolute;
      inset: 6px;
      border-radius: inherit;
      background: #bef264;
    }
    #pulse {
      position: fixed;
      left: 0;
      top: 0;
      width: 42px;
      height: 42px;
      margin: -21px 0 0 -21px;
      border: 3px solid #bef264;
      border-radius: 999px;
      opacity: 0;
      transform: translate3d(0, 0, 0) scale(.45);
    }
    #indicator {
      position: fixed;
      left: 50%;
      bottom: 28px;
      max-width: min(420px, calc(100vw - 32px));
      padding: 9px 14px;
      border: 1px solid rgba(255, 255, 255, .42);
      border-radius: 999px;
      background: rgba(17, 24, 39, .92);
      box-shadow: 0 8px 28px rgba(0, 0, 0, .2);
      color: #fff;
      font-size: 13px;
      font-weight: 700;
      letter-spacing: .01em;
      opacity: 0;
      transform: translateX(-50%);
    }
    #indicator[data-visible="true"] { opacity: 1; }
    #badge {
      position: fixed;
      top: 14px;
      right: 14px;
      max-width: min(390px, calc(100vw - 28px));
      padding: 8px 11px;
      border: 1px solid rgba(17, 24, 39, .14);
      border-radius: 10px;
      background: rgba(255, 255, 255, .94);
      box-shadow: 0 6px 24px rgba(0, 0, 0, .13);
      color: #111827;
      font-size: 12px;
      font-weight: 700;
      opacity: 0;
    }
    #badge[data-visible="true"] { opacity: 1; }
    #badge[data-tone="active"]::before { color: #65a30d; }
    #badge[data-tone="warning"]::before { color: #dc2626; }
    #badge::before { content: "●"; margin-right: 7px; color: #6b7280; }
    @media (prefers-reduced-motion: reduce) {
      #cursor { transition: none; }
    }
  `;
  root.append(style);
}

function animatePulse(element: HTMLElement): void {
  const keyframes = [
    { opacity: 0.9, transform: element.style.transform + " scale(.45)" },
    { opacity: 0, transform: element.style.transform + " scale(1.35)" },
  ];
  element.animate?.(keyframes, {
    duration: 360,
    easing: "cubic-bezier(.2,.8,.2,1)",
  });
}

export function createSignalOverlay(
  documentRef: Document = document,
): SignalOverlay {
  const existing = overlayByDocument.get(documentRef);
  if (existing?.host.isConnected) return existing;

  documentRef.getElementById(OVERLAY_ID)?.remove();

  const host = documentRef.createElement("div");
  host.id = OVERLAY_ID;
  host.setAttribute("aria-hidden", "true");
  Object.assign(host.style, {
    position: "fixed",
    inset: "0",
    pointerEvents: "none",
    zIndex: "2147483647",
    contain: "layout style",
  });

  const root = host.attachShadow({ mode: "closed" });
  appendStyle(root);

  const surface = documentRef.createElement("div");
  surface.id = "surface";
  const cursor = documentRef.createElement("div");
  cursor.id = "cursor";
  cursor.dataset.visible = "false";
  const pulse = documentRef.createElement("div");
  pulse.id = "pulse";
  const indicator = documentRef.createElement("div");
  indicator.id = "indicator";
  indicator.dataset.visible = "false";
  const badge = documentRef.createElement("div");
  badge.id = "badge";
  badge.dataset.visible = "false";
  badge.dataset.tone = "neutral";
  surface.append(cursor, pulse, indicator, badge);
  root.append(surface);

  (documentRef.documentElement ?? documentRef.body).append(host);

  let position = { x: 0, y: 0 };

  const overlay: SignalOverlay = {
    host,
    get position() {
      return { ...position };
    },
    setCursor(next, visible = true) {
      position = { x: next.x, y: next.y };
      cursor.style.transform = `translate3d(${next.x}px, ${next.y}px, 0)`;
      cursor.dataset.visible = String(visible);
    },
    setCursorVisible(visible) {
      cursor.dataset.visible = String(visible);
    },
    showClick(next = position) {
      pulse.style.transform = `translate3d(${next.x}px, ${next.y}px, 0)`;
      animatePulse(pulse);
    },
    showScroll(deltaY) {
      const direction = deltaY < 0 ? "↑" : "↓";
      indicator.textContent = `${direction} Scrolling`;
      indicator.dataset.visible = "true";
    },
    showZoom(percent) {
      indicator.textContent = `Zoom ${Math.round(percent)}%`;
      indicator.dataset.visible = "true";
    },
    showStatus(message, tone = "neutral") {
      if (
        badge.textContent === message &&
        badge.dataset.tone === tone &&
        badge.dataset.visible === String(Boolean(message))
      ) {
        return;
      }
      badge.textContent = message;
      badge.dataset.tone = tone;
      badge.dataset.visible = String(Boolean(message));
    },
    clearIndicators() {
      indicator.textContent = "";
      indicator.dataset.visible = "false";
    },
    setNativeCursorHidden(hidden) {
      documentRef.getElementById(NATIVE_CURSOR_STYLE_ID)?.remove();
      if (!hidden) return;
      const nativeCursorStyle = documentRef.createElement("style");
      nativeCursorStyle.id = NATIVE_CURSOR_STYLE_ID;
      nativeCursorStyle.textContent =
        "html,body,body *{cursor:none!important}";
      (documentRef.head ?? documentRef.documentElement).append(nativeCursorStyle);
    },
    reset(options = {}) {
      this.clearIndicators();
      this.setNativeCursorHidden(false);
      if (options.hideCursor ?? true) this.setCursorVisible(false);
      if (options.status !== undefined) {
        this.showStatus(options.status);
      } else {
        badge.textContent = "";
        badge.dataset.visible = "false";
      }
    },
    destroy() {
      this.setNativeCursorHidden(false);
      host.remove();
      overlayByDocument.delete(documentRef);
    },
  };

  overlayByDocument.set(documentRef, overlay);
  return overlay;
}
