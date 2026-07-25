import type { ActionPlan } from "../contracts";
import { checkPublicHttpsLiteralHost } from "../security";

export const browserActionTypeValues = [
  "open_url",
  "wait",
  "show_notification",
  "speak_text",
  "play_sound",
  "discord_webhook",
  "media_control",
  "show_overlay",
] as const satisfies readonly ActionPlan["steps"][number]["action"]["type"][];

export type BrowserActionTab = Pick<Window, "closed" | "location" | "focus">;

export type BrowserExecutionContext = {
  actionTab?: BrowserActionTab | null;
  fetch?: typeof globalThis.fetch;
  speechSynthesis?: SpeechSynthesis;
  notification?: typeof Notification;
  document?: Document;
  onStatus?(message: string): void;
  onOverlay?(title: string, body: string, durationMs: number): void;
  signal?: AbortSignal;
};

export type BrowserPlanReceipt = {
  completedSteps: number;
  messages: string[];
};

export function isBrowserSafeAction(
  action: ActionPlan["steps"][number]["action"],
) {
  return (browserActionTypeValues as readonly string[]).includes(action.type);
}

export function isBrowserSafeActionType(actionType: string) {
  return (browserActionTypeValues as readonly string[]).includes(actionType);
}

export function isBrowserSafePlan(plan: ActionPlan) {
  return plan.steps.every((step) => isBrowserSafeAction(step.action));
}

export function assertSafeBrowserUrl(value: string) {
  const checked = checkPublicHttpsLiteralHost(value);
  if (!checked.ok) {
    throw new Error(
      "Signal only navigates to public HTTPS URLs without embedded credentials.",
    );
  }
  return checked.canonicalUrl;
}

function wait(durationMs: number, signal?: AbortSignal) {
  return new Promise<void>((resolve, reject) => {
    if (signal?.aborted) {
      reject(new DOMException("Command cancelled.", "AbortError"));
      return;
    }
    const timer = window.setTimeout(resolve, durationMs);
    signal?.addEventListener(
      "abort",
      () => {
        window.clearTimeout(timer);
        reject(new DOMException("Command cancelled.", "AbortError"));
      },
      { once: true },
    );
  });
}

function mediaElements(documentRef: Document) {
  return Array.from(
    documentRef.querySelectorAll<HTMLMediaElement>("audio, video"),
  ).filter((element) => !element.closest(".signal-camera-feed"));
}

async function executeAction(
  action: ActionPlan["steps"][number]["action"],
  context: BrowserExecutionContext,
) {
  if (!isBrowserSafeAction(action)) {
    throw new Error(
      `${action.type.replaceAll("_", " ")} is not available in browser-only Signal.`,
    );
  }

  switch (action.type) {
    case "open_url": {
      const url = assertSafeBrowserUrl(action.parameters.url);
      if (!context.actionTab || context.actionTab.closed) {
        throw new Error(
          "Prepare the reusable action tab before running a navigation command.",
        );
      }
      context.actionTab.location.href = url;
      context.actionTab.focus();
      return `Navigated the prepared action tab to ${new URL(url).hostname}.`;
    }
    case "wait":
      await wait(action.parameters.durationMs, context.signal);
      return `Waited ${action.parameters.durationMs} ms.`;
    case "speak_text": {
      const speech = context.speechSynthesis;
      if (!speech || typeof SpeechSynthesisUtterance === "undefined") {
        throw new Error("Speech synthesis is unavailable in this browser.");
      }
      const utterance = new SpeechSynthesisUtterance(action.parameters.text);
      if (action.parameters.rate) utterance.rate = action.parameters.rate;
      speech.speak(utterance);
      return "Spoke the reviewed text.";
    }
    case "show_notification": {
      const NotificationApi = context.notification;
      if (!NotificationApi || NotificationApi.permission !== "granted") {
        context.onOverlay?.(
          action.parameters.title,
          action.parameters.body,
          4_000,
        );
        return "Displayed the notification inside Signal.";
      }
      new NotificationApi(action.parameters.title, {
        body: action.parameters.body,
      });
      return "Displayed a browser notification.";
    }
    case "play_sound": {
      const audio = new Audio();
      const audioContextConstructor =
        window.AudioContext ??
        (window as typeof window & { webkitAudioContext?: typeof AudioContext })
          .webkitAudioContext;
      if (!audioContextConstructor) {
        void audio;
        throw new Error("Web Audio is unavailable in this browser.");
      }
      const audioContext = new audioContextConstructor();
      const oscillator = audioContext.createOscillator();
      const gain = audioContext.createGain();
      oscillator.frequency.value = action.parameters.sound === "Ping" ? 880 : 620;
      gain.gain.setValueAtTime(0.05, audioContext.currentTime);
      gain.gain.exponentialRampToValueAtTime(
        0.0001,
        audioContext.currentTime + 0.18,
      );
      oscillator.connect(gain);
      gain.connect(audioContext.destination);
      oscillator.start();
      oscillator.stop(audioContext.currentTime + 0.18);
      return `Played the ${action.parameters.sound} cue.`;
    }
    case "discord_webhook": {
      const fetcher = context.fetch ?? globalThis.fetch;
      const requestId = `browser_${crypto.randomUUID()}`;
      const response = await fetcher("/api/v1/integrations/discord", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          schemaVersion: 1,
          requestId,
          approved: true,
          action,
        }),
        signal: context.signal,
      });
      if (!response.ok) {
        throw new Error("The protected Discord action was not accepted.");
      }
      const receipt = (await response.json()) as { status?: string };
      return receipt.status === "sent"
        ? "Sent the reviewed Discord message."
        : "Simulated the Discord message because no server credential is configured.";
    }
    case "media_control": {
      const documentRef = context.document ?? document;
      const elements = mediaElements(documentRef);
      if (elements.length === 0) {
        throw new Error("Signal has no controllable media on this page.");
      }
      for (const element of elements) {
        if (
          action.parameters.command === "pause" ||
          (action.parameters.command === "toggle_play_pause" && !element.paused)
        ) {
          element.pause();
        } else if (
          action.parameters.command === "play" ||
          action.parameters.command === "toggle_play_pause"
        ) {
          await element.play();
        }
      }
      return `Applied ${action.parameters.command.replaceAll("_", " ")} to Signal media.`;
    }
    case "show_overlay":
      context.onOverlay?.(
        action.parameters.title,
        action.parameters.body,
        action.parameters.durationMs,
      );
      return "Displayed the reviewed Signal overlay.";
    default:
      throw new Error("This action is not available in browser-only Signal.");
  }
}

export async function executeBrowserPlan(
  plan: ActionPlan,
  context: BrowserExecutionContext = {},
): Promise<BrowserPlanReceipt> {
  const messages: string[] = [];
  let completedSteps = 0;

  for (const step of plan.steps) {
    if (context.signal?.aborted) {
      throw new DOMException("Command cancelled.", "AbortError");
    }
    try {
      const message = await executeAction(step.action, context);
      messages.push(message);
      completedSteps += 1;
      context.onStatus?.(message);
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "The browser action failed.";
      if (step.onFailure === "continue") {
        messages.push(`Skipped ${step.id}: ${message}`);
        context.onStatus?.(`Skipped ${step.id}: ${message}`);
        continue;
      }
      throw new Error(`${step.id}: ${message}`);
    }
  }

  return { completedSteps, messages };
}
