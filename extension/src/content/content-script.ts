import {
  InteractionController,
  type SignalMode,
  type TrackingFrame,
} from "./interaction";
import { createSignalOverlay } from "./overlay";
import {
  pageCapability,
  PROTECTED_PAGE_MESSAGE,
} from "./page-capabilities";
import type {
  SignalModeMessage,
  SignalTuningMessage,
  SignalResetMessage,
  ContentActionMessage,
  ContentActionResultMessage,
  TrackingFrameMessage,
  UnsupportedPageMessage,
  ZoomStatusMessage,
} from "../shared/messages";
import type { BrowserCommandAction } from "../shared/types";
import { DemoCapture, type DemoCaptureResult } from "./demo-capture";
import {
  runBoltPromptAutomation,
  runSpotifyNextTrackAutomation,
} from "./website-actions";

type DemoControlMessage =
  | {
      version: 1;
      type: "signal:demo/start";
      sessionId: string;
      maxActions?: number;
    }
  | {
      version: 1;
      type: "signal:demo/stop";
      sessionId?: string;
    };

type DemoResultMessage = DemoCaptureResult & {
  version: 1;
  type: "signal:demo/result";
};

type IncomingMessage =
  | TrackingFrameMessage
  | SignalModeMessage
  | SignalTuningMessage
  | SignalResetMessage
  | ZoomStatusMessage
  | UnsupportedPageMessage
  | ContentActionMessage
  | DemoControlMessage;

interface ChromeContentRuntime {
  onMessage?: {
    addListener(
      listener: (
        message: IncomingMessage,
        sender: unknown,
        sendResponse: (response?: unknown) => void,
      ) => boolean | void,
    ): void;
    removeListener?(
      listener: (
        message: IncomingMessage,
        sender: unknown,
        sendResponse: (response?: unknown) => void,
      ) => boolean | void,
    ): void;
  };
  sendMessage?: (message: unknown) => unknown;
}

const CONTENT_INSTANCE_KEY = Symbol.for("signal.extension.content-instance");

export interface SignalContentRuntime {
  controller: InteractionController;
  dispose(): void;
}

function runtimeGlobal(): ChromeContentRuntime | undefined {
  return globalThis.chrome?.runtime as ChromeContentRuntime | undefined;
}

function actionResult(
  requestId: string,
  ok: boolean,
  message: string,
): ContentActionResultMessage {
  return {
    version: 1,
    type: "signal:content-action-result",
    requestId,
    ok,
    message,
  };
}

function queryHtmlElement(
  documentRef: Document,
  selector: string,
): HTMLElement {
  let selected: Element | null;
  try {
    selected = documentRef.querySelector(selector);
  } catch {
    throw new Error("The reviewed selector is not valid on this page.");
  }
  const htmlConstructor = documentRef.defaultView?.HTMLElement;
  if (!htmlConstructor || !(selected instanceof htmlConstructor)) {
    throw new Error("The reviewed page control was not found.");
  }
  return selected;
}

function setFieldValue(
  documentRef: Document,
  target: HTMLElement,
  value: string,
): void {
  const view = documentRef.defaultView;
  if (!view) throw new Error("The page is no longer available.");

  if (target instanceof view.HTMLInputElement) {
    const type = target.type.toLowerCase();
    const autocomplete = target.autocomplete.toLowerCase();
    if (
      type === "password" ||
      ["current-password", "new-password", "one-time-code"].includes(
        autocomplete,
      )
    ) {
      throw new Error("Signal will not type into a sensitive field.");
    }
    const setter = Object.getOwnPropertyDescriptor(
      view.HTMLInputElement.prototype,
      "value",
    )?.set;
    setter?.call(target, value);
  } else if (target instanceof view.HTMLTextAreaElement) {
    const setter = Object.getOwnPropertyDescriptor(
      view.HTMLTextAreaElement.prototype,
      "value",
    )?.set;
    setter?.call(target, value);
  } else if (target.isContentEditable) {
    target.textContent = value;
  } else {
    throw new Error("The reviewed selector is not an editable field.");
  }

  target.dispatchEvent(
    new view.InputEvent("input", {
      bubbles: true,
      composed: true,
      data: value,
      inputType: "insertText",
    }),
  );
  target.dispatchEvent(
    new view.Event("change", { bubbles: true, composed: true }),
  );
}

