import type { TabZoomController } from "./zoom";
import { safeParseSignalCommand } from "../shared/schema";
import type {
  BrowserCommandAction,
  CommandStep,
  SignalCommand,
} from "../shared/types";

export type CommandTab = {
  id: number;
  windowId?: number;
  index?: number;
  active?: boolean;
};

export type ContentActionReceipt = {
  ok: boolean;
  message: string;
};

export type CommandExecutorDependencies = {
  getActiveTab(): Promise<CommandTab | null>;
  createTab(options: { url: string; active: boolean }): Promise<CommandTab>;
  updateTab(
    tabId: number,
    changes: { url?: string; active?: boolean },
  ): Promise<CommandTab>;
  removeTab(tabId: number): Promise<void>;
  listTabs(windowId?: number): Promise<CommandTab[]>;
  sendContentAction(
    tabId: number,
    action: BrowserCommandAction,
    requestId: string,
  ): Promise<ContentActionReceipt>;
  zoom: Pick<TabZoomController, "set">;
  createNotification(options: {
    title: string;
    message: string;
  }): Promise<void>;
  runProtectedWebhook?(
    configurationId: string,
    payload: string,
    signal?: AbortSignal,
  ): Promise<void>;
  runClaudeWorkflow?(
    configurationId: string,
    workflowId: string,
    input: string,
    signal?: AbortSignal,
  ): Promise<void>;
  now?(): number;
  randomId?(): string;
};

export type CommandExecutionReceipt = {
  commandId: string;
  completedSteps: number;
  messages: string[];
};

function wait(durationMs: number, signal?: AbortSignal) {
  return new Promise<void>((resolve, reject) => {
    if (signal?.aborted) {
      reject(new DOMException("Command cancelled.", "AbortError"));
      return;
    }
    const timer = setTimeout(resolve, durationMs);
    signal?.addEventListener(
      "abort",
      () => {
        clearTimeout(timer);
        reject(new DOMException("Command cancelled.", "AbortError"));
      },
      { once: true },
    );
  });
}

function withTimeout<T>(
  operation: (signal: AbortSignal) => Promise<T>,
  timeoutMs: number,
  parentSignal?: AbortSignal,
) {
  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  const abort = () => {
    const reason =
      parentSignal?.reason instanceof Error
        ? parentSignal.reason
        : new DOMException("Command cancelled.", "AbortError");
    controller.abort(reason);
  };
  if (parentSignal?.aborted) abort();
  else parentSignal?.addEventListener("abort", abort, { once: true });
  const running = operation(controller.signal);
  const timeout = new Promise<T>((_, reject) => {
    timer = setTimeout(() => {
      const error = new Error("The command step timed out.");
      controller.abort(error);
      reject(error);
    }, timeoutMs);
    controller.signal.addEventListener("abort", () => {
      if (timer) clearTimeout(timer);
      reject(
        controller.signal.reason instanceof Error
          ? controller.signal.reason
          : new DOMException("Command cancelled.", "AbortError"),
      );
    }, { once: true });
  });
  void running.then(
    () => {
      if (timer) clearTimeout(timer);
    },
    () => {
      if (timer) clearTimeout(timer);
    },
  );
  return Promise.race([running, timeout]).finally(() => {
    parentSignal?.removeEventListener("abort", abort);
  });
}

export class CommandExecutor {
  constructor(private readonly dependencies: CommandExecutorDependencies) {}

  async execute(
    input: SignalCommand,
    options: { signal?: AbortSignal; confirmationsApproved?: boolean } = {},
  ): Promise<CommandExecutionReceipt> {
    const parsed = safeParseSignalCommand(input);
    if (!parsed.success) throw parsed.error;
    const command = parsed.data;
    if (!command.enabled) throw new Error("This Signal command is disabled.");
    if (
      command.plan.confirmation.mode === "every_run" &&
      !options.confirmationsApproved
    ) {
      throw new Error("This command requires review before every run.");
    }

    const messages: string[] = [];
    let completedSteps = 0;
    const startedAt = this.dependencies.now?.() ?? Date.now();
    for (const step of command.plan.steps) {
      if (options.signal?.aborted) {
        throw new DOMException("Command cancelled.", "AbortError");
      }
      if (
        (step.confirmation.mode === "every_run" ||
          step.onFailure === "ask") &&
        !options.confirmationsApproved
      ) {
        throw new Error(`${step.id}: this action requires confirmation.`);
      }
      try {
        const elapsed = (this.dependencies.now?.() ?? Date.now()) - startedAt;
        const remaining = command.plan.timeoutMs - elapsed;
        if (remaining <= 0) {
          throw new Error("The command exceeded its total timeout.");
        }
        const message = await withTimeout(
          (signal) => this.executeStep(step, signal),
          Math.min(step.timeoutMs, remaining),
          options.signal,
        );
        messages.push(message);
        completedSteps += 1;
      } catch (error) {
        const message =
          error instanceof Error ? error.message : "The action failed.";
        if (step.onFailure === "continue") {
          messages.push(`Skipped ${step.id}: ${message}`);
          continue;
        }
        throw new Error(`${step.id}: ${message}`);
      }
    }
    return { commandId: command.id, completedSteps, messages };
  }

