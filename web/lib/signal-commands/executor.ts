import { PreparedActionTab } from "./action-tab";
import {
  BrowserCommandSchema,
  type BrowserAction,
  type BrowserCommand,
} from "./schema";

export interface CommandNote {
  id: string;
  text: string;
  createdAt: string;
}

export interface BrowserCommandEnvironment {
  started: boolean;
  approved: boolean;
  actionTab: PreparedActionTab;
  navigateSignal(path: string): void;
  speak(text: string, rate?: number): void;
  scheduleTimer(label: string, durationSeconds: number): void;
  saveNote(note: CommandNote): void;
  wait?(durationMs: number, signal?: AbortSignal): Promise<void>;
  now?: () => Date;
}

export interface BrowserCommandExecution {
  status:
    | "completed"
    | "paused"
    | "approval_required"
    | "action_tab_confirmation_required"
    | "failed"
    | "cancelled";
  completedStepIds: string[];
  pendingUrl?: string;
  error?: string;
}

function defaultWait(durationMs: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) {
      reject(new DOMException("Command was cancelled.", "AbortError"));
      return;
    }
    const timeout = setTimeout(resolve, durationMs);
    signal?.addEventListener(
      "abort",
      () => {
        clearTimeout(timeout);
        reject(new DOMException("Command was cancelled.", "AbortError"));
      },
      { once: true },
    );
  });
}

async function executeAction(
  action: BrowserAction,
  environment: BrowserCommandEnvironment,
  signal?: AbortSignal,
): Promise<{ pendingUrl?: string }> {
  if (signal?.aborted) throw new DOMException("Command was cancelled.", "AbortError");
  switch (action.type) {
    case "navigate_signal":
      environment.navigateSignal(action.path);
      return {};
    case "open_url": {
      const result = environment.actionTab.navigate(action.url);
      if (result.status === "rejected") throw new Error("Unsafe URL was rejected.");
      if (result.status === "requires_same_tab_confirmation") {
        return { pendingUrl: result.url };
      }
      return {};
    }
    case "speak_text":
      environment.speak(action.text, action.rate);
      return {};
    case "start_timer":
      environment.scheduleTimer(action.label, action.durationSeconds);
      return {};
    case "save_note": {
      const now = (environment.now ?? (() => new Date()))();
      environment.saveNote({
        id: `note-${now.getTime().toString(36)}`,
        text: action.text,
        createdAt: now.toISOString(),
      });
      return {};
    }
    case "wait":
      await (environment.wait ?? defaultWait)(action.durationMs, signal);
      return {};
  }
}

export async function executeBrowserCommand(
  value: unknown,
  environment: BrowserCommandEnvironment,
  signal?: AbortSignal,
): Promise<BrowserCommandExecution> {
  if (!environment.started) {
    return { status: "paused", completedStepIds: [] };
  }
  if (!environment.approved) {
    return { status: "approval_required", completedStepIds: [] };
  }
  const checked = BrowserCommandSchema.safeParse(value);
  if (!checked.success) {
    return {
      status: "failed",
      completedStepIds: [],
      error: "Command validation failed before execution.",
    };
  }
  const command: BrowserCommand = checked.data;
  const completedStepIds: string[] = [];
  for (const step of command.steps) {
    try {
      const result = await executeAction(step.action, environment, signal);
      if (result.pendingUrl) {
        return {
          status: "action_tab_confirmation_required",
          completedStepIds,
          pendingUrl: result.pendingUrl,
        };
      }
      completedStepIds.push(step.id);
    } catch (error) {
      if (signal?.aborted || (error instanceof DOMException && error.name === "AbortError")) {
        return { status: "cancelled", completedStepIds };
      }
      if (step.onFailure === "continue") continue;
      return {
        status: "failed",
        completedStepIds,
        error: error instanceof Error ? error.message : "Command step failed.",
      };
    }
  }
  return { status: "completed", completedStepIds };
}