export async function executeContentAction(
  documentRef: Document,
  overlay: ReturnType<typeof createSignalOverlay>,
  message: ContentActionMessage,
): Promise<ContentActionResultMessage> {
  const { requestId, action } = message;
  try {
    if (
      "origin" in action.parameters &&
      typeof action.parameters.origin === "string" &&
      action.parameters.origin !== documentRef.location.origin
    ) {
      throw new Error(
        "This taught action is bound to a different website origin.",
      );
    }
    switch (action.type) {
      case "scroll_to_selector": {
        const target = queryHtmlElement(
          documentRef,
          action.parameters.selector,
        );
        target.scrollIntoView({
          behavior: action.parameters.behavior ?? "auto",
          block: action.parameters.block ?? "center",
        });
        return actionResult(requestId, true, "Scrolled to the page control.");
      }
      case "click_selector": {
        const target = queryHtmlElement(
          documentRef,
          action.parameters.selector,
        );
        if (
          target.getAttribute("aria-disabled") === "true" ||
          ("disabled" in target && target.disabled === true)
        ) {
          throw new Error("The reviewed page control is disabled.");
        }
        target.focus({ preventScroll: true });
        target.click();
        return actionResult(requestId, true, "Clicked the page control.");
      }
      case "focus_field": {
        const target = queryHtmlElement(
          documentRef,
          action.parameters.selector,
        );
        target.focus({ preventScroll: true });
        return actionResult(requestId, true, "Focused the page field.");
      }
      case "type_text": {
        const target = queryHtmlElement(
          documentRef,
          action.parameters.selector,
        );
        target.focus({ preventScroll: true });
        setFieldValue(documentRef, target, action.parameters.text);
        return actionResult(requestId, true, "Typed the predefined text.");
      }
      case "speak_text": {
        const view = documentRef.defaultView;
        if (
          !view ||
          !("speechSynthesis" in view) ||
          typeof view.SpeechSynthesisUtterance !== "function"
        ) {
          throw new Error("Speech is unavailable on this page.");
        }
        const utterance = new view.SpeechSynthesisUtterance(
          action.parameters.text,
        );
        if (action.parameters.rate !== undefined) {
          utterance.rate = action.parameters.rate;
        }
        const requestedVoice = action.parameters.voice;
        if (requestedVoice) {
          utterance.voice =
            view.speechSynthesis
              .getVoices()
              .find((voice) => voice.name === requestedVoice) ?? null;
        }
        view.speechSynthesis.speak(utterance);
        return actionResult(requestId, true, "Spoke the reviewed text.");
      }
      case "show_overlay":
        overlay.showStatus(
          `${action.parameters.title}: ${action.parameters.body}`,
          "active",
        );
        return actionResult(requestId, true, "Displayed the Signal message.");
      case "media_control": {
        const media = Array.from(
          documentRef.querySelectorAll("video,audio"),
        ).find(
          (element): element is HTMLMediaElement =>
            element instanceof HTMLMediaElement && !element.paused,
        ) ?? documentRef.querySelector<HTMLMediaElement>("video,audio");
        if (!media) throw new Error("No media control was found on this page.");
        const shouldPlay =
          action.parameters.command === "play" ||
          (action.parameters.command === "toggle_play_pause" && media.paused);
        if (shouldPlay) {
          await media.play();
        } else {
          media.pause();
        }
        return actionResult(requestId, true, "Updated the page media.");
      }
      case "bolt_prompt": {
        const result = await runBoltPromptAutomation(documentRef, {
          timeoutMs: 15_000,
        });
        return actionResult(requestId, result.ok, result.message);
      }
      case "spotify_next_track": {
        const result = await runSpotifyNextTrackAutomation(documentRef, {
          timeoutMs: 10_000,
        });
        return actionResult(requestId, result.ok, result.message);
      }
      default:
        return actionResult(
          requestId,
          false,
          `The ${String((action as BrowserCommandAction).type)} action does not run in a page.`,
        );
    }
  } catch (error) {
    return actionResult(
      requestId,
      false,
      error instanceof Error ? error.message : "The page action failed.",
    );
  }
}