  private async executeStep(step: CommandStep, signal?: AbortSignal) {
    const action = step.action;
    switch (action.type) {
      case "open_url":
        if (action.parameters.disposition === "current_tab") {
          const tab = await this.requireActiveTab();
          await this.dependencies.updateTab(tab.id, {
            url: action.parameters.url,
          });
          return "Navigated the active tab.";
        }
        await this.dependencies.createTab({
          url: action.parameters.url,
          active: true,
        });
        return "Opened the reviewed URL in a new tab.";
      case "create_tab":
        await this.dependencies.createTab({
          url: action.parameters.url,
          active: action.parameters.active ?? true,
        });
        return "Created a browser tab.";
      case "navigate_current_tab": {
        const tab = await this.requireActiveTab();
        await this.dependencies.updateTab(tab.id, {
          url: action.parameters.url,
        });
        return "Navigated the active tab.";
      }
      case "close_tab": {
        const tab = await this.requireActiveTab();
        await this.dependencies.removeTab(tab.id);
        return "Closed the active tab.";
      }
      case "switch_tab": {
        const current = await this.requireActiveTab();
        const tabs = (await this.dependencies.listTabs(current.windowId)).sort(
          (left, right) => (left.index ?? 0) - (right.index ?? 0),
        );
        if (tabs.length < 2) throw new Error("There is no other tab to switch to.");
        const index = tabs.findIndex((tab) => tab.id === current.id);
        if (index < 0) throw new Error("The active tab is no longer available.");
        const offset = action.parameters.direction === "next" ? 1 : -1;
        const target = tabs[(index + offset + tabs.length) % tabs.length]!;
        await this.dependencies.updateTab(target.id, { active: true });
        return `Switched to the ${action.parameters.direction} tab.`;
      }
      case "set_tab_zoom": {
        const tab = await this.requireActiveTab();
        const status = await this.dependencies.zoom.set(
          tab.id,
          action.parameters.factor,
          this.dependencies.now?.() ?? Date.now(),
        );
        if (!status.supported) {
          throw new Error(status.error ?? "Tab zoom is unavailable.");
        }
        return `Set tab zoom to ${status.percentage}%.`;
      }
      case "show_notification":
        await this.dependencies.createNotification({
          title: action.parameters.title,
          message: action.parameters.body,
        });
        return "Displayed a Signal notification on the active page.";
      case "protected_webhook":
        if (!this.dependencies.runProtectedWebhook) {
          throw new Error("The protected webhook is not configured.");
        }
        await this.dependencies.runProtectedWebhook(
          action.parameters.configurationId,
          action.parameters.payload,
          signal,
        );
        return "Ran the configured protected webhook.";
      case "discord_webhook":
        if (!this.dependencies.runProtectedWebhook) {
          if (action.parameters.fallback === "local_receipt") {
            return "Simulated the webhook because no credential is configured.";
          }
          throw new Error("The protected webhook is not configured.");
        }
        await this.dependencies.runProtectedWebhook(
          action.parameters.secretRef,
          action.parameters.message,
          signal,
        );
        return "Ran the configured protected webhook.";
      case "claude_workflow":
        if (!this.dependencies.runClaudeWorkflow) {
          throw new Error("The Claude workflow is not configured.");
        }
        await this.dependencies.runClaudeWorkflow(
          action.parameters.configurationId,
          action.parameters.workflowId,
          action.parameters.input,
          signal,
        );
        return "Ran the configured Claude workflow.";
      case "wait":
        await wait(action.parameters.durationMs, signal);
        return `Waited ${action.parameters.durationMs} ms.`;
      case "scroll_to_selector":
      case "click_selector":
      case "focus_field":
      case "type_text":
      case "speak_text":
      case "show_overlay":
      case "media_control":
      case "bolt_prompt":
      case "spotify_next_track": {
        const tab = await this.requireActiveTab();
        const requestId =
          this.dependencies.randomId?.() ??
          `signal_${Date.now()}_${Math.random().toString(36).slice(2)}`;
        const receipt = await this.dependencies.sendContentAction(
          tab.id,
          action,
          requestId,
        );
        if (!receipt.ok) throw new Error(receipt.message);
        return receipt.message;
      }
      default:
        throw new Error("This action is not available in Signal.");
    }
  }

  private async requireActiveTab() {
    const tab = await this.dependencies.getActiveTab();
    if (!tab) throw new Error("Signal has no active controllable tab.");
    return tab;
  }
}