export function startSignalContentRuntime(
  documentRef: Document = document,
): SignalContentRuntime {
  const globalRecord = globalThis as typeof globalThis & {
    [CONTENT_INSTANCE_KEY]?: SignalContentRuntime;
  };
  const existing = globalRecord[CONTENT_INSTANCE_KEY];
  if (existing) return existing;

  const overlay = createSignalOverlay(documentRef);
  const capability = pageCapability(documentRef.location.href);
  const runtime = runtimeGlobal();
  // tabs.sendMessage without a frameId can reach every all_frames content
  // script. Keep page interaction in the top frame so one gesture cannot
  // activate the same page multiple times. Frame-specific routing can opt in
  // later without weakening the top-level release.
  const topFrame = window.top === window;
  const demoCapture = new DemoCapture(documentRef);
  let modeBeforeDemo: SignalMode | null = null;
  const controller = new InteractionController(
    documentRef,
    overlay,
    (message) => {
      void runtime?.sendMessage?.(message);
    },
  );

  if (!capability.supported) {
    controller.setMode("paused");
    overlay.showStatus(PROTECTED_PAGE_MESSAGE, "warning");
  }

  const onMessage = (
    message: IncomingMessage,
    _sender: unknown,
    sendResponse: (response?: unknown) => void,
  ): boolean | void => {
    if (!topFrame) return;
    if (!message || typeof message.type !== "string") return;
    if (message.version !== 1) return;

    switch (message.type) {
      case "signal:tracking-frame":
        if (capability.supported) {
          controller.handleTrackingFrame(message as TrackingFrame);
        }
        break;
      case "signal:mode":
        if (capability.supported) {
          const applied = controller.setMode(message.mode);
          sendResponse({
            ok: true,
            applied,
            mode: controller.currentMode,
            transactionState: controller.transactionState,
          });
        } else {
          sendResponse({ ok: false, error: PROTECTED_PAGE_MESSAGE });
        }
        break;
      case "signal:tuning":
        if (capability.supported) {
          controller.updatePointerTuning(message.tuning);
          sendResponse({ ok: true });
        } else {
          sendResponse({ ok: false, error: PROTECTED_PAGE_MESSAGE });
        }
        break;
      case "signal:reset":
        controller.reset(message.reason, true, message.generation);
        break;
      case "signal:zoom-status": {
        if (!message.supported) {
          overlay.clearIndicators();
          overlay.showStatus(
            message.error ?? "Signal cannot change zoom on this page.",
            "warning",
          );
          break;
        }
        const factor =
          message.factor ??
          (typeof message.percentage === "number"
            ? message.percentage / 100
            : undefined);
        if (factor !== undefined) {
          controller.setZoomFactor(factor);
          if (controller.transactionState === "zooming") {
            overlay.showZoom(factor * 100);
          }
        }
        break;
      }
      case "signal:unsupported":
        controller.setMode("paused");
        overlay.showStatus(
          message.message || PROTECTED_PAGE_MESSAGE,
          "warning",
        );
        break;
      case "signal:content-action":
        if (!capability.supported) {
          sendResponse(
            actionResult(
              message.requestId,
              false,
              PROTECTED_PAGE_MESSAGE,
            ),
          );
          return;
        }
        void executeContentAction(documentRef, overlay, message).then(
          sendResponse,
        );
        return true;
      case "signal:demo/start":
        if (!capability.supported) {
          sendResponse({ ok: false, error: PROTECTED_PAGE_MESSAGE });
          return;
        }
        if (!demoCapture.isRecording) {
          modeBeforeDemo = controller.currentMode;
        }
        controller.setMode("paused");
        demoCapture.start({
          sessionId: message.sessionId,
          maxActions: message.maxActions,
        });
        overlay.showStatus(
          "Teach by Demo is capturing browser actions only",
          "active",
        );
        sendResponse({
          version: 1,
          type: "signal:demo/state",
          state: "recording",
          sessionId: message.sessionId,
        });
        break;
      case "signal:demo/stop": {
        const result: DemoResultMessage = {
          version: 1,
          type: "signal:demo/result",
          ...demoCapture.stop(),
        };
        if (modeBeforeDemo) {
          controller.setMode(modeBeforeDemo);
          modeBeforeDemo = null;
        }
        sendResponse(result);
        break;
      }
    }
  };

  runtime?.onMessage?.addListener(onMessage);

  const resetForNavigation = (): void => {
    controller.reset("navigation");
  };
  const resetForVisibility = (): void => {
    if (documentRef.visibilityState === "hidden") {
      controller.reset("visibility-hidden");
    }
  };
  window.addEventListener("pagehide", resetForNavigation);
  window.addEventListener("pageshow", resetForNavigation);
  window.addEventListener("popstate", resetForNavigation);
  window.addEventListener("hashchange", resetForNavigation);
  documentRef.addEventListener("visibilitychange", resetForVisibility);

  const navigationApi = (
    window as typeof window & {
      navigation?: {
        addEventListener(type: "navigate", listener: () => void): void;
        removeEventListener?(type: "navigate", listener: () => void): void;
      };
    }
  ).navigation;
  navigationApi?.addEventListener("navigate", resetForNavigation);

  const instance: SignalContentRuntime = {
    controller,
    dispose() {
      runtime?.onMessage?.removeListener?.(onMessage);
      window.removeEventListener("pagehide", resetForNavigation);
      window.removeEventListener("pageshow", resetForNavigation);
      window.removeEventListener("popstate", resetForNavigation);
      window.removeEventListener("hashchange", resetForNavigation);
      documentRef.removeEventListener(
        "visibilitychange",
        resetForVisibility,
      );
      navigationApi?.removeEventListener?.("navigate", resetForNavigation);
      demoCapture.dispose();
      controller.destroy();
      delete globalRecord[CONTENT_INSTANCE_KEY];
    },
  };
  globalRecord[CONTENT_INSTANCE_KEY] = instance;

  if (topFrame) {
    void runtime?.sendMessage?.({
      version: 1,
      type: "signal:content-ready",
      supported: capability.supported,
      reason: capability.supported ? undefined : PROTECTED_PAGE_MESSAGE,
      url: documentRef.location.href,
      topFrame,
    });
  }

  return instance;
}

if (
  typeof document !== "undefined" &&
  typeof window !== "undefined" &&
  !(globalThis as typeof globalThis & {
    __SIGNAL_DISABLE_AUTO_START__?: boolean;
  }).__SIGNAL_DISABLE_AUTO_START__
) {
  startSignalContentRuntime();
}
